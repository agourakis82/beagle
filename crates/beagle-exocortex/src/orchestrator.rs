//! Personal Exocortex Orchestrator
//!
//! The main orchestration layer that unifies all cognitive components:
//! - Identity (who you are, your preferences, expertise)
//! - Brain (consciousness, attention, metacognition)
//! - Memory (episodic, semantic, working memory)
//! - Context (world state, physiological state, environment)
//! - Agents (specialized capabilities, team coordination)
//!
//! This creates a unified personal assistant that truly knows you.

use std::sync::Arc;
use tokio::sync::RwLock;

use beagle_core::BeagleContext;
use beagle_llm::RequestMeta;

#[cfg(feature = "personality")]
use beagle_personality::{ConversationContext, PersonalityConfig, PersonalitySystem};

use crate::agents::{AgentCapability, AgentMesh, AgentMeshConfig, AgentTeam};
use crate::brain::{AwarenessLevel, BrainConnector, BrainConnectorConfig, ConsciousnessState};
use crate::config::ExocortexConfig;
use crate::context::{
    ContextAdaptations, ContextManager, ContextManagerConfig, SituationalContext,
};
use crate::error::{ExocortexError, ExocortexResult};
use crate::identity::{IdentitySystem, IdentitySystemConfig, PersistenceMode, UserProfile};
use crate::memory::{
    EmotionalValence, EpisodicMemory, MemoryBridge, MemoryBridgeConfig, MemorySource,
};

// ============================================================================
// Exocortex Request/Response
// ============================================================================

/// Input to the exocortex
#[derive(Debug, Clone)]
pub struct ExocortexInput {
    /// The user's query or request
    pub query: String,
    /// Optional explicit intent
    pub intent: Option<String>,
    /// Modality of input
    pub modality: InputModality,
    /// Additional context from the request
    pub context: Option<String>,
    /// Urgency level (0-1)
    pub urgency: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputModality {
    #[default]
    Text,
    Voice,
    Multimodal,
}

/// Output from the exocortex
#[derive(Debug, Clone)]
pub struct ExocortexOutput {
    /// The generated response
    pub response: String,
    /// Confidence in this response
    pub confidence: f32,
    /// Which agents contributed
    pub agents_used: Vec<String>,
    /// Consciousness state during generation
    pub consciousness_state: ConsciousnessState,
    /// Adaptations applied based on context
    pub adaptations_applied: Vec<String>,
    /// Proactive suggestions (if any)
    pub proactive_suggestions: Vec<ProactiveSuggestion>,
    /// Metadata
    pub metadata: OutputMetadata,
}

#[derive(Debug, Clone)]
pub struct OutputMetadata {
    /// Processing time in milliseconds
    pub processing_time_ms: u64,
    /// Memories retrieved
    pub memories_retrieved: usize,
    /// Working memory utilization
    pub working_memory_usage: f32,
}

/// A proactive suggestion from the exocortex
#[derive(Debug, Clone)]
pub struct ProactiveSuggestion {
    /// What the system suggests
    pub suggestion: String,
    /// Why it's suggesting this
    pub reasoning: String,
    /// Relevance score (0-1)
    pub relevance: f32,
    /// Category
    pub category: SuggestionCategory,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SuggestionCategory {
    Task,
    Learning,
    Health,
    Reminder,
    Connection, // Related to past conversations
}

// ============================================================================
// Personal Exocortex
// ============================================================================

/// The main Personal Exocortex orchestrator
pub struct PersonalExocortex {
    config: ExocortexConfig,

    /// BeagleContext for LLM routing and other services
    beagle_ctx: Option<Arc<BeagleContext>>,

    /// Identity system - who the user is
    identity: Arc<RwLock<IdentitySystem>>,

    /// Brain connector - consciousness and attention
    brain: Arc<RwLock<BrainConnector>>,

    /// Memory bridge - episodic, semantic, working memory
    memory: Arc<RwLock<MemoryBridge>>,

    /// Context manager - situational awareness
    context: Arc<RwLock<ContextManager>>,

