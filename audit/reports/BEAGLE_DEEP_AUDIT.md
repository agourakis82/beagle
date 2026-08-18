# BEAGLE Deep Audit

Generated: 2026-05-16 16:40:30
Branch: `feat/ios-terminal-quality-pass` at `bdfddb16`

## Executive Verdict

BEAGLE still has a recoverable core, but it has suffered severe scope drift. The original useful system was not a generic dashboard or aesthetic cockpit; it was a Darwin-derived scientific exocortex: GraphRAG/Self-RAG, persistent memory, HERMES/Triad synthesis/review, Observer/physiology, PBPK/Julia/HPC scientific compute, feedback, and durable artifacts.

The repo now contains a large amount of expansion surface whose utility is unproven or actively distracting: Workbench/Warp visual probes, Apple UI flourish layers, Sounio/workspace infrastructure, cluster/network fabric, and rhetorically named cognitive crates. Some of that may be salvageable, but none of it should be trusted without a direct contract to the core loop.

## Audit Coverage

- Files audited into line map: **1430**
- Line-map rows: **33093**
- Cargo packages from metadata: **67**
- Current branch/head: `feat/ios-terminal-quality-pass` / `bdfddb16`
- Generated primary artifact: `audit/reports/BEAGLE_LINE_MAP.csv`

## Classification Summary

|Kind|Blocks|Lines|
|---|---|---|
|core-origin|4691|53407|
|documentation-fiction|1714|15551|
|generated-artifact|49|7853|
|scope-drift|6308|55452|
|stub|10005|126082|
|uncertain|3923|43410|
|useful-extension|6403|65026|

## Top Directory/Kind Mass

|Directory|Kind|Lines|
|---|---|---|
|beagle-ios|scope-drift|28349|
|docs|stub|20720|
|k8s/project-cockpit|stub|16218|
|apps/project-cockpit|stub|14444|
|docs|useful-extension|13114|
|docs|documentation-fiction|12492|
|crates/beagle-hermes|core-origin|11785|
|beagle-julia|core-origin|8983|
|beagle-ios|stub|8731|
|crates/beagle-hypergraph|core-origin|8680|
|scripts|useful-extension|7910|
|crates/beagle-transcend|scope-drift|7045|
|audit|stub|6316|
|crates/beagle-agents|uncertain|5133|
|crates/beagle-worldmodel|uncertain|5082|
|crates/beagle-observer|core-origin|5036|
|scripts|uncertain|4946|
|crates/beagle-twitter|scope-drift|4780|
|crates/beagle-hypergraph|stub|4741|
|apps/beagle-ide|generated-artifact|4616|
|crates/beagle-agents|useful-extension|4469|
|crates/beagle-hermes|stub|4153|
|crates/beagle-llm|core-origin|3944|
|apps/beagle-monorepo|stub|3894|
|crates/beagle-void|scope-drift|3860|
|crates/beagle-server|uncertain|3426|
|crates/beagle-whisper|stub|3236|
|docs|uncertain|3209|
|crates/beagle-exocortex|useful-extension|3176|
|apps/project-cockpit|scope-drift|3064|

## Findings

|ID|Finding|Why it matters|Evidence|
|---|---|---|---|
|F1|Documentation fiction is systemic|Docs claim 100% complete/production/operational while the same doc set records placeholders, pending work, or contradictory percentages.|docs/DARWIN_WORKSPACE_MIGRATION_AUDIT.md:9-18 vs later 100% section; docs/BEAGLE_v0_2_COMPLETE.md:43-50 labels placeholders as complete.|
|F2|Scope drift overtook the original loop|The commit history and file tree shifted from Darwin scientific exocortex into Apple UI, Workbench/Warp probes, cluster fabric, and exotic cognitive modules.|git log Apr-May 2026; BEAGLE_SCOPE_DRIFT_LEDGER.md.|
|F3|The core is still visible and salvageable|Darwin GraphRAG/Self-RAG, Memory/MCP, HERMES/Triad, Observer, feedback, PBPK/Julia and artifacts are still present as identifiable surfaces.|README.md:1-45; docs/BEAGLE_v0_1_CORE.md; crates/beagle-darwin*; crates/beagle-memory; beagle-mcp-server.|
|F4|Many expansion modules need proof before trust|Automated line map flags stub/mock/TODO/placeholder signals and low-alignment paths. These should not be treated as product capability.|BEAGLE_LINE_MAP.csv rows with kind=stub/scope-drift/documentation-fiction.|
|F5|Current green baseline is narrow, not proof of product health|`make rescue-check` proves selected Rust/frontend/Tauri compilation only; it does not prove the full Darwin pipeline, memory, MCP, Triad or iOS behavior.|scripts/rescue-check.sh; recent commits 22a8b2eb and bdfddb16.|

