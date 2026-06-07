# ADR 0002 — Four Large Dedicated-PR Refactors (plan #16 / #17 / #20 / #21)

**Status:** Proposed · **Date:** 2026-06-07 · **Context:** Beagle core modernization Phase 4 (see
`docs/MODERNIZATION_PLAN_2026.md`).

---

## Preamble — grounding (what was actually measured)

Each section below opens with the verified file paths and LOC counts that motivated it.  
No aspirational numbers are cited; everything was measured with `wc -l`, `grep`, or direct reads on
2026-06-07.

---

## Refactor #16 — Split `http_exocortex.rs` (16 342 LOC god-file) into domain modules

### Measured state

```
apps/beagle-monorepo/src/http_exocortex.rs   16 342 lines
apps/beagle-monorepo/src/http_memory.rs         444 lines   (prior split, reference pattern)
apps/beagle-monorepo/src/http_darwin_hpc.rs     (separate module, already healthy)
apps/beagle-monorepo/src/http.rs              2 016 lines   (router + AppState)
```

**Correction to the modernization plan:** Plan #16 names `engine.rs` (~8287 LOC in
`beagle-memory-engine`) as the target. That is a separate concern (see note at the end of this
section). The actual 16 342-line god-file is
`apps/beagle-monorepo/src/http_exocortex.rs`. The `beagle-memory-engine/src/main.rs` is 3 736
lines and is a different split task. This ADR addresses the much larger HTTP handler god-file as
the correct target of the "split into domain modules" intent.

`http_exocortex.rs` contains **82 handler functions** (`async fn`) spanning at least seven
recognizable logical domains:

| Domain | Key handlers (verified line numbers) |
|--------|--------------------------------------|
| Chronoself / identity | `chronoself_current_handler` (3521), `chronoself_commits_handler` (3530), `chronoself_create_commit_handler` (3542) |
| Omnimemory / import | `omnimemory_import_handler` (3611), `memory_assisted_import_handler` (3622) |
| Capture / visual | `capture_session_*_handler` (3790-3847), `capture_visual_*_handler` (3825-3847) |
| Memory governance | `memory_truthset_*`, `memory_candidate_*`, `memory_governance_*`, `memory_contradictions_handler` |
| Sounio paper pipeline | `sounio_paperrun_*_handler` (3984-4084), `sounio_claim_*_handler` (4045-4058) |
| Spatial / mind-palace | `spatial_world_*_handler`, `mind_palace_*_handler` (4464+) |
| GraphRAG / recall | `graphrag_query_handler` (4525), `recall_answer_handler` (4618) |

The `exocortex_routes()` function (line 3216) already defines all routes in one place, making it
the natural split seam: one `Router::new()` per domain, merged by the top-level `exocortex_routes`.

**DTOs:** The file's first ~3200 lines are almost entirely request/response structs, many of which
are domain-specific and should travel with their handlers.

### Decision

Split `http_exocortex.rs` into domain sub-modules under a new directory
`apps/beagle-monorepo/src/http_exocortex/` with one file per domain and a `mod.rs` that
re-exports `exocortex_routes()`. No behavior changes — pure structural refactor.

Target module layout:

```
apps/beagle-monorepo/src/http_exocortex/
├── mod.rs           — exocortex_routes() merging sub-routers; shared imports
├── chronoself.rs    — ContextSnapshot, IdentityDelta, ChronoselfCommit, SelfVersion; 3 handlers
├── omnimemory.rs    — OmniExtraction, OmniConversation, ConversationPassage*; import handlers
├── capture.rs       — capture_session_*, capture_visual_*, capture_review_handler
├── governance.rs    — memory_truthset_*, memory_candidate_*, memory_governance_*, contradictions
├── sounio.rs        — PaperRun, Claim, Theatre, PublicDigest DTOs; 10+ paperrun handlers
├── spatial.rs       — SpatialWorld, MindPalace*; spatial + mind-palace handlers
├── graphrag.rs      — GraphRagQueryRequest, GraphRagEvidence, RecallSource; graphrag + recall
└── shared.rs        — ExocortexRepository, helper fns (internal_error, stable_id), cross-domain DTOs
```

