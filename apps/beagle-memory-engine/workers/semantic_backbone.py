#!/usr/bin/env python3
"""Native semantic backbone worker for Beagle Memory Engine.

The canonical memory source is still beagle-core JSONL/Merkle/Chronoself.
This worker builds and queries a derived LanceDB multivector table. It uses
real LanceDB/Arrow multivector storage when available and falls back to a
deterministic token-vector encoder when heavyweight ColBERT runtime libraries
are not installed in the image.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

DIM = int(os.getenv("BEAGLE_MEMORY_COLBERT_DIM", "128"))
MAX_TOKENS = int(os.getenv("BEAGLE_MEMORY_COLBERT_MAX_TOKENS", "48"))
TABLE_DEFAULT = os.getenv("BEAGLE_LANCEDB_TABLE", "semantic_memory_v1")
MODEL_DEFAULT = os.getenv("BEAGLE_MEMORY_COLBERT_MODEL", "jinaai/jina-colbert-v2")
FALLBACK_MODEL_DEFAULT = os.getenv("BEAGLE_MEMORY_SOVEREIGN_EMBEDDING_MODEL", "BAAI/bge-m3")
RERANKER_DEFAULT = os.getenv(
    "BEAGLE_MEMORY_SOVEREIGN_RERANKING_MODEL",
    "Alibaba-NLP/gte-reranker-modernbert-base",
)


def load_json(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: str, payload: dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")


def tokenize(text: str) -> list[str]:
    tokens = re.findall(r"[\wÀ-ÿ./:@+-]+", (text or "").lower(), flags=re.UNICODE)
    return tokens[:MAX_TOKENS] or ["empty"]


def stable_vector(seed: str, dim: int = DIM) -> list[float]:
    values: list[float] = []
    counter = 0
    while len(values) < dim:
        digest = hashlib.sha256(f"{seed}:{counter}".encode("utf-8")).digest()
        for idx in range(0, len(digest), 4):
            raw = int.from_bytes(digest[idx : idx + 4], "little", signed=False)
            values.append((raw / 2**32) * 2.0 - 1.0)
            if len(values) == dim:
                break
        counter += 1
    norm = math.sqrt(sum(value * value for value in values)) or 1.0
    return [round(value / norm, 8) for value in values]


def deterministic_multivector(text: str) -> list[list[float]]:
    return [stable_vector(token) for token in tokenize(text)]


class ColbertEncoder:
    def __init__(self, model_name: str) -> None:
        self.model_name = model_name
        self.backend = "deterministic-token-multivector"
        self._tokenizer = None
        self._model = None
        self._torch = None
        if os.getenv("BEAGLE_COLBERT_ENABLE_MODEL", "false").lower() not in {
            "1",
            "true",
            "yes",
        }:
            return
        try:
            import torch  # type: ignore
            from transformers import AutoModel, AutoTokenizer  # type: ignore

            self._torch = torch
            self._tokenizer = AutoTokenizer.from_pretrained(model_name, trust_remote_code=True)
            self._model = AutoModel.from_pretrained(model_name, trust_remote_code=True)
            self._model.eval()
            self.backend = model_name
        except Exception as exc:  # pragma: no cover - cluster capability dependent
            self.backend = f"deterministic-token-multivector:model-unavailable:{type(exc).__name__}"
            self._tokenizer = None
            self._model = None
            self._torch = None

    def encode(self, text: str, is_query: bool = False) -> list[list[float]]:
        if self._tokenizer is None or self._model is None or self._torch is None:
            return deterministic_multivector(text)
        with self._torch.no_grad():  # pragma: no cover - cluster capability dependent
            inputs = self._tokenizer(
                text,
                truncation=True,
                max_length=MAX_TOKENS,
                return_tensors="pt",
            )
            output = self._model(**inputs)
            hidden = output.last_hidden_state[0].detach().cpu().float().numpy()
            vectors = hidden[:MAX_TOKENS, :DIM].tolist()
            return [normalize(vector) for vector in vectors]


def normalize(vector: list[float]) -> list[float]:
    norm = math.sqrt(sum(value * value for value in vector)) or 1.0
    return [round(float(value) / norm, 8) for value in vector]


def text_hash(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def record_text(item: dict[str, Any], kind: str) -> str:
    if kind == "MemoryAtom":
        return str(item.get("text") or item.get("normalized_text") or "")
    if kind == "MemoryEpisode":
        return str(item.get("summary") or item.get("content_preview") or item.get("source_ref") or "")
    if kind == "MemoryWorld":
        return " ".join(
            str(item.get(key) or "")
            for key in ("label", "summary", "project_slug", "merkle_root")
        )
    return json.dumps(item, ensure_ascii=False, sort_keys=True)[:4000]


def collect_records(export: dict[str, Any], encoder: ColbertEncoder) -> tuple[list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    restricted_count = 0
    sources = [
        ("episodes", "MemoryEpisode"),
        ("atoms", "MemoryAtom"),
        ("worlds", "MemoryWorld"),
    ]
    for field, kind in sources:
        for item in export.get(field, []) or []:
            privacy = str(item.get("privacy_class") or "sensitive").lower()
            if privacy == "restricted":
                restricted_count += 1
                continue
            text = record_text(item, kind)
            if not text.strip():
                continue
            canonical_id = str(item.get("id") or item.get("source_ref") or text_hash(text))
            records.append(
                {
                    "canonical_id": canonical_id,
                    "kind": kind,
                    "content_hash": str(item.get("content_hash") or text_hash(text)),
                    "privacy_class": privacy,
                    "source_refs": json.dumps(item.get("source_refs") or [], ensure_ascii=False),
                    "chronoself_commit": str(item.get("chronoself_commit") or ""),
                    "provenance": json.dumps(item.get("provenance") or {}, ensure_ascii=False, sort_keys=True),
                    "occurred_at": str(item.get("occurred_at") or item.get("created_at") or ""),
                    "text": text[:12000],
                    "mv": encoder.encode(text, is_query=False),
                    "embedding_backend": encoder.backend,
                }
            )
    return records, restricted_count


def open_lancedb(path: str):
    import lancedb  # type: ignore

    Path(path).mkdir(parents=True, exist_ok=True)
    return lancedb.connect(path)


def arrow_schema():
    import pyarrow as pa  # type: ignore

    return pa.schema(
        [
            pa.field("canonical_id", pa.string()),
            pa.field("kind", pa.string()),
            pa.field("content_hash", pa.string()),
            pa.field("privacy_class", pa.string()),
            pa.field("source_refs", pa.string()),
            pa.field("chronoself_commit", pa.string()),
            pa.field("provenance", pa.string()),
            pa.field("occurred_at", pa.string()),
            pa.field("text", pa.string()),
            pa.field("embedding_backend", pa.string()),
            pa.field("mv", pa.list_(pa.list_(pa.float32(), DIM))),
        ]
    )


def rebuild(args: argparse.Namespace) -> dict[str, Any]:
    started = time.time()
    export = load_json(args.export)
    encoder = ColbertEncoder(args.model)
    rows, restricted_excluded_count = collect_records(export, encoder)
    table_name = args.table
    native_lancedb = False
    index_ready = False
    worker_status = "empty"
    error: str | None = None
    try:
        db = open_lancedb(args.lancedb_path)
        table = db.create_table(table_name, data=rows, schema=arrow_schema(), mode="overwrite")
        native_lancedb = True
        worker_status = "native-lancedb-table"
        if rows:
            try:
                table.create_index(metric="cosine", vector_column_name="mv")
                index_ready = True
            except Exception as exc:  # small tables or old LanceDB may skip ANN
                error = f"index_degraded:{type(exc).__name__}:{exc}"
                index_ready = False
    except Exception as exc:
        error = f"native_lancedb_unavailable:{type(exc).__name__}:{exc}"
        fallback_path = Path(args.lancedb_path) / "semantic_records.jsonl"
        Path(args.lancedb_path).mkdir(parents=True, exist_ok=True)
        with fallback_path.open("w", encoding="utf-8") as handle:
            for row in rows:
                compact = {key: value for key, value in row.items() if key != "mv"}
                compact["vector_count"] = len(row["mv"])
                compact["vector_dim"] = DIM
                json.dump(compact, handle, ensure_ascii=False, sort_keys=True)
                handle.write("\n")
        worker_status = "jsonl-fallback"

    payload = {
        "status": "indexed-native-multivector" if native_lancedb else worker_status,
        "native_lancedb": native_lancedb,
        "table_name": table_name,
        "row_count": len(rows),
        "index_ready": index_ready,
        "maxsim_ready": native_lancedb and bool(rows),
        "embedding_backend": encoder.backend,
        "model": args.model,
        "fallback_model": args.fallback_model,
        "reranker_model": args.reranker_model,
        "restricted_leak_count": 0,
        "restricted_excluded_count": restricted_excluded_count,
        "lancedb_path": args.lancedb_path,
        "vector_dim": DIM,
        "max_tokens": MAX_TOKENS,
        "latency_ms": round((time.time() - started) * 1000, 3),
        "worker_status": worker_status,
        "error": error,
    }
    write_json(args.output, payload)
    return payload


def query(args: argparse.Namespace) -> dict[str, Any]:
    started = time.time()
    encoder = ColbertEncoder(args.model)
    rows: list[dict[str, Any]] = []
    native_lancedb = False
    error: str | None = None
    try:
        db = open_lancedb(args.lancedb_path)
        table = db.open_table(args.table)
        query_mv = encoder.encode(args.query, is_query=True)
        result = table.search(query_mv).limit(args.limit).to_arrow().to_pylist()
        native_lancedb = True
        for row in result:
            distance = row.get("_distance")
            rows.append(
                {
                    "canonical_id": row.get("canonical_id"),
                    "kind": row.get("kind"),
                    "content_hash": row.get("content_hash"),
                    "score": None if distance is None else round(1.0 - float(distance), 6),
                    "occurred_at": row.get("occurred_at"),
                    "provenance": row.get("provenance"),
                    "source_refs": row.get("source_refs"),
                    "text_preview": str(row.get("text") or "")[:500],
                }
            )
    except Exception as exc:
        error = f"query_degraded:{type(exc).__name__}:{exc}"

    payload = {
        "status": "ok" if native_lancedb else "degraded",
        "native_lancedb": native_lancedb,
        "table_name": args.table,
        "query": args.query,
        "results": rows,
        "embedding_backend": encoder.backend,
        "latency_ms": round((time.time() - started) * 1000, 3),
        "error": error,
    }
    write_json(args.output, payload)
    return payload


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Beagle native semantic backbone worker")
    sub = parser.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--lancedb-path", required=True)
    common.add_argument("--table", default=TABLE_DEFAULT)
    common.add_argument("--model", default=MODEL_DEFAULT)
    common.add_argument("--fallback-model", default=FALLBACK_MODEL_DEFAULT)
    common.add_argument("--reranker-model", default=RERANKER_DEFAULT)
    common.add_argument("--output", required=True)

    rebuild_parser = sub.add_parser("rebuild", parents=[common])
    rebuild_parser.add_argument("--export", required=True)

    query_parser = sub.add_parser("query", parents=[common])
    query_parser.add_argument("--query", required=True)
    query_parser.add_argument("--limit", type=int, default=8)

    args = parser.parse_args(argv)
    payload = rebuild(args) if args.command == "rebuild" else query(args)
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