## What Was BEAGLE/Darwin?

Based on repo evidence, Darwin began as a runtime/ecosystem around Darwin Core API, Darwin Workspace API, Darwin Analytics, Qdrant, and Ollama (`legacy/config.yaml`). BEAGLE then became the orchestrating exocortex: research question capture, Darwin retrieval/reasoning, physiological context, HERMES synthesis, Triad adversarial review, artifacts, feedback, memory, and MCP access.

## Where It Drifted

The highest-risk drift is not one file; it is the pattern of adding impressive surfaces without closing the original loop. Commits in April-May 2026 show repeated expansion into iOS model catalogs, visionOS, quantum/consciousness UI, Workbench/Warp visual probes, and cluster fabric. These may contain useful pieces, but they are not the core unless they make the scientific loop easier to run.

## What Still Looks Useful

- `crates/beagle-darwin*`: canonical Darwin retrieval/reasoning surface.
- `apps/beagle-monorepo`: core server and pipeline entrypoint.
- `crates/beagle-memory` + `beagle-mcp-server`: memory/control-plane layer.
- `crates/beagle-hermes`, `crates/beagle-triad`, `crates/beagle-feedback`: synthesis, adversarial review, and learning loop.
- `crates/beagle-observer`, `crates/beagle-physio`, `crates/beagle-bio`: physiological context if kept grounded.
- `beagle-julia` + `crates/beagle-workspace`: Darwin scientific compute if verified against PBPK/KEC/heliobiology artifacts.

## What Is Theater Until Proven Otherwise

- Completion docs claiming 100% without fresh commands or artifact evidence.
- Exotic modules named for consciousness/void/fractal/noetic/ontic/transcendence when not wired to pipeline acceptance tests.
- Visual-first Workbench/Warp routes that do not capture memory, run Darwin, produce artifacts, or review drafts.
- Apple surfaces that showcase model catalogs or emotion polish instead of capture/physio/memory/core operation.

## Required Next Move

Do not add new features. Use `BEAGLE_LINE_MAP.csv` to quarantine all `scope-drift`, `stub`, and `documentation-fiction` areas. Then run a single real end-to-end scientific workflow and rebuild outward from that proof.

## Claim/Stub Evidence Samples