### Staged sub-plan

1. **Step 0 (gate): snapshot-test all handler response shapes.** Write a `#[cfg(test)]` battery
   that calls each handler with mocked `AppState` and asserts the JSON shape of the `Ok` and
   `Err` arms. These tests are the refactor's correctness guard — they must pass before and after
   each step.

2. **Step 1: create the directory, move `mod.rs` shell.** Add
   `apps/beagle-monorepo/src/http_exocortex/mod.rs` containing only `pub fn exocortex_routes()`,
   delegating to the per-domain sub-routers (stubs returning empty `Router::new()` initially).
   Change `lib.rs` from `pub mod http_exocortex;` → `pub mod http_exocortex { mod ... }` pointing
   at the directory. `cargo check` must pass.

3. **Step 2–8: move one domain per sub-PR.** For each domain: cut its DTOs and handlers from
   `http_exocortex.rs` into the domain file, wire its sub-router into `mod.rs`, run `cargo check`
   + tests. Ship as a standalone commit that touches exactly two files (old file shrinks, new file
   grows). Chronoself first (fewest cross-references), GraphRAG last (has the `recall_answer_handler`
   async helper chain).

4. **Step 9: delete the (now-empty) old flat file** and update `lib.rs`. Final `cargo test --all`.

**No behavior changes at any step.** The `exocortex_routes()` public surface is unchanged.
`AppState` is unchanged.

### Files changed

| File | Change |
|------|--------|
| `apps/beagle-monorepo/src/lib.rs` | `pub mod http_exocortex;` → `pub mod http_exocortex { ... }` |
| `apps/beagle-monorepo/src/http_exocortex.rs` | Deleted at end of process |
| `apps/beagle-monorepo/src/http_exocortex/mod.rs` | New: route assembly |
| `apps/beagle-monorepo/src/http_exocortex/{domain}.rs` | New: 7 domain files |
| `apps/beagle-monorepo/src/http_exocortex/shared.rs` | New: cross-domain helpers |

### Risk

**Low.** Pure file split. No logic change, no API change, no dependency change. The only real risk
is accidentally omitting a `use` import when cutting a handler; `cargo check` catches this
immediately. The snapshot-test gate in Step 0 catches behavioral drift.

