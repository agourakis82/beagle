//! Estado compartilhado da aplicação Axum.

use std::sync::Arc;
use tokio::sync::Mutex;

use anyhow::Context;
use beagle_agents::{
    ArchitectureEvolver,
    // Existing
    CausalReasoner,
    // NEW - Adversarial
    CompetitionArena,
    CoordinatorAgent,
    DebateOrchestrator,
    HybridReasoner,
    HypergraphReasoner,
    InterferenceEngine,
    // NEW - Deep Research
    MCTSEngine,
    // NEW - Quantum
    MeasurementOperator,
    // NEW - Neuro-Symbolic
    NeuralExtractor,
    // NEW - Meta-Cognitive
    PerformanceMonitor,
    QualityAgent,
    ResearcherAgent,
    RetrievalAgent,
    SimulationEngine,
    SpecializedAgentFactory,
    // NEW - Swarm
    SwarmOrchestrator,
    // NEW - Temporal
    TemporalReasoner,
    ValidationAgent,
    WeaknessAnalyzer,
};
use beagle_events::{BeaglePulsar, EventPublisher};
use beagle_hypergraph::storage::CachedPostgresStorage;
use beagle_llm::{AnthropicClient, GeminiClient, LLMOrchestrator, VertexAIClient};
use beagle_memory::ContextBridge;
use tracing::{info, warn};

/// Returns true when Pulsar integration is enabled.
/// Controlled by `BEAGLE_PULSAR_ENABLED` env-var (default: true for backward compat).
fn pulsar_enabled() -> bool {
    std::env::var("BEAGLE_PULSAR_ENABLED")
        .map(|v| !matches!(v.to_lowercase().as_str(), "false" | "0" | "no" | "off"))
        .unwrap_or(true)
}

use crate::config::Config;

/// Estado imutável compartilhado entre os handlers.
#[derive(Clone)]
pub struct AppState {
    pub storage: Arc<CachedPostgresStorage>,
    jwt_secret: Arc<String>,
    jwt_expiration_hours: i64,
    admin_username: Arc<String>,
    admin_password_hash: Arc<String>,
    vertex_client: Option<Arc<VertexAIClient>>,
    gemini_client: Option<Arc<GeminiClient>>,
    anthropic_client: Option<Arc<AnthropicClient>>,
    orchestrator: Arc<LLMOrchestrator>,
    context_bridge: Arc<ContextBridge>,
    researcher_agent: Option<Arc<ResearcherAgent>>,
    coordinator_agent: Option<Arc<CoordinatorAgent>>,
    debate_orchestrator: Option<Arc<DebateOrchestrator>>,
    hypergraph_reasoner: Option<Arc<HypergraphReasoner>>,
    causal_reasoner: Option<Arc<CausalReasoner>>,
    // Revolutionary techniques (v2.0)
    deep_research_engine: Option<Arc<MCTSEngine>>,
    swarm_orchestrator: Option<Arc<SwarmOrchestrator>>,
    temporal_reasoner: Option<Arc<TemporalReasoner>>,
    performance_monitor: Arc<Mutex<PerformanceMonitor>>,
    weakness_analyzer: Option<Arc<WeaknessAnalyzer>>,
    architecture_evolver: Option<Arc<Mutex<ArchitectureEvolver>>>,
    neural_extractor: Option<Arc<NeuralExtractor>>,
    hybrid_reasoner: Option<Arc<Mutex<HybridReasoner>>>,
    measurement_operator: Arc<MeasurementOperator>,
    interference_engine: Arc<InterferenceEngine>,
    competition_arena: Option<Arc<CompetitionArena>>,
    // Events — both are None when Pulsar is disabled or unreachable.
    pub pulsar: Option<Arc<BeaglePulsar>>,
    pub event_publisher: Option<Arc<Mutex<EventPublisher>>>,
}

