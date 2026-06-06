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
# Cap windows emitted per conversation turn so a pathological huge turn cannot
# explode into thousands of ColBERT-embedded windows.
MAX_WINDOWS_PER_TURN = int(os.getenv("BEAGLE_MEMORY_MAX_WINDOWS_PER_TURN", "64"))


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
        # External embedding service (cluster TEI) — real semantic embeddings without torch/GPU
        # in this pod. Returns one dense vector per text, used as a 1-element multivector
        # (MaxSim degrades to cosine). Takes precedence over the in-pod torch model.
        self.tei_url = (os.getenv("BEAGLE_TEI_EMBED_URL", "") or "").strip() or None
        if self.tei_url:
            self.backend = f"tei:{self.tei_url}"
            return
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
        if getattr(self, "tei_url", None):
            try:
                import json as _json
                import urllib.request as _u

                req = _u.Request(
                    self.tei_url,
                    data=_json.dumps({"inputs": text}).encode("utf-8"),
                    headers={"content-type": "application/json"},
                )
                with _u.urlopen(req, timeout=30) as resp:
                    out = _json.loads(resp.read().decode("utf-8"))
                # TEI returns [[...]] (batch) or [...]; normalize to a flat dense vector.
                vec = out[0] if (isinstance(out, list) and out and isinstance(out[0], list)) else out
                if isinstance(vec, list) and vec and isinstance(vec[0], (int, float)):
                    return [normalize([float(x) for x in vec])]
            except Exception:
                pass
            # On any TEI failure, degrade gracefully rather than crash the rebuild.
            return deterministic_multivector(text)
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


def chunk_text(
    text: str,
    window: int = 800,
    overlap: int = 100,
    min_chars: int = 40,
) -> list[str]:
    """Yield ~``window``-character windows (counted by characters, never bytes) with ``overlap``
    characters of carry-over between consecutive windows. Windows shorter than ``min_chars`` are
    skipped. Used to break long conversation turns into durable, individually indexed passages."""
    text = text or ""
    if not text:
        return []
    step = max(1, window - overlap)
    windows: list[str] = []
    start = 0
    length = len(text)
    while start < length:
        chunk = text[start : start + window]
        if len(chunk) >= min_chars:
            windows.append(chunk)
        if start + window >= length:
            break
        start += step
    return windows


def record_text(item: dict[str, Any], kind: str) -> str:
    if kind == "ConversationPassage":
        # The window text is precomputed during chunking and stored on the synthetic item.
        return str(item.get("text") or "")
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
        ("passages", "ConversationPassage"),
    ]
    for field, kind in sources:
        for item in export.get(field, []) or []:
            privacy = str(item.get("privacy_class") or "sensitive").lower()
            if privacy == "restricted":
                restricted_count += 1
                continue
            if kind == "ConversationPassage":
                records.extend(collect_passage_records(item, privacy, encoder))
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


