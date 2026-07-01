// Physiome correlation engine — relates the body (HRV, resting HR, sleep, mood, activity) to the
// environment + space weather (barometric pressure trend, geomagnetic Kp, solar wind, F10.7, UV, AQI)
// across a series of daily aggregates (the shape aggregateDay() in digest.mjs returns).
//
// Everything here is PURE (no I/O) so it is fully testable. Statistics:
//  - Spearman rank correlation (rho) is the primary measure — robust to non-normal, monotonic-but-
//    nonlinear physiological responses and to outliers, which dominate this kind of data.
//  - Pearson r is reported alongside for reference.
//  - A real two-tailed p-value (Student t via the regularized incomplete beta) so results become
//    inferential as the series grows. With few days, treat correlations as EXPLORATORY, not causal.
//  - Lag scan: a geomagnetic/weather driver on day d may move the body on day d, d+1, d+2 — we scan
//    lags and keep the strongest, since the physiological response is often delayed.
//
// NOTE on `mood`: it flows from HealthKit State of Mind (HKStateOfMind, iOS 18+). Both the iOS
// capture (HealthSyncEngine.fetchNewStateOfMind/registerStateOfMindObserver) and aggregateDay's
// extraction were missing until 2026-07-01 — the iOS side never fetched/uploaded it at all, so
// this engine's `agg.health.mood` read was correct but had nothing to read. Fixed on both ends now.

function finite(v) {
  return typeof v === "number" && Number.isFinite(v);
}

// ---- core statistics -------------------------------------------------------

export function pearson(xs, ys) {
  const n = Math.min(xs.length, ys.length);
  if (n < 2) return null;
  let sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
  for (let i = 0; i < n; i++) {
    sx += xs[i]; sy += ys[i];
    sxx += xs[i] * xs[i]; syy += ys[i] * ys[i];
    sxy += xs[i] * ys[i];
  }
  const cov = n * sxy - sx * sy;
  const dx = n * sxx - sx * sx;
  const dy = n * syy - sy * sy;
  if (dx <= 0 || dy <= 0) return null; // no variance in one series → undefined correlation
  const r = cov / Math.sqrt(dx * dy);
  return Math.max(-1, Math.min(1, r));
}

// Average-rank transform (ties share the mean of their rank positions).
function ranks(values) {
  const idx = values.map((v, i) => [v, i]).sort((a, b) => a[0] - b[0]);
  const r = new Array(values.length);
  let i = 0;
  while (i < idx.length) {
    let j = i;
    while (j + 1 < idx.length && idx[j + 1][0] === idx[i][0]) j++;
    const avg = (i + j) / 2 + 1; // ranks are 1-based
    for (let k = i; k <= j; k++) r[idx[k][1]] = avg;
    i = j + 1;
  }
  return r;
}

export function spearman(xs, ys) {
  const n = Math.min(xs.length, ys.length);
  if (n < 2) return null;
  return pearson(ranks(xs.slice(0, n)), ranks(ys.slice(0, n)));
}

// ---- Student t two-tailed p via regularized incomplete beta (Numerical Recipes) ----

function gammln(xx) {
  const cof = [
    76.18009172947146, -86.50532032941677, 24.01409824083091,
    -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5,
  ];
  let x = xx, y = xx;
  let tmp = x + 5.5;
  tmp -= (x + 0.5) * Math.log(tmp);
  let ser = 1.000000000190015;
  for (let j = 0; j < 6; j++) ser += cof[j] / ++y;
  return -tmp + Math.log((2.5066282746310005 * ser) / x);
}

function betacf(a, b, x) {
  const FPMIN = 1e-300, EPS = 3e-12, MAXIT = 200;
  let qab = a + b, qap = a + 1, qam = a - 1;
  let c = 1, d = 1 - (qab * x) / qap;
  if (Math.abs(d) < FPMIN) d = FPMIN;
  d = 1 / d;
  let h = d;
  for (let m = 1; m <= MAXIT; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1 + aa * d; if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c; if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d; h *= d * c;
    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1 + aa * d; if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c; if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d;
    const del = d * c; h *= del;
    if (Math.abs(del - 1) < EPS) break;
  }
  return h;
}

