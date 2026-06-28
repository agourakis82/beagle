#!/usr/bin/env python3
"""
DICE Task 1 — Export preference pairs from beagle-feedback JSONL.

Reads BEAGLE_DATA_DIR/feedback/*.jsonl, filters positive/negative feedback events,
and writes ShareGPT-format DPO pairs to BEAGLE_DATA_DIR/dice/preference_pairs_round0.jsonl.

Pair construction:
  chosen   = assistant turn where user gave thumbs-up (rating >= 4) or accepted a proposal
  rejected = assistant turn in the same conversation where user gave thumbs-down (rating <= 2)
  If no explicit pair, uses implicit signal: last message before abandon vs. explicit thumbs-up.

Usage:
  python3 export_preference_pairs.py [--min-pairs N] [--dry-run]
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path


def find_feedback_jsonl(data_dir: Path) -> list[Path]:
    feedback_dir = data_dir / "feedback"
    if not feedback_dir.exists():
        return []
    return sorted(feedback_dir.glob("*.jsonl"))


def load_events(paths: list[Path]) -> list[dict]:
    events = []
    for p in paths:
        with open(p) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return events


def build_pairs(events: list[dict]) -> list[dict]:
    """Group events by conversation_id and extract DPO pairs."""
    by_conv = defaultdict(list)
    for e in events:
        cid = e.get("conversation_id") or e.get("run_id") or e.get("session_id")
        if cid:
            by_conv[cid].append(e)

    pairs = []
    for cid, conv_events in by_conv.items():
        # Sort by timestamp
        conv_events.sort(key=lambda e: e.get("timestamp", e.get("created_at", "")))

        positives = [
            e for e in conv_events
            if e.get("event_type") in ("human_feedback", "accept_proposal")
            and (e.get("rating", 0) >= 4 or e.get("event_type") == "accept_proposal")
            and e.get("assistant_text")
        ]
        negatives = [
            e for e in conv_events
            if e.get("event_type") in ("human_feedback", "reject_proposal")
            and (e.get("rating", 0) <= 2 or e.get("event_type") == "reject_proposal")
            and e.get("assistant_text")
        ]

        # Simple pairing: cross-product of same-prompt positives and negatives
        for pos in positives:
            prompt = pos.get("prompt") or pos.get("user_text", "")
            if not prompt:
                continue
            for neg in negatives:
                neg_prompt = neg.get("prompt") or neg.get("user_text", "")
                if neg_prompt and neg_prompt != prompt:
                    continue
                pairs.append({
                    "conversations": [
                        {"from": "human", "value": prompt},
                    ],
                    "chosen": [
                        {"from": "gpt", "value": pos["assistant_text"]},
                    ],
                    "rejected": [
                        {"from": "gpt", "value": neg["assistant_text"]},
                    ],
                    "source": "beagle-feedback",
                    "conversation_id": cid,
                })

    return pairs


def main():
    parser = argparse.ArgumentParser(description="Export DPO preference pairs from beagle feedback")
    parser.add_argument("--min-pairs", type=int, default=10, help="Warn if fewer pairs than this")
    parser.add_argument("--dry-run", action="store_true", help="Print stats, do not write")
    args = parser.parse_args()

    data_dir = Path(os.environ.get("BEAGLE_DATA_DIR", os.path.expanduser("~/beagle-data")))
    paths = find_feedback_jsonl(data_dir)
    if not paths:
        print(f"[dice] No feedback JSONL found in {data_dir}/feedback/", file=sys.stderr)
        sys.exit(0)

    events = load_events(paths)
    print(f"[dice] Loaded {len(events)} feedback events from {len(paths)} files")

    pairs = build_pairs(events)
    print(f"[dice] Extracted {len(pairs)} preference pairs")

    if len(pairs) < args.min_pairs:
        print(f"[dice] WARNING: only {len(pairs)} pairs (< {args.min_pairs}). "
              "Consider bootstrapping with synthetic pairs or collecting more feedback.")

    if args.dry_run:
        print("[dice] Dry run — not writing output")
        return

    out_dir = data_dir / "dice"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "preference_pairs_round0.jsonl"
    with open(out_path, "w") as f:
        for pair in pairs:
            f.write(json.dumps(pair, ensure_ascii=False) + "\n")

    print(f"[dice] Wrote {len(pairs)} pairs → {out_path}")


if __name__ == "__main__":
    main()
