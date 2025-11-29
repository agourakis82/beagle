//! Configuration for the Personal Exocortex

use serde::{Deserialize, Serialize};

/// Main configuration for the exocortex system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExocortexConfig {
    /// Identity system configuration
    pub identity: IdentityConfig,

    /// Brain connector (consciousness) configuration
    pub brain: BrainConfig,

    /// Context manager configuration
    pub context: ContextConfig,

    /// Agent mesh configuration
    pub agents: AgentConfig,

    /// Memory bridge configuration
    pub memory: MemoryConfig,

    /// Feature flags
    pub features: FeatureFlags,
}

impl Default for ExocortexConfig {
    fn default() -> Self {
        Self {
            identity: IdentityConfig::default(),
            brain: BrainConfig::default(),
            context: ContextConfig::default(),
            agents: AgentConfig::default(),
            memory: MemoryConfig::default(),
            features: FeatureFlags::default(),
        }
    }
}

impl ExocortexConfig {
    /// Minimal configuration for testing
    pub fn minimal() -> Self {
        Self {
            features: FeatureFlags {
                enable_consciousness: false,
                enable_personality: false,
                enable_worldmodel: false,
                enable_observer: false,
                enable_proactive: false,
                enable_learning: false,
            },
            ..Default::default()
        }
    }

    /// Full configuration with all features enabled
    pub fn full() -> Self {
        Self {
            features: FeatureFlags {
                enable_consciousness: true,
                enable_personality: true,
                enable_worldmodel: true,
                enable_observer: true,
                enable_proactive: true,
                enable_learning: true,
            },
            ..Default::default()
        }
    }
}

/// Identity system configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IdentityConfig {
    /// Persistence backend (memory, file, postgres)
    pub persistence: String,

    /// Path for file-based persistence
    pub persistence_path: Option<String>,

    /// Database URL for postgres persistence
    pub database_url: Option<String>,

    /// Maximum session history to retain
    pub max_session_history: usize,

    /// Enable expertise level tracking
    pub track_expertise: bool,

    /// Enable preference learning
    pub learn_preferences: bool,
}

impl Default for IdentityConfig {
    fn default() -> Self {
        Self {
            persistence: "memory".to_string(),
            persistence_path: None,
            database_url: None,
            max_session_history: 100,
            track_expertise: true,
            learn_preferences: true,
        }
    }
}

/// Brain connector (consciousness) configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrainConfig {
    /// Phi (Φ) threshold for deep reasoning escalation
    pub phi_threshold: f64,

    /// Enable IIT 4.0 consciousness calculation
    pub enable_iit: bool,

    /// Enable Global Workspace Theory attention spotlight
    pub enable_gwt: bool,

    /// Ignition threshold for GWT
    pub gwt_ignition_threshold: f64,

    /// Maximum attention span (items in working memory)
    pub max_attention_span: usize,

    /// Confidence calibration per domain
    pub calibrate_confidence: bool,
}

impl Default for BrainConfig {
    fn default() -> Self {
        Self {
            phi_threshold: 0.5,
            enable_iit: true,
            enable_gwt: true,
            gwt_ignition_threshold: 0.6,
            max_attention_span: 7, // Miller's law: 7 +/- 2
            calibrate_confidence: true,
        }
    }
}

/// Context manager configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextConfig {
    /// Enable world model integration
    pub enable_worldmodel: bool,

    /// Enable causal reasoning
    pub enable_causal: bool,

    /// Enable counterfactual reasoning
    pub enable_counterfactual: bool,

    /// Context window size (tokens)
    pub context_window: usize,

    /// Enable situational adaptation
    pub adapt_to_situation: bool,
}

impl Default for ContextConfig {
    fn default() -> Self {
        Self {
            enable_worldmodel: true,
            enable_causal: true,
            enable_counterfactual: true,
            context_window: 8192,
            adapt_to_situation: true,
        }
    }
}

/// Agent mesh configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    /// Maximum concurrent agents
    pub max_concurrent: usize,

    /// Enable agent specialization learning
    pub enable_specialization: bool,

    /// Enable team coordination
    pub enable_coordination: bool,

    /// Default agent timeout (seconds)
    pub timeout_secs: u64,

    /// Enable proactive task suggestions
    pub enable_proactive: bool,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            max_concurrent: 5,
            enable_specialization: true,
            enable_coordination: true,
            timeout_secs: 60,
            enable_proactive: true,
        }
    }
}

/// Memory bridge configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryConfig {
    /// Enable semantic search
    pub enable_semantic: bool,

    /// Enable episodic memory
    pub enable_episodic: bool,

    /// Enable consciousness state tagging
    pub tag_consciousness: bool,

    /// Maximum memories to retrieve
    pub max_retrieval: usize,

    /// Similarity threshold for retrieval
    pub similarity_threshold: f32,

    /// Enable memory consolidation (long-term learning)
    pub enable_consolidation: bool,
}

impl Default for MemoryConfig {
    fn default() -> Self {
        Self {
            enable_semantic: true,
            enable_episodic: true,
            tag_consciousness: true,
            max_retrieval: 10,
            similarity_threshold: 0.7,
            enable_consolidation: true,
        }
    }
}

/// Feature flags for optional components
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureFlags {
    /// Enable consciousness substrate (IIT/GWT)
    pub enable_consciousness: bool,

    /// Enable personality system integration
    pub enable_personality: bool,

    /// Enable world model integration
    pub enable_worldmodel: bool,

    /// Enable observer (HRV, environmental) integration
    pub enable_observer: bool,

    /// Enable proactive intelligence
    pub enable_proactive: bool,

    /// Enable continuous learning from feedback
    pub enable_learning: bool,
}

impl Default for FeatureFlags {
    fn default() -> Self {
        Self {
            enable_consciousness: true,
            enable_personality: true,
            enable_worldmodel: true,
            enable_observer: true,
            enable_proactive: false, // Disabled by default - can be intrusive
            enable_learning: true,
        }
    }
}
