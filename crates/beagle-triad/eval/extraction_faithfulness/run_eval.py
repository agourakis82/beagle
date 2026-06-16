#!/usr/bin/env python3
"""Eval #2 — NL->formal extraction faithfulness on clinical prose (CPP2026).

Measures the load-bearing weak link the deep-research synthesis flagged: how
faithfully the production extraction model (deepseek-chat) translates a clinical
NL claim into the solver-checkable artifact, and where it breaks (per trap type).

Pipeline per case (uses BOTH production services, end-to-end):
  1. EXTRACT: run the EXACT production extraction prompt (parsed verbatim from
     crates/beagle-triad/src/lib.rs) on the claim via the LiteLLM router.
  2. SOLVE: feed the extracted artifact to the live Sounio verb (sounio-inference).
  3. SCORE: compare the solver VERDICT to the curated gold verdict.

Verdict-match is a strong faithfulness proxy here BY DESIGN: every trap case is
constructed so that a mistranslation (sign flip, variable split, missing unit
conversion, wrong op, invented edge) flips the verdict. `no_valid_extraction`
cases are faithful iff the extractor correctly abstains.

Honest scope: this measures extraction faithfulness via the verdict (what the
pipeline actually acts on); it is not a structural artifact diff. Two distinct
wrong artifacts that happen to share a verdict would be scored faithful — the
traps are built to avoid that coincidence, but the proxy is noted.

Run (needs router + sounio-inference reachable):
  ROUTER=http://127.0.0.1:14000  SOUNIO=http://10.0.1.242:8799 \
    python3 run_eval.py [corpus.jsonl] [out_dir]
"""
import json, os, re, sys, urllib.request, urllib.error
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE.parent.parent / "src" / "lib.rs"
ROUTER = os.environ.get("ROUTER", "http://127.0.0.1:14000").rstrip("/")
SOUNIO = os.environ.get("SOUNIO", "http://10.0.1.242:8799").rstrip("/")
MODEL = os.environ.get("EXTRACT_MODEL", "deepseek-chat")
GUM_UNDERSTATED_FACTOR = 0.8  # mirrors lib.rs: claimed < 0.8*u_c => understated

# ---- extract the EXACT production prompts from lib.rs (verbatim) -------------
def extract_prompt(src: str, start_marker: str) -> str:
    """Pull the Rust string literal that begins with `start_marker` (a unique
    opening phrase of one `let prompt = format!(\"...\")`), unescape it, and
    return the template (with the trailing draft placeholder `{}` intact)."""
    mi = src.index(start_marker)
    # back up to the opening quote of the literal
    q = src.rfind('"', 0, mi)
    i = q + 1
    out = []
    while i < len(src):
        c = src[i]
        if c == "\\":
            out.append(src[i : i + 2])
            i += 2
            continue
        if c == '"':
            break
        out.append(c)
        i += 1
    raw = "".join(out)
    # 1) string continuations: backslash + real newline + leading ws  -> removed
    raw = re.sub(r"\\\n[ \t]*", "", raw)
    # 2) standard escapes
    raw = raw.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\\\", "\\")
    # 3) format! literal braces
    raw = raw.replace("{{", "{").replace("}}", "}")
    return raw

SRC = LIB.read_text(encoding="utf-8")
PROMPTS = {
    "smt": extract_prompt(SRC, "Extraia afirmações quantitativas LINEARES"),
    "causal": extract_prompt(SRC, "Extraia DO TEXTO abaixo, SE E SOMENTE SE houver afirmações causais"),
    "gum": extract_prompt(SRC, "Extraia DO TEXTO abaixo, SE E SOMENTE SE houver uma grandeza DERIVADA"),
}
# Each extraction template ends with "=== TEXTO ===\n{}" — one draft placeholder.
for k, p in PROMPTS.items():
    assert p.count("{}") == 1, f"{k} prompt: expected exactly one draft placeholder, got {p.count('{}')}"

def build_prompt(domain: str, claim: str) -> str:
    return PROMPTS[domain].replace("{}", claim)

# ---- HTTP helpers -----------------------------------------------------------
def post_json(url: str, body: dict, timeout=90):
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)

