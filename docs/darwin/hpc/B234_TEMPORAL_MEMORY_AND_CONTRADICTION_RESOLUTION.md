# B23.4 — Temporal Memory & Contradiction Resolution

## Objective

Add the first bounded temporal memory layer so Beagle can preserve:

- current truth
- historical truth
- explicit contradiction markers

without deleting prior memory versions or introducing a parallel graph runtime.

## Canonical stance

- `Qdrant` remains the vector-store direction
- the current dense lanes remain in place:
  - `voyage-4-large` for general retrieval
  - `voyage-code-3` for code retrieval
  - `bge-m3` for the sovereign track
- sparse lexical retrieval remains active
- reranking remains bounded
- temporal truth is derived over Beagle-owned `MemoryRecord`s and canonical
  Beagle entities rather than a separate temporal database

## What is live

- `GET /api/memory/temporal`
- `POST /api/memory/temporal/query`
- bounded temporal summaries in:
  - workstream context packets
  - program/campaign context packets

## Temporal model

`B23.4` introduces three bounded ideas:

- temporal truth key
  - a canonical subject such as `claim:*`, `result:*`, or a bounded procedural
    subject derived from repo-native workflow memory
- current truth
  - the newest valid memory version for that subject
- historical truth
  - prior preserved versions that remain retrievable and inspectable

The runtime keeps history instead of deleting it. A new version supersedes the
previous one by time, but the older version remains visible as historical
truth.

## Contradiction handling

Contradictions are explicit records, not silent overwrites.

The first bounded contradiction detector marks a contradiction when:

- the same temporal subject preserves multiple versions
- a newer version flips state against an older version

This keeps the layer honest: Beagle can say "this is current", "this used to
be true", and "these two preserved versions contradict each other".

## Context integration

Workstream and program context packets now carry a bounded temporal summary:

- truth view used
- bounded subject refs
- current memory ids
- historical memory ids
- contradiction count and ids
- short temporal preview

This keeps temporal truth useful in tool context without exploding packet size.
