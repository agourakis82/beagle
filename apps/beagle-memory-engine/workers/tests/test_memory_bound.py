import json, sys, tracemalloc
from pathlib import Path
WORKERS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKERS))
import semantic_backbone as sb  # noqa: E402

def _make_big_export(path, n_passages=4000, turns=4, chars=3000):
    blob = "x" * chars
    with open(path, "w", encoding="utf-8") as fh:
        fh.write('{"episodes":[],"atoms":[],"worlds":[],"passages":[')
        for i in range(n_passages):
            if i:
                fh.write(",")
            rec = {"id": f"pa{i}", "privacy_class": "sensitive", "occurred_at": "2026-01-01",
                   "session_id": "s", "source_platform": "x",
                   "turns": [{"content": blob} for _ in range(turns)]}
            fh.write(json.dumps(rec))
        fh.write("]}")

def test_streaming_manifest_peak_below_full_load(tmp_path):
    p = tmp_path / "big.json"
    _make_big_export(str(p))
    # baseline: json.load whole file
    tracemalloc.start()
    export = sb.load_json(str(p)); _ = len(export["passages"])
    full_peak = tracemalloc.get_traced_memory()[1]; tracemalloc.stop()
    del export
    # streaming manifest pass
    tracemalloc.start()
    cur = {}
    for c in sb.iter_candidates(str(p)):
        cur[c["canonical_id"]] = c["content_hash"]
    stream_peak = tracemalloc.get_traced_memory()[1]; tracemalloc.stop()
    # streaming peak must be a fraction of the full-load peak
    assert stream_peak < full_peak * 0.5, f"stream={stream_peak} full={full_peak}"
    assert len(cur) > 0
