# Dialogue Tapestry — Sovereign Cognitive Telemetry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the functor F (dyadic dialogue trajectory → bit-exact 𝕊-valued telemetry of coherence / speaker-asymmetry / dissociation) over Demetrios' own conversations, consumable live by the companion and historically (correlated with Physiome). The paper artifact (instantiated F + resolved FP64/J_n) falls out of a real instrument.

**Architecture:** Phase A = F in Sounio stdlib (bit-exact, builds on `math::sedenion`, `sed_associator`, `octonion`, `g2_equivariant`, `psychiatry.sio`). Phase B = telemetry pipeline in Beagle (exocortex convos + embeddings → `souc` runs F → write telemetry back). Phase C = two consumers (companion grounding + Physiome correlation extension + report).

**Tech Stack:** Sounio (`.sio`, `souc`), Node.js (Beagle apps), bge-m3 sovereign embedder, exocortex assisted-import, LanceDB telemetry.

**Spec:** `docs/superpowers/specs/2026-06-23-dialogue-tapestry-telemetry-design.md`

**Authority boundary:** Phase A is **Sounio** — branch from `integration/sounio-dev-ready-base` (NEVER main); use `SOUC_BIN` + `SOUNIO_STDLIB_PATH` per the Sounio CLAUDE.md. Phase B/C are **Beagle** (`feat/exocortex-grounding` or a new branch).

---

## Phase A — Functor F in Sounio (`stdlib/cybernetic/dialogue_tapestry.sio`)

> Prereq: `cd /home/devsounio/sounio && git switch integration/sounio-dev-ready-base && git switch -c feat/dialogue-tapestry-f && export SOUC_BIN="$(pwd)/bin/souc" && export SOUNIO_STDLIB_PATH="$(pwd)/stdlib"`. Read `stdlib/cybernetic/psychiatry.sio` (`patient_as_sedenion`, `zero_divisor_proximity`, the 168-theorem comment) and `stdlib/gpu/sedenion_kernels.sio` (`sed_associator`) before writing — reuse them.

### Task A1: turn lift + module scaffold (TDD)

**Files:**
- Create: `stdlib/cybernetic/dialogue_tapestry.sio`
- Create test: `stdlib/cybernetic/dialogue_tapestry_test.sio` (follow the pattern of `stdlib/compiler/ast/sedenion_test.sio`)

- [ ] **Step 1: Failing test** — `turn_to_octonion` maps an 8-component embedding slice to a normalized pure-imaginary octonion (e0 component = 0, ‖o‖≈1 for nonzero input).

```sio
// dialogue_tapestry_test.sio (excerpt)
fn test_turn_to_octonion_normalizes() -> bool with Mut, Div, Panic {
    let v: [f64; 8] = [0.0, 1.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    let o = turn_to_octonion(v)
    // e0 (real part) forced to 0; norm of imaginary part ~ 1
    dt_approx_eq(o[0], 0.0, 0.0001) && dt_approx_eq(oct_norm8(o), 1.0, 0.001)
}
```

