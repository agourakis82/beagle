# B20.1 — JATS-Ready Manuscript Assembly

Status: GO

## Objective

Create the first bounded JATS-ready manuscript assembly layer so Beagle can
transform a canonical campaign into a manuscript-oriented package linked to
claims, evidence, provenance, and citation metadata.

## Canonical Shift

Before `B20.1`, Beagle could assemble review bundles with explicit claims and
bounded evidence.

After `B20.1`, Beagle can also export:

- one canonical JATS-ready manuscript pack
- one bounded section map for editorial structure
- one JATS-oriented article payload linked to campaign evidence
- one restart-safe manuscript object that keeps claims, evidence and
  provenance aligned

## Internal Surface

- `GET /api/darwin/campaigns/{id}/jats-manuscript-pack`

## Editorial Profile

The manuscript export remains intentionally bounded:

- `JATS 1.4 ready` as the editorial export profile
- claim/evidence/provenance linkage preserved from the canonical campaign path
- citation metadata carried forward from the manuscript/evidence stack

This phase does not attempt automated submission, DOI minting, or full
auto-written manuscript prose.

## Included

- JATS-ready manuscript runtime assembly
- bounded section mapping
- XML article payload export
- smoke + validator

## Excluded

- DOI creation
- submission automation
- public UI
- ingress / edge / HA
- manuscript auto-writing magic

## Canonical Target

- program: `beagle-physio-symbolic-exocortex`
- campaign: `expedition-002-hrv-aware`
- manuscript target: `expedition-002-results`

## Expected Artifacts

- `.artifacts/darwin-hpc/jats-manuscript-pack/jats-manuscript-pack.json`
- `.artifacts/darwin-hpc/jats-manuscript-pack/jats-article.xml`
- `.artifacts/darwin-hpc/jats-manuscript-pack/jats-manuscript-pack-after-restart.json`
- `.artifacts/darwin-hpc/jats-manuscript-pack/smoke.json`
- `.artifacts/darwin-hpc/jats-manuscript-pack/final-cluster-health.txt`

## Canonical Live Proof

- workspace: `b201-jats-pack-0323075229`
- session: `ws-20260323105550`
- status: `smoke=ok`, `validator=ok`
- JATS profile: `jats-1.4-ready`
- article type: `research-article`
- readiness state: `claim-linked-human-eval-pending`
