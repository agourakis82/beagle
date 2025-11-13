//! Estado compartilhado da aplicação Axum.

use std::sync::Arc;

use anyhow::Context;
use beagle_agents::{
    CausalReasoner, CoordinatorAgent, DebateOrchestrator, HypergraphReasoner, QualityAgent,
    ResearcherAgent, RetrievalAgent, ValidationAgent,
};
use beagle_hypergraph::storage::CachedPostgresStorage;
use beagle_llm::{AnthropicClient, GeminiClient, VertexAIClient};
use beagle_memory::ContextBridge;
use tracing::{info, warn};

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
    context_bridge: Arc<ContextBridge>,
    researcher_agent: Option<Arc<ResearcherAgent>>,
    coordinator_agent: Option<Arc<CoordinatorAgent>>,
    debate_orchestrator: Option<Arc<DebateOrchestrator>>,
    hypergraph_reasoner: Option<Arc<HypergraphReasoner>>,
    causal_reasoner: Option<Arc<CausalReasoner>>,
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

        Ok(Self {
            storage,
            jwt_secret: Arc::new(config.jwt_secret().to_owned()),
            jwt_expiration_hours: config.jwt_expiration_hours(),
            admin_username: Arc::new(config.admin_username().to_owned()),
            admin_password_hash: Arc::new(config.admin_password_hash().to_owned()),
            vertex_client,
            gemini_client,
            anthropic_client,
            context_bridge,
            researcher_agent,
            coordinator_agent,
            debate_orchestrator,
            hypergraph_reasoner,
            causal_reasoner,
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
}
