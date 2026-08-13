import express from "express";
import { makePool, ensureSchema, upsertHealthSamples, upsertWeather } from "../src/db.mjs";
import { validateBatch } from "../src/validate.mjs";
import { aggregateRange } from "../src/digest.mjs";
import { correlatePhysiome, summarizeCorrelations } from "../src/correlate.mjs";

const PORT = Number(process.env.PORT || 8090);
const INGEST_TOKEN = process.env.PHYSIOME_INGEST_TOKEN || "";

const pool = makePool();
await ensureSchema(pool);

const app = express();

// ── INSTRUMENTAÇÃO DO INGEST ────────────────────────────────────────────────
// Existe para responder uma pergunta concreta: vale trocar JSON por Apache Arrow
// no transporte? A fila do relógio pode ter milhões de amostras, e cada linha
// JSON custa ~175 bytes (o uuid sozinho são 36 caracteres, e type/unit repetem a
// mesma string milhão de vezes).
//
// Arrow só compensa se o gargalo for CPU de serialização. Se for tamanho de fio,
// gzip resolve com uma linha e nenhuma dependência nova. Isto mede qual dos dois.
//
// O parse acontece DENTRO do express.json, antes do handler — por isso os
// carimbos ficam em volta do middleware, não dentro dele.
const marco = () => Number(process.hrtime.bigint() / 1000n) / 1000; // ms

app.use((req, _res, next) => { req._t0 = marco(); next(); });
app.use(express.json({
  limit: "16mb",
  verify: (req, _res, buf) => { req._bytes = buf.length; req._tLido = marco(); },
}));

/// Resumo rolante em memória. Sem série temporal, sem dependência: só o suficiente
/// para decidir. Zera quando o pod reinicia, e tudo bem — isto é uma investigação,
/// não observabilidade permanente.
const perfil = {
  desde: new Date().toISOString(),
  requisicoes: 0, linhas: 0, bytes: 0,
  ms: { leitura: 0, parse: 0, validacao: 0, banco: 0, total: 0 },
  picos: { bytes: 0, linhas: 0, total_ms: 0 },
  cliente: { encode_ms: 0, amostras: 0 },  // vem do header X-Beagle-Client-Timing
};

function anotar(req, medidas, linhas) {
  perfil.requisicoes += 1;
  perfil.linhas += linhas;
  perfil.bytes += req._bytes || 0;
  for (const k of Object.keys(perfil.ms)) perfil.ms[k] += medidas[k] || 0;
  perfil.picos.bytes = Math.max(perfil.picos.bytes, req._bytes || 0);
  perfil.picos.linhas = Math.max(perfil.picos.linhas, linhas);
  perfil.picos.total_ms = Math.max(perfil.picos.total_ms, medidas.total || 0);

  // O telefone manda o que só ele sabe: quanto gastou codificando.
  const t = req.get("x-beagle-client-timing") || "";
  const enc = /encode_ms=([\d.]+)/.exec(t);
  if (enc) { perfil.cliente.encode_ms += Number(enc[1]); perfil.cliente.amostras += 1; }

  const porLinha = linhas ? ((req._bytes || 0) / linhas).toFixed(1) : "0";
  console.log(
    `[physiome] ingest linhas=${linhas} bytes=${req._bytes || 0} bytes_por_linha=${porLinha} ` +
    `leitura=${medidas.leitura.toFixed(1)}ms parse=${medidas.parse.toFixed(1)}ms ` +
    `validacao=${medidas.validacao.toFixed(1)}ms banco=${medidas.banco.toFixed(1)}ms ` +
    `total=${medidas.total.toFixed(1)}ms${t ? ` cliente[${t}]` : ""} ` +
    `encoding=${req.get("content-encoding") || "nenhum"}`
  );
}

/// Onde eu leio o veredito. Media por requisicao e por linha — que e o numero que
/// decide entre Arrow, gzip, ou nada.
app.get("/api/physiome/ingest/perfil", (_req, res) => {
  const n = perfil.requisicoes || 1;
  res.json({
    ...perfil,
    media_por_requisicao: Object.fromEntries(
      Object.entries(perfil.ms).map(([k, v]) => [k, +(v / n).toFixed(2)])
    ),
    bytes_por_linha: perfil.linhas ? +(perfil.bytes / perfil.linhas).toFixed(1) : 0,
    linhas_por_segundo: perfil.ms.total ? +(perfil.linhas / (perfil.ms.total / 1000)).toFixed(0) : 0,
    cliente_encode_ms_medio: perfil.cliente.amostras
      ? +(perfil.cliente.encode_ms / perfil.cliente.amostras).toFixed(2) : null,
  });
});

app.get("/healthz", (_req, res) => res.json({ ok: true }));

function authed(req) {
  if (!INGEST_TOKEN) return true; // unset = open (dev); set in prod
  const auth = req.get("authorization") || "";
  return auth === `Bearer ${INGEST_TOKEN}`;
}

app.post("/api/physiome/ingest", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  const tEntrada = marco();
  try {
    const { health_samples, weather_obs, received, rejected } = validateBatch(req.body || {});
    const tValidado = marco();
    const health = await upsertHealthSamples(pool, health_samples);
    const weather = await upsertWeather(pool, weather_obs);
    const tGravado = marco();

    // leitura = ler o corpo do socket; parse = JSON.parse dentro do express.json.
    // Separo os dois porque só o parse é o que Arrow eliminaria.
    anotar(req, {
      leitura:   (req._tLido || tEntrada) - (req._t0 || tEntrada),
      parse:     tEntrada - (req._tLido || tEntrada),
      validacao: tValidado - tEntrada,
      banco:     tGravado - tValidado,
      total:     tGravado - (req._t0 || tEntrada),
    }, (health_samples?.length || 0) + (weather_obs?.length || 0));
    if (rejected.health || rejected.weather) {
      console.warn(`[physiome] ingest dropped invalid samples: health=${rejected.health}/${received.health} weather=${rejected.weather}/${received.weather}`);
    }
    res.json({ ok: true, ingested: { health, weather }, received, rejected });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

// Correlation insights: body (HRV/sleep/mood/HR) × environment+space (pressure/Kp/solar wind),
// over a rolling window with lag scan. Read-only; same auth gate as ingest.
app.get("/api/physiome/correlations", async (req, res) => {
  if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
  try {
    const days = Math.min(Math.max(Number(req.query.days) || 30, 7), 365);
    const minN = Math.max(Number(req.query.minN) || 7, 3);
    const aggs = await aggregateRange(pool, days);
    const result = correlatePhysiome(aggs, { minN });
    res.json({ ok: true, window_days: days, ...result, summary: summarizeCorrelations(result) });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
});

app.listen(PORT, () => console.log(`[physiome] ingest listening on :${PORT}`));