- [ ] **Step 2: Run, expect FAIL** (`turn_to_octonion` undefined). `bash scripts/run_sio_test_suite.sh dialogue_tapestry`
- [ ] **Step 3: Implement** `turn_to_octonion(v: [f64;8]) -> [f64;8]` (zero the real part, L2-normalize the imaginary part using the `psychiatry_sqrt_f64` pattern) + helper `oct_norm8` + `dt_approx_eq`. Document the seeded-projection assumption (the caller supplies the 8-dim slice; the projection ℝ^1024→ℝ^8 is fixed in Phase B).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(sounio): dialogue_tapestry turn lift (octonion)`.

### Task A2: associator coherence over a triple (TDD, reuse `sed_associator`)

- [ ] **Step 1: Failing test** — `coherence(o_prev, o_cur, o_next)` returns 0 for a collinear/associative triple and >0 for a known non-associative octonion triple (use basis elements whose associator the 168-theorem says is nonzero, e.g. e1,e2,e4 → norm 2).

```sio
fn test_coherence_nonassociative_triple() -> bool with Mut, Div, Panic {
    let a = oct_basis(1); let b = oct_basis(2); let c = oct_basis(4)
    coherence(a, b, c) > 0.5   // nonzero associator (168-theorem: norm 2)
}
fn test_coherence_associative_is_zero() -> bool with Mut, Div, Panic {
    let a = oct_basis(1); let b = oct_basis(1); let c = oct_basis(1)
    dt_approx_eq(coherence(a, b, c), 0.0, 0.0001)
}
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `coherence` = L2 norm of the octonion associator `(ab)c − a(bc)`. Reuse octonion multiply from `stdlib/nn/octonion.sio` (or the sedenion octonion sub-block); add `oct_basis(i)`. Keep it bit-exact (no FP shortcuts).
- [ ] **Step 4: Run, expect PASS. Step 5: Commit** `feat(sounio): associator coherence telemetry`.

### Task A3: L/R speaker-directional asymmetry (TDD — the new operational def)

- [ ] **Step 1: Failing test** — `lr_asymmetry(o_a, o_b)` = ‖o_a·o_b − o_b·o_a‖ is 0 when a==b and >0 for non-commuting basis elements; `fano_mode(i,j)` returns `(i+j) mod 7 + 1`.

```sio
fn test_lr_zero_for_equal() -> bool with Mut, Div, Panic {
    let a = oct_basis(3)
    dt_approx_eq(lr_asymmetry(a, a), 0.0, 0.0001)
}
fn test_lr_nonzero_for_noncommuting() -> bool with Mut, Div, Panic {
    lr_asymmetry(oct_basis(1), oct_basis(2)) > 0.5
}
fn test_fano_mode() -> bool { fano_mode(1, 2) == ((1 + 2) % 7 + 1) }
```

- [ ] **Step 2: FAIL. Step 3: Implement** `lr_asymmetry` (commutator norm) + `fano_mode` (the existing `label(u,v)=e_{(u+v) mod 7 + 1}` encoding). Document that this is the operational definition of correspondence (ii), defended coupled to (i)+(iii).
- [ ] **Step 4: PASS. Step 5: Commit** `feat(sounio): L/R speaker-directional asymmetry + Fano mode`.

### Task A4: zero-divisor proximity per turn (TDD — exact, resolves J_n)

- [ ] **Step 1: Failing test** — reuse the psychiatry lift: a turn sedenion built from (content slice, uncertainty slice); `zd_proximity(s)` ≈ 0 for a constructed zero-divisor configuration and > 0 for a generic one. (Mirror `psychiatry.sio::zero_divisor_proximity`; assert exactness — same input twice gives bit-identical output.)
- [ ] **Step 2: FAIL. Step 3: Implement** `turn_to_sedenion(value:[f64;8], unc:[f64;8]) -> [f64;16]` (same construction as `patient_as_sedenion`) and `zd_proximity(s:[f64;16]) -> f64` (reuse the existing imbalance/ortho formula). All in exact f64 CD arithmetic — no FP approximation path here.
- [ ] **Step 4: PASS. Step 5: Commit** `feat(sounio): exact zero-divisor proximity per turn`.

### Task A5: the functor F over a trajectory (TDD — the artifact)

- [ ] **Step 1: Failing test** — `tapestry(turns)` over a 3-turn fixture returns a telemetry array with, per turn, `{coherence, lr_asymmetry, fano_mode, zd_proximity, rupture}` where `rupture = zd_proximity < RUPTURE_THRESHOLD`; first turn has coherence 0 (no triple yet); shape == number of turns.

```sio
fn test_tapestry_shape_and_rupture() -> bool with Mut, Div, Panic {
    let turns = make_test_turns()   // 3 turns: embed8 + unc8 + speaker
    let tel = tapestry(turns)
    dt_len(tel) == 3 && tel[0].coherence == 0.0 && is_bool(tel[1].rupture)
}
```

