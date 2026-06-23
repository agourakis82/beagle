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