function betai(a, b, x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const bt = Math.exp(gammln(a + b) - gammln(a) - gammln(b) + a * Math.log(x) + b * Math.log(1 - x));
  if (x < (a + 1) / (a + b + 2)) return (bt * betacf(a, b, x)) / a;
  return 1 - (bt * betacf(b, a, 1 - x)) / b;
}

// Two-tailed p-value for a t-statistic with `df` degrees of freedom.
export function studentTwoTailedP(t, df) {
  if (!finite(t) || !finite(df) || df <= 0) return null;
  return betai(df / 2, 0.5, df / (df + t * t));
}

function pFromRho(rho, n) {
  if (rho == null || n < 3) return null;
  const r2 = Math.min(rho * rho, 0.999999);
  const t = rho * Math.sqrt((n - 2) / (1 - r2));
  return studentTwoTailedP(t, n - 2);
}

// ---- pairing across the daily series --------------------------------------

const DRIVERS = ["pressureTrendHpa", "kpMax", "solarWindSpeed", "f107", "uvMax", "aqi", "tempMaxC"];
const OUTCOMES = [
  "hrvMs", "restingHr", "sleepHours", "mood", "steps",
  "balanceSteadiness", "balanceEvents", "gad7", "phq9",
  "drivingMinutes", "voicePitchHz", "voicePitchVariance", "voiceLoudnessDb",
  "voicePauseRatio", "voiceSpeechRateWpm",
  "actigraphyDfaAlpha", "actigraphySampleEntropy",
];

// Flatten the nested daily aggregates into one flat record per day, sorted by date.
export function flattenAggregates(aggs) {
  return (aggs || [])
    .map((a) => ({
      date: a?.date,
      hrvMs: a?.health?.hrvMs ?? null,
      restingHr: a?.health?.restingHr ?? null,
      sleepHours: a?.health?.sleepHours ?? null,
      mood: a?.health?.mood ?? null,
      steps: a?.health?.steps ?? null,
      balanceSteadiness: a?.health?.balanceSteadiness ?? null,
      balanceEvents: a?.health?.balanceEvents ?? null,
      gad7: a?.health?.gad7 ?? null,
      phq9: a?.health?.phq9 ?? null,
      drivingMinutes: a?.health?.drivingMinutes ?? null,
      voicePitchHz: a?.health?.voicePitchHz ?? null,
      voicePitchVariance: a?.health?.voicePitchVariance ?? null,
      voiceLoudnessDb: a?.health?.voiceLoudnessDb ?? null,
      voicePauseRatio: a?.health?.voicePauseRatio ?? null,
      voiceSpeechRateWpm: a?.health?.voiceSpeechRateWpm ?? null,
      actigraphyDfaAlpha: a?.health?.actigraphyDfaAlpha ?? null,
      actigraphySampleEntropy: a?.health?.actigraphySampleEntropy ?? null,
      pressureTrendHpa: a?.weather?.pressureTrendHpa ?? null,
      uvMax: a?.weather?.uvMax ?? null,
      aqi: a?.weather?.aqi ?? null,
      tempMaxC: a?.weather?.tempMaxC ?? null,
      kpMax: a?.space?.kpMax ?? null,
      solarWindSpeed: a?.space?.solarWindSpeed ?? null,
      f107: a?.space?.f107 ?? null,
    }))
    .filter((r) => r.date)
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
}

// Pair driver (day d) with outcome (day d+lag), dropping any pair with a missing value.
export function alignPair(series, driverKey, outcomeKey, lag = 0) {
  const xs = [], ys = [];
  for (let i = 0; i + lag < series.length; i++) {
    const x = series[i][driverKey];
    const y = series[i + lag][outcomeKey];
    if (finite(x) && finite(y)) { xs.push(x); ys.push(y); }
  }
  return { xs, ys };
}