- [ ] **Step 2: FAIL. Step 3: Implement** a `Turn` struct `{speaker: i32, embed: [f64;8], unc: [f64;8]}`, a `Telemetry` struct, and `tapestry(turns: [Turn]) -> [Telemetry]` that walks the trajectory: lift each turn (A1, A4), compute coherence over the sliding triple (A2), lr_asymmetry over adjacent exchange (A3), zd_proximity (A4), rupture flag, and a coarse `g2_class` (v1: bucket of zd_proximity; full G2 orbit deferred to v2 — note in code). Pure + bit-exact.
- [ ] **Step 4: PASS. Step 5: Commit** `feat(sounio): functor F — dyadic trajectory to S-valued telemetry`.

### Task A6: file-driven entrypoint for the pipeline

- [ ] **Step 1:** Add a `tapestry_run` entrypoint that reads a trajectory from a simple line-based input (one turn per line: `speaker e0..e7 u0..u7`) and prints one telemetry record per line as CSV/JSON — so Phase B can invoke `souc run dialogue_tapestry.sio < input`. Test with a fixture file + golden output.
- [ ] **Step 2: Run the full Sounio gate** `bash scripts/run_sio_test_suite.sh dialogue_tapestry` (all A1–A6 green) + `bash scripts/stdlib_reliability_gate.sh` to confirm no stdlib regression. **Step 3: Commit** `feat(sounio): tapestry_run file entrypoint`. Push `feat/dialogue-tapestry-f`.

---

## Phase B — telemetry pipeline (Beagle, `apps/cognitive-telemetry/`)

> Beagle side. Node app, mirrors `apps/exocortex-ingest` patterns (secrets, contracts) + `apps/physiome` test style.

### Task B1: export reader + per-turn embedding (TDD)

**Files:** `apps/cognitive-telemetry/src/turns.mjs`, `test/turns.test.mjs`

- [ ] **Step 1: Failing test** — `extractDyad(conversation)` turns an `omni_conversations` record (turns with role user/assistant) into `[{speaker, text}]`, dropping empty turns; `speaker` is 0 for self/user, 1 for other/assistant.
- [ ] **Step 2: FAIL. Step 3: Implement** `extractDyad`. **Step 4: PASS. Step 5: Commit.**
- [ ] **Step 6:** Add `embedTurns(turns, embedFn)` — calls the sovereign embedder (`BEAGLE_TEI_EMBED_URL`, bge-m3), projects each 1024-dim embedding to the 8 octonion coords via a **fixed seeded projection matrix** (document the seed) + a deterministic 8-dim affect-uncertainty proxy (v1: normalized token-length/punctuation/sentiment-lexicon features). TDD with a stub embedder. Commit.

### Task B2: F input generation + `souc` invocation (TDD)

**Files:** `apps/cognitive-telemetry/src/runF.mjs`, `test/runF.test.mjs`

- [ ] **Step 1: Failing test** — `toFInput(embeddedTurns)` produces the exact line format `tapestry_run` expects; `parseFOutput(text)` parses the telemetry lines back into objects.
- [ ] **Step 2: FAIL. Step 3: Implement** both + `runF(turns, {soucBin, stdlibPath})` that shells `souc run dialogue_tapestry.sio` with the input and parses output. TDD `runF` with a stub `souc` script echoing canned telemetry. **Step 4: PASS. Step 5: Commit.**

### Task B3: write telemetry back to the exocortex (sovereign) (TDD)

**Files:** `apps/cognitive-telemetry/src/store.mjs`, `bin/run-telemetry.mjs`, `test/store.test.mjs`

