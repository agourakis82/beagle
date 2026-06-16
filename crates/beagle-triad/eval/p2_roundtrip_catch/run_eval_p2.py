#!/usr/bin/env python3
"""Eval — P2 (SymbCoT round-trip) catch rate (layer-2, CPP2026).

Does the P2 semantic-faithfulness check (`verify_translation_faithfulness`) abstain
on a mistranslated artifact and pass a faithful one? Eval #3 showed self-consistency
cannot catch deterministic mistranslation; the deep-research synthesis says the round-
trip check is the right lever. This measures whether it actually is.

Controlled labeled set (by construction, like eval #1):
  - FAITHFUL pair  = (claim, GOLD artifact)            -> P2 should PASS (equivalent)
  - UNFAITHFUL pair = (claim, CORRUPTED gold artifact) -> P2 should ABSTAIN
    corruptions: smt sign-flip; gum op-swap; gum unit-desync; causal spurious-edge.

Uses the EXACT production P2 prompt (parsed verbatim from lib.rs) on the router.

Metrics:
  recall  = abstain rate on UNFAITHFUL pairs (the catch rate, per corruption)
  false-abstain = abstain rate on FAITHFUL pairs (over-caution)

Run:
  ROUTER=http://127.0.0.1:14000 python3 run_eval_p2.py [corpus.jsonl] [out_dir]
"""
import json, os, sys, copy
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "extraction_faithfulness"))
import run_eval as R

# P2 prompt verbatim from lib.rs (3 placeholders: source, NL desc, JSON)
P2_TMPL = R.extract_prompt(R.SRC, "You are a semantic faithfulness verifier")
assert P2_TMPL.count("{}") == 3, f"P2 prompt: expected 3 placeholders, got {P2_TMPL.count('{}')}"

def p2_prompt(source, nl_desc, formal_json):
    parts = P2_TMPL.split("{}")
    return parts[0] + source + parts[1] + nl_desc + parts[2] + formal_json + (parts[3] if len(parts) > 3 else "")

def p2_abstains(source, nl_desc, formal_json):
    """Returns True if P2 says NOT equivalent (abstain), False if equivalent (pass)."""
    txt = R.chat(p2_prompt(source, nl_desc, formal_json))
    obj = R.first_json_object(txt)
    if not obj or "equivalent" not in obj:
        return False  # mirror lib.rs: unparseable -> pass (benefit of the doubt)
    return obj.get("equivalent") is False

# ---- (B) NL back-translation + (C) solver JSON — EXACT mirror of lib.rs ------
def nl_desc(domain, art):
    if domain == "smt":
        lines = []
        for c in (art.get("constraints") or []):
            label = c.get("label") or "constraint"
            nz = [(i, k) for i, k in enumerate(c.get("coeffs") or []) if k != 0]
            b = c.get("bound")
            if len(nz) == 1 and nz[0][1] == 1:
                lines.append(f"{label}: the quantity must be <= {b}")
            elif len(nz) == 1 and nz[0][1] == -1:
                lines.append(f"{label}: the quantity must be >= {-b}")
            else:
                lines.append(f"{label}: sum({c.get('coeffs')})·x <= {b}")
        return ("The following linear integer constraints (over the same shared variable unless noted) "
                "were extracted from the claim: " + "; ".join(lines))
    if domain == "gum":
        a, b = art.get("a", {}), art.get("b", {})
        op = art.get("op")
        al, bl, yl = a.get("label", "A"), b.get("label", "B"), art.get("y_label", "Y")
        return (f"The derived quantity '{yl}' is computed as '{al}' {op} '{bl}' using the {op} operation. "
                f"Input '{al}' has value {float(a.get('value',0)):.4f} ± {float(a.get('u',0)):.4f}; "
                f"input '{bl}' has value {float(b.get('value',0)):.4f} ± {float(b.get('u',0)):.4f}. "
                f"The draft declares uncertainty ±{float(art.get('claimed_uncertainty',0)):.4f} for the derived quantity.")
    if domain == "causal":
        names = art.get("nodes") or []
        x, y = art.get("x", 0), art.get("y", 0)
        xn = names[x] if x < len(names) else f"node{x}"
        yn = names[y] if y < len(names) else f"node{y}"
        z = art.get("z") or []
        cond = ", ".join(names[i] if i < len(names) else f"node{i}" for i in z)
        edges = art.get("edges") or []
        elist = ", ".join(f"{names[e[0]] if e[0]<len(names) else '?'}→{names[e[1]] if e[1]<len(names) else '?'}"
                          for e in edges if isinstance(e, list) and len(e) == 2)
        return (f"A directed acyclic graph with nodes [{', '.join(names)}] and {len(edges)} "
                f"directed edge(s) [{elist}] was extracted. The query asks whether '{xn}' and '{yn}' are d-separated "
                f"given conditioning set {{{cond}}}. The draft claims they have a causal/dependency "
                f"relation: '{art.get('claim','')}'")
    return json.dumps(art)

def fjson(domain, art):
    """(C) = the EXACT JSON payload POSTed to the solver (mirrors the Rust request struct)."""
    if domain == "smt":
        cons = [{"coeffs": c.get("coeffs"), "bound": c.get("bound"), **({"label": c["label"]} if c.get("label") else {})}
                for c in (art.get("constraints") or [])]
        return json.dumps({"constraints": cons}, ensure_ascii=False)
    if domain == "gum":
        a, b = art.get("a", {}), art.get("b", {})
        inputs = [{"value": a.get("value"), "u": a.get("u"), **({"label": a["label"]} if a.get("label") else {})},
                  {"value": b.get("value"), "u": b.get("u"), **({"label": b["label"]} if b.get("label") else {})}]
        return json.dumps({"inputs": inputs, "op": art.get("op")}, ensure_ascii=False)
    if domain == "causal":
        nodes = art.get("nodes") or []
        return json.dumps({"n": len(nodes), "edges": art.get("edges") or [],
                           "x": art.get("x"), "y": art.get("y"), "z": art.get("z") or []}, ensure_ascii=False)
    return json.dumps(art, ensure_ascii=False)

