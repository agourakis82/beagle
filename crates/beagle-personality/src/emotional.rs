use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::RwLock;

// ========================= Cognitive Appraisal Theory =========================
// Based on Scherer's Component Process Model (CPM) and Lazarus' appraisal theory
// Emotions emerge from cognitive evaluation of events, not direct stimuli

/// Scherer's Stimulus Evaluation Checks (SECs)
/// The core appraisal dimensions that determine emotional response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppraisalDimensions {
    /// Relevance: Is this event relevant to my goals/needs? [0-1]
    pub relevance: f32,

    /// Implications: Is this event conducive (positive) or obstructive (negative) to my goals? [-1 to 1]
    pub goal_conduciveness: f32,

    /// Coping potential: Can I cope with/control this event? [0-1]
    pub coping_potential: f32,

    /// Norm/self compatibility: Is this event compatible with my values/norms? [-1 to 1]
    pub norm_compatibility: f32,

    /// Novelty: How unexpected/novel is this event? [0-1]
    pub novelty: f32,

    /// Certainty: How certain am I about this appraisal? [0-1]
    pub certainty: f32,

    /// Agency: Who/what caused this event? (self=1, other=0, circumstance=0.5)
    pub agency_self: f32,
    pub agency_other: f32,

    /// Urgency: How immediately must I respond? [0-1]
    pub urgency: f32,

    /// Power: Do I have power over the situation? [0-1]
    pub power: f32,
}

impl Default for AppraisalDimensions {
    fn default() -> Self {
        Self {
            relevance: 0.5,
            goal_conduciveness: 0.0,
            coping_potential: 0.5,
            norm_compatibility: 0.0,
            novelty: 0.0,
            certainty: 0.5,
            agency_self: 0.33,
            agency_other: 0.33,
            urgency: 0.3,
            power: 0.5,
        }
    }
}

/// Appraisal event that triggers emotional response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppraisalEvent {
    /// Event description
    pub description: String,

    /// Appraisal dimensions for this event
    pub appraisals: AppraisalDimensions,

    /// Additional context
    pub context: HashMap<String, String>,

    /// Timestamp
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

/// Cognitive Appraisal Engine
/// Converts appraisals to emotions using Scherer's CPM rules
#[derive(Debug, Clone)]
pub struct CognitiveAppraisalEngine {
    /// Appraisal-to-emotion mapping weights
    emotion_mappings: AppraisalEmotionMappings,

    /// History of appraisals for pattern detection
    appraisal_history: VecDeque<AppraisalEvent>,

    /// Maximum history size
    max_history: usize,
}

/// Weights for mapping appraisals to emotions
/// Based on empirical research in affective science
#[derive(Debug, Clone)]
struct AppraisalEmotionMappings {
    // Each emotion has a characteristic appraisal profile
    // Format: (relevance, conduciveness, coping, norm_compat, novelty, certainty, agency_self, agency_other, urgency, power)
    joy_profile: [f32; 10],
    sadness_profile: [f32; 10],
    anger_profile: [f32; 10],
    fear_profile: [f32; 10],
    disgust_profile: [f32; 10],
    surprise_profile: [f32; 10],
    trust_profile: [f32; 10],
    anticipation_profile: [f32; 10],

    // Secondary emotions (combinations)
    contempt_profile: [f32; 10],
    shame_profile: [f32; 10],
    guilt_profile: [f32; 10],
    pride_profile: [f32; 10],
}