- [ ] **Step 1: Failing test** — `telemetryDoc(sessionId, telemetry)` builds an assisted-import payload tagged `["cognitive-telemetry","pinned","session:<id>"]`, privacy `sensitive`, with a compact deterministic summary (coherence trend, rupture count, min zd_proximity) + the raw series in metadata. Idempotent session id `cognitive-telemetry:<sessionId>`.
- [ ] **Step 2: FAIL. Step 3: Implement** `telemetryDoc` + `bin/run-telemetry.mjs` (iterate sessions from the export, B1→B2→B3, conc 1 — beagle-core store is not concurrency-safe, see [[project_exocortex_ingest_constraints]]). **Step 4: PASS. Step 5: Commit.**
- [ ] **Step 6:** Dockerfile + a CronJob (`k8s/cognitive-telemetry/`, tolerations for the tainted nodes, seccomp Unconfined) that runs the pipeline over new sessions nightly. Build via kaniko. Commit.

---

## Phase C — consumers

### Task C1: companion live grounding (TDD)

**Files:** modify `apps/project-cockpit/server/auth-bridge.mjs` (+ `mobile-routes.mjs`)

- [ ] **Step 1:** Add `fetchCognitiveDigest()` mirroring `fetchPhysiomeDigest` — `/api/memory/query` tags `["cognitive-telemetry"]`, returns a compact recent-telemetry digest. TDD the digest formatting.
- [ ] **Step 2:** In the Personal-space block of `mobile-routes.mjs`, inject the cognitive digest alongside biography + physiome (best-effort, never blocks chat). **Step 3:** Deploy via the cockpit build/deploy lineage ([[project_cockpit_deploy_lineage]]). Verify with a real Personal chat that references a coherence/rupture insight.

### Task C2: Physiome correlation extension (TDD)

**Files:** modify `apps/physiome/src/correlate.mjs` + `digest.mjs`

- [ ] **Step 1: Failing test** — `flattenAggregates` accepts optional daily cognitive aggregates (`coherenceMean`, `zdMin`, `ruptureCount`) and `correlatePhysiome` surfaces e.g. `kpMax → zdMin` and `sleepHours → coherenceMean` when present.
- [ ] **Step 2: FAIL. Step 3: Implement** — add cognitive series to `OUTCOMES`/`DRIVERS` (coherence/dissociation as outcomes), a `cognitiveDailyAgg(pool/exocortex)` source, and fold into the daily digest. **Step 4: PASS (full physiome suite green). Step 5: Commit.**

### Task C3: historical report

- [ ] **Step 1:** A `bin/report.mjs` that emits a markdown report over a window: coherence trend, rupture/dissociation episodes (dates + sessions), top Fano modes, and the cognitive×physiome correlation table (reusing C2). **Step 2:** Smoke-run on real telemetry once Phase B has populated it. Commit.

---

## Self-Review Notes

- **Spec coverage:** Phase A instantiates F (all 3 correspondences + the new L/R def) bit-exact (deep-research blocker #1) and computes zd exactly (blocker #2); Phase B makes it run on the real corpus (sovereign instrument); Phase C delivers the chosen "both — consultável" utility (live + historical + Physiome correlation). ✔
- **Reuse:** A2/A4 build on `sed_associator` + `psychiatry.sio` rather than reimplementing CD math. ✔
- **Type consistency:** `Turn{speaker,embed[8],unc[8]}` and `Telemetry{coherence,lr_asymmetry,fano_mode,zd_proximity,rupture,g2_class}` are used identically across A5/A6/B2/B3. ✔
- **No placeholders:** Phase A/B carry signatures, test code, and reuse targets; the embedding→algebra projection is explicitly a fixed seeded choice (documented), not a TODO. The genuinely-novel math (L/R def, G2 class) is specified at v1 fidelity with v2 stretches flagged. ✔
- **Boundary/safety:** Phase A on `integration/sounio-dev-ready-base`; conc-1 ingest; sensitive/sovereign telemetry never leaves the cluster; tolerations + seccomp Unconfined on cluster jobs. ✔
