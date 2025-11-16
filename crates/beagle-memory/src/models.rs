use beagle_personality::Domain;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Conversation turn stored in hypergraph
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationTurn {
    pub id: Uuid,
    pub session_id: Uuid,
    pub query: String,
    pub response: String,
    pub domain: Domain,
    pub model: String,
    pub timestamp: DateTime<Utc>,
    pub metadata: ConversationMetadata,
}

/// Metadata for conversation context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationMetadata {
    /// System prompt used (preview)
    pub system_prompt_preview: Option<String>,

    /// User feedback (if any)
    pub feedback: Option<UserFeedback>,

    /// Performance metrics
    pub metrics: PerformanceMetrics,

    /// Tags for categorization
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserFeedback {
    pub helpful: bool,
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub latency_ms: u64,
    pub tokens_input: Option<u32>,
    pub tokens_output: Option<u32>,
    pub cost_usd: Option<f32>,
}

/// Session representing a conversation thread
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationSession {
    pub id: Uuid,
    pub user_id: Option<String>,
    pub started_at: DateTime<Utc>,
    pub last_active: DateTime<Utc>,
    pub turn_count: usize,
}

/// Context retrieval result
#[derive(Debug, Clone)]
pub struct RetrievedContext {
    pub turns: Vec<ConversationTurn>,
    pub relevance_scores: Vec<f32>,
    pub total_tokens: usize,
}

impl ConversationTurn {
    pub fn new(
        session_id: Uuid,
        query: String,
        response: String,
        domain: Domain,
        model: String,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            session_id,
            query,
            response,
            domain,
            model,
            timestamp: Utc::now(),
            metadata: ConversationMetadata {
                system_prompt_preview: None,
                feedback: None,
                metrics: PerformanceMetrics {
                    latency_ms: 0,
                    tokens_input: None,
                    tokens_output: None,
                    cost_usd: None,
                },
                tags: vec![],
            },
        }
    }

    /// Total character count (for context window management)
    pub fn char_count(&self) -> usize {
        self.query.len() + self.response.len()
    }
}

impl RetrievedContext {
    /// Truncate context to fit token budget
    pub fn truncate_to_budget(&mut self, max_tokens: usize) {
        let mut current_tokens = 0;
        let mut keep_count = 0;

        for turn in &self.turns {
            // Rough approximation: 4 chars = 1 token
            let turn_tokens = turn.char_count() / 4;
            if current_tokens + turn_tokens > max_tokens {
                break;
            }
            current_tokens += turn_tokens;
            keep_count += 1;
        }

        self.turns.truncate(keep_count);
        self.relevance_scores.truncate(keep_count);
        self.total_tokens = current_tokens;
    }
}
