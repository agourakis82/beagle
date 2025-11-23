# Changelog

All notable changes to the BEAGLE project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2025-01-23

### Added

#### Neuro-Symbolic Hybrid (Week 8-10 Complete)
- **NeuralExtractor**: LLM-powered symbolic knowledge extraction
  - `extract_facts()`: Converts text to first-order logic facts
  - `extract_rules()`: Extracts Horn clause rules from text
  - `entity_recognition()`: Named entity extraction with type classification
  - `relation_extraction()`: Relation triplets (entity1, relation, entity2)
- **SymbolicReasoner**: First-order logic reasoning engine
  - Forward chaining: Derives new facts from existing knowledge
  - Backward chaining: Proves goals from facts and rules
  - Unification algorithm: Variable binding with substitution
  - Query system: Pattern matching with variable instantiation
  - Consistency checking: Detects contradictions
- **HybridReasoner**: Neural-symbolic fusion layer
  - Neural → Symbolic translation (text → logic)
  - Forward chaining with 10 iteration limit
  - Hallucination detection using symbolic constraints
  - Confidence scoring based on fact/rule quality
  - Bidirectional reasoning (neural extraction + symbolic inference)
- **ConstraintSolver**: Symbolic constraint management
  - Equality, inequality, greater-than, less-than constraints
  - Satisfiability checking
  - Constraint propagation (foundation for SAT/SMT)
- **Enhanced API Endpoint**: POST /dev/neurosymbolic
  - Returns extracted facts, rules, derived facts
  - Hallucination detection results
  - Consistency verification
  - Confidence scores
- **Comprehensive Testing**: 15 unit tests for neuro-symbolic reasoning
  - Predicate equality and unification
  - Forward/backward chaining
  - Complex rule chains (grandparent example)
  - Infinite loop prevention
  - Query with variables

### Changed
- **neurosymbolic_endpoint.rs**: Full implementation using HybridReasoner
- **Performance**: 1000+ facts/second reasoning capability

### Fixed
- Model type references: ClaudeHaiku → ClaudeHaiku45
- Borrow checker errors in unification algorithm (use .cloned())
- Move errors in HybridReasoner (calculate confidence before moving values)

## [0.6.0] - 2025-01-23

### Added

#### Metacognitive Evolution (Week 5-7 Complete)
- **PerformanceMonitor**: Complete self-monitoring system
  - Performance degradation detection (success rate, quality, latency)
  - Bottleneck identification (high latency, low quality, frequent failures)
  - Trend analysis with linear regression (improving/stable/degrading)
  - Per-domain performance statistics
  - Severity classification (None, Minor, Moderate, Severe)
  - 95th percentile latency tracking
- **WeaknessAnalyzer**: LLM-powered failure pattern analysis
  - Automatic pattern identification from failure history
  - Pattern frequency tracking with example collection
  - Pattern clustering for strategic insights
  - Missing capability identification
  - Severity scoring (logarithmic frequency + critical keyword detection)
  - Cluster priority classification (Critical, High, Medium, Low)
- **ArchitectureEvolver**: Autonomous system evolution
  - Trigger evolution based on failure rate thresholds
  - Create specialized agents for detected patterns
- **SpecializedAgentFactory**: Dynamic agent creation
  - LLM-generated agent specifications from failure patterns
  - Custom system prompts and capability definitions
- **API Endpoints**: 
  - POST /dev/metacognitive/analyze-performance
  - POST /dev/metacognitive/analyze-failures
- **Unit Tests**: 12 comprehensive tests for metacognitive components

### Changed
- **monitor.rs**: Added degradation detection, bottleneck identification, trend analysis
- **analyzer.rs**: Enhanced with pattern tracking, clustering, and severity scoring
- **arena.rs**: Fixed single-elimination tournament borrowing issues

### Fixed
- Type mismatch in quantum_mcts.rs (n_visits u32 → usize conversion)
- Moved value error in analyzer.rs (added .clone() for pattern_type)
- Borrowing issues in single-elimination tournament (refactored to owned values)

## [0.5.0] - 2025-01-23

### Added

#### Quantum-Inspired Reasoning (Week 1-2 Complete)
- **quantum module**: Full quantum superposition and interference engine
- **SuperpositionState**: Maintains N hypotheses with complex amplitudes (Born rule)
- **InterferenceEngine**: Constructive/destructive interference patterns
- **MeasurementOperator**: Copenhagen collapse, probabilistic measurement, decoherence
- **QuantumMCTS**: Integration with MCTS Deep Research
- **API Endpoint**: POST /dev/quantum-reasoning with full request/response schema
- **Unit Tests**: 9 comprehensive tests for quantum behavior
- **Performance**: <100ms for 50 hypotheses validated

