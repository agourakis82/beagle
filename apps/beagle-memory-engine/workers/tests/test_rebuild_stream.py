import importlib.util
import sys
from pathlib import Path

import pytest

WORKERS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKERS))
import semantic_backbone as sb  # noqa: E402

_HAS_LANCEDB = importlib.util.find_spec("lancedb") is not None

FIX = Path(__file__).parent / "fixtures" / "export_small.json"


class StubEncoder:
    backend = "stub"

    def encode(self, text, is_query=False):
        return [[0.0] * sb.DIM]  # one token-vector; shape matches arrow_schema list(list(float32, DIM))


def _args(tmp, full=False):
    import argparse
    # output/fallback_model/reranker_model are required by rebuild()'s payload + write_json;
    # the plan's _args omitted them, so add them here to let the roundtrip actually execute.
    return argparse.Namespace(export=str(FIX), model="stub", table="semantic_memory_v1",
                              lancedb_path=str(tmp), full=full,
                              output=str(Path(tmp) / "rebuild_out.json"),
                              fallback_model="stub-fallback", reranker_model="stub-reranker")


@pytest.mark.skipif(not _HAS_LANCEDB, reason="lancedb not installed in test env")
def test_full_then_incremental_roundtrip(tmp_path, monkeypatch):
    monkeypatch.setattr(sb, "ColbertEncoder", lambda *_a, **_k: StubEncoder())
    # full build
    out = sb.rebuild(_args(tmp_path, full=True))
    assert out["row_count"] >= 4
    assert out["rebuild_mode"] in ("full", "full-fallback")
    # second run with an unchanged corpus → incremental, nothing upserted
    out2 = sb.rebuild(_args(tmp_path, full=False))
    assert out2["rebuild_mode"] == "incremental"
    assert out2["row_count"] == out["row_count"]
