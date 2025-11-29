//! Memory Bridge - Unified semantic/episodic memory with consciousness tagging
//!
//! Bridges the Memory system with consciousness states, providing:
//! - Episodic memory with emotional salience
//! - Semantic memory with knowledge graphs
//! - Working memory with attention spotlight
//! - Memory consolidation during "rest" states
//! - Optional integration with beagle-memory for persistent storage

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;

#[cfg(feature = "memory")]
use beagle_memory::{
    MemoryEngine, MemoryQuery as BeagleMemoryQuery, MemoryResult as BeagleMemoryResult,
};

use crate::error::{ExocortexError, ExocortexResult};

// ============================================================================
// Memory Types
// ============================================================================

/// Emotional valence for memory encoding
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EmotionalValence {
    /// Pleasure-displeasure axis (-1 to 1)
    pub valence: f32,
    /// Calm-excited axis (0 to 1)
    pub arousal: f32,
    /// Weak-strong axis (0 to 1)
    pub dominance: f32,
}

impl Default for EmotionalValence {
    fn default() -> Self {
        Self {
            valence: 0.0,
            arousal: 0.3,
            dominance: 0.5,
        }
    }
}

impl EmotionalValence {
    /// Calculate salience for memory prioritization
    pub fn salience(&self) -> f32 {
        // High arousal + extreme valence = high salience
        let valence_extremity = self.valence.abs();
        (valence_extremity * 0.4 + self.arousal * 0.4 + self.dominance * 0.2).clamp(0.0, 1.0)
    }
}

/// An episodic memory - a specific experience or event
#[derive(Debug, Clone)]
pub struct EpisodicMemory {
    /// Unique identifier
    pub id: String,
    /// When this memory was formed
    pub timestamp: chrono::DateTime<chrono::Utc>,
    /// The content/description of the episode
    pub content: String,
    /// Emotional context during encoding
    pub emotional_context: EmotionalValence,
    /// Consciousness level during encoding (Phi value)
    pub phi_at_encoding: f32,
    /// Attention focus during encoding
    pub attention_focus: Vec<String>,
    /// Related semantic concepts
    pub semantic_links: Vec<String>,
    /// Access count (for rehearsal-based consolidation)
    pub access_count: u32,
    /// Last access time
    pub last_accessed: chrono::DateTime<chrono::Utc>,
    /// Consolidation strength (0-1, increases with rehearsal)
    pub consolidation: f32,
}

impl EpisodicMemory {
    /// Calculate retrieval probability using temporal decay + consolidation
    pub fn retrieval_probability(&self, now: chrono::DateTime<chrono::Utc>) -> f32 {
        let age_hours = (now - self.timestamp).num_hours() as f32;

        // Power law forgetting curve (Wixted & Ebbesen, 1991)
        let temporal_decay = 1.0 / (1.0 + (age_hours / 24.0).powf(0.5));

        // Rehearsal strengthening
        let rehearsal_boost = (self.access_count as f32 * 0.1).min(0.5);

        // Emotional salience boost
        let emotional_boost = self.emotional_context.salience() * 0.3;

        // Consolidation provides base retention
        let base = self.consolidation * 0.5;

        (base + temporal_decay * (1.0 - base) + rehearsal_boost + emotional_boost).clamp(0.0, 1.0)
    }
}

/// A semantic memory - factual/conceptual knowledge
#[derive(Debug, Clone)]
pub struct SemanticMemory {
    /// Unique identifier
    pub id: String,
    /// The concept/fact
    pub content: String,
    /// Category/domain
    pub domain: String,
    /// Confidence in this knowledge (0-1)
    pub confidence: f32,
    /// Source reliability
    pub source_reliability: f32,
    /// Links to related concepts (concept_id -> relationship_type)
    pub relations: HashMap<String, String>,
    /// How many times verified/reinforced
    pub reinforcement_count: u32,
    /// Embedding vector for similarity search
    pub embedding: Option<Vec<f32>>,
}