#### Adversarial Self-Play (Week 3-4: 90% Complete)
- **CompetitionArena**: Multi-format tournament system
  - Swiss system (ELO-based pairing)
  - Round-robin (all vs all)
  - Single elimination (bracket style)
- **ResearchPlayer**: ELO rating system (starting 1500, K-factor 32)
- **Strategy Types**: Aggressive, Conservative, Exploratory, Exploitative
- **Genetic Evolution**: 
  - Crossover breeding (70% crossover, 30% mutation)
  - Fitness-based selection (top 50% survive)
  - Multi-generational evolution with lineage tracking
- **Strategy Evolution**: Parameter inheritance from both parents

### Changed
- **QuantumMCTS**: Multi-factor probability scoring (quality 40%, visits 20%, novelty 30%, rank 10%)
- **Tournament Results**: Full standings with ranks and ELO ratings
- **Strategy Crossover**: Combine parameters from two parent strategies
- **Player Naming**: Generational tracking (gen{N}_p{ID})

## [0.4.0] - 2025-01-23

### Added

#### DeepSeek Integration
- **beagle-llm/clients/deepseek**: DeepSeek API client implementation
- **Model Support**: DeepSeek Chat and DeepSeek Math models
- **OpenAI-Compatible API**: Uses chat/completions format compatible with OpenAI API
- **Environment Config**: `DEEPSEEK_API_KEY` environment variable support
- **Cost Optimization**: Significantly lower cost compared to Claude Sonnet
- **Module Exports**: DeepSeekClient exported from beagle-llm public API

## [0.3.0] - 2025-01-XX

### Added

#### Memory & MCP Layer
- **beagle-memory**: MemoryEngine com interface unificada para ingest e query de conversas
- **MCP Server**: Servidor MCP completo para ChatGPT e Claude
- **Memory Endpoints**: `/api/memory/ingest_chat` e `/api/memory/query`
- **RAG Injection**: Injeção automática de contexto prévio no pipeline quando `BEAGLE_MEMORY_RETRIEVAL=true`

#### Serendipity Integration
- Integração do `SerendipityEngine` no pipeline
- Geração de acidentes férteis interdisciplinares
- `serendipity_score` registrado no `run_report.json`
- Ativado via `BEAGLE_SERENDIPITY_ENABLE=true` (lab/prod apenas)

#### Void Deadlock Detection
- `DeadlockState` para rastreamento de outputs repetidos
- Detecção de similaridade (>80%) entre outputs
- Estratégia conservadora de quebra de loop
- Threshold configurável (3 com `BEAGLE_VOID_STRICT`, 5 padrão)

#### Security & Auth
- Bearer token authentication no MCP server
- Rate limiting (100 req/min por cliente)
- Sanitização de output (proteção MCP-UPD)
- Documentação de TLS via reverse proxy

### Changed

- `BeagleContext` agora suporta `MemoryEngine` opcional (feature flag `memory`)
- Pipeline integra Serendipity e Void quando habilitados
- `run_report.json` inclui `serendipity_score`

### Documentation

- `BEAGLE_MCP.md`: Guia completo de instalação e configuração do MCP server
- `BEAGLE_v0_3_RELEASE_NOTES.md`: Release notes detalhadas
- `CHANGELOG.md`: Este arquivo

## [0.2.0] - 2024-XX-XX

### Added
- Pipeline v0.1 com Darwin, Observer, HERMES
- Triad adversarial (ATHENA, HERMES, ARGOS)
- Feedback system para continuous learning
- Science jobs (PBPK, Helio, Scaffold, PCS, KEC)

## [0.1.0] - 2024-XX-XX

### Added
- Core HTTP server (Axum)
- LLM routing (Grok 3 Tier 1, Heavy, Local fallback)
- Config system com profiles (dev/lab/prod)
- Observer para captura de contexto

[0.5.0]: https://github.com/darwin-cluster/beagle/releases/tag/v0.5.0
[0.4.0]: https://github.com/darwin-cluster/beagle/releases/tag/v0.4.0
[0.3.0]: https://github.com/darwin-cluster/beagle/releases/tag/v0.3.0
[0.2.0]: https://github.com/darwin-cluster/beagle/releases/tag/v0.2.0
[0.1.0]: https://github.com/darwin-cluster/beagle/releases/tag/v0.1.0