```text
QUICKSTART.md:269:# Use mock mode for testing
QUICKSTART.md:327:- **Concurrent:** 50 runs in ~10 seconds (5 concurrent, with mocks)
docs/FINAL_STATUS.md:12:- ✅ Fallback para mock se indisponível
docs/CONTINUOUS_LEARNING_V0.1.md:3:## Status: ✅ 100% Implementado
docs/BEAGLE_RESTORATION_PLAN.md:19:- ❌ **Mock implementations everywhere** - external integrations are stubs
docs/BEAGLE_RESTORATION_PLAN.md:60:# Find all mocks and placeholders
docs/BEAGLE_RESTORATION_PLAN.md:61:grep -r "mock\|placeholder\|TODO\|FIXME\|unimplemented" crates/ > audit/mocks_found.txt
docs/BEAGLE_RESTORATION_PLAN.md:64:./scripts/categorize_mocks.sh
docs/BEAGLE_RESTORATION_PLAN.md:71:- `audit/MOCK_INVENTORY.md` - All placeholder implementations
docs/BEAGLE_RESTORATION_PLAN.md:101:**Current Issue:** Smart router likely using placeholder implementations
docs/BEAGLE_RESTORATION_PLAN.md:158:**Current Issue:** GraphRAG queries likely return placeholder data
docs/BEAGLE_RESTORATION_PLAN.md:206:**Current Issue:** Likely generates placeholder papers, not real academic content
docs/BEAGLE_RESTORATION_PLAN.md:386:**Current Issue:** HealthKit integration likely mocked
docs/BEAGLE_RESTORATION_PLAN.md:459:**Current Issue:** Stress tests likely run mocked pipelines
docs/BEAGLE_RESTORATION_PLAN.md:576:3. **Real Data Testing:** Use actual data sources, not mocked responses
docs/BEAGLE_RESTORATION_PLAN.md:600:- [ ] All mocks and placeholders documented
docs/BEAGLE_V2.3_FINAL_STATUS.md:110:- [ ] Integração real com Darwin/HERMES (atualmente placeholders)
docs/RELEASE_NOTES_v0.24.0.md:51:- **Zero Python**: ✅ Tudo Rust/Julia
docs/IMPLEMENTATION_SUMMARY.md:21:- ✅ Fallback inteligente para mock se Qdrant não disponível
docs/IMPLEMENTATION_SUMMARY.md:87:- **QdrantVectorStore**: Fallback para mock em caso de erro HTTP
docs/IMPLEMENTATION_SUMMARY.md:155:Todos os componentes podem ser testados com mocks:
docs/IMPLEMENTATION_SUMMARY.md:161:let ctx = BeagleContext::new_with_mocks(cfg);
docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:23:**TODOS os 10 crates alegados EXISTEM:**
docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:39:**TODOS os arquivos alegados EXISTEM:**
docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:46:**TODOS os scripts alegados EXISTEM:**
docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:53:**TODOS os apps alegados EXISTEM:**
docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:272:3. **Teste de integração HRV (mock data)**
docs/QUANTUM_WEEK1_COMPLETE.md:4:**Status:** ✅ 100% Implementado e Testado
docs/QUANTUM_WEEK1_COMPLETE.md:150:2. **LLM Integration**: Substituir mocks por chamadas reais ao LLM
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:28:#### **beagle-core** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:34:#### **beagle-config** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:41:#### **beagle-db** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:46:#### **beagle-observability** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:52:#### **beagle-health** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:57:#### **beagle-events** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:63:#### **beagle-grpc** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:68:#### **beagle-workspace** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:78:#### **beagle-hypergraph** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:87:#### **beagle-memory** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:93:#### **beagle-search** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:134:#### **beagle-hermes** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:142:#### **beagle-triad** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:149:#### **beagle-darwin** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:160:#### **beagle-llm** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:180:#### **beagle-smart-router** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:186:#### **beagle-grok-api** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:197:#### **beagle-whisper** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:207:#### **beagle-lora-voice** + **beagle-lora-voice-auto** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:212:#### **beagle-lora-auto** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:222:#### **beagle-personality** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:228:#### **beagle-bilingual** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:238:#### **beagle-observer** v0.2 + v0.3 ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:254:#### **beagle-feedback** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:267:#### **beagle-publish** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:276:#### **beagle-arxiv-validate** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:279:#### **beagle-twitter** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:307:#### **beagle-cosmo** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:316:#### **beagle-fractal** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:347:#### **beagle-experiments** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:388:#### **beagle-physio** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:397:#### **beagle-darwin-core** ✅ Production Ready
docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md:400:#### **beagle-grok-full** ✅ Production Ready
docs/BEAGLE_v0_1_CORE.md:5:**Status:** Production Ready
docs/BEAGLE_v0_1_CORE.md:676:# Run 50 concurrent pipelines (5 at a time) with mocks
docs/BEAGLE_v0_1_CORE.md:741:**Solution:** Set safe mode and use mock context:
docs/BEAGLE_v0_1_CORE.md:764:**Solution:** Use mock mode:
docs/BEAGLE_v0_1_CORE.md:782:# Integration tests (requires mock)
docs/BEAGLE_v0_1_CORE.md:783:cargo test -p beagle-monorepo --test pipeline_mock
docs/FRAMEWORK_INTEGRATION_PLAN.md:19:- Operational requirements (`offline_required`, `approximate_tokens`)
docs/CONTINUOUS_LEARNING.md:3:## Status: ✅ 100% Implementado
docs/DIA_2_COMPLETO.md:71:**DIA 2: 100% COMPLETO** 🎉
docs/PATCHES_100_PERCENT_COMPLETO_2025-11-20.md:1:# PATCHES 100% COMPLETO - 2025-11-20
docs/PATCHES_100_PERCENT_COMPLETO_2025-11-20.md:3:## ✅ STATUS FINAL: 100% COMPLETO
docs/PATCHES_100_PERCENT_COMPLETO_2025-11-20.md:109:**Status: 100% COMPLETO** ✅
docs/COMPLETE_WORKFLOW_GUIDE.md:307:- Results (may be placeholder if purely theoretical)
docs/COMPLETE_WORKFLOW_GUIDE.md:433:  "Good structure but Methods need more PBPK detail. Results section is placeholder."
docs/COMPLETE_WORKFLOW_GUIDE.md:816:# Use mock LLM for testing
docs/COMPLETE_WORKFLOW_GUIDE.md:832:# Stress test with mocks
docs/VLLM_SERVER_SETUP.md:270:    "dummy".to_string(),  // vLLM não precisa de key real
docs/BEAGLE_V2.3_COMPLETE.md:141:- [ ] Integração real com Darwin/HERMES (atualmente placeholders)
```