impl SemanticMemory {
    /// Calculate knowledge strength
    pub fn strength(&self) -> f32 {
        let reinforcement_factor = (self.reinforcement_count as f32).sqrt() / 10.0;
        (self.confidence * 0.5 + self.source_reliability * 0.3 + reinforcement_factor.min(0.2))
            .clamp(0.0, 1.0)
    }
}

/// Working memory item - currently active information
#[derive(Debug, Clone)]
pub struct WorkingMemoryItem {
    /// Content identifier
    pub id: String,
    /// The information
    pub content: String,
    /// When loaded into working memory
    pub loaded_at: Instant,
    /// Attention weight (0-1)
    pub attention_weight: f32,
    /// Source: episodic, semantic, or external
    pub source: MemorySource,
    /// Decay rate per second
    pub decay_rate: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemorySource {
    Episodic,
    Semantic,
    External,
    Generated,
}

impl WorkingMemoryItem {
    /// Get current activation level with decay
    pub fn activation(&self) -> f32 {
        let elapsed = self.loaded_at.elapsed().as_secs_f32();
        let decayed = self.attention_weight * (-self.decay_rate * elapsed).exp();
        decayed.max(0.0)
    }
}

// ============================================================================
// Memory Bridge
// ============================================================================

/// Working memory buffer with capacity limits
pub struct WorkingMemoryBuffer {
    /// Items in working memory (max ~7 +/- 2, Miller's law)
    items: Vec<WorkingMemoryItem>,
    /// Maximum capacity
    capacity: usize,
    /// Attention spotlight - which items are in focus
    spotlight: Vec<String>,
}

impl Default for WorkingMemoryBuffer {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            capacity: 7, // Miller's magical number
            spotlight: Vec::new(),
        }
    }
}

