//! Identity System - Persistent user profile and preferences
//!
//! Manages the user's cognitive identity across sessions:
//! - Expertise levels per domain
//! - Communication preferences
//! - Long-term goals
//! - Interaction history
//! - Voice/style preservation

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::error::{ExocortexError, ExocortexResult};

// ============================================================================
// Persistence Mode
// ============================================================================

/// How to persist user profiles
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PersistenceMode {
    /// In-memory only (lost on restart)
    Memory,
    /// File-based persistence
    File,
    /// PostgreSQL database
    Postgres,
}

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for the identity system
#[derive(Debug, Clone)]
pub struct IdentitySystemConfig {
    /// How to persist profiles
    pub persistence_mode: PersistenceMode,
    /// Track expertise levels
    pub track_expertise: bool,
    /// Track preferences
    pub track_preferences: bool,
    /// Maximum session history to retain
    pub session_history_limit: usize,
}

impl Default for IdentitySystemConfig {
    fn default() -> Self {
        Self {
            persistence_mode: PersistenceMode::Memory,
            track_expertise: true,
            track_preferences: true,
            session_history_limit: 100,
        }
    }
}

// ============================================================================
// User Profile
// ============================================================================

/// User's persistent cognitive profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserProfile {
    /// Unique user identifier
    pub user_id: String,

    /// Optional display name
    pub display_name: Option<String>,

    /// Expertise levels per domain (0.0 - 1.0)
    pub expertise_levels: HashMap<String, ExpertiseLevel>,

    /// Communication preferences
    pub preferences: UserPreferences,

    /// Session history summaries
    pub session_history: Vec<SessionSummary>,

    /// Profile creation time
    pub created_at: DateTime<Utc>,

    /// Last active time
    pub last_active: DateTime<Utc>,
}

impl UserProfile {
    /// Create a new user profile
    pub fn new(user_id: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            user_id: user_id.into(),
            display_name: None,
            expertise_levels: HashMap::new(),
            preferences: UserPreferences::default(),
            session_history: Vec::new(),
            created_at: now,
            last_active: now,
        }
    }

    /// Get expertise level for a domain (returns 0.3 if unknown)
    pub fn expertise_for(&self, domain: &str) -> f32 {
        self.expertise_levels
            .get(domain)
            .map(|e| e.level)
            .unwrap_or(0.3)
    }

    /// Update expertise based on interaction
    pub fn update_expertise(&mut self, domain: &str, demonstrated_level: f32) {
        let entry = self.expertise_levels
            .entry(domain.to_string())
            .or_insert_with(|| ExpertiseLevel::new(0.3));

        // Exponential moving average
        entry.level = 0.9 * entry.level + 0.1 * demonstrated_level;
        entry.interactions += 1;
        entry.last_updated = Utc::now();
    }
}

/// Expertise level for a specific domain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExpertiseLevel {
    /// Current expertise level (0.0 = novice, 1.0 = expert)
    pub level: f32,
    /// Number of interactions in this domain
    pub interactions: u32,
    /// Last update time
    pub last_updated: DateTime<Utc>,
}

impl ExpertiseLevel {
    pub fn new(level: f32) -> Self {
        Self {
            level,
            interactions: 0,
            last_updated: Utc::now(),
        }
    }
}

/// User communication preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPreferences {
    /// Preferred response length
    pub response_length: ResponseLength,
    /// Preferred formality level (0.0 = casual, 1.0 = formal)
    pub formality: f32,
    /// Preferred technical depth (0.0 = simplified, 1.0 = technical)
    pub technical_depth: f32,
    /// Enable analogies and metaphors
    pub use_analogies: bool,
    /// Preferred language code
    pub language: String,
    /// Voice characteristics
    pub voice: VoicePreferences,
}

impl Default for UserPreferences {
    fn default() -> Self {
        Self {
            response_length: ResponseLength::Balanced,
            formality: 0.5,
            technical_depth: 0.5,
            use_analogies: true,
            language: "en".to_string(),
            voice: VoicePreferences::default(),
        }
    }
}

/// Response length preference
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ResponseLength {
    Brief,
    Balanced,
    Detailed,
}