# ---- corruptions (produce an UNFAITHFUL artifact) ---------------------------
def corrupt(domain, art):
    out = []
    if domain == "smt":
        c = copy.deepcopy(art)
        if c.get("constraints"):
            con = c["constraints"][0]
            con["coeffs"] = [-x for x in con.get("coeffs", [])]
            con["bound"] = -con.get("bound", 0)  # flip the inequality direction
            out.append(("sign_flip", c))
    elif domain == "gum":
        c = copy.deepcopy(art)
        swap = {"div": "sub", "mul": "add", "add": "div", "sub": "mul"}
        c["op"] = swap.get(c.get("op", "div"), "add")  # wrong operator
        out.append(("op_swap", c))
        c2 = copy.deepcopy(art)
        if c2.get("a"):  # desync units: scale A's value+u by 1000, label unchanged
            c2["a"]["value"] = c2["a"].get("value", 0) * 1000
            c2["a"]["u"] = c2["a"].get("u", 0) * 1000
            out.append(("unit_desync", c2))
    elif domain == "causal":
        c = copy.deepcopy(art)
        x, y = c.get("x"), c.get("y")
        if isinstance(x, int) and isinstance(y, int):
            c.setdefault("edges", []).append([x, y])  # spurious direct edge x->y
            out.append(("spurious_edge", c))
    return out

def main():
    corpus = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "extraction_faithfulness" / "corpus.jsonl"
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE
    cases = [json.loads(l) for l in corpus.read_text().splitlines() if l.strip() and not l.startswith("#")]

    trials = int(os.environ.get("TRIALS", "3"))
    # build the labeled pairs once
    pairs = []  # (kind, domain, label, claim, B, C)
    for c in cases:
        gj = c["gold_artifact_json"].strip()
        if gj == "null":
            continue
        art = json.loads(gj)
        domain, claim = c["domain"], c["nl_claim"]
        pairs.append(("faithful", domain, c["trap_type"], claim, nl_desc(domain, art), fjson(domain, art)))
        for ctype, cart in corrupt(domain, art):
            pairs.append(("unfaithful", domain, ctype, claim, nl_desc(domain, cart), fjson(domain, cart)))

    # run each pair `trials` times; a pair "abstains" by majority vote across trials
    faithful_rows, unfaithful_rows = [], []
    for kind, domain, label, claim, B, C in pairs:
        votes = sum(1 for _ in range(trials) if p2_abstains(claim, B, C))
        ab = votes > trials / 2  # majority abstain
        row = {"domain": domain, "label": label, "p2_abstain": ab, "abstain_votes": f"{votes}/{trials}"}
        (faithful_rows if kind == "faithful" else unfaithful_rows).append(row)
        good = (ab if kind == "unfaithful" else not ab)
        print(f"{'ok' if good else 'XX'} {kind:10s} [{domain}/{label}] abstain={ab} ({votes}/{trials})")

    def rate(rs):
        return (sum(1 for r in rs if r["p2_abstain"]) / len(rs)) if rs else float("nan")
    recall = rate(unfaithful_rows)               # caught (abstain) among unfaithful
    false_abstain = rate(faithful_rows)          # abstain among faithful (over-caution)
    by_corruption = {}
    for r in unfaithful_rows:
        by_corruption.setdefault(r["label"], []).append(r)

    report = {"eval": "p2-roundtrip-catch", "model": R.MODEL,
              "n_faithful": len(faithful_rows), "n_unfaithful": len(unfaithful_rows),
              "recall_catch": recall, "false_abstain_rate": false_abstain,
              "by_corruption": {k: {"n": len(v), "catch_rate": rate(v)} for k, v in sorted(by_corruption.items())}}
    (out_dir / "results.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))

    md = ["# Eval — P2 (SymbCoT round-trip) catch rate\n",
          f"model: `{R.MODEL}` · {len(faithful_rows)} faithful + {len(unfaithful_rows)} corrupted pairs · "
          f"**BEAGLE_TRIAD_SYMB_VERIFY must be ON** for P2 to run in prod (this eval calls the prompt directly)\n",
          "| metric | value |", "|---|---|",
          f"| recall (catch rate on mistranslations) | **{recall:.3f}** |",
          f"| false-abstain rate (on faithful gold) | {false_abstain:.3f} |", "",
          "## Catch rate by corruption type\n", "| corruption | n | catch rate |", "|---|---|---|"]
    for k, v in sorted(by_corruption.items()):
        md.append(f"| {k} | {len(v)} | {rate(v):.3f} |")
    md.append("\n_recall = P2 abstains on a deliberately-mistranslated artifact (gold sign-flipped / op-swapped / "
              "unit-desynced / spurious-edge). false-abstain = P2 wrongly abstains on the faithful gold artifact. "
              "The P2 prompt explicitly ignores unit normalization, so `unit_desync` catch rate is expected to be low._")
    (out_dir / "results.md").write_text("\n".join(md) + "\n")

    print(f"\nP2 recall (catch)={recall:.3f}  false-abstain={false_abstain:.3f}")
    print("by corruption:", {k: round(rate(v), 3) for k, v in sorted(by_corruption.items())})

if __name__ == "__main__":
    main()