impl Default for AppraisalEmotionMappings {
    fn default() -> Self {
        // Empirically-derived appraisal profiles from Scherer's research
        // Values represent the "ideal" appraisal pattern for each emotion
        Self {
            // Joy: High relevance, goal-conducive, high coping, norm-compatible, low novelty
            joy_profile: [0.9, 0.9, 0.8, 0.7, 0.2, 0.8, 0.3, 0.3, 0.3, 0.7],

            // Sadness: High relevance, goal-obstructive, low coping, low urgency
            sadness_profile: [0.9, -0.8, 0.2, 0.0, 0.3, 0.7, 0.2, 0.3, 0.2, 0.2],

            // Anger: High relevance, goal-obstructive, high coping, norm-incompatible, other-caused
            anger_profile: [0.9, -0.8, 0.8, -0.7, 0.4, 0.7, 0.1, 0.9, 0.8, 0.7],

            // Fear: High relevance, goal-obstructive, low coping, high urgency
            fear_profile: [0.9, -0.7, 0.2, 0.0, 0.6, 0.4, 0.1, 0.5, 0.9, 0.2],

            // Disgust: High relevance, goal-obstructive, norm-incompatible
            disgust_profile: [0.7, -0.6, 0.5, -0.9, 0.4, 0.7, 0.1, 0.3, 0.5, 0.5],

            // Surprise: High novelty, uncertain
            surprise_profile: [0.5, 0.0, 0.5, 0.0, 0.95, 0.2, 0.3, 0.3, 0.5, 0.5],

            // Trust: Goal-conducive, norm-compatible, other-involved
            trust_profile: [0.7, 0.6, 0.6, 0.8, 0.2, 0.7, 0.2, 0.6, 0.3, 0.5],

            // Anticipation: Future-oriented, uncertain but hopeful
            anticipation_profile: [0.8, 0.3, 0.5, 0.3, 0.4, 0.4, 0.4, 0.2, 0.6, 0.5],

            // Contempt: Other-caused norm violation, high power
            contempt_profile: [0.6, -0.3, 0.9, -0.8, 0.2, 0.8, 0.1, 0.8, 0.3, 0.9],

            // Shame: Self-caused norm violation, low power
            shame_profile: [0.8, -0.5, 0.3, -0.8, 0.3, 0.7, 0.9, 0.1, 0.4, 0.2],

            // Guilt: Self-caused harm to other
            guilt_profile: [0.8, -0.6, 0.4, -0.7, 0.2, 0.8, 0.9, 0.1, 0.5, 0.4],

            // Pride: Self-caused positive outcome, norm-compatible
            pride_profile: [0.8, 0.8, 0.8, 0.7, 0.3, 0.8, 0.9, 0.1, 0.2, 0.8],
        }
    }
}

impl CognitiveAppraisalEngine {
    pub fn new() -> Self {
        Self {
            emotion_mappings: AppraisalEmotionMappings::default(),
            appraisal_history: VecDeque::with_capacity(100),
            max_history: 100,
        }
    }

    /// Compute emotions from appraisal dimensions using Scherer's CPM
    pub fn compute_emotions(&mut self, event: &AppraisalEvent) -> EmotionalStimulus {
        let appraisals = &event.appraisals;

        // Convert appraisals to feature vector
        let appraisal_vec = [
            appraisals.relevance,
            appraisals.goal_conduciveness,
            appraisals.coping_potential,
            appraisals.norm_compatibility,
            appraisals.novelty,
            appraisals.certainty,
            appraisals.agency_self,
            appraisals.agency_other,
            appraisals.urgency,
            appraisals.power,
        ];

        // Compute similarity to each emotion profile
        let joy = self.profile_match(&appraisal_vec, &self.emotion_mappings.joy_profile);
        let sadness = self.profile_match(&appraisal_vec, &self.emotion_mappings.sadness_profile);
        let anger = self.profile_match(&appraisal_vec, &self.emotion_mappings.anger_profile);
        let fear = self.profile_match(&appraisal_vec, &self.emotion_mappings.fear_profile);
        let disgust = self.profile_match(&appraisal_vec, &self.emotion_mappings.disgust_profile);
        let surprise = self.profile_match(&appraisal_vec, &self.emotion_mappings.surprise_profile);
        let trust = self.profile_match(&appraisal_vec, &self.emotion_mappings.trust_profile);
        let anticipation =
            self.profile_match(&appraisal_vec, &self.emotion_mappings.anticipation_profile);

        // Scale by relevance (irrelevant events don't cause strong emotions)
        let relevance_scale = appraisals.relevance;

        // Store in history
        self.appraisal_history.push_back(event.clone());
        while self.appraisal_history.len() > self.max_history {
            self.appraisal_history.pop_front();
        }

        EmotionalStimulus {
            trigger: event.description.clone(),
            context: event.context.clone(),
            joy_delta: joy * relevance_scale,
            trust_delta: trust * relevance_scale,
            fear_delta: fear * relevance_scale,
            surprise_delta: surprise * relevance_scale,
            sadness_delta: sadness * relevance_scale,
            disgust_delta: disgust * relevance_scale,
            anger_delta: anger * relevance_scale,
            anticipation_delta: anticipation * relevance_scale,
        }
    }