    /// Agent mesh - specialized capabilities
    agents: Arc<RwLock<AgentMesh>>,

    /// Personality system - adaptive response personality
    #[cfg(feature = "personality")]
    personality: Option<Arc<RwLock<PersonalitySystem>>>,

    /// Session start time
    session_start: chrono::DateTime<chrono::Utc>,

    /// Interaction count this session
    interaction_count: Arc<RwLock<u64>>,
}

impl PersonalExocortex {
    /// Create a new Personal Exocortex with configuration
    pub async fn new(config: ExocortexConfig) -> ExocortexResult<Self> {
        Self::new_internal(config, None).await
    }

    /// Create a new Personal Exocortex with BeagleContext for LLM routing
    pub async fn with_context(
        config: ExocortexConfig,
        beagle_ctx: Arc<BeagleContext>,
    ) -> ExocortexResult<Self> {
        Self::new_internal(config, Some(beagle_ctx)).await
    }

    /// Internal constructor
    async fn new_internal(
        config: ExocortexConfig,
        beagle_ctx: Option<Arc<BeagleContext>>,
    ) -> ExocortexResult<Self> {
        // Initialize all subsystems using nested config
        let identity = IdentitySystem::new(IdentitySystemConfig {
            persistence_mode: PersistenceMode::Memory,
            track_expertise: config.identity.track_expertise,
            track_preferences: config.identity.learn_preferences,
            session_history_limit: config.identity.max_session_history,
        });

        let brain = BrainConnector::new(BrainConnectorConfig {
            enable_iit: config.brain.enable_iit,
            enable_gwt: config.brain.enable_gwt,
            enable_metacognition: config.brain.calibrate_confidence,
            phi_threshold: config.brain.phi_threshold as f32,
            attention_capacity: config.brain.max_attention_span,
        });

        let memory = MemoryBridge::new(MemoryBridgeConfig {
            emotional_encoding: config.memory.enable_episodic,
            consciousness_tagging: config.memory.tag_consciousness,
            consolidation_threshold: config.memory.similarity_threshold,
            working_memory_capacity: 7, // Miller's law
            default_decay_rate: 0.01,
        });

        let context = ContextManager::new(ContextManagerConfig {
            enable_world_model: config.context.enable_worldmodel,
            enable_physio_tracking: config.features.enable_observer,
            enable_environment_sensing: config.context.adapt_to_situation,
            adaptation_sensitivity: 0.5,
        });

        let agents = AgentMesh::new(AgentMeshConfig {
            enable_proactive: config.agents.enable_proactive,
            enable_specialization_learning: config.agents.enable_specialization,
            max_team_size: config.agents.max_concurrent,
            collaboration_threshold: 0.6,
        });

        // Initialize personality system if enabled
        #[cfg(feature = "personality")]
        let personality = if config.features.enable_personality {
            match PersonalitySystem::new(PersonalityConfig::default()).await {
                Ok(ps) => {
                    tracing::info!("Personality system initialized");
                    Some(Arc::new(RwLock::new(ps)))
                }
                Err(e) => {
                    tracing::warn!("Failed to initialize personality system: {}", e);
                    None
                }
            }
        } else {
            None
        };

        Ok(Self {
            config,
            beagle_ctx,
            identity: Arc::new(RwLock::new(identity)),
            brain: Arc::new(RwLock::new(brain)),
            memory: Arc::new(RwLock::new(memory)),
            context: Arc::new(RwLock::new(context)),
            agents: Arc::new(RwLock::new(agents)),
            #[cfg(feature = "personality")]
            personality,
            session_start: chrono::Utc::now(),
            interaction_count: Arc::new(RwLock::new(0)),
        })
    }

    /// Load user profile (returns existing or creates new)
    pub async fn load_user(&self, user_id: &str) -> ExocortexResult<UserProfile> {
        self.identity.write().await.load_or_create(user_id).await
    }

