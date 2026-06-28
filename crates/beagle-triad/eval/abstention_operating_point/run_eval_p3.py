#!/usr/bin/env python3
"""Eval #3 — P3 self-consistency abstention operating point (CPP2026).

P3 runs the extraction k times and trusts the artifact only if >= `agree` of the k
runs agree on it (majority for smt/theorem, unanimous for causal/gum); otherwise it
abstains. This eval sweeps (k, agreement) and measures the coverage vs precision
trade-off, answering the deep-research open Q4: what abstention operating point
trades coverage against the factual-domain autoformalization harm?

Sharp hypothesis (from eval #2): the extraction failures were DETERMINISTIC
(0 variance across 5 trials). Self-consistency catches NOISY disagreement, not
CONFIDENT wrongness — so if the k runs all agree on the same wrong artifact, P3
will NOT abstain and precision-on-trusted will not improve. This eval tests that.

Method: collect K_MAX extractions per case once (cached), then evaluate every
(k, mode) config offline against the cache using P3's per-domain canonical key.

Reuses run_eval.py (same prompts parsed from lib.rs, same live verbs for scoring).

Run:
  K_MAX=5 ROUTER=http://127.0.0.1:14000 SOUNIO=http://10.0.1.242:8799 \
    python3 run_eval_p3.py [corpus.jsonl] [out_dir]
"""
import json, os, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "extraction_faithfulness"))
import run_eval as R  # chat, build_prompt, first_json_object, VERDICT_FN, PROMPTS

K_MAX = int(os.environ.get("K_MAX", "5"))

# ---- P3 canonical keys (mirror lib.rs intent) -------------------------------
def smt_key(art):
    if not art:
        return None
    cons = art.get("constraints") or []
    items = []
    for c in cons:
        coeffs = c.get("coeffs")
        bound = c.get("bound")
        if not isinstance(coeffs, list) or not isinstance(bound, int):
            return None
        lbl = (c.get("label") or "").strip()
        items.append(f"{lbl}|{bound}|{sorted(coeffs)}")
    if len(items) < 2:
        return "ABSTAIN"  # extractor declined / too few constraints
    return "||".join(sorted(items))

def gum_key(art):
    if not art or not art.get("found", False):
        return "ABSTAIN"
    op = (art.get("op") or "").lower()
    a = (art.get("a") or {}).get("label", "")
    b = (art.get("b") or {}).get("label", "")
    cu = art.get("claimed_uncertainty")
    cu = round(float(cu), 3) if isinstance(cu, (int, float)) else None
    return f"{op}|{a}|{b}|{cu}"

def causal_key(art):
    if not art:
        return None
    nodes = art.get("nodes") or []
    claim = (art.get("claim") or "").strip()
    if not nodes or not claim:
        return "ABSTAIN"
    edges = art.get("edges") or []
    es = sorted(f"{e[0]}->{e[1]}" for e in edges if isinstance(e, list) and len(e) == 2)
    return f"x{art.get('x')}y{art.get('y')}|{','.join(es)}"

KEY_FN = {"smt": smt_key, "gum": gum_key, "causal": causal_key}

