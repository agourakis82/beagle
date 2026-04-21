# B15.2 - Aspirational Beagle Charter

## Current status

B15.2 is `GO`.

Canonical deliverables for this phase:

- `docs/darwin/hpc/B152_ASPIRATIONAL_BEAGLE_CHARTER.md`
- `docs/darwin/hpc/B152_GO_NO_GO.md`
- `docs/darwin/hpc/B152_KNOWN_LIMITS.md`
- `docs/darwin/hpc/PROGRAM_LINEAGE.md`
- `docs/darwin/hpc/contracts/project-constitution.yaml`
- `scripts/infrastructure/darwin-hpc/run_project_constitution_consistency_check.sh`
- `scripts/infrastructure/darwin-hpc/validate_project_constitution_consistency_check.sh`

Canonical consistency-check evidence lives under:

- `.artifacts/darwin-hpc/project-constitution-consistency-check/source-summary.json`
- `.artifacts/darwin-hpc/project-constitution-consistency-check/constitution-normalized.json`
- `.artifacts/darwin-hpc/project-constitution-consistency-check/current-state-summary.json`
- `.artifacts/darwin-hpc/project-constitution-consistency-check/lineage-summary.json`
- `.artifacts/darwin-hpc/project-constitution-consistency-check/consistency-summary.json`

## Objective

Create the first repo-native constitutional bridge between:

1. operational Beagle as already proven
2. aspirational Beagle as the intended Workstream OS
3. the planes, lanes, workstreams, boundaries and governance states that define
   that identity

This phase does not add a new technical subsystem. It establishes the
constitutional layer that tells the repo what Beagle already is, what it is not
allowed to regress into, and what it is trying to become.

## North star

Beagle's north star is:

1. one repo-native operating system for governed workstreams
2. cluster-first by default
3. explicit about session, handoff, results, providers and governance
4. able to host real work continuously without recentering the VM or inventing
   parallel architecture

## Operational Beagle vs aspirational Beagle

### Operational Beagle

Operational Beagle is the already-proven kernel:

- `core_server` is the canonical runtime entrypoint
- `beagle-cluster` is the canonical default dev plane
- the VM is `fallback-only`
- one canonical workstream is cut over, recipe-backed and governance-backed
- the control room exists internally and can resolve workstream, recipe,
  governance, handoff and last-result state
- the cheap provider lane is live and bounded

### Aspirational Beagle

Aspirational Beagle is the declared direction:

- Beagle becomes the canonical operating system for multiple governed
  workstreams
- workstreams remain repo-native objects, not implicit behavior
- promotion, rollback and recovery remain explicit and bounded
- control remains internal-first and governance-led
- forward growth happens by governed expansion of workstreams and recipes, not
  by reopening lower layers or multiplying ad hoc surfaces

## Canonical planes

The charter freezes these planes as the current identity skeleton:

1. workspace/session plane
   - authority: `crates/beagle-darwin/src/workspace_plane.rs`
   - role: session, handoff, fallback and workstream cutover continuity
2. workstream contract plane
   - authority: `docs/darwin/hpc/workstreams/`
   - role: registry, spec and recipe identity
3. control-room plane
   - authority: `crates/beagle-darwin/src/workstream_control_room.rs`
   - role: operator visibility over workstream state
4. compute plane
   - authority: `apps/beagle-monorepo/src/http_darwin_hpc.rs` plus the external
     Darwin HPC gateway
   - role: CPU/GPU profile execution and result lookup
5. truth plane
   - authority: `crates/beagle-darwin/src/object_results.rs` and
     `crates/beagle-darwin/src/result_catalog.rs`
   - role: object-backed publication, retrieval and catalog state
6. provider bridge plane
   - authority: `crates/beagle-darwin/src/tool_bridge.rs` and
     `docs/darwin/hpc/contracts/tool-bridge-policy.yaml`
   - role: bounded provider execution lanes and ledger
7. governance plane
   - authority: workstream contracts, workspace policy and config state
   - role: promotion, hold, rollback and recovery semantics

## Lanes

The charter distinguishes lanes instead of hiding them:

1. dev-plane lane
   - default: `beagle-cluster`
   - fallback role: `fallback-only`
2. provider lanes
   - `cheap_api`: `deepseek`, `glm5`, `minimax`, `grok_fast`, `kimi`
   - `human_premium`: represented but never automatic cluster center
   - `mcp_connector`: bounded connector lane
3. consumer lanes
   - `operator`: full
   - `darwin_research`: bounded

## Workstream model

The charter freezes the current workstream model as:

1. repo-native registry in `docs/darwin/hpc/workstreams/registry.yaml`
2. explicit spec per canonical workstream
3. recipe-backed execution semantics
4. governance-backed lifecycle states
5. one current canonical workstream:
   - `beagle-darwin-hpc-governance`

## Governance states

The minimum governance lifecycle is part of the identity, not an implementation
detail:

- states:
  - `staged`
  - `pilot`
  - `canonical`
  - `held`
  - `rollback`
  - `recovery`
- transitions:
  - `promote`
  - `hold`
  - `resume`
  - `rollback`
  - `recover`

## Non-negotiables

The constitutional non-negotiables are:

1. `default_dev_plane` remains `beagle-cluster`
2. the VM remains `fallback-only`
3. fallback stays explicit, bounded and recorded
4. workstreams remain repo-native, recipe-backed and governance-backed
5. result publication and retrieval remain object-backed
6. the provider bridge remains ledgered and bounded
7. no hidden premium lane recentering
8. no hidden multi-agent or magic fallback behavior
9. no reopening ingress, edge, HA or backplane redesign on this line

## Current canonical state

The charter reflects this already-proven state:

1. `B14.1 = GO`
2. `B14.2 = GO`
3. `B14.3 = GO`
4. `B14.4 = GO`
5. `B15.1 = GO`
6. live service:
   - deployment: `beagle-core`
   - service: `beagle-core`
   - binary: `core_server`
   - profile: `cluster`
7. canonical workstream:
   - `beagle-darwin-hpc-governance`
8. canonical governance state:
   - `canonical`
   - last transition: `resume`
9. cheap lane:
   - status: `effectively_closed`
   - `deepseek`
   - `glm5`
   - `minimax`
   - `grok_fast`
   - `kimi`

## Forbidden regressions

The charter explicitly forbids:

1. recentering the VM as the normal development plane
2. treating workstreams as implicit or ad hoc behavior again
3. bypassing the repo-native registry/spec/recipe layer
4. replacing the canonical live service with legacy parallel server paths
5. reopening provider expansion as the center of the roadmap
6. widening into public UI, ingress, edge or HA before the internal operating
   model asks for it explicitly

## Forward map

The forward map from here is:

1. strengthen governed internal operation first
2. widen from one canonical workstream to a portfolio only when the same
   constitutional rules remain intact
3. add capability by extending workstreams, recipes and governance, not by
   reopening the foundation

## Result

B15.2 closes as `GO` because the repo now has:

1. a first-class charter
2. a first-class YAML constitution
3. a first-class lineage document
4. a local consistency check that proves the constitutional layer matches the
   already-proven operational state