    /// Process an input through the exocortex
    pub async fn process(&self, input: ExocortexInput) -> ExocortexResult<ExocortexOutput> {
        let start = std::time::Instant::now();

        // 1. Update interaction count
        {
            let mut count = self.interaction_count.write().await;
            *count += 1;
        }

        // 2. Update consciousness state based on input urgency
        let awareness = if input.urgency > 0.8 {
            AwarenessLevel::Focused
        } else if input.urgency > 0.5 {
            AwarenessLevel::Normal
        } else {
            AwarenessLevel::Automatic
        };

        self.brain.write().await.set_awareness_level(awareness);

        // 3. Get current consciousness state
        let consciousness_state = self.brain.read().await.get_state();

        // 4. Load relevant memories into working memory
        let relevant_episodes = self
            .memory
            .read()
            .await
            .retrieve_episodes(&input.query, 5)
            .await;

        for episode in &relevant_episodes {
            self.memory
                .write()
                .await
                .load_to_working_memory(
                    episode.id.clone(),
                    episode.content.clone(),
                    MemorySource::Episodic,
                )
                .await;
        }

        // 5. Get context adaptations
        let context = self.context.read().await.get_context().await;
        let adaptations = self.context.read().await.get_adaptations(&context);

        // 6. Select appropriate agents
        let capabilities = self.infer_capabilities(&input);
        let team = self.agents.read().await.select_team(&capabilities, 0.6);

        // 7. Get user profile for personalization
        let profile = self.identity.read().await.get_current_profile();

        // 8. Generate response (placeholder - would connect to actual LLM pipeline)
        let response = self
            .generate_response(
                &input,
                &relevant_episodes,
                &context,
                &adaptations,
                &team,
                profile.as_ref(),
            )
            .await?;

        // 9. Encode this interaction as episodic memory
        self.memory
            .write()
            .await
            .encode_episode(
                format!("Q: {} -> A: {}", input.query, response),
                consciousness_state.attention_spotlight.clone(),
            )
            .await?;

        // 10. Get proactive suggestions
        let proactive_suggestions = if self.config.features.enable_proactive {
            self.generate_proactive_suggestions(&input, &relevant_episodes)
                .await
        } else {
            Vec::new()
        };

        // 11. Collect adaptation names
        let adaptations_applied: Vec<String> =
            adaptations.iter().map(|a| a.description.clone()).collect();

        // 12. Build output
        let processing_time_ms = start.elapsed().as_millis() as u64;
        let memory_stats = self.memory.read().await.stats().await;

        Ok(ExocortexOutput {
            response,
            confidence: consciousness_state.metacognitive_confidence,
            agents_used: team.members.iter().map(|m| m.name.clone()).collect(),
            consciousness_state,
            adaptations_applied,
            proactive_suggestions,
            metadata: OutputMetadata {
                processing_time_ms,
                memories_retrieved: relevant_episodes.len(),
                working_memory_usage: memory_stats.working_memory_count as f32
                    / memory_stats.working_memory_capacity as f32,
            },
        })
    }

    /// Infer required capabilities from input
    fn infer_capabilities(&self, input: &ExocortexInput) -> Vec<AgentCapability> {
        let query_lower = input.query.to_lowercase();
        let mut capabilities = Vec::new();

        // Simple keyword-based inference (would use NLU in production)
        if query_lower.contains("research")
            || query_lower.contains("paper")
            || query_lower.contains("study")
        {
            capabilities.push(AgentCapability::Research);
        }
        if query_lower.contains("write")
            || query_lower.contains("draft")
            || query_lower.contains("compose")
        {
            capabilities.push(AgentCapability::Writing);
        }
        if query_lower.contains("code")
            || query_lower.contains("program")
            || query_lower.contains("implement")
        {
            capabilities.push(AgentCapability::Coding);
        }
        if query_lower.contains("analyze")
            || query_lower.contains("compare")
            || query_lower.contains("evaluate")
        {
            capabilities.push(AgentCapability::Analysis);
        }
        if query_lower.contains("math")
            || query_lower.contains("calculate")
            || query_lower.contains("equation")
        {
            capabilities.push(AgentCapability::Mathematics);
        }
        if query_lower.contains("creative")
            || query_lower.contains("imagine")
            || query_lower.contains("story")
        {
            capabilities.push(AgentCapability::Creative);
        }
        if query_lower.contains("plan")
            || query_lower.contains("strategy")
            || query_lower.contains("organize")
        {
            capabilities.push(AgentCapability::Strategy);
        }

        // Default to general if nothing specific detected
        if capabilities.is_empty() {
            capabilities.push(AgentCapability::Analysis);
        }

        capabilities
    }