def threshold(mode, k):
    return k if mode == "unanimous" else (k // 2 + 1)  # majority

def main():
    corpus = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "extraction_faithfulness" / "corpus.jsonl"
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE
    cases = [json.loads(l) for l in corpus.read_text().splitlines() if l.strip() and not l.startswith("#")]

    # ---- collect K_MAX extractions per case (cached) ----
    cache = []
    for i, c in enumerate(cases):
        domain = c["domain"]
        arts = []
        for _ in range(K_MAX):
            try:
                arts.append(R.first_json_object(R.chat(R.build_prompt(domain, c["nl_claim"]))))
            except Exception:
                arts.append(None)
        # full-info reference verdict (faithfulness of a single best-effort extraction)
        gold = "abstain" if c["gold_verdict"] == "abstain" else c["gold_verdict"]
        ref_verdict = R.VERDICT_FN[domain](arts[0]) if arts[0] is not None else "abstain"
        cache.append({"i": i, "domain": domain, "trap": c["trap_type"], "gold": gold,
                      "arts": arts, "ref_faithful": ref_verdict == gold})
        print(f"cached {domain}/{c['trap_type']} ({i+1}/{len(cases)})")

    # ---- evaluate configs offline ----
    configs = [(1, "majority"), (3, "majority"), (5, "majority"), (3, "unanimous"), (5, "unanimous")]
    # production policy: smt/theorem majority(k=3), causal/gum unanimous(k=3)
    prod_policy = {"smt": (3, "majority"), "gum": (3, "unanimous"), "causal": (3, "unanimous")}

    def eval_config(get_km):
        """get_km(domain) -> (k, mode). Returns (coverage, precision, n_trusted, n,
        abstained_unfaithful, total_unfaithful)."""
        trusted = faithful = 0
        ab_unfaithful = tot_unfaithful = 0
        n = len(cache)
        for e in cache:
            k, mode = get_km(e["domain"])
            arts = e["arts"][:k]
            keys = [KEY_FN[e["domain"]](a) for a in arts]
            # majority key among the k
            counts = {}
            for kk in keys:
                if kk is None:
                    continue
                counts[kk] = counts.get(kk, 0) + 1
            if not counts:
                top_key, votes = None, 0
            else:
                top_key, votes = max(counts.items(), key=lambda kv: kv[1])
            is_trusted = top_key is not None and top_key != "ABSTAIN" and votes >= threshold(mode, k)
            # reference (full info) faithfulness for harm accounting
            if not e["ref_faithful"]:
                tot_unfaithful += 1
            if is_trusted:
                trusted += 1
                rep = arts[keys.index(top_key)]
                v = R.VERDICT_FN[e["domain"]](rep)
                if v == e["gold"]:
                    faithful += 1
            else:
                # abstained
                if not e["ref_faithful"]:
                    ab_unfaithful += 1
        cov = trusted / n
        prec = (faithful / trusted) if trusted else float("nan")
        return cov, prec, trusted, n, ab_unfaithful, tot_unfaithful

    rows = []
    for k, mode in configs:
        cov, prec, nt, n, abu, tot = eval_config(lambda d, k=k, mode=mode: (k, mode))
        rows.append({"config": f"k={k}/{mode}", "coverage": cov, "precision_on_trusted": prec,
                     "trusted": nt, "n": n, "abstained_unfaithful": abu, "total_unfaithful": tot})
    covp, precp, ntp, n, abup, totp = eval_config(lambda d: prod_policy[d])
    rows.append({"config": "production-policy", "coverage": covp, "precision_on_trusted": precp,
                 "trusted": ntp, "n": n, "abstained_unfaithful": abup, "total_unfaithful": totp})

    report = {"eval": "p3-abstention-operating-point", "model": R.MODEL, "k_max": K_MAX,
              "n": len(cache), "configs": rows,
              "per_case": [{"id": f"{e['domain']}-{e['trap']}-{e['i']:02d}", "domain": e["domain"],
                            "trap": e["trap"], "gold": e["gold"], "ref_faithful": e["ref_faithful"],
                            "distinct_keys_k5": len({KEY_FN[e["domain"]](a) for a in e["arts"]})}
                           for e in cache]}
    (out_dir / "results.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))

    md = ["# Eval #3 — P3 self-consistency abstention operating point\n",
          f"model: `{R.MODEL}` · {len(cache)} cases · K_MAX={K_MAX}\n",
          "| config | coverage | precision(trusted) | abstained-unfaithful / total-unfaithful |",
          "|---|---|---|---|"]
    for r in rows:
        md.append(f"| {r['config']} | {r['coverage']:.3f} | {r['precision_on_trusted']:.3f} "
                  f"| {r['abstained_unfaithful']}/{r['total_unfaithful']} |")
    # how often did the 5 extractions actually disagree?
    flaky = sum(1 for e in cache if len({KEY_FN[e['domain']](a) for a in e['arts']}) > 1)
    md.append(f"\nExtraction key disagreement across K={K_MAX}: **{flaky}/{len(cache)}** cases. "
              "Self-consistency can only abstain where the k runs disagree; deterministic mistranslations "
              "(all k agree on the same wrong artifact) are invisible to it.")
    md.append("\n_coverage = fraction trusted (not abstained); precision = faithful among trusted; "
              "abstained-unfaithful = of cases whose single-shot verdict is unfaithful, how many P3 abstained on._")
    (out_dir / "results.md").write_text("\n".join(md) + "\n")

    print("\n=== P3 abstention operating point ===")
    for r in rows:
        print(f"{r['config']:>18}: coverage={r['coverage']:.3f} precision={r['precision_on_trusted']:.3f} "
              f"caught-unfaithful={r['abstained_unfaithful']}/{r['total_unfaithful']}")
    print(f"key-disagreement across K={K_MAX}: {flaky}/{len(cache)} cases")

if __name__ == "__main__":
    main()