def chat(prompt: str) -> str:
    body = {"model": MODEL, "temperature": 0, "max_tokens": 2048,
            "messages": [{"role": "user", "content": prompt}]}
    d = post_json(f"{ROUTER}/v1/chat/completions", body)
    return d["choices"][0]["message"]["content"]

def first_json_object(s: str):
    start = s.find("{")
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(s)):
        if s[i] == "{":
            depth += 1
        elif s[i] == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(s[start : i + 1])
                except Exception:
                    return None
    return None

# ---- per-domain: artifact -> solver verdict ---------------------------------
def smt_verdict(art):
    cons = []
    for c in (art.get("constraints") or []):
        coeffs = c.get("coeffs")
        bound = c.get("bound")
        if not isinstance(coeffs, list) or not all(isinstance(x, int) for x in coeffs):
            continue
        if not isinstance(bound, int):
            continue
        cons.append({"coeffs": coeffs, "bound": bound, "label": c.get("label")})
    if len(cons) < 2:
        return "abstain"
    d = post_json(f"{SOUNIO}/v1/smt/check", {"constraints": cons})
    return d.get("result", "UNKNOWN")

def gum_verdict(art):
    if not art.get("found", True):
        return "abstain"
    a, b = art.get("a"), art.get("b")
    op = (art.get("op") or "").lower()
    cu = art.get("claimed_uncertainty")
    if not (a and b and op in ("add", "sub", "mul", "div")) or not isinstance(cu, (int, float)) or cu <= 0:
        return "abstain"
    try:
        inputs = [{"value": float(a["value"]), "u": float(a["u"])},
                  {"value": float(b["value"]), "u": float(b["u"])}]
    except Exception:
        return "abstain"
    d = post_json(f"{SOUNIO}/v1/gum/propagate", {"inputs": inputs, "op": op})
    uc = d.get("combined_std_uncertainty")
    if not isinstance(uc, (int, float)) or uc <= 0:
        return "abstain"
    return "gum-understated" if cu < GUM_UNDERSTATED_FACTOR * uc else "gum-ok"

def causal_verdict(art):
    nodes = art.get("nodes") or []
    edges = art.get("edges") or []
    claim = (art.get("claim") or "").strip()
    if not nodes or not claim or len(nodes) < 2:
        return "abstain"
    n = len(nodes)
    x, y = art.get("x"), art.get("y")
    z = art.get("z") or []
    if not isinstance(x, int) or not isinstance(y, int) or x >= n or y >= n or x == y:
        return "abstain"
    ed = []
    for e in edges:
        if isinstance(e, list) and len(e) == 2 and all(isinstance(v, int) and v < n for v in e):
            ed.append([e[0], e[1]])
    if not ed:
        return "abstain"
    d = post_json(f"{SOUNIO}/v1/causal/dsep", {"n": n, "edges": ed, "x": x, "y": y, "z": z})
    return "d-separated" if d.get("d_separated") else "d-connected"

VERDICT_FN = {"smt": smt_verdict, "gum": gum_verdict, "causal": causal_verdict}

# ---- run --------------------------------------------------------------------
def run_once(cases):
    """One trial: extract + solve + score every case. Returns a list of per-case
    dicts. LLM extraction is nondeterministic even at temp 0, so callers should
    run several trials (TRIALS env) and aggregate mean +/- std."""
    out = []
    for i, c in enumerate(cases):
        domain, trap, gold = c["domain"], c["trap_type"], c["gold_verdict"]
        gold_norm = "abstain" if gold == "abstain" else gold
        try:
            raw = chat(build_prompt(domain, c["nl_claim"]))
            art = first_json_object(raw)
            got = VERDICT_FN[domain](art) if art is not None else "abstain"
            err = None
        except Exception as e:
            got, err = "ERROR", str(e)[:160]
        out.append({"id": f"{domain}-{trap}-{i:02d}", "domain": domain, "trap_type": trap,
                    "lang": c.get("lang", ""), "gold": gold_norm, "got": got,
                    "faithful": got == gold_norm, "error": err})
    return out


