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
# Sidecar manifest mapping {canonical_id: content_hash}, written next to the LanceDB table.
# It lets a rebuild diff the current export against the previously-indexed state and only
# (re)embed/upsert changed rows + delete stale ones, instead of re-embedding everything.
MANIFEST_NAME = "semantic_index_manifest.json"
# Max ids per "canonical_id IN (...)" delete statement so a huge stale set is batched.
DELETE_BATCH_SIZE = 500
# Memory-bounded index build: embed + write to LanceDB in batches of this many rows so peak
# memory is ~one batch of multivector embeddings, not the whole corpus at once. This is what
# lets a rebuild of tens of thousands of rows complete without OOM.
BUILD_BATCH_SIZE = int(os.getenv("BEAGLE_MEMORY_BUILD_BATCH", "1000"))


def _chunked(seq: list[Any], size: int):
    size = max(1, size)
    for start in range(0, len(seq), size):
        yield seq[start : start + size]


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


def collect_candidates(export: dict[str, Any]) -> tuple[list[dict[str, Any]], int]:
    """Build the canonical row dicts WITHOUT embedding them. Each candidate carries every
    schema field except "mv" and "embedding_backend"; those are filled in by encode_row() only
    for the rows that actually need to be (re)indexed. This is what makes incremental reindex
    cheap — collection no longer hits the encoder/TEI for every row."""
    candidates: list[dict[str, Any]] = []
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
                candidates.extend(collect_passage_records(item, privacy))
                continue
            text = record_text(item, kind)
            if not text.strip():
                continue
            canonical_id = str(item.get("id") or item.get("source_ref") or text_hash(text))
            candidates.append(
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
                }
            )
    return candidates, restricted_count


def encode_row(row: dict[str, Any], encoder: ColbertEncoder) -> dict[str, Any]:
    """Return a NEW embedded row dict (candidate fields + "mv" + "embedding_backend").
    Non-mutating by design: the source candidate stays text-only so that embedded rows are
    transient and freed after each write batch (bounds peak memory). Only called for rows
    that are actually being (re)indexed."""
    return {
        **row,
        "mv": encoder.encode(row["text"], is_query=False),
        "embedding_backend": encoder.backend,
    }


