# Branch Reconciliation Plan — `redesign/apple-cockpit-foundation` ↔ `feat/ios-100pct-real`

_Author: reconciliation analysis, 2026-06-11. Status: PROPOSED (no action taken yet)._

## 1. Why two branches exist

Both diverged from **`2444825` (Merge PR #16, feat/ios-fleet-terminal)** and grew into two
parallel lineages that each own one half of the product:

| Branch | What it is | Ahead of merge-base | Owns |
|---|---|---|---|
| **`redesign/apple-cockpit-foundation`** | The Apple cockpit redesign + UI clarity lineage | **+54 commits, 118 files** (iOS-heavy) | The current **iOS app UI**: Apple redesign foundation (IA 7→3), dark-only, living-mesh, Home/Work clarity, the on-device route picker, and the **provider Set-up form** |
| **`feat/ios-100pct-real`** | The "make the backend real" + deploy lineage | **+23 commits, 31 files** (backend-heavy) | The **deployed backend**: un-stubbed engines (Waves 1–5), real capture/refine/recall APIs, DB migrations, cockpit IaC durability (`6c44977` = the live `durable` cockpit), workspace-agent fixes, and now the **ported provider-config feature + hardening** |

**The core problem:** the iOS app is split. `redesign` has the redesign UI but an
**older/divergent backend that crashes when built** (`job-routes.mjs`). `feat` has the
only **working + deployed backend** and some iOS "real wiring" (Mind/Deep/Capture/Recall,
Fleet polish, iPad command bar) that `redesign` lacks. Neither branch has both halves.

## 2. Conflict surface (measured)

Of 118 (redesign) + 31 (feat) changed files, only **16 overlap** (both touched since
merge-base) — that is the entire conflict surface:

**Backend overlap (~7) — resolution: take `feat` (it is deployed + newer backend):**
- `apps/beagle-workspace-agent/src/{server,workbench-core,pty-supervisor}.mjs` — *same provider-config feature on both* (it was authored on redesign, then ported to feat); feat also has the hardening. **Take feat.**
- `apps/project-cockpit/server/workspace-routes.mjs` — same (feat has base_url-only + security fixes). **Take feat.**
- `crates/beagle-llm/src/{router_tiered,tier}.rs`, `apps/beagle-monorepo/{Cargo.toml,Dockerfile.core_server,src/http.rs}`, `Cargo.lock` — feat's Wave backend work is authoritative. **Take feat.**
- `k8s/project-cockpit/deployment.yaml` — feat's IaC reconcile (`6b78325`) reflects live. **Take feat.**

**iOS overlap (~5) — resolution: take `redesign` UI, GRAFT feat's real-wiring:**
- `BeagleCockpitApp.swift`, `BeagleSurface.swift` — redesign's IA/UX is newer. **Take redesign**, re-check any feat nav wiring still referenced.
- `CognitiveRecall.swift`, `GoDeepStore.swift` — redesign has clarity/loop fixes; feat has Recall robustness (multi-URL fallback, typed errors). **Merge by hand:** keep redesign's surface, graft feat's network-robustness.
- `BeagleCore/Models.swift` — both add types (redesign: provider-config models; feat: Wave engine models). **Union** — additive, low risk.

**iOS-only on feat that redesign LACKS (must not be lost):** Mind/Deep/Capture real
wiring (`4367e3c`, `bfe9e45`, `0a115d3`, `6a8f068`), Recall robustness (`e10e0c0`),
Fleet polish (`23cebeb`). These are on feat but were never in the redesign UI lineage —
they need to be carried into the unified app.

## 3. Recommended canonical trunk + direction

**Make `feat/ios-100pct-real` the canonical trunk; merge `redesign` INTO it.**

Rationale: `feat` is what the cluster actually runs (backend + cockpit + workspace-agent
images all build cleanly from it). Making `redesign` canonical would mean the trunk's
backend crashes on build — unacceptable. Bring the UI to the deployed lineage, not the
reverse.

## 4. Step-by-step (incremental, each step validated)

Do NOT do one 54-commit merge. Work on an integration branch off `feat`, in chunks,
building after each:

1. `git checkout -b integration/cockpit-unified origin/feat/ios-100pct-real`
2. **Backend is already correct on feat** — nothing to take from redesign here; confirm the
   16-file backend overlap stays at feat's version during the merge (resolve "take ours").
3. **Merge redesign's iOS-only files** (the ~113 non-overlapping iOS files) — these apply
   clean (feat never touched them). This brings the Apple redesign + clarity + provider form.
4. **Resolve the ~5 iOS overlap files by hand** (§2): redesign surface + feat real-wiring graft.
5. **Re-verify feat's iOS real-wiring survived** (Mind/Deep/Capture/Recall/Fleet) — these
   files are redesign-absent, so they merge clean, but confirm they still compile against
   the redesigned views (call-site drift is the risk).
6. **Build iOS on the Mac** (`ssh mac` → BeagleCockpit scheme, macOS). Fix Swift 6 fallout.
7. **Build backend images** from the integration branch (kaniko) — must stay green (it's
   feat-based, so it will).
8. When iOS + backend both green: fast-forward `feat/ios-100pct-real` to the integration
   branch (or open a PR), redeploy, and **retire `redesign`** (tag it `archive/redesign-pre-merge`).

## 5. Risks & mitigations

- **iOS call-site drift (highest risk):** feat's real-wiring views may call into stores/types
  the redesign reworked. Mitigation: step 5 + a full Mac build; resolve per-error.
- **Lost UI work:** redesign's 113 iOS-only files are the bulk — they apply clean, low risk.
- **Backend regression:** none expected (trunk stays feat); the merge must never take
  redesign's backend versions (they crash). Enforce "take ours" on the 7 backend overlaps.
- **Deploy lineage drift persists until merged:** see [[project_cockpit_deploy_lineage]].
  Until reconciliation, iOS ships from redesign, backend from feat — keep that split
  documented so deploys target the right branch.
- **Rollback:** integration is a branch; nothing deployed until step 8. `feat` stays the
  safe deployed trunk throughout.

## 6. Stale branches to prune (separate cleanup)

`git branch --contains` shows the merge-base era branches still around: `feat/cockpit-apple-redesign`,
`feat/ios-fleet-polish`, `feat/beagle-16/17/21`, `feat/beagle-axum-08`, `feature/exocortex-passage-projection`,
`dockerfile-protoc-fix`. Audit + delete after reconciliation; they predate both live lineages.

## 7. Effort estimate

- Steps 1–5 (merge + hand-resolve 5 iOS files): ~half a focused session.
- Step 6 (Mac iOS build + Swift 6 fixes): the unknown; needs the Mac up. Could be quick or
  a few iterations depending on call-site drift.
- Steps 7–8 (build + deploy + retire): ~1 build/deploy cycle each (pipeline already proven).