    /// Compute cosine similarity between appraisal and emotion profile
    fn profile_match(&self, appraisal: &[f32; 10], profile: &[f32; 10]) -> f32 {
        // Weighted cosine similarity
        let mut dot_product = 0.0f32;
        let mut norm_a = 0.0f32;
        let mut norm_b = 0.0f32;

        // Weights for each dimension (some matter more for certain emotions)
        let weights = [1.0, 1.5, 1.0, 1.0, 0.8, 0.6, 0.8, 0.8, 0.7, 0.7];

        for i in 0..10 {
            let a = appraisal[i] * weights[i];
            let b = profile[i] * weights[i];
            dot_product += a * b;
            norm_a += a * a;
            norm_b += b * b;
        }

        let norm_product = (norm_a.sqrt() * norm_b.sqrt()).max(0.0001);
        let similarity = dot_product / norm_product;

        // Transform to [0, 1] range and apply non-linearity
        // Higher threshold for emotion activation (emotions need strong match)
        let activated = ((similarity + 1.0) / 2.0).powf(2.0);

        // Threshold: emotions only activate above certain similarity
        if activated > 0.3 {
            (activated - 0.3) / 0.7
        } else {
            0.0
        }
    }

    /// Detect emotional patterns over time (e.g., chronic stress, mood disorders)
    pub fn detect_patterns(&self) -> EmotionalPatterns {
        if self.appraisal_history.is_empty() {
            return EmotionalPatterns::default();
        }

        let n = self.appraisal_history.len() as f32;

        // Compute averages
        let mut avg_relevance = 0.0f32;
        let mut avg_conduciveness = 0.0f32;
        let mut avg_coping = 0.0f32;
        let mut negative_count = 0;
        let mut low_coping_count = 0;

        for event in &self.appraisal_history {
            avg_relevance += event.appraisals.relevance;
            avg_conduciveness += event.appraisals.goal_conduciveness;
            avg_coping += event.appraisals.coping_potential;

            if event.appraisals.goal_conduciveness < -0.3 {
                negative_count += 1;
            }
            if event.appraisals.coping_potential < 0.3 {
                low_coping_count += 1;
            }
        }

        avg_relevance /= n;
        avg_conduciveness /= n;
        avg_coping /= n;

        // Detect patterns
        let chronic_stress =
            (negative_count as f32 / n) > 0.6 && (low_coping_count as f32 / n) > 0.5;
        let learned_helplessness = avg_coping < 0.3 && avg_conduciveness < -0.2;
        let generally_positive = avg_conduciveness > 0.3 && avg_coping > 0.5;

        EmotionalPatterns {
            chronic_stress,
            learned_helplessness,
            generally_positive,
            average_relevance: avg_relevance,
            average_conduciveness: avg_conduciveness,
            average_coping: avg_coping,
        }
    }
}

/// Detected emotional patterns over time
#[derive(Debug, Clone, Default)]
pub struct EmotionalPatterns {
    pub chronic_stress: bool,
    pub learned_helplessness: bool,
    pub generally_positive: bool,
    pub average_relevance: f32,
    pub average_conduciveness: f32,
    pub average_coping: f32,
}