def collect_passage_records(
    record: dict[str, Any],
    privacy: str,
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


def load_manifest(path: str) -> dict[str, str]:
    """Load the sidecar manifest {canonical_id: content_hash}. Fail-soft: a missing or corrupt
    manifest yields {} so a rebuild simply falls back to a full index."""
    manifest_path = Path(path) / MANIFEST_NAME
    try:
        with manifest_path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
        if isinstance(data, dict):
            return {str(k): str(v) for k, v in data.items()}
    except Exception:
        pass
    return {}


def write_manifest(path: str, mapping: dict[str, str]) -> None:
    """Atomically write the sidecar manifest (write to a temp file in the same dir + os.replace)."""
    Path(path).mkdir(parents=True, exist_ok=True)
    manifest_path = Path(path) / MANIFEST_NAME
    tmp_path = Path(path) / f"{MANIFEST_NAME}.tmp"
    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(mapping, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
    os.replace(str(tmp_path), str(manifest_path))


def _sql_quote(value: str) -> str:
    """SQL-quote a string literal for a LanceDB filter (single quotes, doubled to escape)."""
    return "'" + str(value).replace("'", "''") + "'"


def rebuild(args: argparse.Namespace) -> dict[str, Any]:
    started = time.time()
    export = load_json(args.export)
    encoder = ColbertEncoder(args.model)
    candidates, restricted_excluded_count = collect_candidates(export)
    cur = {c["canonical_id"]: c["content_hash"] for c in candidates}
    table_name = args.table

    force_full = getattr(args, "full", False)
    manifest_path = args.lancedb_path
    prev = {} if force_full else load_manifest(manifest_path)

    native_lancedb = False
    index_ready = False
    worker_status = "empty"
    error: str | None = None
    # Diff counters reported in the payload.
    added = 0
    deleted = 0
    skipped = 0
    rebuild_mode = "full"
    row_count = len(candidates)

    def create_index_guarded(table: Any) -> None:
        """Build the ANN index after writes; small/old tables may skip it (kept from prior code)."""
        nonlocal index_ready, error
        try:
            if table.count_rows() > 0:
                table.create_index(metric="cosine", vector_column_name="mv")
                index_ready = True
        except Exception as exc:  # small tables or old LanceDB may skip ANN
            error = f"index_degraded:{type(exc).__name__}:{exc}"
            index_ready = False

    def full_overwrite(db: Any) -> Any:
        """Encode + overwrite the whole table, BATCHED so peak memory is ~one batch of
        embeddings rather than every candidate's multivector at once."""
        nonlocal added, deleted, skipped
        deleted = 0
        skipped = 0
        if not candidates:
            table = db.create_table(table_name, data=[], schema=arrow_schema(), mode="overwrite")
            added = 0
            return table
        table = None
        written = 0
        for batch in _chunked(candidates, BUILD_BATCH_SIZE):
            rows = [encode_row(c, encoder) for c in batch]
            if table is None:
                # First batch creates (overwrites) the table; rest append.
                table = db.create_table(table_name, data=rows, schema=arrow_schema(), mode="overwrite")
            else:
                table.add(rows)
            written += len(rows)
            rows = None  # free this batch's embeddings before the next
        added = written
        return table

    try:
        db = open_lancedb(args.lancedb_path)
        table_exists = table_name in db.table_names()
        incremental = bool(prev) and table_exists and not force_full

        if incremental:
            try:
                table = db.open_table(table_name)
                to_upsert = [c for c in candidates if prev.get(c["canonical_id"]) != c["content_hash"]]
                stale = [cid for cid in prev if cid not in cur]
                if stale:
                    for start in range(0, len(stale), DELETE_BATCH_SIZE):
                        batch = stale[start : start + DELETE_BATCH_SIZE]
                        in_list = ", ".join(_sql_quote(cid) for cid in batch)
                        table.delete(f"canonical_id IN ({in_list})")
                # Embed + merge_insert in batches so a large changed-set doesn't hold every
                # embedding in memory at once (the first rebuild after a big ingest has a huge set).
                upserted = 0
                for batch in _chunked(to_upsert, BUILD_BATCH_SIZE):
                    rows = [encode_row(c, encoder) for c in batch]
                    (
                        table.merge_insert("canonical_id")
                        .when_matched_update_all()
                        .when_not_matched_insert_all()
                        .execute(rows)
                    )
                    upserted += len(rows)
                    rows = None
                added = upserted
                deleted = len(stale)
                skipped = len(candidates) - len(to_upsert)
                rebuild_mode = "incremental"
                worker_status = "native-incremental"
                create_index_guarded(table)
                row_count = table.count_rows()
                native_lancedb = True
            except Exception as exc:  # incremental path failed -> full overwrite fallback
                sys.stderr.write(
                    f"[semantic_backbone] incremental reindex failed, falling back to full overwrite: "
                    f"{type(exc).__name__}:{exc}\n"
                )
                error = f"incremental_failed:{type(exc).__name__}:{exc}"
                table = full_overwrite(db)
                rebuild_mode = "full-fallback"
                worker_status = "native-full-fallback"
                create_index_guarded(table)
                row_count = table.count_rows()
                native_lancedb = True
        else:
            table = full_overwrite(db)
            rebuild_mode = "full"
            worker_status = "native-lancedb-table"
            create_index_guarded(table)
            row_count = table.count_rows()
            native_lancedb = True

        # Record the new indexed state so the next rebuild can diff against it.
        write_manifest(manifest_path, cur)
    except Exception as exc:
        native_lancedb = False
        if error:
            error = f"{error}; native_lancedb_unavailable:{type(exc).__name__}:{exc}"
        else:
            error = f"native_lancedb_unavailable:{type(exc).__name__}:{exc}"
        # JSONL fallback needs every embedding. Encode + stream to file in batches so we never
        # hold every embedding in memory at once.
        fallback_path = Path(args.lancedb_path) / "semantic_records.jsonl"
        Path(args.lancedb_path).mkdir(parents=True, exist_ok=True)
        written = 0
        with fallback_path.open("w", encoding="utf-8") as handle:
            for batch in _chunked(candidates, BUILD_BATCH_SIZE):
                for c in batch:
                    row = encode_row(c, encoder)
                    # Persist the FULL row INCLUDING "mv" (the embeddings) so the pure-Python query
                    # fallback can score without native LanceDB.
                    row["vector_count"] = len(row.get("mv") or [])
                    row["vector_dim"] = DIM
                    json.dump(row, handle, ensure_ascii=False, sort_keys=True)
                    handle.write("\n")
                    written += 1
        worker_status = "jsonl-fallback"
        rebuild_mode = "full"
        added = written
        deleted = 0
        skipped = 0
        row_count = written

    payload = {
        "status": "indexed-native-multivector" if native_lancedb else worker_status,
        "native_lancedb": native_lancedb,
        "table_name": table_name,
        "row_count": row_count,
        "added": added,
        "deleted": deleted,
        "skipped": skipped,
        "rebuild_mode": rebuild_mode,
        "index_ready": index_ready,
        "maxsim_ready": native_lancedb and row_count > 0,
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


# Over-fetch this many x the requested limit before de-duplicating overlapping windows, so that
# collapsing near-duplicate passage windows still leaves enough distinct results to fill the limit.
DEDUP_FETCH_FACTOR = 4
DEDUP_FETCH_CAP = 64
# Two results are treated as the same passage if their token sets overlap by at least this fraction
# (containment = |A∩B| / min(|A|,|B|)). Adjacent ~800-char windows share ~700 chars -> ~0.85+.
DEDUP_CONTAINMENT = 0.82


def dedup_overlapping(rows: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    """Collapse near-duplicate / overlapping passage windows from a rank-ordered result list,
    keeping the highest-scored representative (rows are already in rank order). Generic text-
    containment dedup: also catches duplicate passages across records, not just adjacent windows."""
    kept: list[dict[str, Any]] = []
    kept_tokens: list[set[str]] = []
    for row in rows:
        toks = set(tokenize(str(row.get("text_preview") or "")))
        is_dup = False
        if toks:
            for kt in kept_tokens:
                if not kt:
                    continue
                inter = len(toks & kt)
                if inter and inter / min(len(toks), len(kt)) >= DEDUP_CONTAINMENT:
                    is_dup = True
                    break
        if not is_dup:
            kept.append(row)
            kept_tokens.append(toks)
        if len(kept) >= limit:
            break
    return kept


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
        result = (
            table.search(query_mv)
            .limit(min(args.limit * DEDUP_FETCH_FACTOR, DEDUP_FETCH_CAP))
            .to_arrow()
            .to_pylist()
        )
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
                for score, rec in scored[: min(args.limit * DEDUP_FETCH_FACTOR, DEDUP_FETCH_CAP)]:
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

    # Collapse overlapping/near-duplicate passage windows, then trim to the requested limit.
    rows = dedup_overlapping(rows, args.limit)

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
    rebuild_parser.add_argument(
        "--full",
        action="store_true",
        help="Force a full re-embed + overwrite, ignoring the sidecar manifest.",
    )

    query_parser = sub.add_parser("query", parents=[common])
    query_parser.add_argument("--query", required=True)
    query_parser.add_argument("--limit", type=int, default=8)

    args = parser.parse_args(argv)
    payload = rebuild(args) if args.command == "rebuild" else query(args)
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