    /// Generate response using BeagleContext router for LLM calls
    async fn generate_response(
        &self,
        input: &ExocortexInput,
        memories: &[EpisodicMemory],
        context: &SituationalContext,
        adaptations: &[ContextAdaptations],
        team: &AgentTeam,
        profile: Option<&UserProfile>,
    ) -> ExocortexResult<String> {
        // Build context from memories
        let memory_context = if memories.is_empty() {
            String::new()
        } else {
            let memory_snippets: Vec<String> = memories
                .iter()
                .take(5)
                .map(|m| format!("- {}", m.content.chars().take(200).collect::<String>()))
                .collect();
            format!(
                "\n=== Relevant Past Context ===\n{}\n",
                memory_snippets.join("\n")
            )
        };

        // Build adaptation instructions
        let adaptation_instructions = if adaptations.is_empty() {
            String::new()
        } else {
            let instructions: Vec<String> = adaptations
                .iter()
                .map(|a| format!("- {}", a.description))
                .collect();
            format!(
                "\n=== Context Adaptations ===\n{}\n",
                instructions.join("\n")
            )
        };

        // Build personalization context
        let personalization = profile
            .map(|p| {
                let expertise_str = p
                    .expertise_levels
                    .iter()
                    .map(|(k, v)| format!("{}: {:.1}", k, v.level))
                    .collect::<Vec<_>>()
                    .join(", ");
                format!(
                    "\n=== User Profile ===\nUser: {}\nExpertise: {}\n",
                    p.display_name.as_deref().unwrap_or(&p.user_id),
                    if expertise_str.is_empty() {
                        "general".to_string()
                    } else {
                        expertise_str
                    }
                )
            })
            .unwrap_or_default();

        // Build team context
        let team_context = if team.members.is_empty() {
            String::new()
        } else {
            let agents: Vec<String> = team.members.iter().map(|m| m.name.clone()).collect();
            format!("\n=== Active Agents ===\n{}\n", agents.join(", "))
        };

        // Build situational context
        let situation_context = if let Some(ref physio) = context.physio_state {
            format!(
                "\n=== Situational Context ===\nHRV State: {:?}, Stress: {:.2}, Energy: {:.2}, Focus: {:.2}\nTime: {:?}\n",
                physio.hrv_state, physio.stress_level, physio.energy_level, physio.focus_level,
                context.environment.time_of_day
            )
        } else {
            format!(
                "\n=== Situational Context ===\nTime: {:?}\n",
                context.environment.time_of_day
            )
        };

        // Build the full prompt
        let prompt = format!(
            "You are the BEAGLE Personal Exocortex, a unified cognitive assistant.\n\
            {memory_context}\
            {personalization}\
            {adaptation_instructions}\
            {team_context}\
            {situation_context}\n\
            User Query: {}\n\n\
            Provide a helpful, personalized response that takes into account the user's \
            context, expertise level, and current cognitive state.",
            input.query
        );

        // Apply personality adaptation if available
        #[cfg(feature = "personality")]
        let prompt = if let Some(ref personality) = self.personality {
            // Build conversation context for personality system
            let conv_context = ConversationContext {
                user_id: profile.map(|p| p.user_id.clone()),
                session_id: uuid::Uuid::new_v4().to_string(),
                role: Some("cognitive_assistant".to_string()),
                preferred_tone: if let Some(ref physio) = context.physio_state {
                    match physio.hrv_state {
                        crate::context::HrvState::Stressed | crate::context::HrvState::Fatigued => {
                            Some("calm".to_string())
                        }
                        crate::context::HrvState::Flow => Some("engaging".to_string()),
                        _ => Some("balanced".to_string()),
                    }
                } else {
                    Some("balanced".to_string())
                },
                cultural_context: None,
                feedback: None,
                history_length: memories.len(),
                metadata: std::collections::HashMap::new(),
            };

            // Get personality-adapted system prompt
            match personality
                .read()
                .await
                .get_system_prompt(&conv_context)
                .await
            {
                Ok(personality_prompt) => {
                    format!(
                        "{}\n\n{}\n\nUser Query: {}\n\n\
                        Provide a helpful, personalized response that takes into account the user's \
                        context, expertise level, and current cognitive state.",
                        personality_prompt, prompt, input.query
                    )
                }
                Err(e) => {
                    tracing::warn!("Failed to get personality prompt: {}", e);
                    prompt
                }
            }
        } else {
            prompt
        };

        // If we have a BeagleContext, use the router for LLM calls
        if let Some(ref ctx) = self.beagle_ctx {
            // Determine request metadata based on capabilities and urgency
            let requires_high_quality = input.urgency > 0.7
                || team
                    .members
                    .iter()
                    .any(|m| m.capability == AgentCapability::Research);
            let requires_phd = team
                .members
                .iter()
                .any(|m| m.capability == AgentCapability::Mathematics);

            let meta = RequestMeta {
                offline_required: false,
                requires_math: requires_phd,
                requires_vision: input.modality == InputModality::Multimodal,
                approximate_tokens: prompt.len() / 4,
                requires_high_quality,
                high_bias_risk: false,
                requires_phd_level_reasoning: requires_phd,
                critical_section: input.urgency > 0.9,
            };

            // Get current stats for routing
            let run_id = uuid::Uuid::new_v4().to_string();
            let stats = ctx.llm_stats.get_or_create(&run_id);

            // Route to appropriate LLM
            let (client, _tier) = ctx.router.choose_with_limits(&meta, &stats);

            // Make the LLM call
            match client.complete(&prompt).await {
                Ok(output) => {
                    tracing::info!(
                        tokens_in = output.tokens_in_est,
                        tokens_out = output.tokens_out_est,
                        "Exocortex LLM response generated"
                    );
                    Ok(output.text)
                }
                Err(e) => {
                    tracing::warn!(error = %e, "Exocortex LLM call failed, using fallback");
                    // Fallback to a basic response
                    Ok(format!(
                        "I understand your question: \"{}\". However, I'm currently \
                        experiencing connectivity issues. Please try again shortly.",
                        input.query
                    ))
                }
            }
        } else {
            // No BeagleContext - return structured placeholder
            Ok(format!(
                "[Exocortex - No LLM Context]\n\
                Query: {}\n\
                Memory context: {} items\n\
                Adaptations: {} applied\n\
                Team: {} agents\n\n\
                Configure BeagleContext with PersonalExocortex::with_context() for LLM responses.",
                input.query,
                memories.len(),
                adaptations.len(),
                team.members.len()
            ))
        }
    }