impl AppState {
    /// Inicializa estado a partir da configuração carregada.
    pub async fn new(config: &Config) -> anyhow::Result<Self> {
        let storage = CachedPostgresStorage::new(config.database_url(), config.redis_url())
            .await
            .with_context(|| "Falha ao inicializar camada de armazenamento (Postgres + Redis)")?;

        let vertex_client = if let Some(project_id) = config.vertex_project_id() {
            let client = VertexAIClient::new(project_id, config.vertex_location())
                .await
                .with_context(|| {
                    format!(
                        "Falha ao inicializar VertexAIClient para o projeto {}",
                        project_id
                    )
                })?;
            Some(Arc::new(client))
        } else {
            info!("Vertex AI não configurado; rota /api/v1/chat retornará erro 503");
            None
        };

        let gemini_client = if let Some(project_id) = config.vertex_project_id() {
            let model_id = config
                .vertex_model_id()
                .unwrap_or_else(|| "gemini-1.5-pro".to_string());
            let client = GeminiClient::new(project_id, config.vertex_location(), model_id)
                .await
                .with_context(|| "Falha ao inicializar GeminiClient via Vertex AI")?;
            Some(Arc::new(client))
        } else {
            None
        };

        // === Anthropic API Direct ===
        let anthropic_client = if let Some(api_key) = config.anthropic_api_key() {
            match AnthropicClient::new(api_key) {
                Ok(client) => {
                    info!("✅ Anthropic API client initialized");
                    Some(Arc::new(client))
                }
                Err(e) => {
                    warn!("⚠️ Falha ao inicializar Anthropic client: {}", e);
                    None
                }
            }
        } else {
            info!("💡 ANTHROPIC_API_KEY não configurada");
            None
        };

        let storage = Arc::new(storage);
        let context_bridge = Arc::new(ContextBridge::new(storage.clone()));

        // Initialize LLM Orchestrator for multi-provider routing
        let orchestrator = Arc::new(LLMOrchestrator::auto_configure());
        info!(
            "✅ LLM Orchestrator initialized with {} providers",
            orchestrator.available_providers().len()
        );

        // Initialize Researcher Agent (sequencial) if Anthropic available
        let researcher_agent = anthropic_client.as_ref().map(|anthropic| {
            let personality = Arc::new(beagle_personality::PersonalityEngine::new());
            let agent = ResearcherAgent::new(
                anthropic.clone(),
                personality.clone(),
                context_bridge.clone(),
            );
            info!("✅ Researcher Agent (sequential) initialized");
            Arc::new(agent)
        });

        // Initialize Coordinator Agent (parallel multi-agent) if Anthropic available
        let coordinator_agent = anthropic_client.as_ref().map(|anthropic| {
            let personality = Arc::new(beagle_personality::PersonalityEngine::new());
            let coordinator = CoordinatorAgent::new(
                anthropic.clone(),
                personality.clone(),
                context_bridge.clone(),
            )
            .register_agent(Arc::new(RetrievalAgent::new(context_bridge.clone())))
            .register_agent(Arc::new(ValidationAgent::new(anthropic.clone())))
            .register_agent(Arc::new(QualityAgent::new(anthropic.clone())));

            info!(
                "⚡ CoordinatorAgent (parallel) initialized with Retrieval + Validation + Quality"
            );
            Arc::new(coordinator)
        });

        let debate_orchestrator = anthropic_client.as_ref().map(|llm| {
            info!("🥊 DebateOrchestrator initialized");
            Arc::new(DebateOrchestrator::new(llm.clone()))
        });

        let hypergraph_reasoner = anthropic_client.as_ref().map(|llm| {
            info!("🕸️ HypergraphReasoner initialized");
            Arc::new(HypergraphReasoner::new(storage.clone(), llm.clone()))
        });

        let causal_reasoner = anthropic_client.as_ref().map(|llm| {
            info!("🔗 CausalReasoner initialized");
            Arc::new(CausalReasoner::new(llm.clone()))
        });

        // Performance monitoring (always active)
        let performance_monitor = Arc::new(Mutex::new(PerformanceMonitor::new(1000)));

        // Measurement operator (always active)
        let measurement_operator = Arc::new(MeasurementOperator::new(0.7));

        // Interference engine (always active)
        let interference_engine = Arc::new(InterferenceEngine::new());

        // Deep Research Engine
        let deep_research_engine = if let (
            Some(ref anthropic),
            Some(ref debate),
            Some(ref reasoning),
            Some(ref causal),
        ) = (
            &anthropic_client,
            &debate_orchestrator,
            &hypergraph_reasoner,
            &causal_reasoner,
        ) {
            let simulator = Arc::new(SimulationEngine::new(
                debate.clone(),
                reasoning.clone(),
                causal.clone(),
            ));
            let engine = MCTSEngine::new(
                anthropic.clone(),
                simulator,
                20, // iterations
            );
            info!("✅ Deep Research Engine initialized (MCTS + PUCT)");
            Some(Arc::new(engine))
        } else {
            warn!("⚠️  Deep Research Engine not initialized");
            None
        };

        // Swarm Intelligence
        let swarm_orchestrator = anthropic_client.as_ref().map(|llm| {
            let swarm = SwarmOrchestrator::new(20, llm.clone()); // 20 agents
            info!("✅ Swarm Intelligence initialized (20 agents)");
            Arc::new(swarm)
        });

        // Temporal Multi-Scale
        let temporal_reasoner = anthropic_client.as_ref().map(|llm| {
            let reasoner = TemporalReasoner::new(llm.clone());
            info!("✅ Temporal Multi-Scale Reasoner initialized");
            Arc::new(reasoner)
        });

        // Meta-Cognitive
        let (weakness_analyzer, architecture_evolver) =
            if let Some(ref anthropic) = anthropic_client {
                let analyzer = Arc::new(WeaknessAnalyzer::new(anthropic.clone()));
                let factory = SpecializedAgentFactory::new(anthropic.clone());
                let evolver = Arc::new(Mutex::new(ArchitectureEvolver::new(factory)));
                info!("✅ Meta-Cognitive System initialized");
                (Some(analyzer), Some(evolver))
            } else {
                (None, None)
            };

        // Neuro-Symbolic
        let (neural_extractor, hybrid_reasoner) = if let Some(ref anthropic) = anthropic_client {
            let extractor = Arc::new(NeuralExtractor::new(anthropic.clone()));
            let hybrid = Arc::new(Mutex::new(HybridReasoner::new(extractor.clone())));
            info!("✅ Neuro-Symbolic Hybrid initialized");
            (Some(extractor), Some(hybrid))
        } else {
            (None, None)
        };

        // Adversarial Self-Play
        let competition_arena = anthropic_client.as_ref().map(|llm| {
            let arena = CompetitionArena::new(llm.clone());
            info!("✅ Adversarial Competition Arena initialized");
            Arc::new(arena)
        });

        // Initialize Pulsar (events) — optional.
        // Disabled by BEAGLE_PULSAR_ENABLED=false (or 0/no/off).
        // When enabled but Pulsar is unreachable the server still boots; events are silently dropped.
        let (pulsar, event_publisher) = if pulsar_enabled() {
            let broker_url = std::env::var("PULSAR_BROKER_URL")
                .unwrap_or_else(|_| "pulsar://localhost:6650".to_string());
            match BeaglePulsar::new(&broker_url, None).await {
                Ok(bp) => {
                    let bp = Arc::new(bp);
                    match EventPublisher::new(&bp, "beagle.events").await {
                        Ok(publisher) => {
                            info!("Apache Pulsar connected at {}", broker_url);
                            (Some(bp), Some(Arc::new(Mutex::new(publisher))))
                        }
                        Err(e) => {
                            warn!(
                                "Pulsar reachable but EventPublisher failed ({}); events disabled",
                                e
                            );
                            (None, None)
                        }
                    }
                }
                Err(e) => {
                    warn!(
                        "Cannot connect to Pulsar at {} ({}); events disabled. \
                         Set BEAGLE_PULSAR_ENABLED=false to silence this warning.",
                        broker_url, e
                    );
                    (None, None)
                }
            }
        } else {
            info!("Pulsar disabled (BEAGLE_PULSAR_ENABLED=false); events are no-op");
            (None, None)
        };

        Ok(Self {
            storage,
            jwt_secret: Arc::new(config.jwt_secret().to_owned()),
            jwt_expiration_hours: config.jwt_expiration_hours(),
            admin_username: Arc::new(config.admin_username().to_owned()),
            admin_password_hash: Arc::new(config.admin_password_hash().to_owned()),
            vertex_client,
            gemini_client,
            anthropic_client,
            orchestrator,
            context_bridge,
            researcher_agent,
            coordinator_agent,
            debate_orchestrator,
            hypergraph_reasoner,
            causal_reasoner,
            deep_research_engine,
            swarm_orchestrator,
            temporal_reasoner,
            performance_monitor,
            weakness_analyzer,
            architecture_evolver,
            neural_extractor,
            hybrid_reasoner,
            measurement_operator,
            interference_engine,
            competition_arena,
            pulsar,
            event_publisher,
        })
    }