/// Emotional state management with cognitive appraisal support
#[derive(Debug, Clone)]
pub struct EmotionalState {
    current: Arc<RwLock<EmotionVector>>,
    history: Arc<RwLock<VecDeque<EmotionalSnapshot>>>,
    dynamics: Arc<EmotionalDynamics>,
    config: EmotionalConfig,
    /// Cognitive appraisal engine for SOTA emotion generation
    appraisal_engine: Arc<RwLock<CognitiveAppraisalEngine>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmotionVector {
    // Primary emotions (Plutchik's wheel)
    pub joy: f32,
    pub trust: f32,
    pub fear: f32,
    pub surprise: f32,
    pub sadness: f32,
    pub disgust: f32,
    pub anger: f32,
    pub anticipation: f32,

    // Meta-emotions
    pub arousal: f32,   // Low to high activation
    pub valence: f32,   // Negative to positive
    pub dominance: f32, // Submissive to dominant
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmotionalSnapshot {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub state: EmotionVector,
    pub trigger: String,
    pub context: HashMap<String, String>,
}

#[derive(Debug, Clone)]
pub struct EmotionalDynamics {
    decay_rates: HashMap<String, f32>,
    amplification_factors: HashMap<String, f32>,
    interaction_matrix: HashMap<(String, String), f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmotionalConfig {
    pub baseline_mood: EmotionVector,
    pub volatility: f32,           // How quickly emotions change
    pub resilience: f32,           // How quickly return to baseline
    pub empathy_level: f32,        // Sensitivity to others' emotions
    pub expression_threshold: f32, // Minimum emotion level to express
}

impl Default for EmotionVector {
    fn default() -> Self {
        Self {
            joy: 0.5,
            trust: 0.5,
            fear: 0.0,
            surprise: 0.0,
            sadness: 0.0,
            disgust: 0.0,
            anger: 0.0,
            anticipation: 0.3,
            arousal: 0.5,
            valence: 0.5,
            dominance: 0.5,
        }
    }
}

impl Default for EmotionalConfig {
    fn default() -> Self {
        Self {
            baseline_mood: EmotionVector::default(),
            volatility: 0.5,
            resilience: 0.7,
            empathy_level: 0.6,
            expression_threshold: 0.3,
        }
    }
}

impl EmotionalState {
    pub fn new(config: EmotionalConfig) -> Self {
        let dynamics = Arc::new(EmotionalDynamics {
            decay_rates: HashMap::from([
                ("joy".to_string(), 0.1),
                ("anger".to_string(), 0.15),
                ("fear".to_string(), 0.2),
                ("sadness".to_string(), 0.05),
                ("surprise".to_string(), 0.3),
                ("disgust".to_string(), 0.1),
                ("trust".to_string(), 0.02),
                ("anticipation".to_string(), 0.1),
            ]),
            amplification_factors: HashMap::from([
                ("joy".to_string(), 1.2),
                ("anger".to_string(), 1.3),
                ("fear".to_string(), 1.5),
                ("sadness".to_string(), 0.9),
            ]),
            interaction_matrix: HashMap::from([
                (("joy".to_string(), "sadness".to_string()), -0.8),
                (("anger".to_string(), "fear".to_string()), 0.3),
                (("trust".to_string(), "disgust".to_string()), -0.6),
                (("surprise".to_string(), "anticipation".to_string()), -0.4),
            ]),
        });

        Self {
            current: Arc::new(RwLock::new(config.baseline_mood.clone())),
            history: Arc::new(RwLock::new(VecDeque::new())),
            dynamics,
            config,
            appraisal_engine: Arc::new(RwLock::new(CognitiveAppraisalEngine::new())),
        }
    }

    /// Update emotional state using cognitive appraisal (SOTA approach)
    /// This is the preferred method - emotions emerge from appraisals, not direct stimuli
    pub async fn update_from_appraisal(
        &self,
        event: AppraisalEvent,
    ) -> Result<EmotionVector, Box<dyn std::error::Error + Send + Sync>> {
        // Use cognitive appraisal engine to compute emotions from event appraisals
        let stimulus = {
            let mut engine = self.appraisal_engine.write().await;
            engine.compute_emotions(&event)
        };

        // Apply the computed stimulus using the standard update mechanism
        self.update(stimulus).await
    }

    /// Get detected emotional patterns (chronic stress, learned helplessness, etc.)
    pub async fn get_emotional_patterns(&self) -> EmotionalPatterns {
        let engine = self.appraisal_engine.read().await;
        engine.detect_patterns()
    }

    /// Convenience method to create an appraisal event from natural descriptions
    pub fn create_appraisal_event(
        description: &str,
        relevance: f32,
        goal_conduciveness: f32,
        coping_potential: f32,
        novelty: f32,
    ) -> AppraisalEvent {
        AppraisalEvent {
            description: description.to_string(),
            appraisals: AppraisalDimensions {
                relevance,
                goal_conduciveness,
                coping_potential,
                novelty,
                ..Default::default()
            },
            context: HashMap::new(),
            timestamp: chrono::Utc::now(),
        }
    }

    pub async fn update(
        &self,
        stimulus: EmotionalStimulus,
    ) -> Result<EmotionVector, Box<dyn std::error::Error + Send + Sync>> {
        let mut current = self.current.write().await;

        // Apply stimulus with volatility factor
        current.joy += stimulus.joy_delta * self.config.volatility;
        current.trust += stimulus.trust_delta * self.config.volatility;
        current.fear += stimulus.fear_delta * self.config.volatility;
        current.surprise += stimulus.surprise_delta * self.config.volatility;
        current.sadness += stimulus.sadness_delta * self.config.volatility;
        current.disgust += stimulus.disgust_delta * self.config.volatility;
        current.anger += stimulus.anger_delta * self.config.volatility;
        current.anticipation += stimulus.anticipation_delta * self.config.volatility;

        // Apply emotion interactions
        self.apply_interactions(&mut current).await;

        // Update meta-emotions
        self.update_meta_emotions(&mut current);

        // Clamp all values to [0, 1]
        self.normalize_emotions(&mut current);

        // Record snapshot
        let snapshot = EmotionalSnapshot {
            timestamp: chrono::Utc::now(),
            state: current.clone(),
            trigger: stimulus.trigger,
            context: stimulus.context,
        };

        let mut history = self.history.write().await;
        history.push_back(snapshot);

        // Limit history size
        while history.len() > 1000 {
            history.pop_front();
        }

        Ok(current.clone())
    }

    async fn apply_interactions(&self, emotions: &mut EmotionVector) {
        // Apply emotion interaction effects
        let interactions = &self.dynamics.interaction_matrix;

        // Calculate interaction effects
        let mut deltas = HashMap::new();

        for ((emotion1, emotion2), factor) in interactions.iter() {
            let value1 = self.get_emotion_value(emotions, emotion1);
            let value2 = self.get_emotion_value(emotions, emotion2);

            let delta1 = value2 * factor * 0.1;
            let delta2 = value1 * factor * 0.1;

            deltas.insert(emotion1.clone(), delta1);
            deltas.insert(emotion2.clone(), delta2);
        }

        // Apply deltas
        for (emotion, delta) in deltas {
            self.apply_emotion_delta(emotions, &emotion, delta);
        }
    }

    fn get_emotion_value(&self, emotions: &EmotionVector, name: &str) -> f32 {
        match name {
            "joy" => emotions.joy,
            "trust" => emotions.trust,
            "fear" => emotions.fear,
            "surprise" => emotions.surprise,
            "sadness" => emotions.sadness,
            "disgust" => emotions.disgust,
            "anger" => emotions.anger,
            "anticipation" => emotions.anticipation,
            _ => 0.0,
        }
    }

    fn apply_emotion_delta(&self, emotions: &mut EmotionVector, name: &str, delta: f32) {
        match name {
            "joy" => emotions.joy += delta,
            "trust" => emotions.trust += delta,
            "fear" => emotions.fear += delta,
            "surprise" => emotions.surprise += delta,
            "sadness" => emotions.sadness += delta,
            "disgust" => emotions.disgust += delta,
            "anger" => emotions.anger += delta,
            "anticipation" => emotions.anticipation += delta,
            _ => {}
        }
    }

    fn update_meta_emotions(&self, emotions: &mut EmotionVector) {
        // Calculate arousal (activation level)
        emotions.arousal =
            (emotions.anger + emotions.fear + emotions.surprise + emotions.anticipation) / 4.0
                + (emotions.joy * 0.5);

        // Calculate valence (pleasantness)
        emotions.valence = (emotions.joy + emotions.trust + emotions.anticipation * 0.5) / 2.5
            - (emotions.sadness + emotions.fear + emotions.disgust + emotions.anger) / 4.0
            + 0.5;

        // Calculate dominance (control)
        emotions.dominance = (emotions.anger * 0.7 + emotions.disgust * 0.5 + emotions.trust) / 2.2
            - (emotions.fear + emotions.sadness * 0.5) / 1.5
            + 0.5;
    }

    fn normalize_emotions(&self, emotions: &mut EmotionVector) {
        emotions.joy = emotions.joy.clamp(0.0, 1.0);
        emotions.trust = emotions.trust.clamp(0.0, 1.0);
        emotions.fear = emotions.fear.clamp(0.0, 1.0);
        emotions.surprise = emotions.surprise.clamp(0.0, 1.0);
        emotions.sadness = emotions.sadness.clamp(0.0, 1.0);
        emotions.disgust = emotions.disgust.clamp(0.0, 1.0);
        emotions.anger = emotions.anger.clamp(0.0, 1.0);
        emotions.anticipation = emotions.anticipation.clamp(0.0, 1.0);
        emotions.arousal = emotions.arousal.clamp(0.0, 1.0);
        emotions.valence = emotions.valence.clamp(0.0, 1.0);
        emotions.dominance = emotions.dominance.clamp(0.0, 1.0);
    }

    pub async fn decay(&self) -> Result<EmotionVector, Box<dyn std::error::Error + Send + Sync>> {
        let mut current = self.current.write().await;
        let baseline = &self.config.baseline_mood;
        let resilience = self.config.resilience;

        // Decay towards baseline
        current.joy += (baseline.joy - current.joy) * resilience * 0.01;
        current.trust += (baseline.trust - current.trust) * resilience * 0.005;
        current.fear += (baseline.fear - current.fear) * resilience * 0.02;
        current.surprise += (baseline.surprise - current.surprise) * resilience * 0.03;
        current.sadness += (baseline.sadness - current.sadness) * resilience * 0.01;
        current.disgust += (baseline.disgust - current.disgust) * resilience * 0.015;
        current.anger += (baseline.anger - current.anger) * resilience * 0.02;
        current.anticipation += (baseline.anticipation - current.anticipation) * resilience * 0.01;

        self.update_meta_emotions(&mut current);
        self.normalize_emotions(&mut current);

        Ok(current.clone())
    }

    pub async fn get_current(&self) -> EmotionVector {
        self.current.read().await.clone()
    }

    pub async fn get_dominant_emotion(&self) -> String {
        let current = self.current.read().await;

        let mut max_emotion = "neutral";
        let mut max_value = 0.0;

        let emotions = [
            ("joy", current.joy),
            ("trust", current.trust),
            ("fear", current.fear),
            ("surprise", current.surprise),
            ("sadness", current.sadness),
            ("disgust", current.disgust),
            ("anger", current.anger),
            ("anticipation", current.anticipation),
        ];

        for (name, value) in emotions {
            if value > max_value && value > self.config.expression_threshold {
                max_emotion = name;
                max_value = value;
            }
        }

        max_emotion.to_string()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmotionalStimulus {
    pub trigger: String,
    pub context: HashMap<String, String>,
    pub joy_delta: f32,
    pub trust_delta: f32,
    pub fear_delta: f32,
    pub surprise_delta: f32,
    pub sadness_delta: f32,
    pub disgust_delta: f32,
    pub anger_delta: f32,
    pub anticipation_delta: f32,
}