def main():
    import statistics
    corpus = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "corpus.jsonl"
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE
    trials = int(os.environ.get("TRIALS", "5"))
    cases = [json.loads(l) for l in corpus.read_text().splitlines() if l.strip() and not l.startswith("#")]

    def rate(rs):
        return (sum(1 for r in rs if r["faithful"]) / len(rs)) if rs else float("nan")

    trial_runs = []
    per_overall, per_domain_series = [], {}
    for t in range(trials):
        rs = run_once(cases)
        trial_runs.append(rs)
        per_overall.append(rate(rs))
        bd = {}
        for r in rs:
            bd.setdefault(r["domain"], []).append(r)
        for d, drs in bd.items():
            per_domain_series.setdefault(d, []).append(rate(drs))
        print(f"trial {t + 1}/{trials}: overall={per_overall[-1]:.3f}  "
              + " ".join(f"{d}={rate(drs):.2f}" for d, drs in sorted(bd.items())))

    def ms(xs):
        return (statistics.mean(xs), (statistics.pstdev(xs) if len(xs) > 1 else 0.0))

    # per-case stability: fraction of trials the case was faithful
    ncases = len(cases)
    case_faithful_frac = []
    for i in range(ncases):
        fr = sum(1 for rs in trial_runs if rs[i]["faithful"]) / trials
        meta = trial_runs[0][i]
        gots = sorted({rs[i]["got"] for rs in trial_runs})
        case_faithful_frac.append({"id": meta["id"], "domain": meta["domain"], "trap_type": meta["trap_type"],
                                   "lang": meta["lang"], "gold": meta["gold"],
                                   "faithful_frac": fr, "verdicts_seen": gots})

    o_mean, o_std = ms(per_overall)
    by_domain = {d: {"mean": ms(s)[0], "std": ms(s)[1], "trials": s} for d, s in sorted(per_domain_series.items())}
    # per (domain,trap) mean over trials
    dt_series = {}
    for rs in trial_runs:
        bdt = {}
        for r in rs:
            bdt.setdefault((r["domain"], r["trap_type"]), []).append(r)
        for k, v in bdt.items():
            dt_series.setdefault(k, []).append(rate(v))
    by_trap = {f"{d}/{t}": {"mean": ms(s)[0], "std": ms(s)[1]} for (d, t), s in sorted(dt_series.items())}

    report = {"eval": "extraction-faithfulness-clinical", "model": MODEL, "n": ncases, "trials": trials,
              "overall_faithfulness_mean": o_mean, "overall_faithfulness_std": o_std,
              "by_domain": by_domain, "by_domain_trap": by_trap,
              "per_case_stability": case_faithful_frac}
    (out_dir / "results.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))

    md = ["# Eval #2 — NL→formal extraction faithfulness (clinical prose)\n",
          f"model: `{MODEL}` · {ncases} cases · **{trials} trials** (temp 0; LLM still nondeterministic)\n",
          f"**Overall faithfulness: {o_mean:.3f} ± {o_std:.3f}**\n",
          "## By domain (mean ± std over trials)\n", "| domain | mean | std |", "|---|---|---|"]
    for d, v in by_domain.items():
        md.append(f"| {d} | {v['mean']:.3f} | {v['std']:.3f} |")
    md += ["\n## By trap type\n", "| domain / trap | mean | std |", "|---|---|---|"]
    for k, v in by_trap.items():
        md.append(f"| {k} | {v['mean']:.3f} | {v['std']:.3f} |")
    flaky = [c for c in case_faithful_frac if 0.0 < c["faithful_frac"] < 1.0]
    md += ["\n## Unstable cases (verdict flips across trials)\n",
           f"{len(flaky)} of {ncases} cases were nondeterministic across {trials} trials:" if flaky else "None — all cases stable across trials."]
    for c in flaky:
        md.append(f"- `{c['id']}` (gold={c['gold']}) faithful {c['faithful_frac']:.0%} of trials, verdicts seen: {c['verdicts_seen']}")
    md.append("\n_Faithful = live Sounio verdict on the extracted artifact matches the solver-derived gold verdict. "
              "Trap cases are built so a mistranslation flips the verdict; `no_valid_extraction` is faithful iff the extractor abstains._")
    (out_dir / "results.md").write_text("\n".join(md) + "\n")

    print(f"\noverall faithfulness = {o_mean:.3f} ± {o_std:.3f}  (n={ncases}, {trials} trials)")
    print("by domain:", {d: f"{v['mean']:.2f}±{v['std']:.2f}" for d, v in by_domain.items()})
    print(f"{len(flaky)} unstable case(s); wrote results.json + results.md")


if __name__ == "__main__":
    main()