    /// Segredo usado para assinar tokens JWT.
    pub fn jwt_secret(&self) -> &str {
        &self.jwt_secret
    }

    /// Janelas de expiração em horas para tokens JWT.
    pub fn jwt_expiration_hours(&self) -> i64 {
        self.jwt_expiration_hours
    }

    /// Usuário administrador canônico.
    pub fn admin_username(&self) -> &str {
        &self.admin_username
    }

    /// Hash Argon2 da senha administrativa.
    pub fn admin_password_hash(&self) -> &str {
        &self.admin_password_hash
    }

    /// Cliente Vertex AI configurado (se disponível).
    pub fn vertex_client(&self) -> Option<Arc<VertexAIClient>> {
        self.vertex_client.clone()
    }

    /// Cliente Gemini (Vertex Google) quando habilitado.
    pub fn gemini_client(&self) -> Option<Arc<GeminiClient>> {
        self.gemini_client.clone()
    }

    pub fn anthropic_client(&self) -> Option<Arc<AnthropicClient>> {
        self.anthropic_client.clone()
    }

    /// Alias for anthropic_client() - for compatibility with old endpoint code
    pub fn claude_client(&self) -> Option<Arc<AnthropicClient>> {
        self.anthropic_client.clone()
    }

    /// Get the LLM orchestrator for multi-provider routing
    pub fn orchestrator(&self) -> Arc<LLMOrchestrator> {
        self.orchestrator.clone()
    }

