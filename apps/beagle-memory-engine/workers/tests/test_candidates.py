import json, sys
from pathlib import Path

WORKERS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKERS))
import semantic_backbone as sb  # noqa: E402

FIX = Path(__file__).parent / "fixtures" / "export_small.json"

def test_collect_candidates_baseline():
    export = sb.load_json(str(FIX))
    cands, restricted = sb.collect_candidates(export)
    ids = [c["canonical_id"] for c in cands]
    # episode, atom at1, world, one passage window (the empty turn yields nothing); restricted at2 excluded
    assert restricted == 1
    assert "ep1" in ids and "at1" in ids and "w1" in ids
    assert any(i.startswith("passage:pa1:0:") for i in ids)
    assert "at2" not in ids
    # every candidate is text-bearing and carries a content_hash
    assert all(c["text"].strip() and c["content_hash"] for c in cands)


def test_iter_candidates_matches_collect():
    export = sb.load_json(str(FIX))
    expected, _ = sb.collect_candidates(export)
    got = list(sb.iter_candidates(str(FIX)))
    assert got == expected  # same rows, same order, byte-identical dicts


def test_iter_candidates_counts_restricted():
    stats = {"restricted_excluded": 0}
    list(sb.iter_candidates(str(FIX), stats))
    assert stats["restricted_excluded"] == 1


def test_iter_candidates_numeric_provenance_serializable(tmp_path):
    # Regression: ijson defaults to Decimal -> json.dumps crashes. Provenance/source_refs with
    # numbers must round-trip identically to json.load (use_float=True).
    import json as _j
    exp = tmp_path / "num.json"
    exp.write_text(_j.dumps({
        "episodes": [], "worlds": [], "passages": [],
        "atoms": [{
            "id": "n1", "text": "atom with numeric provenance", "privacy_class": "sensitive",
            "content_hash": "h-n1",
            "provenance": {"score": 1.5, "n": 3, "nested": {"k": 2.0}},
            "source_refs": [{"w": 0.25, "i": 7}],
        }],
    }))
    expected, _ = sb.collect_candidates(sb.load_json(str(exp)))
    got = list(sb.iter_candidates(str(exp)))
    assert got == expected, "streaming must match json.load on numeric fields"
    # and the produced provenance/source_refs strings must be valid JSON (no Decimal)
    for c in got:
        _j.loads(c["provenance"]); _j.loads(c["source_refs"])