    /// Generate proactive suggestions based on context
    async fn generate_proactive_suggestions(
        &self,
        input: &ExocortexInput,
        memories: &[EpisodicMemory],
    ) -> Vec<ProactiveSuggestion> {
        let mut suggestions = Vec::new();

        // Check for related past work
        if !memories.is_empty() {
            let oldest = memories.iter().min_by_key(|m| m.timestamp).unwrap();

            let days_ago = (chrono::Utc::now() - oldest.timestamp).num_days();
            if days_ago > 7 {
                suggestions.push(ProactiveSuggestion {
                    suggestion: format!(
                        "You worked on something similar {} days ago. Would you like to review that context?",
                        days_ago
                    ),
                    reasoning: "Found related episodic memory from past session".to_string(),
                    relevance: 0.7,
                    category: SuggestionCategory::Connection,
                });
            }
        }

        // Check agents for proactive suggestions
        let agent_suggestions = self.agents.read().await.get_proactive_suggestions(input);
        for (suggestion, relevance) in agent_suggestions {
            suggestions.push(ProactiveSuggestion {
                suggestion,
                reasoning: "Agent specialization insight".to_string(),
                relevance,
                category: SuggestionCategory::Task,
            });
        }

        suggestions
    }

    /// Trigger memory consolidation (call during idle periods)
    pub async fn consolidate_memories(&self) {
        self.memory.write().await.consolidate().await;
    }