    pub fn context_bridge(&self) -> Arc<ContextBridge> {
        self.context_bridge.clone()
    }

    pub fn researcher_agent(&self) -> Option<Arc<ResearcherAgent>> {
        self.researcher_agent.clone()
    }

    pub fn coordinator_agent(&self) -> Option<Arc<CoordinatorAgent>> {
        self.coordinator_agent.clone()
    }

    pub fn debate_orchestrator(&self) -> Option<Arc<DebateOrchestrator>> {
        self.debate_orchestrator.clone()
    }

    pub fn hypergraph_reasoner(&self) -> Option<Arc<HypergraphReasoner>> {
        self.hypergraph_reasoner.clone()
    }

    pub fn causal_reasoner(&self) -> Option<Arc<CausalReasoner>> {
        self.causal_reasoner.clone()
    }

    pub fn deep_research_engine(&self) -> Option<Arc<MCTSEngine>> {
        self.deep_research_engine.clone()
    }

    pub fn swarm_orchestrator(&self) -> Option<Arc<SwarmOrchestrator>> {
        self.swarm_orchestrator.clone()
    }

    pub fn temporal_reasoner(&self) -> Option<Arc<TemporalReasoner>> {
        self.temporal_reasoner.clone()
    }

    pub fn performance_monitor(&self) -> Arc<Mutex<PerformanceMonitor>> {
        self.performance_monitor.clone()
    }

    pub fn weakness_analyzer(&self) -> Option<Arc<WeaknessAnalyzer>> {
        self.weakness_analyzer.clone()
    }

    pub fn architecture_evolver(&self) -> Option<Arc<Mutex<ArchitectureEvolver>>> {
        self.architecture_evolver.clone()
    }

    pub fn neural_extractor(&self) -> Option<Arc<NeuralExtractor>> {
        self.neural_extractor.clone()
    }

    pub fn hybrid_reasoner(&self) -> Option<Arc<Mutex<HybridReasoner>>> {
        self.hybrid_reasoner.clone()
    }

    pub fn measurement_operator(&self) -> Arc<MeasurementOperator> {
        self.measurement_operator.clone()
    }

    pub fn interference_engine(&self) -> Arc<InterferenceEngine> {
        self.interference_engine.clone()
    }

    pub fn competition_arena(&self) -> Option<Arc<CompetitionArena>> {
        self.competition_arena.clone()
    }
}
