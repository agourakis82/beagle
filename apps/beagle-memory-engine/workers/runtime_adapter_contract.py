#!/usr/bin/env python3
"""Runtime adapter contract smoke for federated memory candidates."""

from __future__ import annotations

import json
import os

RUNTIMES = [
    ("FalkorDB", "BEAGLE_FALKORDB_URL"),
    ("Memgraph", "BEAGLE_MEMGRAPH_URL"),
    ("ArangoDB", "BEAGLE_ARANGODB_URL"),
    ("SurrealDB", "BEAGLE_SURREALDB_URL"),
    ("ArcadeDB", "BEAGLE_ARCADEDB_URL"),
    ("Kuzu", "BEAGLE_KUZU_PATH"),
    ("LanceDB", "BEAGLE_LANCEDB_URI"),
    ("DuckDB-VSS", "BEAGLE_DUCKDB_VSS_PATH"),
    ("Postgres pgvectorscale", "BEAGLE_POSTGRES_VECTOR_URL"),
    ("TypeDB", "BEAGLE_TYPEDB_URL"),
]


def main() -> int:
    print(
        json.dumps(
            {
                "schema_version": "beagle-federated-memory-engine-v1.6",
                "runtimes": [
                    {
                        "name": name,
                        "env": env_key,
                        "configured": bool(os.getenv(env_key)),
                    }
                    for name, env_key in RUNTIMES
                ],
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