/// Voice and personality preferences
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoicePreferences {
    /// Enthusiasm level (0.0 = neutral, 1.0 = enthusiastic)
    pub enthusiasm: f32,
    /// Humor level (0.0 = serious, 1.0 = playful)
    pub humor: f32,
    /// Directness (0.0 = diplomatic, 1.0 = blunt)
    pub directness: f32,
}

impl Default for VoicePreferences {
    fn default() -> Self {
        Self {
            enthusiasm: 0.5,
            humor: 0.3,
            directness: 0.6,
        }
    }
}

/// Session summary for history
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSummary {
    /// Session timestamp
    pub timestamp: DateTime<Utc>,
    /// Topics discussed
    pub topics: Vec<String>,
    /// Brief summary
    pub summary: String,
    /// Number of exchanges
    pub exchange_count: u32,
}

// ============================================================================
// Identity System
// ============================================================================

/// Identity system manager
pub struct IdentitySystem {
    /// Configuration
    config: IdentitySystemConfig,
    /// Current user profile (if loaded)
    current_profile: Arc<RwLock<Option<UserProfile>>>,
    /// Profile cache
    profiles: Arc<RwLock<HashMap<String, UserProfile>>>,
}

impl IdentitySystem {
    /// Create new identity system
    pub fn new(config: IdentitySystemConfig) -> Self {
        Self {
            config,
            current_profile: Arc::new(RwLock::new(None)),
            profiles: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Load or create a user profile
    pub async fn load_or_create(&mut self, user_id: &str) -> ExocortexResult<UserProfile> {
        // Check cache first
        {
            let profiles = self.profiles.read().await;
            if let Some(profile) = profiles.get(user_id) {
                let mut current = self.current_profile.write().await;
                *current = Some(profile.clone());
                return Ok(profile.clone());
            }
        }

        // Create new profile
        let profile = UserProfile::new(user_id);

        // Store in cache
        {
            let mut profiles = self.profiles.write().await;
            profiles.insert(user_id.to_string(), profile.clone());
        }

        // Set as current
        {
            let mut current = self.current_profile.write().await;
            *current = Some(profile.clone());
        }

        Ok(profile)
    }

    /// Get current profile (if any)
    pub fn get_current_profile(&self) -> Option<UserProfile> {
        // Use try_read to avoid blocking
        self.current_profile
            .try_read()
            .ok()
            .and_then(|guard| guard.clone())
    }

    /// Record expertise gain
    pub async fn record_expertise(&mut self, domain: &str, delta: f32) {
        let mut current = self.current_profile.write().await;
        if let Some(ref mut profile) = *current {
            let current_level = profile.expertise_for(domain);
            profile.update_expertise(domain, (current_level + delta).clamp(0.0, 1.0));
        }
    }

    /// Update profile
    pub async fn update_profile<F>(&self, updater: F) -> ExocortexResult<()>
    where
        F: FnOnce(&mut UserProfile),
    {
        let mut current = self.current_profile.write().await;
        if let Some(ref mut profile) = *current {
            updater(profile);

            // Update cache
            let mut profiles = self.profiles.write().await;
            profiles.insert(profile.user_id.clone(), profile.clone());
        }
        Ok(())
    }

    /// Save current profile (for persistent modes)
    pub async fn save(&self) -> ExocortexResult<()> {
        match self.config.persistence_mode {
            PersistenceMode::Memory => Ok(()),
            PersistenceMode::File => {
                // TODO: Implement file persistence
                Ok(())
            }
            PersistenceMode::Postgres => {
                // TODO: Implement postgres persistence
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_identity_system() {
        let mut system = IdentitySystem::new(IdentitySystemConfig::default());

        let profile = system.load_or_create("test_user").await.unwrap();
        assert_eq!(profile.user_id, "test_user");

        let current = system.get_current_profile();
        assert!(current.is_some());
    }

    #[tokio::test]
    async fn test_expertise_tracking() {
        let mut system = IdentitySystem::new(IdentitySystemConfig::default());
        system.load_or_create("test_user").await.unwrap();

        system.record_expertise("rust", 0.2).await;

        let profile = system.get_current_profile().unwrap();
        assert!(profile.expertise_for("rust") > 0.3);
    }
}