def collect_passage_records(
    record: dict[str, Any],
    privacy: str,
    encoder: ColbertEncoder,
) -> list[dict[str, Any]]:
    """Expand one durable conversation-passage record into per-window semantic records: for each
    turn, chunk ``turn["content"]`` into ~800-char windows and emit one ConversationPassage record
    per window. occurred_at/provenance/source_refs are carried from the parent record."""
    record_id = str(record.get("id") or text_hash(json.dumps(record, ensure_ascii=False, sort_keys=True)))
    occurred_at = str(record.get("occurred_at") or "")
    provenance = json.dumps(
        record.get("provenance")
        or {
            "session_id": record.get("session_id"),
            "source_platform": record.get("source_platform"),
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    source_refs = json.dumps(record.get("source_refs") or [], ensure_ascii=False)
    out: list[dict[str, Any]] = []
    for turn_idx, turn in enumerate(record.get("turns") or []):
        content = str((turn or {}).get("content") or "")
        windows = chunk_text(content)
        if len(windows) > MAX_WINDOWS_PER_TURN:
            sys.stderr.write(
                f"[semantic_backbone] capping turn {turn_idx} of record {record_id}: "
                f"{len(windows)} windows -> {MAX_WINDOWS_PER_TURN}\n"
            )
            windows = windows[:MAX_WINDOWS_PER_TURN]
        for win_idx, window in enumerate(windows):
            item = {"text": window}
            text = record_text(item, "ConversationPassage")
            if not text.strip():
                continue
            out.append(
                {
                    "canonical_id": f"passage:{record_id}:{turn_idx}:{win_idx}",
                    "kind": "ConversationPassage",
                    "content_hash": text_hash(window),
                    "privacy_class": privacy,
                    "source_refs": source_refs,
                    "chronoself_commit": "",
                    "provenance": provenance,
                    "occurred_at": occurred_at,
                    "text": text[:12000],
                    "mv": encoder.encode(text, is_query=False),
                    "embedding_backend": encoder.backend,
                }
            )
    return out


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
                # Persist the FULL row INCLUDING "mv" (the embeddings) so the pure-Python query
                # fallback can score without native LanceDB. (Previously mv was dropped, leaving the
                # JSONL unsearchable.)
                record = dict(row)
                record["vector_count"] = len(row.get("mv") or [])
                record["vector_dim"] = DIM
                json.dump(record, handle, ensure_ascii=False, sort_keys=True)
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


def maxsim(query_mv: list[list[float]], doc_mv: list[list[float]]) -> float:
    """ColBERT-style MaxSim over normalized multivectors (dot == cosine). For single-vector
    (TEI dense) embeddings this reduces to plain cosine similarity."""
    if not query_mv or not doc_mv:
        return 0.0
    total = 0.0
    for q in query_mv:
        best = 0.0
        for d in doc_mv:
            n = min(len(q), len(d))
            s = 0.0
            for i in range(n):
                s += q[i] * d[i]
            if s > best:
                best = s
        total += best
    return total / len(query_mv)


def lexical_score(query: str, text: str) -> float:
    """Length-normalized query-term frequency (BM25-lite). Used to produce a lexical ranking that
    RRF then fuses with the dense ranking (#8 hybrid). Absolute scale is irrelevant."""
    q_terms = set(tokenize(query))
    if not q_terms:
        return 0.0
    t_terms = tokenize(text)
    if not t_terms:
        return 0.0
    tf: dict[str, int] = {}
    for t in t_terms:
        tf[t] = tf.get(t, 0) + 1
    matches = sum(tf.get(q, 0) for q in q_terms)
    return matches / math.sqrt(len(t_terms))


def rrf_fuse(rankings: list[list[int]], k: float = 60.0) -> list[int]:
    """Reciprocal Rank Fusion over ranked lists of record indices (score = Σ 1/(k+rank+1))."""
    scores: dict[int, float] = {}
    for ranking in rankings:
        for rank, idx in enumerate(ranking):
            scores[idx] = scores.get(idx, 0.0) + 1.0 / (k + rank + 1.0)
    return [i for i, _ in sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))]


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
        # Pure-Python JSONL fallback: when native LanceDB is unavailable, score the stored
        # embeddings (real TEI vectors) with MaxSim/cosine. Makes the index queryable with no
        # lancedb/torch/GPU in the image.
        try:
            fallback_path = Path(args.lancedb_path) / "semantic_records.jsonl"
            if fallback_path.exists():
                query_mv = encoder.encode(args.query, is_query=True)
                recs: list[dict[str, Any]] = []
                sem: list[float] = []
                lex: list[float] = []
                with fallback_path.open("r", encoding="utf-8") as handle:
                    for line in handle:
                        line = line.strip()
                        if not line:
                            continue
                        rec = json.loads(line)
                        recs.append(rec)
                        sem.append(maxsim(query_mv, rec.get("mv") or []))
                        lex.append(lexical_score(args.query, str(rec.get("text") or "")))
                # #8 HYBRID: fuse the dense (MaxSim) ranking with a lexical ranking via RRF. If there
                # is no lexical signal, this reduces to the dense order.
                dense_rank = sorted(range(len(recs)), key=lambda i: sem[i], reverse=True)
                if any(s > 0.0 for s in lex):
                    lex_rank = sorted(range(len(recs)), key=lambda i: lex[i], reverse=True)
                    order = rrf_fuse([dense_rank, lex_rank])
                else:
                    order = dense_rank
                scored = [(sem[i], recs[i]) for i in order]
                for score, rec in scored[: args.limit]:
                    rows.append(
                        {
                            "canonical_id": rec.get("canonical_id"),
                            "kind": rec.get("kind"),
                            "content_hash": rec.get("content_hash"),
                            "score": round(float(score), 6),
                            "occurred_at": rec.get("occurred_at"),
                            "provenance": rec.get("provenance"),
                            "source_refs": rec.get("source_refs"),
                            "text_preview": str(rec.get("text") or "")[:500],
                        }
                    )
                error = None  # served from the JSONL fallback
        except Exception as exc2:  # pragma: no cover
            error = f"{error}; jsonl_fallback_failed:{type(exc2).__name__}:{exc2}"

    payload = {
        "status": "ok" if (native_lancedb or rows) else "degraded",
        "native_lancedb": native_lancedb,
        "served_from": "native-lancedb" if native_lancedb else ("jsonl-fallback" if rows else "none"),
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
