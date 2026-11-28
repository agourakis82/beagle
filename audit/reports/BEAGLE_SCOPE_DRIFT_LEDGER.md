# BEAGLE Scope Drift Ledger

Generated: 2026-05-16 16:40:30

## Verdict Table

|Area|Evidence surface|Verdict|Required action|
|---|---|---|---|
|Workbench/Warp/Project Cockpit|apps/project-cockpit, Workbench/Warp commits and routes|scope-drift|Quarantine unless it launches Darwin/BEAGLE scientific workflows directly.|
|Apple/iOS/watchOS/visionOS cockpit|beagle-ios and Apple proof paths|mixed drift|Keep only capture, memory, terminal-to-core, physio; freeze model catalog/exotic UI flourishes.|
|Sounio/workspace/k8s platform|k8s/sounio-*, workspace-platform, habitat manifests|scope-drift|Move to separate infra repo or quarantine as deployment lab.|
|Cluster/network fabric|NetBox, OrangeFS, 10G, storage fabric docs/commits|scope-drift|Retain only if tied to Darwin HPC artifact flow; otherwise separate ops ledger.|
|Exotic cognitive crates|consciousness, quantum, void, fractal, noetic, ontic, transcend, eternity|scope-drift/stub risk|Demand tests and pipeline contract; demote rhetoric until implemented.|
|MCP/public connector|beagle-mcp-server, Cloudflare connector docs|useful-extension|Preserve because it serves memory/exocortex access if auth and tools work.|
|Darwin HPC governance/reranking|docs/darwin/hpc, feat/darwin-hpc-governance|useful-extension with ops risk|Preserve bounded retrieval/reranking only if it improves Darwin scientific retrieval.|
|Legacy Darwin mapper|legacy/*|core-origin evidence|Preserve as historical artifact; do not run as current system unless ported.|

## Drift Evidence Samples

```text
./src/quantum/mod.rs:5://! Amplitude-based probability (like quantum mechanics)
./src/lib.rs:7:pub mod quantum;
./src/lib.rs:20:pub use quantum::{
./src/quantum/interference.rs:9:/// Handles quantum-like interference between hypotheses
./src/quantum/measurement.rs:57:    /// Stochastic measurement (like quantum mechanics)
./Cargo.toml:23:    "crates/beagle-quantum",
./Cargo.toml:27:    "crates/beagle-consciousness",
./Cargo.toml:28:    "crates/beagle-fractal",
./Cargo.toml:31:    "crates/beagle-noetic", "crates/beagle-ontic", "crates/beagle-void", "crates/beagle-paradox", "crates/beagle-cosmo", "crates/beagle-transcend", "crates/beagle-eternity", "beagle-bin", "crates/beagle-grok-api", "crates/beagle-grok-full", "crates/beagle-smart-router", "crates/beagle-config", "crates/beagle-core", "crates/beagle-health", "crates/beagle-observability",     "crates/beagle-darwin", "crates/beagle-darwin-core", "crates/beagle-workspace",
./beagle-ide/src/store.ts:28:  setView: (view: View) => void;
./beagle-ide/src/store.ts:29:  setProject: (projectId: string) => Promise<void>;
./beagle-ide/src/store.ts:30:  loadFiles: (projectPath: string) => Promise<void>;
./beagle-ide/src/store.ts:31:  toggleNode: (path: string, expanded: boolean) => void;
./beagle-ide/src/store.ts:32:  setFiles: (updater: (nodes: FileNode[]) => FileNode[]) => void;
./BEAGLE_MODULES_GUIDE.md:10:2. [Quantum Computing](#quantum-computing)
./BEAGLE_MODULES_GUIDE.md:90:use beagle_quantum::{QuantumSystem, QuantumCircuit};
./BEAGLE_MODULES_GUIDE.md:93:let quantum = QuantumSystem::new();
./BEAGLE_MODULES_GUIDE.md:101:let result = quantum.simulate(&circuit).await?;
./BEAGLE_MODULES_GUIDE.md:105:let measurements = quantum.measure(&circuit, 1000).await?;
./BEAGLE_MODULES_GUIDE.md:113:let hamiltonian = quantum.create_hamiltonian(&[
./BEAGLE_MODULES_GUIDE.md:116:let ground_state = quantum.vqe(hamiltonian, 100).await?;
./BEAGLE_MODULES_GUIDE.md:119:let problem = quantum.create_max_cut_problem(&graph);
./BEAGLE_MODULES_GUIDE.md:120:let solution = quantum.qaoa(problem, 5, 100).await?;
./BEAGLE_MODULES_GUIDE.md:124:let result = quantum.grover_search(100, oracle).await?;
./BEAGLE_MODULES_GUIDE.md:329:let results = search.search("quantum computing").await?;
./BEAGLE_MODULES_GUIDE.md:421:    "1/ Let's talk about quantum computing",
./BEAGLE_MODULES_GUIDE.md:543:async fn quantum_optimization(problem: OptimizationProblem) -> Result<Solution> {
./BEAGLE_MODULES_GUIDE.md:544:    let quantum = QuantumSystem::new();
./BEAGLE_MODULES_GUIDE.md:550:    // Create quantum circuit for optimization
./BEAGLE_MODULES_GUIDE.md:551:    let circuit = quantum.create_qaoa_circuit(&encoding, 5)?;
./BEAGLE_MODULES_GUIDE.md:553:    // Run quantum optimization
./BEAGLE_MODULES_GUIDE.md:554:    let quantum_solution = quantum.run_qaoa(circuit, 100).await?;
./BEAGLE_MODULES_GUIDE.md:557:    let solution = neural.decode_solution(&quantum_solution).await?;
./audit/reports/UNFINISHED_FEATURES_REPORT.md:36:- **File:** `/mnt/e/workspace/beagle-remote/apps/beagle-monorepo/src/pipeline_void.rs:106`
./audit/reports/UNFINISHED_FEATURES_REPORT.md:37:- **Issue:** `TODO: Integrar VoidNavigator quando beagle-ontic estiver disponível`
./audit/reports/UNFINISHED_FEATURES_REPORT.md:40:- **Recommendation:** Complete beagle-ontic integration and implement VoidNavigator properly
./audit/reports/UNFINISHED_FEATURES_REPORT.md:128:- **Impact:** HRV reading only works with mock data, no real Apple Watch integration
./audit/reports/UNFINISHED_FEATURES_REPORT.md:184:- **File:** `/mnt/e/workspace/beagle-remote/crates/beagle-noetic/src/noetic_detector.rs:142-205`
./audit/reports/UNFINISHED_FEATURES_REPORT.md:187:- **Recommendation:** Complete noetic network detection algorithm
./audit/reports/UNFINISHED_FEATURES_REPORT.md:190:- **File:** `/mnt/e/workspace/beagle-remote/crates/beagle-ontic/src/void_navigator.rs:163`
./audit/reports/UNFINISHED_FEATURES_REPORT.md:193:- **Recommendation:** Implement robust void navigation without fallbacks
./audit/reports/UNFINISHED_FEATURES_REPORT.md:290:  - `/mnt/e/workspace/beagle-remote/apps/beagle-monorepo/tests/pipeline_void.rs:25` - Void pipeline
./audit/reports/UNFINISHED_FEATURES_REPORT.md:421:#### 4.5 VoidNavigator from beagle-ontic
./audit/reports/UNFINISHED_FEATURES_REPORT.md:423:  - `/mnt/e/workspace/beagle-remote/apps/beagle-monorepo/src/pipeline_void.rs:106`
./audit/reports/UNFINISHED_FEATURES_REPORT.md:424:  - `/mnt/e/workspace/beagle-remote/crates/beagle-ontic/src/void_navigator.rs`
./audit/reports/UNFINISHED_FEATURES_REPORT.md:425:- **Status:** beagle-ontic exists but VoidNavigator not properly integrated into pipeline
./audit/reports/UNFINISHED_FEATURES_REPORT.md:428:  1. Import VoidNavigator into pipeline_void.rs
./audit/reports/UNFINISHED_FEATURES_REPORT.md:433:#### 4.6 HealthKit Bridge (Apple Watch HRV)
./audit/reports/UNFINISHED_FEATURES_REPORT.md:445:  4. Implement HRV data streaming from Apple Watch
./audit/reports/UNFINISHED_FEATURES_REPORT.md:566:- **Issue:** Only mock HRV available, no real Apple Watch integration
./audit/reports/UNFINISHED_FEATURES_REPORT.md:654:   - Import into pipeline_void
./audit/reports/UNFINISHED_FEATURES_REPORT.md:667:   - Test with real Apple Watch
./audit/reports/REPOSITORY_AUDIT_2025-11-24.md:77:- `beagle-quantum` - Quantum-inspired algorithms
./audit/reports/REPOSITORY_AUDIT_2025-11-24.md:83:- `beagle-consciousness` - Consciousness simulation
./audit/reports/REPOSITORY_AUDIT_2025-11-24.md:87:- `beagle-fractal` - Fractal reasoning patterns
./audit/reports/REPOSITORY_AUDIT_2025-11-24.md:98:- `beagle-eternity` - Long-term persistence
./src/quantum/hypothesis.rs:10:    /// Complex amplitude (like quantum wavefunction)
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:38:1. **Real-time HRV Stream:** Apple Watch/Polar H10 → Swift bridge → Rust
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:238:**Modules:** `beagle-quantum` + `beagle-agents`
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:247:- Variational quantum algorithms
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:253:Use quantum interference principles to improve LLM ensemble reasoning:
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:280:- **Not true quantum computing** (classical simulation)
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:281:- But quantum-inspired algorithms can have provable speedups
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:285:**Difficulty:** ⚡⚡⚡⚡ (requires quantum computing background)  
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:291:- Can we prove quantum advantage over classical ensemble?
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:435:   - "Search PubMed for quantum entanglement in photosynthesis"
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:544:**Modules:** `beagle-transcend` + `beagle-metacog` + `beagle-consciousness`
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:650:- **Sensors:** Apple Watch, Polar H10, or custom hardware?
./BEYOND_SOTA_DISCUSSION_FRAMEWORK.md:672:- **Theory:** Is this truly quantum-inspired or just fancy ensemble?
./audit/reports/WEBSOCKET_FIXES_REPORT.md:108:⚠️ **PARTIAL** - `beagle-eternity` crate has unrelated compilation errors
./audit/reports/WEBSOCKET_FIXES_REPORT.md:111:**Pre-existing issues**: `beagle-eternity` has type mismatches (unrelated to WebSocket fixes)
./audit/reports/WEBSOCKET_FIXES_REPORT.md:182:3. ⏭️ Fix `beagle-eternity` compilation errors (unrelated to this work)
./audit/reports/AGENTS.md:17:- Naming: snake_case for functions/modules, PascalCase for types/traits, SCREAMING_SNAKE_CASE for consts/env vars; avoid cross-crate cycles and keep new crates under `crates/`.
./audit/reports/AGENTS.md:32:- Prefer Docker (`docker-compose*.yml`) for reproducible stacks and shut down external services after tests to avoid stale state.
./src/temporal/mod.rs:7://! - Micro (ms-s): Molecular/quantum
./audit/reports/CRATE_ANALYSIS.md:21:- **beagle-consciousness**: 6 files, 510 lines
./audit/reports/CRATE_ANALYSIS.md:27:- **beagle-eternity**: 2 files, 244 lines
./audit/reports/CRATE_ANALYSIS.md:31:- **beagle-fractal**: 7 files, 1127 lines
./audit/reports/CRATE_ANALYSIS.md:48:- **beagle-noetic**: 7 files, 1805 lines
./audit/reports/CRATE_ANALYSIS.md:52:- **beagle-ontic**: 7 files, 1460 lines
./audit/reports/CRATE_ANALYSIS.md:57:- **beagle-quantum**: 10 files, 1097 lines
./audit/reports/CRATE_ANALYSIS.md:66:- **beagle-transcend**: 2 files, 210 lines
./audit/reports/CRATE_ANALYSIS.md:69:- **beagle-void**: 6 files, 1185 lines
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:11:Successfully completed comprehensive fixes to the **beagle-fractal** crate addressing all critical issues. The system now compiles without errors and passes all test suites.
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:44:- Implemented `init_fractal_root()` - Initialize global root
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:49:### **fractal_node.rs** - Already Well-Implemented
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:103:beagle-consciousness    # Consciousness integration
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:111:- `test_fractal_root_initialization` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:112:- `test_fractal_root_global_storage` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:113:- `test_fractal_node_creation` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:114:- `test_fractal_node_spawn_child` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:117:- `test_fractal_recursion_to_depth_3` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:133:- `test_fractal_cognitive_cycle` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:134:- `test_fractal_node_runtime_getters` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:137:- `test_fractal_depth_tracking` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:138:- `test_fractal_parent_child_relationship` ✅
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:151:| Inconsistent definitions | 🟡 HIGH | ✅ FIXED | Used fractal_node.rs version |
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:220:| beagle-noetic | ❌ Broken | ✅ Fixed |
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:221:| beagle-eternity | ⚠️ Partial | ✅ Complete |
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:223:| beagle-ontic | ? Unknown | ✅ Ready |
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:250:   - Test with beagle-noetic
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:251:   - Test with beagle-eternity
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:256:   - Tutorial for using the fractal system
./audit/reports/FRACTAL_IMPLEMENTATION_COMPLETE.md:279:The beagle-fractal crate has been completely rehabilitated from a broken, partially-implemented system to a production-ready, fully-featured recursive cognitive architecture. All critical issues have been resolved, comprehensive tests have been added, and the system now properly integrates with the rest of the beagle ecosystem.
./tests/README_TESTING.md:126:| 3 | `test_arxiv_search_quantum` | arXiv API search | ~3s | Internet |
./tests/README_TESTING.md:282:# Watch network traffic
./tests/integration_e2e.rs:56:async fn test_quantum_circuit_execution() -> Result<()> {
./tests/integration_e2e.rs:57:    use beagle_quantum::{QuantumSimulator, QuantumGate};
./tests/integration_e2e.rs:312:    use beagle_quantum::QuantumSimulator;
./tests/integration_e2e.rs:315:    // Test quantum simulator with invalid operations
./tests/integration_e2e.rs:318:    assert!(matches!(sim.apply_gate(5, beagle_quantum::QuantumGate::H), Err(_)));
./tests/integration_e2e.rs:431:    let _ = beagle_quantum::QuantumSimulator::new(2)?;
./CLAUDE.md:355:# Watch spans with run_id
./crates/beagle-personality/src/detector_extended.rs:181:            "quantum",
./crates/beagle-personality/src/detector_extended.rs:295:            "fractal",
./crates/beagle-personality/src/detector_extended.rs:296:            "dimensão fractal",
./crates/beagle-personality/src/detector_extended.rs:323:            "transcendental",
./beagle-ide/index.html:142:    #quantum-view {
./beagle-ide/index.html:153:    .quantum-superposition {
./beagle-ide/index.html:164:    .quantum-state {
./beagle-ide/index.html:230:        <div id="quantum-view"></div>
./beagle-ide/index.html:650:    const quantumEl = document.getElementById('quantum-view');
./beagle-ide/index.html:660:      quantumEl.innerHTML = `
./beagle-ide/index.html:661:        <div class="quantum-superposition">⚛️</div>
./beagle-ide/index.html:662:        <div class="quantum-state">${states[stateIndex]}</div>
./beagle-ide/index.html:663:        <div class="quantum-state" style="margin-top: 20px; font-size: 12px; opacity: 0.6;">
./docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:57:- ✅ `beagle-ios/BeagleWatch/` - **CONFIRMADO**
./docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:143:**NOTA**: Requer iOS/Apple Watch, não testado no stress test Linux
./docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:207:**Validado empiricamente: 4/10 (40%)** - *6 features requerem ambiente específico (iOS/Apple Watch)*
./docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:229:  ⚠️  HRV: Requer iOS/Apple Watch (não testável em Linux)
./docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:274:   # Criar teste que simula dados HRV do Apple Watch
./docs/RELATORIO_AUDITORIA_FINAL_2025-11-20.md:281:**Nota técnica adicionada**: Algumas features requerem ambiente específico (iOS/Apple Watch) e não são testáveis no stress test Linux atual.
./examples/integrated_application.rs:16:use beagle_quantum::{QuantumSimulator, QuantumGate};
./examples/integrated_application.rs:49:    let quantum_result = demo_quantum_system(&observer).await?;
./examples/integrated_application.rs:50:    println!("   ✓ Quantum simulation result: {}\n", quantum_result);
./examples/integrated_application.rs:100:            content: "Quantum computing leverages quantum mechanics principles like superposition and entanglement to process information in ways classical computers cannot.".to_string(),
./examples/integrated_application.rs:123:    let query = "How does quantum computing work?";
./examples/integrated_application.rs:141:/// Demo quantum simulation
./examples/integrated_application.rs:142:async fn demo_quantum_system(observer: &Arc<SystemObserver>) -> Result<String> {
./examples/integrated_application.rs:158:        Metric::gauge("quantum.qubits", 2.0)
```

## Hard Rule

A surface is not preserved because it is impressive. It is preserved only if it operates the Darwin/BEAGLE loop: capture -> memory/retrieval -> scientific synthesis -> adversarial review -> artifact -> feedback.