impl WorkingMemoryBuffer {
    /// Add item to working memory, evicting lowest activation if full
    pub fn add(&mut self, item: WorkingMemoryItem) {
        // Check if already present
        if let Some(existing) = self.items.iter_mut().find(|i| i.id == item.id) {
            existing.attention_weight = item.attention_weight;
            existing.loaded_at = Instant::now();
            return;
        }

        if self.items.len() >= self.capacity {
            // Evict lowest activation item
            self.items.sort_by(|a, b| {
                b.activation()
                    .partial_cmp(&a.activation())
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            self.items.pop();
        }

        self.items.push(item);
    }

    /// Get all items above activation threshold
    pub fn active_items(&self, threshold: f32) -> Vec<&WorkingMemoryItem> {
        self.items
            .iter()
            .filter(|i| i.activation() > threshold)
            .collect()
    }

    /// Focus attention on specific items
    pub fn focus(&mut self, item_ids: &[String]) {
        self.spotlight = item_ids.to_vec();

        for item in &mut self.items {
            if item_ids.contains(&item.id) {
                item.attention_weight = (item.attention_weight + 0.3).min(1.0);
                item.decay_rate *= 0.5; // Slow decay for attended items
            }
        }
    }

    /// Clear items below threshold
    pub fn cleanup(&mut self, threshold: f32) {
        self.items.retain(|i| i.activation() > threshold);
    }

    /// Get current spotlight
    pub fn spotlight(&self) -> &[String] {
        &self.spotlight
    }
}

/// Configuration for memory bridge
#[derive(Debug, Clone)]
pub struct MemoryBridgeConfig {
    /// Enable emotional encoding
    pub emotional_encoding: bool,
    /// Enable consciousness-tagged memories
    pub consciousness_tagging: bool,
    /// Consolidation threshold (min salience to consolidate)
    pub consolidation_threshold: f32,
    /// Working memory capacity
    pub working_memory_capacity: usize,
    /// Default memory decay rate
    pub default_decay_rate: f32,
}

impl Default for MemoryBridgeConfig {
    fn default() -> Self {
        Self {
            emotional_encoding: true,
            consciousness_tagging: true,
            consolidation_threshold: 0.3,
            working_memory_capacity: 7,
            default_decay_rate: 0.01,
        }
    }
}

/// Memory Bridge - unifies all memory systems with consciousness integration
pub struct MemoryBridge {
    config: MemoryBridgeConfig,

    /// Working memory buffer
    working_memory: Arc<RwLock<WorkingMemoryBuffer>>,

    /// Recent episodic memories (in-memory cache)
    episodic_cache: Arc<RwLock<Vec<EpisodicMemory>>>,

    /// Semantic memory index (in-memory cache)
    semantic_cache: Arc<RwLock<HashMap<String, SemanticMemory>>>,

    /// Current emotional state for encoding
    current_emotion: Arc<RwLock<EmotionalValence>>,

    /// Current consciousness level (Phi)
    current_phi: Arc<RwLock<f32>>,

    /// Real memory engine for persistent storage (optional)
    #[cfg(feature = "memory")]
    memory_engine: Option<Arc<MemoryEngine>>,
}

impl MemoryBridge {
    /// Create new memory bridge (in-memory only)
    pub fn new(config: MemoryBridgeConfig) -> Self {
        let capacity = config.working_memory_capacity;
        Self {
            config,
            working_memory: Arc::new(RwLock::new(WorkingMemoryBuffer {
                capacity,
                ..Default::default()
            })),
            episodic_cache: Arc::new(RwLock::new(Vec::new())),
            semantic_cache: Arc::new(RwLock::new(HashMap::new())),
            current_emotion: Arc::new(RwLock::new(EmotionalValence::default())),
            current_phi: Arc::new(RwLock::new(0.5)),
            #[cfg(feature = "memory")]
            memory_engine: None,
        }
    }

    /// Create memory bridge with real beagle-memory engine for persistent storage
    #[cfg(feature = "memory")]
    pub fn with_engine(config: MemoryBridgeConfig, engine: Arc<MemoryEngine>) -> Self {
        let capacity = config.working_memory_capacity;
        Self {
            config,
            working_memory: Arc::new(RwLock::new(WorkingMemoryBuffer {
                capacity,
                ..Default::default()
            })),
            episodic_cache: Arc::new(RwLock::new(Vec::new())),
            semantic_cache: Arc::new(RwLock::new(HashMap::new())),
            current_emotion: Arc::new(RwLock::new(EmotionalValence::default())),
            current_phi: Arc::new(RwLock::new(0.5)),
            memory_engine: Some(engine),
        }
    }

    /// Check if persistent memory engine is available
    #[cfg(feature = "memory")]
    pub fn has_persistent_storage(&self) -> bool {
        self.memory_engine.is_some()
    }

    /// Check if persistent memory engine is available (always false without feature)
    #[cfg(not(feature = "memory"))]
    pub fn has_persistent_storage(&self) -> bool {
        false
    }

    /// Update current emotional state
    pub async fn set_emotional_state(&self, emotion: EmotionalValence) {
        *self.current_emotion.write().await = emotion;
    }

    /// Update current consciousness level
    pub async fn set_consciousness_level(&self, phi: f32) {
        *self.current_phi.write().await = phi;
    }

    /// Encode a new episodic memory with current context
    pub async fn encode_episode(
        &self,
        content: String,
        attention_focus: Vec<String>,
    ) -> ExocortexResult<EpisodicMemory> {
        let emotion = *self.current_emotion.read().await;
        let phi = *self.current_phi.read().await;
        let now = chrono::Utc::now();

        let memory = EpisodicMemory {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: now,
            content,
            emotional_context: emotion,
            phi_at_encoding: phi,
            attention_focus,
            semantic_links: Vec::new(),
            access_count: 1,
            last_accessed: now,
            consolidation: emotion.salience() * 0.3 + phi * 0.2, // Initial consolidation
        };

        // Add to cache
        self.episodic_cache.write().await.push(memory.clone());

        // Also load into working memory
        self.load_to_working_memory(
            memory.id.clone(),
            memory.content.clone(),
            MemorySource::Episodic,
        )
        .await;

        Ok(memory)
    }

    /// Store semantic knowledge
    pub async fn store_semantic(
        &self,
        content: String,
        domain: String,
        confidence: f32,
        source_reliability: f32,
    ) -> ExocortexResult<SemanticMemory> {
        let memory = SemanticMemory {
            id: uuid::Uuid::new_v4().to_string(),
            content,
            domain,
            confidence,
            source_reliability,
            relations: HashMap::new(),
            reinforcement_count: 1,
            embedding: None,
        };

        self.semantic_cache
            .write()
            .await
            .insert(memory.id.clone(), memory.clone());

        Ok(memory)
    }

    /// Load content into working memory
    pub async fn load_to_working_memory(&self, id: String, content: String, source: MemorySource) {
        let item = WorkingMemoryItem {
            id,
            content,
            loaded_at: Instant::now(),
            attention_weight: 0.7,
            source,
            decay_rate: self.config.default_decay_rate,
        };

        self.working_memory.write().await.add(item);
    }

    /// Focus attention on specific working memory items
    pub async fn focus_attention(&self, item_ids: &[String]) {
        self.working_memory.write().await.focus(item_ids);
    }

    /// Get current working memory contents
    pub async fn get_working_memory(&self, activation_threshold: f32) -> Vec<WorkingMemoryItem> {
        self.working_memory
            .read()
            .await
            .active_items(activation_threshold)
            .into_iter()
            .cloned()
            .collect()
    }

    /// Retrieve episodic memories by similarity/recency
    /// If persistent memory engine is available, also queries it for additional context
    pub async fn retrieve_episodes(&self, query: &str, max_results: usize) -> Vec<EpisodicMemory> {
        let now = chrono::Utc::now();
        let mut episodes = self.episodic_cache.read().await.clone();

        // If we have a persistent memory engine, query it for additional memories
        #[cfg(feature = "memory")]
        if let Some(ref engine) = self.memory_engine {
            let memory_query = BeagleMemoryQuery {
                query: query.to_string(),
                scope: None,
                max_items: Some(max_results),
            };

            match engine.query(memory_query).await {
                Ok(result) => {
                    // Convert highlights to episodic memories
                    for highlight in result.highlights {
                        let episode = EpisodicMemory {
                            id: highlight
                                .session_id
                                .unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
                            timestamp: highlight.date.unwrap_or_else(chrono::Utc::now),
                            content: highlight.snippet,
                            emotional_context: EmotionalValence::default(),
                            phi_at_encoding: 0.5, // Unknown from persistent storage
                            attention_focus: vec![],
                            semantic_links: vec![highlight.source.clone()],
                            access_count: 1,
                            last_accessed: now,
                            consolidation: highlight.relevance,
                        };
                        episodes.push(episode);
                    }
                }
                Err(e) => {
                    tracing::warn!("Failed to query persistent memory: {}", e);
                }
            }
        }

        // Score by retrieval probability and simple keyword match
        episodes.sort_by(|a, b| {
            let score_a = a.retrieval_probability(now)
                + if a.content.to_lowercase().contains(&query.to_lowercase()) {
                    0.3
                } else {
                    0.0
                };
            let score_b = b.retrieval_probability(now)
                + if b.content.to_lowercase().contains(&query.to_lowercase()) {
                    0.3
                } else {
                    0.0
                };
            score_b
                .partial_cmp(&score_a)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        episodes.into_iter().take(max_results).collect()
    }

    /// Query persistent memory directly (returns summary and highlights)
    #[cfg(feature = "memory")]
    pub async fn query_persistent_memory(
        &self,
        query: &str,
        scope: Option<&str>,
        max_items: usize,
    ) -> Option<BeagleMemoryResult> {
        if let Some(ref engine) = self.memory_engine {
            let memory_query = BeagleMemoryQuery {
                query: query.to_string(),
                scope: scope.map(|s| s.to_string()),
                max_items: Some(max_items),
            };

            match engine.query(memory_query).await {
                Ok(result) => Some(result),
                Err(e) => {
                    tracing::warn!("Persistent memory query failed: {}", e);
                    None
                }
            }
        } else {
            None
        }
    }

    /// Retrieve semantic memories by domain
    pub async fn retrieve_semantic_by_domain(&self, domain: &str) -> Vec<SemanticMemory> {
        self.semantic_cache
            .read()
            .await
            .values()
            .filter(|m| m.domain == domain)
            .cloned()
            .collect()
    }

    /// Consolidate memories (should be called during low-activity periods)
    pub async fn consolidate(&self) {
        let threshold = self.config.consolidation_threshold;

        // Strengthen high-salience episodic memories
        let mut episodes = self.episodic_cache.write().await;
        for episode in episodes.iter_mut() {
            if episode.emotional_context.salience() > threshold {
                episode.consolidation = (episode.consolidation + 0.1).min(1.0);
            }
        }

        // Prune very old, low-consolidation memories
        let cutoff = chrono::Utc::now() - chrono::Duration::days(30);
        episodes.retain(|e| e.consolidation > 0.2 || e.timestamp > cutoff);

        // Clean up working memory
        self.working_memory.write().await.cleanup(0.1);
    }

    /// Get memory statistics
    pub async fn stats(&self) -> MemoryStats {
        let episodic_count = self.episodic_cache.read().await.len();
        let semantic_count = self.semantic_cache.read().await.len();
        let working_count = self.working_memory.read().await.items.len();

        MemoryStats {
            episodic_count,
            semantic_count,
            working_memory_count: working_count,
            working_memory_capacity: self.config.working_memory_capacity,
        }
    }
}

/// Memory statistics
#[derive(Debug, Clone)]
pub struct MemoryStats {
    pub episodic_count: usize,
    pub semantic_count: usize,
    pub working_memory_count: usize,
    pub working_memory_capacity: usize,
}

// ============================================================================
// Memory-Consciousness Integration
// ============================================================================

/// Consciousness-tagged memory query
pub struct ConsciousMemoryQuery {
    /// Text query
    pub query: String,
    /// Minimum consciousness level for retrieval
    pub min_phi: f32,
    /// Emotional filter (if any)
    pub emotional_filter: Option<EmotionalValence>,
    /// Time range
    pub time_range: Option<(chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>)>,
}

impl MemoryBridge {
    /// Query memories with consciousness filtering
    pub async fn conscious_query(&self, query: ConsciousMemoryQuery) -> Vec<EpisodicMemory> {
        let episodes = self.episodic_cache.read().await;

        episodes
            .iter()
            .filter(|e| {
                // Phi filter
                if e.phi_at_encoding < query.min_phi {
                    return false;
                }

                // Time range filter
                if let Some((start, end)) = query.time_range {
                    if e.timestamp < start || e.timestamp > end {
                        return false;
                    }
                }

                // Emotional similarity filter
                if let Some(ref target_emotion) = query.emotional_filter {
                    let valence_diff = (e.emotional_context.valence - target_emotion.valence).abs();
                    let arousal_diff = (e.emotional_context.arousal - target_emotion.arousal).abs();
                    if valence_diff > 0.5 || arousal_diff > 0.5 {
                        return false;
                    }
                }

                // Content match
                e.content
                    .to_lowercase()
                    .contains(&query.query.to_lowercase())
            })
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_emotional_salience() {
        let neutral = EmotionalValence::default();
        assert!(neutral.salience() < 0.5);

        let excited = EmotionalValence {
            valence: 0.8,
            arousal: 0.9,
            dominance: 0.7,
        };
        assert!(excited.salience() > 0.7);
    }

    #[test]
    fn test_working_memory_capacity() {
        let mut buffer = WorkingMemoryBuffer::default();

        // Add more than capacity
        for i in 0..10 {
            buffer.add(WorkingMemoryItem {
                id: format!("item_{}", i),
                content: format!("Content {}", i),
                loaded_at: Instant::now(),
                attention_weight: 0.5,
                source: MemorySource::External,
                decay_rate: 0.01,
            });
        }

        // Should not exceed capacity
        assert!(buffer.items.len() <= buffer.capacity);
    }

    #[tokio::test]
    async fn test_memory_bridge_encode() {
        let bridge = MemoryBridge::new(MemoryBridgeConfig::default());

        let episode = bridge
            .encode_episode(
                "Learned about IIT 4.0".to_string(),
                vec!["consciousness".to_string(), "phi".to_string()],
            )
            .await
            .unwrap();

        assert!(!episode.id.is_empty());
        assert!(episode.consolidation > 0.0);
    }
}
