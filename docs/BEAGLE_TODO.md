# BEAGLE TODO

Generated: 2026-05-16

This is the operating checklist for keeping BEAGLE pointed at the original
Darwin/BEAGLE purpose: a personal scientific exocortex that preserves,
extends, challenges, and documents the operator's research mind.

## Current Direction

BEAGLE is not a generic productivity app, not a beautiful empty cockpit, and
not a pile of ambitious modules. The core path is:

```text
thought or voice note
-> memory capture
-> hypothesis generation
-> evidence interference
-> hyperbolic memory placement
-> adversarial review
-> scientific artifact
-> feedback into memory
```

PBPK is delegated to Sounio. BEAGLE should consume Sounio outputs as evidence
or artifacts, not reimplement PBPK internally.

## Ground Rules

- Keep `make rescue-check` green.
- Do not add new modules until one existing module has a deterministic local
  path, tests, and workflow use.
- Do not accept "100 percent complete", "production ready", or "real" unless
  there is command evidence in the repo.
- Do not build UI surfaces unless they operate the living workflow or reduce
  cognitive load.
- Do not flatten the project into a generic chat app.
- Preserve weirdness only when it is disciplined by tests, provenance, or
  artifact generation.

## P0: Keep The Base Alive

- [x] Restore macOS baseline for `core_server`.
- [x] Restore frontend build for `apps/beagle-ide`.
- [x] Add `make rescue-check`.
- [x] Commit rescue baseline.
- [ ] Add CI or local preflight documentation that runs `make rescue-check`.
- [ ] Reduce only blocker warnings that hide real failures.
- [ ] Keep `git status` clean after each completed slice.

Acceptance:

```text
make rescue-check
git status --short
```

## P1: Preserve The North Star

- [x] Add `BEAGLE_NORTH_STAR.md`.
- [x] Add deep audit reports.
- [x] Add exotic modules contract.
- [x] Record PBPK delegation to Sounio.
- [ ] Rewrite or quarantine docs that make false completion claims.
- [ ] Create a single `docs/BEAGLE_CURRENT_STATE.md` that supersedes scattered
  status docs.
- [ ] Add a doc index that marks old reports as historical, current, or
  superseded.

Acceptance:

- A new contributor can open three files and know what BEAGLE is, what is
  working, and what is next.
- No current doc claims completion without dated command evidence.

## P2: Make Exotic Modules Real

- [x] Fix `beagle-hyperbolic` distance so it uses Poincare-ball geometry.
- [x] Fix `beagle-hyperbolic` communities so they are real connected
  components.
- [x] Make `beagle-quantum` hypothesis sets stable when empty or degenerate.
- [x] Make `beagle-quantum` interference work offline with lexical fallback.
- [ ] Add `beagle-quantum` measurement fallback for offline critic failure.
- [ ] Add a small end-to-end test:
  thought -> hypotheses -> evidence -> changed confidence ranking.
- [ ] Wire `beagle-hyperbolic` into memory placement for captured thoughts.
- [ ] Add a curvature or anomaly score that can surface fertile links.
- [ ] Reframe `beagle-consciousness` as emergence/metacognition metrics, not
  subjective consciousness claims.
- [ ] Give `beagle-void` a deterministic negative-space analysis output.
- [ ] Give `beagle-paradox` a contradiction ledger and repair proposal output.
- [ ] Give `beagle-ontic` an ontology break/rebuild contract with safeguards.
- [ ] Give `beagle-noetic` provenance-bound multi-agent comparison metrics.
- [ ] Keep `beagle-transcend` and `beagle-eternity` frozen until primitives are
  proven in workflow.

Acceptance:

```text
cargo test -p beagle-quantum --lib
cargo test -p beagle-hyperbolic
cargo check -p beagle-fractal
```

Plus one workflow artifact showing that evidence changed hypothesis ranking.

## P3: Recover Memory And Darwin Core

