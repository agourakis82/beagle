#!/usr/bin/env python3
"""Prepare explicit conversation exports for Beagle OmniMemory import v1.

This script is intentionally dependency-light. It normalizes common JSON,
JSONL, Markdown, and text exports into canonical JSONL, classifies basic
privacy risk, and deduplicates by content hash with optional fuzzy matching.
It can also salvage explicit local app cache blobs when requested, but only
as a best-effort extraction path with provenance marked as non-export cache.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Iterable


SUPPORTED_SUFFIXES = {".json", ".jsonl", ".txt", ".md"}
BINARY_CACHE_SUFFIXES = {".data", ".ldb", ".log", ""}
PIPELINE_VERSION = "omnimemory_import_pipeline_v1"

SECRET_PATTERNS = [
    ("api_key", re.compile(r"\b(?:sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b")),
    ("private_key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----")),
    ("auth_token", re.compile(r"\b(?:access_token|refresh_token|client_secret|api_key)\b", re.I)),
]

PII_PATTERNS = [
    ("email", re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.I)),
    ("phone", re.compile(r"(?:\+\d{1,3}[\s.-]?)?(?:\(?\d{2,3}\)?[\s.-]?)?\d{4,5}[\s.-]?\d{4}")),
    ("cpf_like", re.compile(r"\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b")),
    ("credit_card_like", re.compile(r"\b(?:\d[ -]*?){13,19}\b")),
]

SENSITIVE_TERMS = re.compile(
    r"\b("
    r"diagn[oó]stic|medical|m[eé]dic|patient|paciente|psychiatr|psiquiatr|"
    r"legal|jur[ií]dic|lawsuit|processo|financial|financeiro|bank|banco|"
    r"senha|password|secret|segredo|token|auth0|cloudflare|healthkit|hrv"
    r")\b",
    re.I,
)


@dataclass
class Turn:
    role: str
    content: str


@dataclass
class CanonicalRecord:
    record_id: str
    source_platform: str
    source_file: str
    source_conversation_id: str | None
    source_title: str | None
    source_created_at: str | None
    source_updated_at: str | None
    canonical_text: str
    turns: list[Turn]
    content_hash: str
    privacy_class: str
    privacy_tags: list[str]
    provenance: dict[str, Any]
    metadata: dict[str, Any] = field(default_factory=dict)


def sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def canonical_hash_payload(source_platform: str, title: str | None, turns: list[Turn], text: str) -> str:
    payload = {
        "source_platform": source_platform,
        "title": title or "",
        "turns": [asdict(turn) for turn in turns],
        "text": text,
    }
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def classify_privacy(text: str) -> tuple[str, list[str]]:
    tags: list[str] = []
    for name, pattern in SECRET_PATTERNS:
        if pattern.search(text):
            tags.append(name)
    if tags:
        return "restricted", sorted(set(tags))

    for name, pattern in PII_PATTERNS:
        if pattern.search(text):
            tags.append(name)
    if SENSITIVE_TERMS.search(text):
        tags.append("sensitive_terms")

    if tags:
        return "sensitive", sorted(set(tags))
    return "public", []


def normalize_role(role: Any) -> str:
    value = str(role or "unknown").strip().lower()
    if value in {"assistant", "bot", "model", "claude", "chatgpt", "gpt", "gemini", "grok"}:
        return "assistant"
    if value in {"user", "human", "me", "demetrios"}:
        return "user"
    if value in {"system", "developer", "tool"}:
        return value
    return "unknown"


def text_from_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, dict):
                parts.append(text_from_value(item.get("text") or item.get("content") or item.get("value")))
            else:
                parts.append(text_from_value(item))
        return "\n".join(part for part in parts if part)
    if isinstance(value, dict):
        for key in ("text", "content", "value", "message"):
            if key in value:
                return text_from_value(value[key])
    return str(value)


def turns_from_messages(messages: Any) -> list[Turn]:
    turns: list[Turn] = []
    if not isinstance(messages, list):
        return turns
    for msg in messages:
        if isinstance(msg, dict):
            role = normalize_role(msg.get("role") or msg.get("author") or msg.get("sender"))
            content = text_from_value(msg.get("content") or msg.get("text") or msg.get("message"))
        else:
            role = "unknown"
            content = text_from_value(msg)
        content = content.strip()
        if content:
            turns.append(Turn(role=role, content=content))
    return turns


def flatten_chatgpt_mapping(mapping: Any) -> list[Turn]:
    turns: list[Turn] = []
    if not isinstance(mapping, dict):
        return turns
    nodes = []
    for node in mapping.values():
        if isinstance(node, dict):
            message = node.get("message")
            if isinstance(message, dict):
                create_time = message.get("create_time") or 0
                author = message.get("author") or {}
                role = normalize_role(author.get("role") if isinstance(author, dict) else None)
                content = text_from_value(message.get("content")).strip()
                if content:
                    nodes.append((create_time, role, content))
    for _, role, content in sorted(nodes, key=lambda item: item[0] or 0):
        turns.append(Turn(role=role, content=content))
    return turns


def record_candidates_from_json(data: Any) -> Iterable[dict[str, Any]]:
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                yield item
            else:
                yield {"text": text_from_value(item)}
        return
    if isinstance(data, dict):
        for key in ("conversations", "chats", "items", "data"):
            value = data.get(key)
            if isinstance(value, list):
                yield from record_candidates_from_json(value)
                return
        yield data


def normalize_candidate(candidate: dict[str, Any], source_platform: str, source_file: Path) -> tuple[str | None, str | None, str | None, str | None, list[Turn], str]:
    title = text_from_value(candidate.get("title") or candidate.get("name") or candidate.get("conversation_title")).strip() or None
    conversation_id = text_from_value(candidate.get("id") or candidate.get("conversation_id") or candidate.get("uuid")).strip() or None
    created_at = text_from_value(candidate.get("created_at") or candidate.get("create_time") or candidate.get("created")).strip() or None
    updated_at = text_from_value(candidate.get("updated_at") or candidate.get("update_time") or candidate.get("modified")).strip() or None

    turns = (
        turns_from_messages(candidate.get("messages"))
        or turns_from_messages(candidate.get("turns"))
        or turns_from_messages(candidate.get("mapping"))
        or flatten_chatgpt_mapping(candidate.get("mapping"))
    )
    if not turns:
        text = text_from_value(candidate.get("text") or candidate.get("content") or candidate.get("raw_content")).strip()
    else:
        text = "\n\n".join(f"{turn.role}: {turn.content}" for turn in turns)

    if not text and title:
        text = title
    return conversation_id, title, created_at, updated_at, turns, text


def read_text_file(path: Path) -> str:
    raw = path.read_bytes()
    if b"\x00" in raw:
        raise ValueError("null byte found")
    return raw.decode("utf-8")


def printable_strings_from_binary(raw: bytes, min_length: int) -> list[str]:
    ascii_pattern = re.compile(rb"[\x20-\x7e\n\r\t]{" + str(min_length).encode("ascii") + rb",}")
    strings = [match.group(0).decode("utf-8", "ignore").strip() for match in ascii_pattern.finditer(raw)]

    try:
        utf16_text = raw.decode("utf-16-le", "ignore")
    except Exception:  # noqa: BLE001 - best effort only.
        utf16_text = ""
    if utf16_text:
        utf16_pattern = re.compile(r"[\x20-\x7e\n\r\t]{" + str(min_length) + r",}")
        strings.extend(match.group(0).strip() for match in utf16_pattern.finditer(utf16_text))

    clean: list[str] = []
    seen: set[str] = set()
    for value in strings:
        value = re.sub(r"\s+", " ", value).strip()
        if len(value) < min_length:
            continue
        digest = sha256_text(value)
        if digest in seen:
            continue
        seen.add(digest)
        clean.append(value)
    return clean


def parse_file(
    path: Path,
    source_platform: str,
    *,
    include_binary_cache: bool = False,
    binary_min_string: int = 240,
) -> Iterable[tuple[dict[str, Any], str]]:
    try:
        text = read_text_file(path)
    except (UnicodeDecodeError, ValueError) as exc:
        if not include_binary_cache:
            raise
        raw = path.read_bytes()
        strings = printable_strings_from_binary(raw, binary_min_string)
        if not strings:
            raise ValueError("binary cache had no recoverable long strings") from exc
        for index, value in enumerate(strings):
            yield {
                "title": f"{path.name or path.parent.name} recovered string {index + 1}",
                "text": value,
                "id": f"{path.name or path.parent.name}:{index + 1}",
                "metadata": {
                    "cache_extraction": True,
                    "binary_min_string": binary_min_string,
                    "source_kind": "local_app_cache",
                },
            }, f"binary-string:{index}"
        return
    suffix = path.suffix.lower()
    if suffix == ".jsonl":
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.strip():
                yield json.loads(line), f"jsonl:{line_number}"
        return
    if suffix == ".json":
        data = json.loads(text)
        for index, candidate in enumerate(record_candidates_from_json(data)):
            yield candidate, f"json:{index}"
        return
    yield {"title": path.stem, "text": text}, "text:0"


def iter_input_files(input_path: Path, include_binary_cache: bool = False, limit_files: int | None = None) -> list[Path]:
    if input_path.is_file():
        return [input_path]
    suffixes = SUPPORTED_SUFFIXES | (BINARY_CACHE_SUFFIXES if include_binary_cache else set())
    files = sorted(path for path in input_path.rglob("*") if path.is_file() and path.suffix.lower() in suffixes)
    if limit_files is not None:
        return files[:limit_files]
    return files


def build_records(
    input_path: Path,
    source_platform: str,
    *,
    include_binary_cache: bool = False,
    binary_min_string: int = 240,
    limit_files: int | None = None,
    limit_records: int | None = None,
) -> tuple[list[CanonicalRecord], list[dict[str, Any]]]:
    records: list[CanonicalRecord] = []
    errors: list[dict[str, Any]] = []
    for path in iter_input_files(input_path, include_binary_cache=include_binary_cache, limit_files=limit_files):
        try:
            parsed = list(
                parse_file(
                    path,
                    source_platform,
                    include_binary_cache=include_binary_cache,
                    binary_min_string=binary_min_string,
                )
            )
        except Exception as exc:  # noqa: BLE001 - report and continue.
            errors.append({"file": str(path), "error": str(exc)})
            continue
        for candidate, location in parsed:
            try:
                conversation_id, title, created_at, updated_at, turns, text = normalize_candidate(candidate, source_platform, path)
                text = text.strip()
                if not text:
                    errors.append({"file": str(path), "location": location, "error": "empty canonical text"})
                    continue
                hash_payload = canonical_hash_payload(source_platform, title, turns, text)
                content_hash = sha256_text(hash_payload)
                privacy_class, privacy_tags = classify_privacy(text)
                records.append(
                    CanonicalRecord(
                        record_id=content_hash,
                        source_platform=source_platform,
                        source_file=str(path),
                        source_conversation_id=conversation_id,
                        source_title=title,
                        source_created_at=created_at,
                        source_updated_at=updated_at,
                        canonical_text=text,
                        turns=turns,
                        content_hash=content_hash,
                        privacy_class=privacy_class,
                        privacy_tags=privacy_tags,
                        provenance={
                            "imported_via": PIPELINE_VERSION,
                            "explicit_user_export": not bool(candidate.get("metadata", {}).get("cache_extraction")),
                            "source_location": location,
                            "source_kind": candidate.get("metadata", {}).get("source_kind", "explicit_export"),
                        },
                        metadata=candidate.get("metadata", {}) if isinstance(candidate.get("metadata"), dict) else {},
                    )
                )
                if limit_records is not None and len(records) >= limit_records:
                    return records, errors
            except Exception as exc:  # noqa: BLE001 - report and continue.
                errors.append({"file": str(path), "location": location, "error": str(exc)})
    return records, errors


def dedupe_records(records: list[CanonicalRecord], fuzzy_threshold: float) -> tuple[list[CanonicalRecord], list[dict[str, Any]]]:
    unique: list[CanonicalRecord] = []
    seen: dict[str, CanonicalRecord] = {}
    duplicates: list[dict[str, Any]] = []

    for record in records:
        existing = seen.get(record.content_hash)
        if existing:
            duplicates.append({
                "strategy": "exact_sha256",
                "record_id": record.record_id,
                "duplicate_of": existing.record_id,
                "source_file": record.source_file,
            })
            continue

        fuzzy_duplicate: CanonicalRecord | None = None
        fuzzy_score = 0.0
        if fuzzy_threshold > 0:
            for candidate in unique:
                if candidate.source_platform != record.source_platform:
                    continue
                score = SequenceMatcher(None, candidate.canonical_text, record.canonical_text).ratio()
                if score >= fuzzy_threshold:
                    fuzzy_duplicate = candidate
                    fuzzy_score = score
                    break
        if fuzzy_duplicate:
            duplicates.append({
                "strategy": "fuzzy_sequence_matcher",
                "score": round(fuzzy_score, 6),
                "record_id": record.record_id,
                "duplicate_of": fuzzy_duplicate.record_id,
                "source_file": record.source_file,
            })
            continue

        seen[record.content_hash] = record
        unique.append(record)
    return unique, duplicates


def write_jsonl(path: Path, rows: Iterable[Any]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            if hasattr(row, "__dataclass_fields__"):
                value = asdict(row)
            else:
                value = row
            handle.write(json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n")


def prepare(args: argparse.Namespace) -> int:
    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    output_path.mkdir(parents=True, exist_ok=True)

    source_platform = args.source_platform.strip().lower()
    records, errors = build_records(
        input_path,
        source_platform,
        include_binary_cache=args.include_binary_cache,
        binary_min_string=args.binary_min_string,
        limit_files=args.limit_files,
        limit_records=args.limit_records,
    )
    unique, duplicates = dedupe_records(records, args.fuzzy_threshold)

    write_jsonl(output_path / "canonical_records.jsonl", unique)
    write_jsonl(output_path / "duplicates.jsonl", duplicates)

    privacy_counts: dict[str, int] = {}
    for record in unique:
        privacy_counts[record.privacy_class] = privacy_counts.get(record.privacy_class, 0) + 1

    status = "pass" if unique and not errors else "fail" if not unique else "warning"
    validation_report = {
        "status": status,
        "pipeline_version": PIPELINE_VERSION,
        "input": str(input_path),
        "output": str(output_path),
        "source_platform": source_platform,
        "records_seen": len(records),
        "records_unique": len(unique),
        "duplicates": len(duplicates),
        "errors": errors,
        "privacy_counts": privacy_counts,
        "restricted_records": privacy_counts.get("restricted", 0),
    }
    manifest = {
        "pipeline_version": PIPELINE_VERSION,
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_platform": source_platform,
        "input": str(input_path),
        "output": str(output_path),
        "files": [
            str(path)
            for path in iter_input_files(
                input_path,
                include_binary_cache=args.include_binary_cache,
                limit_files=args.limit_files,
            )
        ],
        "canonical_records": "canonical_records.jsonl",
        "duplicates": "duplicates.jsonl",
        "validation_report": "validation_report.json",
        "content_hashes": [record.content_hash for record in unique],
    }

    (output_path / "validation_report.json").write_text(
        json.dumps(validation_report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (output_path / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(json.dumps(validation_report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if status in {"pass", "warning"} else 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_parser = subparsers.add_parser("prepare", help="normalize, validate, classify, and dedupe exports")
    prepare_parser.add_argument("--input", required=True, help="input file or directory")
    prepare_parser.add_argument("--source-platform", required=True, help="chatgpt, claude, grok, gemini, or manual")
    prepare_parser.add_argument("--output", required=True, help="output directory")
    prepare_parser.add_argument(
        "--fuzzy-threshold",
        type=float,
        default=0.985,
        help="SequenceMatcher duplicate threshold; set 0 to disable fuzzy dedupe",
    )
    prepare_parser.add_argument(
        "--include-binary-cache",
        action="store_true",
        help="best-effort salvage of local app cache blobs; marks provenance as local_app_cache",
    )
    prepare_parser.add_argument(
        "--binary-min-string",
        type=int,
        default=240,
        help="minimum printable string length for binary cache extraction",
    )
    prepare_parser.add_argument("--limit-files", type=int, default=None, help="maximum files to scan")
    prepare_parser.add_argument("--limit-records", type=int, default=None, help="maximum records to emit before dedupe")
    prepare_parser.set_defaults(func=prepare)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