// Compute the driver×outcome correlation matrix with a lag scan. Returns the best lag per pair
// (by |rho|), ranked strongest-first; pairs that never reach minN land in `skipped`.
export function correlatePhysiome(aggs, opts = {}) {
  const lags = opts.lags || [0, 1, 2];
  const minN = opts.minN ?? 7;
  const series = flattenAggregates(aggs);
  const correlations = [];
  const skipped = [];

  for (const driver of DRIVERS) {
    for (const outcome of OUTCOMES) {
      let best = null;
      let maxN = 0;
      for (const lag of lags) {
        const { xs, ys } = alignPair(series, driver, outcome, lag);
        maxN = Math.max(maxN, xs.length);
        if (xs.length < minN) continue;
        const rho = spearman(xs, ys);
        if (rho == null) continue;
        if (!best || Math.abs(rho) > Math.abs(best.rho)) {
          best = {
            driver, outcome, lag, n: xs.length,
            rho: round(rho, 3),
            r: round(pearson(xs, ys), 3),
            p: round(pFromRho(rho, xs.length), 4),
          };
        }
      }
      if (best) {
        best.notable = Math.abs(best.rho) >= 0.5 && best.n >= minN && best.p != null && best.p < 0.05;
        correlations.push(best);
      } else {
        skipped.push({ driver, outcome, maxN, reason: maxN < minN ? "insufficient-data" : "no-variance" });
      }
    }
  }

  correlations.sort((a, b) => {
    const da = Math.abs(b.rho) - Math.abs(a.rho);
    if (da !== 0) return da;
    return (a.p ?? 1) - (b.p ?? 1);
  });
  return { correlations, skipped, days: series.length, minN };
}

function round(v, d) {
  if (v == null || !Number.isFinite(v)) return null;
  const f = 10 ** d;
  return Math.round(v * f) / f;
}

// ---- human summary (deterministic pt-BR) for companion grounding -----------

const LABELS = {
  kpMax: "Kp (geomagnético)", hrvMs: "HRV", restingHr: "FC repouso", sleepHours: "sono",
  mood: "humor", steps: "passos", pressureTrendHpa: "tendência de pressão",
  solarWindSpeed: "vento solar", f107: "F10.7", uvMax: "UV", aqi: "AQI", tempMaxC: "temp. máx",
  balanceSteadiness: "equilíbrio (steadiness)", balanceEvents: "eventos de risco de queda",
  gad7: "GAD-7 (ansiedade)", phq9: "PHQ-9 (depressão)", drivingMinutes: "tempo dirigindo",
  voicePitchHz: "voz: pitch médio", voicePitchVariance: "voz: variância de pitch",
  voiceLoudnessDb: "voz: volume", voicePauseRatio: "voz: proporção de pausas",
  voiceSpeechRateWpm: "voz: taxa de fala",
  actigraphyDfaAlpha: "actigrafia: DFA-alpha", actigraphySampleEntropy: "actigrafia: entropia amostral",
};

export function summarizeCorrelations(res, { top = 5 } = {}) {
  const notable = (res?.correlations || []).filter((c) => c.notable);
  const list = (notable.length ? notable : res?.correlations || []).slice(0, top);
  if (!list.length) {
    return `## Correlações físio×ambiente\nSem correlações com dados suficientes ainda (mín. ${res?.minN ?? 7} dias pareados).`;
  }
  const lines = list.map((c) => {
    const dir = c.rho < 0 ? "↓" : "↑";
    const dl = LABELS[c.driver] || c.driver;
    const ol = LABELS[c.outcome] || c.outcome;
    const pp = c.p != null ? `, p=${c.p.toFixed(3)}` : "";
    return `- ${dl} → ${ol} ${dir}: ρ=${c.rho.toFixed(2)} (atraso ${c.lag}d, n=${c.n}${pp})`;
  });
  const head = notable.length
    ? "## Correlações físio×ambiente (notáveis, exploratórias)"
    : "## Correlações físio×ambiente (exploratórias — n baixo)";
  return [head, ...lines].join("\n");
}