    /// Update physiological context (e.g., from HRV data)
    pub async fn update_physio_context(
        &self,
        stress_level: f32,
        energy_level: f32,
        focus_level: f32,
    ) {
        self.context
            .write()
            .await
            .update_physio(stress_level, energy_level, focus_level);

        // Also update emotional state in memory system
        let emotion = EmotionalValence {
            valence: if stress_level > 0.7 { -0.3 } else { 0.2 },
            arousal: stress_level,
            dominance: energy_level,
        };
        self.memory.write().await.set_emotional_state(emotion).await;
    }

    /// Record expertise gain
    pub async fn record_expertise(&self, domain: &str, delta: f32) {
        self.identity
            .write()
            .await
            .record_expertise(domain, delta)
            .await;
    }

    /// Get personality insights (if personality system is enabled)
    #[cfg(feature = "personality")]
    pub async fn get_personality_insights(
        &self,
    ) -> Option<beagle_personality::PersonalityInsights> {
        if let Some(ref personality) = self.personality {
            match personality.read().await.get_insights().await {
                Ok(insights) => Some(insights),
                Err(e) => {
                    tracing::warn!("Failed to get personality insights: {}", e);
                    None
                }
            }
        } else {
            None
        }
    }

    /// Update personality based on emotional context
    #[cfg(feature = "personality")]
    pub async fn update_personality_emotional_state(
        &self,
        emotional: beagle_personality::EmotionalState,
    ) {
        if let Some(ref personality) = self.personality {
            if let Err(e) = personality
                .write()
                .await
                .set_emotional_state(emotional)
                .await
            {
                tracing::warn!("Failed to update personality emotional state: {}", e);
            }
        }
    }

    /// Update context from Observer's UserContext (integrates HRV, environment, space weather)
    #[cfg(feature = "observer")]
    pub async fn update_from_observer(&self, user_ctx: &beagle_observer::UserContext) {
        // Update context manager with full user context
        self.context
            .write()
            .await
            .update_from_observer_user_context(user_ctx)
            .await;

        // Also update memory bridge's emotional state based on HRV
        let stress: f32 = user_ctx.physio.stress_index.unwrap_or(0.3) as f32;
        let valence: f32 = if stress > 0.6 { -0.3 } else { 0.2 };
        let arousal: f32 = stress;

        let emotion = crate::memory::EmotionalValence {
            valence,
            arousal,
            dominance: 1.0_f32 - stress,
        };
        self.memory.write().await.set_emotional_state(emotion).await;

        tracing::debug!(
            hrv_level = ?user_ctx.physio.hrv_level,
            stress_index = ?user_ctx.physio.stress_index,
            "Exocortex updated from Observer context"
        );
    }

    /// Get current HRV state from context
    pub async fn get_hrv_state(&self) -> crate::context::HrvState {
        self.context.read().await.get_hrv_state().await
    }

    /// Check if user is currently in high-stress state
    pub async fn is_user_stressed(&self) -> bool {
        self.context.read().await.is_high_stress().await
    }