- [ ] Revalidate `crates/beagle-memory` against real stored thoughts.
- [ ] Revalidate `beagle-mcp-server` as the memory/control plane.
- [ ] Revalidate `crates/beagle-darwin` and `crates/beagle-darwin-core`
  against GraphRAG/Self-RAG expectations.
- [ ] Identify the minimum storage backend needed for local confidence.
- [ ] Add one smoke test that writes a thought and retrieves it by semantic or
  lexical query.
- [ ] Add one smoke test that links a thought to a hypothesis set.
- [ ] Remove or quarantine orphan memory paths that cannot be reached from the
  core workflow.

Acceptance:

- One prior thought can be retrieved.
- One retrieved thought can influence a hypothesis or artifact.
- The retrieval path is documented with command evidence.

## P4: Restore HERMES, Triad, And Scientific Artifacts

- [ ] Revalidate `crates/beagle-hermes` as artifact generator, not generic text
  generator.
- [ ] Revalidate `crates/beagle-triad` as adversarial review with evidence.
- [ ] Revalidate `crates/beagle-feedback` as feedback into memory.
- [ ] Create one local draft artifact from a captured thought.
- [ ] Run one Triad review that produces critique, risk, and next action.
- [ ] Feed review outcome back into memory.
- [ ] Add a repeatable smoke command or script for this path.

Acceptance:

```text
thought -> draft artifact -> triad review -> feedback record
```

All outputs must be written to local files or storage with provenance.

## P5: Make The IDE A Real Cockpit

- [x] Add first living workflow UI in `apps/beagle-ide`.
- [ ] Connect UI capture to a real backend endpoint.
- [ ] Show memory write status.
- [ ] Show hypothesis set and confidence changes after evidence.
- [ ] Show hyperbolic placement or related memory links.
- [ ] Show adversarial review output.
- [ ] Show final artifact path.
- [ ] Remove UI panels that do not operate a real workflow.
- [ ] Keep design quiet, dense, and confidence-restoring.

Acceptance:

```text
npm --prefix apps/beagle-ide run build
make rescue-check
```

And a manual browser pass proving the first screen operates the workflow.

## P6: Sounio Boundary

- [x] Declare PBPK delegated to Sounio.
- [ ] Define the artifact contract BEAGLE expects from Sounio.
- [ ] Add a sample Sounio artifact fixture if one is available.
- [ ] Add importer/parser for Sounio outputs as evidence.
- [ ] Attach Sounio artifacts to hypotheses and provenance.
- [ ] Avoid any BEAGLE PBPK reimplementation unless explicitly reversed later.

Acceptance:

- BEAGLE can ingest one Sounio artifact as evidence.
- The artifact affects hypothesis ranking or artifact generation.
- The boundary remains documented.

## P7: Quarantine Drift

- [ ] Use `audit/reports/BEAGLE_LINE_MAP.csv` to tag modules as keep, fix,
  freeze, quarantine, or remove.
- [ ] Freeze Workbench/Warp/Project Cockpit unless tied to the core workflow.
- [ ] Freeze Apple/iOS work unless it captures thought, physio, memory, or
  core-server operation.
- [ ] Freeze HPC/cluster work unless it produces scientific artifacts or
  retrieval improvement.
- [ ] Move operations-specific material out of the core path when possible.
- [ ] Delete only after dependency checks prove no core path imports it.

Acceptance:

- Every quarantined area has a written reason.
- Every deletion has dependency evidence.
- No useful Darwin/BEAGLE lineage is lost.

## Next Five Slices

1. Add offline-safe `beagle-quantum` measurement fallback and tests.
2. Add one quantum end-to-end hypothesis/evidence ranking test.
3. Wire captured IDE thought to backend memory write.
4. Wire memory retrieval into hypothesis generation.
5. Generate one artifact with Triad review and feedback.

## Done Means

A slice is done only when:

- Code or docs are changed in the repo.
- Relevant tests or checks pass.
- `git status --short` is understood.
- The next action is visible.
- The work strengthens the living workflow.