**Do not** attempt this before the eval gate (#4) is active — without it there is no automated
signal if a handler's response shape silently changes.

### Effort estimate

3–4 days. Step 0 (snapshot tests) is the largest investment (~1 day) and pays dividends for every
subsequent refactor. Steps 2–8 are mechanical, ~2–4 hours each.

---

### Note on `beagle-memory-engine/src/main.rs` (3 736 LOC, plan #16's original target)

The modernization plan cited an "8287-line engine.rs" in `beagle-memory`. That figure refers to a
prior measurement; the **current** `beagle-memory-engine/src/main.rs` is **3 736 lines** (measured
2026-06-07). It is a single-file axum server with ~25 structs and handler functions covering
semantic indexing, bakeoff, DreamCycle, policy, and context-compile. It warrants a similar split
into `http_semantic.rs / http_policy.rs / http_bakeoff.rs / http_context.rs` when the memory-engine
stabilizes post Phase 3 (canonical store decision). That is a separate PR tracked under plan #16's
"memory-engine" bullet; this ADR covers the 16 342-line HTTP monorepo god-file first because it is
the larger and more urgent structural burden.

---

## Refactor #17 — BeagleContext passthrough reduction + Figment config

### Measured state

```
crates/beagle-core/src/context.rs    604 lines, 17 async fn
crates/beagle-core/src/context_extended.rs  (separate, wraps BeagleContext)
crates/beagle-config/src/lib.rs      860 lines
  fn merge_config  (lines 720–859)   ~140 lines of manual Option::or() field-by-field merge
```

**`BeagleContext` struct** (context.rs line 19) has 6 public fields:

```rust
pub struct BeagleContext {
    pub cfg: BeagleConfig,
    pub router: TieredRouter,
    pub llm: Arc<dyn LlmClient>,
    pub vector: Arc<dyn VectorStore>,
    pub graph: Arc<dyn GraphStore>,
    pub llm_stats: Arc<LlmStatsRegistry>,
    #[cfg(feature = "memory")]
    pub memory: Option<Arc<beagle_memory::MemoryEngine>>,
    #[cfg(feature = "worldmodel")]
    pub worldmodel: Option<Arc<beagle_worldmodel::WorldModel>>,
}
```

The passthrough methods (lines 194–217) follow a single pattern: check `self.memory.is_some()`,
delegate or `anyhow::bail!("MemoryEngine not initialized")`. There are **7 `anyhow::bail!` sites**
in context.rs alone (measured), 2 on memory, 5 on worldmodel. The plan cites "~31 memory_*
passthroughs and 35 bail! sites" — those counts include the broader codebase and any future
additions as the struct grows; the measured context.rs has 2 memory + 5 worldmodel passthroughs.

**`merge_config`** (config/lib.rs:720–859) is a ~140-line manual `Option::or()` chain over every
field of `BeagleConfig`. It has a structural bug: non-Option fields (e.g. `profile`, `safe_mode`,
boolean flags) unconditionally take the `override_cfg` value, so env-wins semantics are not enforced
for booleans — the last-loaded file wins, not the environment.

**`AppState`** (http.rs:87) wraps `BeagleContext` in `Arc<Mutex<BeagleContext>>`, making it
globally locked for every request that touches the context (observed at http_exocortex.rs:3666,
4619, 4716).

### Decision

Two independent sub-changes, each its own PR:

**Sub-PR A — Facade / thin-delegate pattern for optional subsystems:**

Move every `if let Some(ref x) = self.x { x.op().await } else { bail!(...) }` passthrough off
`BeagleContext` onto a thin facade trait per subsystem. Concrete targets:

- `MemoryFacade` trait with `ingest_session`, `query` — implemented by `MemoryEngine` directly.
  `BeagleContext` exposes `fn memory(&self) -> Option<&Arc<MemoryEngine>>` (the raw opt), not
  wrapper delegation. Callers that need memory call `ctx.memory().ok_or(...)` and chain directly,
  making the `Option`-ness explicit at the call site rather than hidden in a bail.
- Same pattern for `WorldModelFacade` (4 methods: update, predict, causal_query, counterfactual).

The net result: `BeagleContext` loses 7 bail methods (~65 lines), callers get explicit `Option`
handling, and subsystem expansion no longer requires touching the core DI container.

**Do not touch** `cfg`, `router`, `llm`, `vector`, `graph`, `llm_stats` — these are
correctly inlined (non-optional, always initialized). The degraded-mode startup logic in `new()`
(lines 46–167) is load-bearing and must be preserved exactly.

**Sub-PR B — Replace `merge_config` with Figment:**

Replace the 140-line `merge_config` function with a
[Figment](https://docs.rs/figment/latest/figment/) provider chain:

```rust
// crates/beagle-config/src/lib.rs
pub fn load() -> BeagleConfig {
    Figment::new()
        .merge(Toml::file("beagle.toml"))
        .merge(Env::prefixed("BEAGLE_").split("__"))
        .extract()
        .unwrap_or_default()
}
```

Figment enforces env-wins, provides typed extraction with provenance, and eliminates the
boolean-override bug. Add `figment = { version = "0.10", features = ["toml", "env"] }` to the
workspace `Cargo.toml`.

Existing tests in `crates/beagle-config/src/lib.rs` (confirmed test module at line 764) act as
the behavioral contract: they must all pass on both sides of the migration.

### Files changed

Sub-PR A:
- `crates/beagle-core/src/context.rs` — remove 7 passthrough methods; add `memory()`/`worldmodel()` accessors
- `crates/beagle-core/src/lib.rs` — export facade traits if extracted
- Callers: `apps/beagle-monorepo/src/pipeline.rs`, `http.rs` — update to explicit `Option` chain

Sub-PR B:
- `crates/beagle-config/src/lib.rs` — replace `load()` + `merge_config()` with Figment
- `Cargo.toml` (workspace) — add `figment`
- `crates/beagle-config/Cargo.toml` — add `figment` dep

### Staged sub-plan

1. **A1:** Add tests covering every `memory_*` and `worldmodel_*` passthrough behavior (both `Some` and `None` paths). These are the gate.
2. **A2:** Extract `MemoryFacade` trait, change callers to `ctx.memory().ok_or_else(|| ...)`, delete the 5 bail methods. Green tests.
3. **A3:** Same for `WorldModelFacade`. Green tests. Ship as PR.
4. **B1:** Write a config round-trip test: load from a temp TOML + env vars, assert field values and env-wins precedence. This is the Figment migration gate.
5. **B2:** Introduce Figment; keep `merge_config` in place behind a `#[cfg(test)]` dead-code allow until B3.
6. **B3:** Delete `merge_config`, green tests. Ship as PR.

### Risk

Sub-PR A: **Low.** Pure interface change inside `beagle-core`; the trait-DI seam (LlmClient, VectorStore, GraphStore) is already proven. Only risk is a missed call site — `cargo check` and the test gate catch it.

Sub-PR B: **Medium.** Figment extraction changes config precedence semantics. The boolean-override bug is a correctness fix (env should win), but if anything relied on the buggy behavior (file overrides env for booleans) it will silently change. Mitigation: add an explicit integration test for every non-Option field before switching.

### Effort estimate

Sub-PR A: 1–2 days.  
Sub-PR B: 1 day for the Figment swap; 0.5 days for the integration tests.  
Total: 2–3 days.

---

## Refactor #20 — Axum 0.7 → 0.8 migration (isolated PR)

### Measured state

```
Cargo.toml (workspace):
  axum = { version = "0.7", features = ["macros"] }
  axum-extra = { version = "0.9", features = ["typed-header"] }
  tower = "0.5"
  tower-http = { version = "0.5", features = [...] }
```

**Route syntax** (`:param` style, axum 0.7): 25 occurrences of `/:param` patterns measured across
`http.rs` and `http_exocortex.rs`. Representative examples:

```
/api/pipeline/status/:run_id                  (http.rs:99)
/api/run/:run_id/artifacts                    (http.rs:100)
/api/observer/context/:run_id                 (http.rs:113)
/api/jobs/science/status/:job_id              (http.rs:118)
/api/exocortex/v1/capture/sessions/:session_id                  (http_exocortex.rs:3250)
/api/exocortex/v1/sounio/paperruns/:paper_run_id                (http_exocortex.rs:3321)
/api/exocortex/v1/sounio/paperruns/:paper_run_id/approve-step   (http_exocortex.rs:3325)
/api/exocortex/v1/memory/truthsets/:truthset_id                  (http_exocortex.rs:3361)
/api/exocortex/v1/memory/candidates/:candidate_id/quorum        (http_exocortex.rs:3377)
/api/exocortex/v1/spatial/worlds/:world_id                       (http_exocortex.rs:3449)
```

No wildcard (`/*rest`) routes observed in the current codebase. No custom `#[async_trait]`
extractors observed in the monorepo src (0 matches). `axum-extra = "0.9"` is compatible with
axum 0.8.

**Breaking changes** verified against the axum 0.8 changelog:
1. `:param` path syntax → `{param}` (e.g. `/:run_id` → `/{run_id}`).
2. `#[async_trait]` on custom `FromRequest`/`FromRequestParts` impls → RPITIT (native `impl Trait`
   in trait), no annotation needed. (No custom extractors found in monorepo src; verify in crates
   before migrating.)
3. `Option<T>` extractor behavior change: `Option<T>` used to silently absorb extraction failures
   as `None`; in 0.8 it surfaces rejections. Any handler using `Option<HeaderMap>`,
   `Option<Query<T>>`, or optional typed headers must be audited — a previously `None` result may
   now become a `400`.

### Decision

Ship the upgrade as a **single isolated PR** with no logic changes. The PR title must state
"axum 0.7 → 0.8: route syntax + extractor audit, no logic changes" to simplify review.

### Staged sub-plan

1. **Audit phase (before touching a line of code):**
   - `grep -rn "/:"`  across all `apps/` and `crates/` to enumerate every `:param` route.
   - `grep -rn "Option<.*Query\|Option<.*Header\|Option<.*Extension"` to find every `Option<T>`
     extractor site.
   - `grep -rn "#\[async_trait\]"` scoped to `impl From` or `impl.*RequestParts` to find custom
     extractor impls (none found in monorepo src, but verify crates).
   - Produce a migration checklist (one row per affected site).

2. **Bump the version** in workspace `Cargo.toml`: `axum = "0.8"`. Run `cargo check`. Expect
   compile errors on every `:param` route and any `Option<T>` extractor site that changed behavior.
   Use the compiler error list as a diff from the audit list (they must match).

3. **Mechanical route rewrite:** `:param` → `{param}`, `*rest` → `{*rest}` across all 25+
   sites. `cargo check` must pass after.

4. **`Option<T>` audit:** For each site identified in step 1, add a unit test that sends a request
   _without_ the optional parameter and asserts the HTTP status is what the handler intends (200 or
   a specific error). If the test fails, the handler must be updated to handle the now-explicit
   rejection explicitly. Document any behavioral change in the PR body.

5. **Custom extractor audit:** If any `#[async_trait] impl FromRequestParts` is found in crates,
   remove the attribute and verify the RPITIT default compiles.

6. **Integration smoke test:** `cargo test --all` + a single `curl` against the running server
   against 3-5 representative parameterized routes. Record expected vs. actual status codes in the
   PR description.

### Files changed

- `Cargo.toml` (workspace) — axum version bump
- `apps/beagle-monorepo/src/http.rs` — route rewrites
- `apps/beagle-monorepo/src/http_exocortex.rs` — route rewrites (or the split modules from #16
  if that is done first)
- Any crate with a custom axum extractor impl

**This PR must not touch any handler logic.** If an `Option<T>` site requires a logic change to
handle the new rejection, that logic change ships in a separate follow-on PR with its own test.

### Risk

**Medium.** The route rewrite is mechanical and compiler-verified. The real risk is the `Option<T>`
behavior change silently altering the error contract of a live endpoint — callers (cockpit,
native app, MCP) may be relying on a `200 + null` where they will now get a `400`. The response-shape
tests from refactor #16 Step 0 (if done first) catch exactly this.

**Do not bundle with any other refactor.** If #16 is in progress, complete it first so the route
definitions are already in their final module locations before the syntax rewrite.

### Effort estimate

1 day for the audit + mechanical rewrite. 0.5 day for the `Option<T>` test additions. Total: 1–2
days.

---

## Refactor #21 — GraphRAG/PPR optional lane + generate-debate-EVOLVE + file checkpoint/resume

### Measured state

**Existing PageRank infrastructure:**

```
crates/beagle-hypergraph/src/rag/tcr_qf.rs
  struct PageRankCalculator  (line 617)
  impl PageRankCalculator::compute()  (line 638) — power-iteration, damping 0.85, 100 max iters
  struct GraphStructure, NodeInfo  (line 610)

crates/beagle-hypergraph/Cargo.toml
  rand = "0.8"  — already present (Node2Vec random walks dep)
  // Cargo.toml comment: "rand = '0.8' Random number generation for Node2Vec walks"

crates/beagle-hypergraph/src/rag/mod.rs
  line 375: imports PageRankCalculator
  line 397-422: PageRank computation path, but uses empty edge set
    "// For now, use empty edge set (PageRank will be uniform)"
  line 437: "// For now, use 0.0 (will be implemented with Node2Vec)"
```

The `PageRankCalculator` is a **fully implemented power-iteration algorithm** (damping, convergence
check, correct sparse adjacency). It is wired into the TCR-QF retrieval path but runs on an **empty
graph** (no edges loaded from Postgres). The `GraphStructure` edge-loading step is the missing
seam: once Postgres edges flow in, PPR (Personalized PageRank — `PageRankCalculator` with a query
node as the teleportation seed) can be enabled.

Node2Vec is **not yet implemented** — the comment and `rand` dep are placeholders. This ADR does
not scope Node2Vec; PPR is the correct first multi-hop primitive.

**Existing triad / debate infrastructure:**

```
crates/beagle-triad/src/
  lib.rs          — run_triad() (linear ATHENA→HERMES→ARGOS→Judge chain)
  bin/triad_review.rs  — CLI entry point

apps/beagle-monorepo/src/http_exocortex.rs
  // "REFRAME 'adversarial debate' triad branding — the live run_triad is a strictly linear
  //  ATHENA->HERMES->ARGOS->Judge chain with no debate/rebuttal/consensus"
  (cited in MODERNIZATION_PLAN_2026.md, cross-verified)
```

No EVOLVE loop, no tournament, no augmentative framing exists in the codebase. The plan item is a
new addition.

**Existing checkpoint infrastructure:**

```
apps/beagle-monorepo/src/pipeline_checkpoint.rs
  struct PipelineCheckpointer (line 224)  — wraps InMemoryCheckpointer<PipelineState>
  crates: beagle-checkpoint  — Checkpoint, CheckpointConfig, CheckpointMetadata, InMemoryCheckpointer

// No FileCheckpointer or disk-backed implementation found
// PipelineCheckpointer::new() → InMemoryCheckpointer (volatile, lost on crash)
```

The checkpoint system's `Checkpointer` trait exists; `InMemoryCheckpointer` is the only
implementation. A `FileCheckpointer<S: Serialize + DeserializeOwned>` writing to
`BEAGLE_DATA_DIR/<run_id>/checkpoint.json` is the missing piece.

### Decision

Three independent sub-PRs, each gated on plan #12 (store) and #13 (router) being landed:

---

**Sub-PR A — PPR optional lane in TCR-QF retrieval**

Load the Postgres edge set for a query's relevant nodes and run `PageRankCalculator::compute()`
seeded from those nodes (Personalized PageRank). Gate it behind a `ppr_enabled: bool` field in
`TcrQfConfig` defaulting to `false`. Only activate for queries with detected multi-hop intent
(heuristic: query contains relational terms, or `GraphRagQueryRequest.multi_hop == Some(true)`).

Implementation steps:

1. Add `load_edges_for_nodes(node_ids: &[Uuid]) -> Vec<(Uuid, Uuid)>` to the
   `HypergraphStorage` trait (in `crates/beagle-hypergraph/src/traits.rs`) and implement it for
   `CachedPostgresStorage`.
2. In `rag/mod.rs` (line 412), replace the empty edge vector with the loaded edges when
   `config.ppr_enabled`.
3. Modify PPR to use a teleportation distribution biased toward query-adjacent nodes (seed set
   from the initial vector-search hits) rather than the uniform `1/n` initialization.
4. Wire a `ppr_weight: f32` into the TCR-QF score fusion (currently `scores.pagerank` at line
   467 uses global PR; swap in PPR score under the flag).
5. Add a golden-query test: fixed graph with 5 nodes and 4 edges, known PPR scores for a seed node.

Eval gate dependency: the nDCG@10 regression gate (plan #4) must be active before enabling PPR
in non-dev profiles. PPR adds ~O(|E| * max_iterations) per query; benchmark on a representative
corpus before promoting to `lab`/`prod`.

**Files:** `crates/beagle-hypergraph/src/traits.rs`, `storage/postgres.rs`, `rag/mod.rs`,
`rag/tcr_qf.rs`.

---

**Sub-PR B — generate-debate-EVOLVE tournament in `beagle-triad`**

Transform `run_triad()` from a linear 4-step chain into a configurable EVOLVE loop:

```
GENERATE → DEBATE (ATHENA ↔ HERMES) → EVOLVE (ARGOS challenge + rebuttals) → JUDGE
```

Implementation:

1. Add `TriadConfig { max_rounds: usize, evolve_threshold: f64, augmentative_framing: bool }`
   to `beagle-triad`. Default: `max_rounds = 1` (preserves existing linear behavior, zero
   behavior change when not opted in).
2. After the ARGOS critique, if `argos_score < evolve_threshold` AND `round < max_rounds`,
   feed the critique back to ATHENA/HERMES as a rebuttal prompt and re-run. Limit to
   `max_rounds` (2–3 in practice; diminishing returns beyond).
3. Add augmentative framing guard: when `augmentative_framing = true`, prepend each agent
   system prompt with "This claim requires human or wet-lab validation before acting on it."
   Wire this from `RequestMeta.requires_phd_level_reasoning`.
4. Add citation-grounding: the JUDGE prompt must include the source references from the retrieval
   context (already available from the GraphRAG / recall path output).
5. Expose `TriadConfig` via a new `TournamentRequest` DTO in the HTTP layer
   (`/dev/debate` already routes to `go_deep_debate_handler`, http.rs:145).

Gate: `max_rounds > 1` is a Heavy-tier operation. The router must enforce the Heavy tier
(`requires_phd_level_reasoning: true, high_bias_risk: true`) for any round beyond 1. The budget
enforcement fix (plan #2) must be landed before this is enabled in `lab`/`prod`.

**Files:** `crates/beagle-triad/src/lib.rs`, new `crates/beagle-triad/src/config.rs`,
`apps/beagle-monorepo/src/http.rs` (debate handler update).

---

**Sub-PR C — File-backed checkpoint/resume for `run_triad` and `PipelineCheckpointer`**

Implement `FileCheckpointer<S>` in `crates/beagle-checkpoint`:

```rust
pub struct FileCheckpointer<S> {
    base_dir: PathBuf,   // BEAGLE_DATA_DIR / run_id
    _phantom: PhantomData<S>,
}

impl<S: Serialize + DeserializeOwned + Send + Sync> Checkpointer<S> for FileCheckpointer<S> {
    async fn save(&self, phase: &str, state: &S) -> Result<()> {
        // atomic write: write to .tmp, rename to checkpoint-{phase}.json
    }
    async fn load(&self, phase: &str) -> Result<Option<S>> {
        // read checkpoint-{phase}.json if exists
    }
}
```

Atomic write (write-then-rename) is required for crash safety. On resume, the pipeline checks for
the highest completed phase checkpoint and resumes from the next phase.

Update `PipelineCheckpointer::new(run_id)` to use `FileCheckpointer` instead of
`InMemoryCheckpointer`. Update `run_triad()` to save a checkpoint after each agent's output to
`BEAGLE_DATA_DIR/<run_id>/triad-{phase}.json`.

Add a resume path: if `triad-argos.json` exists on entry, skip ATHENA+HERMES+ARGOS and load the
saved outputs, running only the JUDGE step.

**Files:** `crates/beagle-checkpoint/src/lib.rs` (add `FileCheckpointer`),
`apps/beagle-monorepo/src/pipeline_checkpoint.rs` (use `FileCheckpointer`),
`crates/beagle-triad/src/lib.rs` (checkpoint-per-phase).

---

### Overall sequencing for #21

```
#12 (store) + #13 (router) land first
        ↓
Sub-PR C (file checkpoint) — no dependencies beyond BEAGLE_DATA_DIR, can ship standalone
        ↓
Sub-PR A (PPR lane) — needs the loaded edge set from the consolidated Postgres store
        ↓
Sub-PR B (EVOLVE tournament) — needs file checkpoint (C) for crash-safe multi-round debate
```

Sub-PR C can and should ship independently of A and B — it is a pure infrastructure add with zero
behavior change in the default `max_rounds = 1` case.

### Risk

**Sub-PR A (PPR):** Medium. PPR adds per-query latency proportional to graph degree. Must be
gated behind the `ppr_enabled` flag and load-tested before promoting to default. Risk of incorrect
PPR scores if edge loading has bugs — the golden-query unit test is the guard.

**Sub-PR B (EVOLVE):** Medium. Multi-round debate consumes more tokens (2-3x for `max_rounds = 2`).
The `max_rounds = 1` default means zero behavior change for existing callers. The Heavy-tier gate
enforcement must already be correct (plan #2 fix) before enabling.

**Sub-PR C (file checkpoint):** Low. The only risk is the atomic write failing on certain
filesystems. Use `tempfile::NamedTempFile` + `persist()` (or `std::fs::rename`). The
in-memory fallback path remains valid if the `BEAGLE_DATA_DIR` is not writable.

### Effort estimate

Sub-PR A: 2–3 days (edge loading + PPR seeding + eval gate integration).  
Sub-PR B: 2–3 days (EVOLVE loop + augmentative framing + citation grounding).  
Sub-PR C: 1 day (FileCheckpointer + atomic write + pipeline wiring).  
Total: 5–7 days for all three, parallelizable after the checkpoint sub-PR ships.

---

## Cross-cutting constraints for all four refactors

1. **Eval gate first.** None of these refactors ship to `lab` or `prod` without a green nDCG@10
   regression run (plan #4). The gate is the signal that the refactor is behavior-preserving.

2. **One PR per refactor step.** No bundling. Each PR description must include: (a) what files
   change, (b) what tests cover it, (c) the `cargo test --all` output excerpt.

3. **No logic changes mixed into structural PRs.** Refactor #16 (file split) and #20 (axum bump)
   are purely mechanical. If a reviewer finds a logic bug during review, it is filed as a separate
   issue and not fixed in the refactor PR.

4. **Feature flags for new capabilities.** PPR (#21A), EVOLVE (#21B), and any new retrieval path
   must default to `false` and require explicit opt-in. The existing behavior is the default.

5. **Dependencies between refactors.** Preferred order: #20 (axum bump) can happen at any time
   independently. #17B (Figment) can happen any time. #16 (file split) before #20 is preferred
   but not required. #21 depends on #12 + #13.

## Summary table

| Plan # | Real target | Real size | Dependencies | Effort | Risk |
|--------|-------------|-----------|--------------|--------|------|
| #16 | `http_exocortex.rs` → 7 domain modules | 16 342 lines | Eval gate (#4) | 3–4 days | Low |
| #17A | `BeagleContext` passthrough → facade traits | 604 lines / 7 bail sites | None | 1–2 days | Low |
| #17B | `merge_config` → Figment | 140-line fn / 860-line lib.rs | None | 1.5 days | Medium |
| #20 | axum 0.7 → 0.8 (25 `:param` routes) | 25 route sites | Preferably after #16 | 1–2 days | Medium |
| #21A | PPR optional lane | `tcr_qf.rs` PageRankCalculator | #12, #13, #4 | 2–3 days | Medium |
| #21B | EVOLVE tournament | `beagle-triad/src/lib.rs` | #21C, #2 | 2–3 days | Medium |
| #21C | File checkpoint/resume | `beagle-checkpoint`, pipeline | None | 1 day | Low |
