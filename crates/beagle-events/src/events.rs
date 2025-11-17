use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ============================================
// EVENT TYPES
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "category", content = "payload")]
pub enum EventType {
    // === RESEARCH WORKFLOWS ===
    Research(ResearchEvent),

    // === AGENT LIFECYCLE ===
    Agent(AgentEvent),

    // === MEMORY & HYPERGRAPH ===
    Memory(MemoryEvent),

    // === DISCOVERY & SERENDIPITY ===
    Discovery(DiscoveryEvent),

    // === SYSTEM & HEALTH ===
    System(SystemEvent),
}

// ============================================
// RESEARCH EVENTS
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ResearchEvent {
    // MCTS Deep Research
    MCTSStarted {
        session_id: String,
        root_hypothesis: String,
        max_iterations: usize,
    },
    MCTSIteration {
        session_id: String,
        iteration: usize,
        best_score: f64,
    },
    MCTSCompleted {
        session_id: String,
        best_hypothesis: String,
        confidence: f64,
        total_iterations: usize,
    },

    // Swarm Intelligence
    SwarmInitialized {
        swarm_id: String,
        agent_count: usize,
        task: String,
    },
    PheromoneDeposited {
        swarm_id: String,
        location: Vec<f64>,
        strength: f64,
    },
    EmergentPatternDetected {
        swarm_id: String,
        pattern_description: String,
    },

    // Adversarial Debate
    DebateStarted {
        debate_id: String,
        topic: String,
        participants: Vec<String>,
    },
    DebateRound {
        debate_id: String,
        round: usize,
        arguments: Vec<String>,
    },
    DebateSynthesized {
        debate_id: String,
        synthesis: String,
        confidence: f64,
    },
}

// ============================================
// AGENT EVENTS
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AgentEvent {
    Spawned {
        agent_id: String,
        agent_type: String,
        capabilities: Vec<String>,
    },
    TaskStarted {
        agent_id: String,
        task_id: String,
        task_description: String,
    },
    TaskCompleted {
        agent_id: String,
        task_id: String,
        result: serde_json::Value,
        duration_ms: u64,
    },
    TaskFailed {
        agent_id: String,
        task_id: String,
        error: String,
    },
    AgentTerminated {
        agent_id: String,
        reason: String,
    },
}

// ============================================
// MEMORY EVENTS
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum MemoryEvent {
    NodeCreated {
        node_id: String,
        node_type: String,
        content: String,
    },
    NodeUpdated {
        node_id: String,
        update_type: String,
    },
    NodeDeleted {
        node_id: String,
    },
    EdgeCreated {
        edge_id: String,
        source_id: String,
        target_id: String,
        edge_type: String,
    },
    QueryExecuted {
        query: String,
        result_count: usize,
        duration_ms: u64,
    },
    EmbeddingGenerated {
        node_id: String,
        embedding_model: String,
        dimension: usize,
    },
}

// ============================================
// DISCOVERY EVENTS
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum DiscoveryEvent {
    NoveltyDetected {
        hypothesis: String,
        novelty_score: f64,
        related_papers: Vec<String>,
    },
    PatternDiscovered {
        pattern_id: String,
        pattern_type: String,
        description: String,
        confidence: f64,
    },
    CrossDomainConnection {
        domain_a: String,
        domain_b: String,
        connection_type: String,
        insight: String,
    },
    SerendipityTriggered {
        trigger: String,
        unexpected_finding: String,
    },
}

// ============================================
// SYSTEM EVENTS
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum SystemEvent {
    HealthCheck {
        service: String,
        status: HealthStatus,
    },
    MetricsSnapshot {
        metrics: serde_json::Value,
    },
    Alert {
        severity: AlertSeverity,
        message: String,
        source: String,
    },
    ConfigUpdated {
        config_key: String,
        old_value: String,
        new_value: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum HealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AlertSeverity {
    Info,
    Warning,
    Error,
    Critical,
}

// ============================================
// EVENT METADATA
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventMetadata {
    pub event_id: Uuid,
    pub timestamp: DateTime<Utc>,
    pub source_service: String,
    pub correlation_id: Option<String>,
    pub user_id: Option<String>,
    pub trace_id: Option<String>, // Distributed tracing
}

impl Default for EventMetadata {
    fn default() -> Self {
        Self {
            event_id: Uuid::new_v4(),
            timestamp: Utc::now(),
            source_service: "beagle-core".to_string(),
            correlation_id: None,
            user_id: None,
            trace_id: None,
        }
    }
}

// ============================================
// COMPLETE EVENT
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeagleEvent {
    pub metadata: EventMetadata,
    pub event_type: EventType,
}

impl BeagleEvent {
    pub fn new(event_type: EventType) -> Self {
        Self {
            metadata: EventMetadata::default(),
            event_type,
        }
    }

    pub fn research(event: ResearchEvent) -> Self {
        Self::new(EventType::Research(event))
    }

    pub fn agent(event: AgentEvent) -> Self {
        Self::new(EventType::Agent(event))
    }

    pub fn memory(event: MemoryEvent) -> Self {
        Self::new(EventType::Memory(event))
    }

    pub fn discovery(event: DiscoveryEvent) -> Self {
        Self::new(EventType::Discovery(event))
    }

    pub fn system(event: SystemEvent) -> Self {
        Self::new(EventType::System(event))
    }

    // Builder methods
    pub fn with_correlation(mut self, correlation_id: impl Into<String>) -> Self {
        self.metadata.correlation_id = Some(correlation_id.into());
        self
    }

    pub fn with_user(mut self, user_id: impl Into<String>) -> Self {
        self.metadata.user_id = Some(user_id.into());
        self
    }

    pub fn with_source(mut self, source_service: impl Into<String>) -> Self {
        self.metadata.source_service = source_service.into();
        self
    }

    pub fn with_trace(mut self, trace_id: impl Into<String>) -> Self {
        self.metadata.trace_id = Some(trace_id.into());
        self
    }
}

// ============================================
// TESTS
// ============================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_serialize_deserialize() {
        let event = BeagleEvent::research(ResearchEvent::MCTSStarted {
            session_id: "session-123".to_string(),
            root_hypothesis: "Test hypothesis".to_string(),
            max_iterations: 100,
        })
        .with_correlation("corr-456")
        .with_user("user-789");

        let json = serde_json::to_string(&event).unwrap();
        let deserialized: BeagleEvent = serde_json::from_str(&json).unwrap();

        assert_eq!(
            event.metadata.correlation_id,
            deserialized.metadata.correlation_id
        );
    }
}