    /// Get session statistics
    pub async fn session_stats(&self) -> SessionStats {
        let interaction_count = *self.interaction_count.read().await;
        let memory_stats = self.memory.read().await.stats().await;
        let consciousness = self.brain.read().await.get_state();
        let session_duration = chrono::Utc::now() - self.session_start;

        SessionStats {
            session_duration_secs: session_duration.num_seconds() as u64,
            interaction_count,
            episodic_memories: memory_stats.episodic_count,
            semantic_memories: memory_stats.semantic_count,
            working_memory_usage: memory_stats.working_memory_count as f32
                / memory_stats.working_memory_capacity as f32,
            current_phi: consciousness.phi,
            current_awareness: consciousness.awareness_level,
        }
    }
}

/// Session statistics
#[derive(Debug, Clone)]
pub struct SessionStats {
    pub session_duration_secs: u64,
    pub interaction_count: u64,
    pub episodic_memories: usize,
    pub semantic_memories: usize,
    pub working_memory_usage: f32,
    pub current_phi: f32,
    pub current_awareness: AwarenessLevel,
}

// ============================================================================
// Builder Pattern for Flexible Configuration
// ============================================================================

/// Builder for PersonalExocortex
pub struct ExocortexBuilder {
    config: ExocortexConfig,
}

impl ExocortexBuilder {
    pub fn new() -> Self {
        Self {
            config: ExocortexConfig::default(),
        }
    }

    pub fn with_consciousness(mut self, enabled: bool) -> Self {
        self.config.features.enable_consciousness = enabled;
        self.config.brain.enable_iit = enabled;
        self.config.brain.enable_gwt = enabled;
        self
    }

    pub fn with_proactive_suggestions(mut self, enabled: bool) -> Self {
        self.config.features.enable_proactive = enabled;
        self.config.agents.enable_proactive = enabled;
        self
    }

    pub fn with_emotional_memory(mut self, enabled: bool) -> Self {
        self.config.memory.enable_episodic = enabled;
        self
    }

    pub fn with_world_model(mut self, enabled: bool) -> Self {
        self.config.features.enable_worldmodel = enabled;
        self.config.context.enable_worldmodel = enabled;
        self
    }

    pub fn with_physio_tracking(mut self, enabled: bool) -> Self {
        self.config.features.enable_observer = enabled;
        self
    }

    pub fn with_expertise_tracking(mut self, enabled: bool) -> Self {
        self.config.identity.track_expertise = enabled;
        self
    }

    pub fn with_preference_learning(mut self, enabled: bool) -> Self {
        self.config.identity.learn_preferences = enabled;
        self
    }

    pub async fn build(self) -> ExocortexResult<PersonalExocortex> {
        PersonalExocortex::new(self.config).await
    }
}

impl Default for ExocortexBuilder {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_exocortex_creation() {
        let exocortex = ExocortexBuilder::new()
            .with_consciousness(true)
            .with_proactive_suggestions(true)
            .build()
            .await
            .unwrap();

        let stats = exocortex.session_stats().await;
        assert_eq!(stats.interaction_count, 0);
    }

    #[tokio::test]
    async fn test_exocortex_process() {
        let exocortex = ExocortexBuilder::new()
            .with_consciousness(true)
            .build()
            .await
            .unwrap();

        let input = ExocortexInput {
            query: "What is consciousness?".to_string(),
            intent: None,
            modality: InputModality::Text,
            context: None,
            urgency: 0.5,
        };

        let output = exocortex.process(input).await.unwrap();

        assert!(!output.response.is_empty());
        // Processing time may be 0ms if very fast, just check it doesn't panic
        assert!(output.metadata.memories_retrieved == 0); // No prior memories

        let stats = exocortex.session_stats().await;
        assert_eq!(stats.interaction_count, 1);
        assert_eq!(stats.episodic_memories, 1); // Should have encoded the interaction
    }

    #[tokio::test]
    async fn test_capability_inference() {
        let exocortex = ExocortexBuilder::new().build().await.unwrap();

        let input = ExocortexInput {
            query: "Write some code to analyze the research paper".to_string(),
            intent: None,
            modality: InputModality::Text,
            context: None,
            urgency: 0.5,
        };

        let capabilities = exocortex.infer_capabilities(&input);

        assert!(capabilities.contains(&AgentCapability::Writing));
        assert!(capabilities.contains(&AgentCapability::Coding));
        assert!(capabilities.contains(&AgentCapability::Research));
    }
}
