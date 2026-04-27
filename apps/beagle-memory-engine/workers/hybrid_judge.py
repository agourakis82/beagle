#!/usr/bin/env python3
"""Cluster-only hybrid judge scaffold for Beagle Memory Engine v1.5.

The worker consumes sanitized JSON exports produced by beagle-core. It never
reads the canonical PVC directly and should write only aggregate metrics or
candidate proposals back through the engine/core APIs.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: hybrid_judge.py <sanitized-export.json>", file=sys.stderr)
        return 2
    export_path = Path(sys.argv[1])
    payload = json.loads(export_path.read_text())
    atoms = payload.get("atoms", [])
    episodes = payload.get("episodes", [])
    restricted = [
        item
        for item in [*atoms, *episodes]
        if item.get("privacy_class") == "restricted"
    ]
    result = {
        "schema_version": "beagle-federated-memory-engine-v1.5",
        "restricted_leak_zero": len(restricted) == 0,
        "episode_count": len(episodes),
        "atom_count": len(atoms),
        "provenance_completeness": sum(1 for atom in atoms if atom.get("source_refs")) / max(len(atoms), 1),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["restricted_leak_zero"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
