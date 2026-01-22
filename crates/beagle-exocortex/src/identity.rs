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
use sqlx::postgres::PgPoolOptions;
use sqlx::types::Json;
use std::collections::HashMap;
use std::path::PathBuf;
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
    /// Base directory for file persistence (defaults to BEAGLE_DATA_DIR/identity).
    pub persistence_path: Option<PathBuf>,
    /// Database URL for postgres persistence.
    pub database_url: Option<String>,
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
            persistence_path: None,
            database_url: None,
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
    /// Optional Postgres pool (only when persistence_mode is Postgres)
    pg_pool: Option<sqlx::PgPool>,
}

impl IdentitySystem {
    /// Create new identity system
    pub fn new(config: IdentitySystemConfig) -> ExocortexResult<Self> {
        let pg_pool = if config.persistence_mode == PersistenceMode::Postgres {
            let database_url = config.database_url.clone().ok_or_else(|| {
                ExocortexError::Config(
                    "identity persistence 'postgres' requires identity.database_url".to_string(),
                )
            })?;
            Some(
                PgPoolOptions::new()
                    .max_connections(5)
                    .connect_lazy(&database_url)
                    .map_err(|e| {
                        ExocortexError::Config(format!(
                            "invalid identity.database_url for postgres persistence: {e}"
                        ))
                    })?,
            )
        } else {
            None
        };

        Ok(Self {
            config,
            current_profile: Arc::new(RwLock::new(None)),
            profiles: Arc::new(RwLock::new(HashMap::new())),
            pg_pool,
        })
    }

    fn base_dir(&self) -> PathBuf {
        self.config
            .persistence_path
            .clone()
            .unwrap_or_else(|| beagle_config::beagle_data_dir().join("identity"))
    }

    fn file_name_for_user_id(user_id: &str) -> String {
        let mut safe = String::with_capacity(user_id.len().min(32));
        for ch in user_id.chars() {
            if safe.len() >= 32 {
                break;
            }
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                safe.push(ch);
            } else {
                safe.push('_');
            }
        }
        let hash = blake3::hash(user_id.as_bytes()).to_hex().to_string();
        let suffix = &hash[..8];
        if safe.is_empty() {
            format!("user_{}.json", suffix)
        } else {
            format!("{}_{}.json", safe, suffix)
        }
    }

    fn profile_path_for(&self, user_id: &str) -> PathBuf {
        self.base_dir()
            .join(Self::file_name_for_user_id(user_id))
    }

    async fn load_from_file(&self, user_id: &str) -> ExocortexResult<Option<UserProfile>> {
        let path = self.profile_path_for(user_id);
        if !path.exists() {
            return Ok(None);
        }
        let text = tokio::fs::read_to_string(&path).await?;
        let mut profile: UserProfile = serde_json::from_str(&text)?;

        // Ensure the loaded profile matches the requested ID (no-op if same).
        profile.user_id = user_id.to_string();
        profile.last_active = Utc::now();
        Ok(Some(profile))
    }

    async fn save_to_file(&self, profile: &UserProfile) -> ExocortexResult<()> {
        let dir = self.base_dir();
        tokio::fs::create_dir_all(&dir).await?;
        let path = dir.join(Self::file_name_for_user_id(&profile.user_id));
        let body = serde_json::to_string_pretty(profile)?;
        tokio::fs::write(&path, body).await?;
        Ok(())
    }

    async fn ensure_postgres_schema(&self) -> ExocortexResult<()> {
        let Some(pool) = &self.pg_pool else {
            return Ok(());
        };

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS beagle_identity_profiles (
                user_id TEXT PRIMARY KEY,
                profile JSONB NOT NULL,
                updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            "#,
        )
        .execute(pool)
        .await?;

        Ok(())
    }

    async fn load_from_postgres(&self, user_id: &str) -> ExocortexResult<Option<UserProfile>> {
        let pool = self.pg_pool.as_ref().ok_or_else(|| {
            ExocortexError::Config(
                "identity persistence 'postgres' requires identity.database_url".to_string(),
            )
        })?;

        self.ensure_postgres_schema().await?;

        let row: Option<Json<UserProfile>> = sqlx::query_scalar(
            "SELECT profile FROM beagle_identity_profiles WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_optional(pool)
        .await?;

        let Some(Json(mut profile)) = row else {
            return Ok(None);
        };

        profile.user_id = user_id.to_string();
        profile.last_active = Utc::now();
        Ok(Some(profile))
    }

    async fn save_to_postgres(&self, profile: &UserProfile) -> ExocortexResult<()> {
        let pool = self.pg_pool.as_ref().ok_or_else(|| {
            ExocortexError::Config(
                "identity persistence 'postgres' requires identity.database_url".to_string(),
            )
        })?;

        self.ensure_postgres_schema().await?;

        sqlx::query(
            r#"
            INSERT INTO beagle_identity_profiles (user_id, profile, updated_at)
            VALUES ($1, $2, now())
            ON CONFLICT (user_id)
            DO UPDATE SET profile = EXCLUDED.profile, updated_at = EXCLUDED.updated_at
            "#,
        )
        .bind(&profile.user_id)
        .bind(Json(profile))
        .execute(pool)
        .await?;

        Ok(())
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

        // Load from persistence backend if enabled
        match self.config.persistence_mode {
            PersistenceMode::File => {
                if let Some(profile) = self.load_from_file(user_id).await? {
                    {
                        let mut profiles = self.profiles.write().await;
                        profiles.insert(user_id.to_string(), profile.clone());
                    }
                    {
                        let mut current = self.current_profile.write().await;
                        *current = Some(profile.clone());
                    }
                    // Persist last_active update best-effort.
                    let _ = self.save().await;
                    return Ok(profile);
                }
            }
            PersistenceMode::Postgres => {
                if let Some(profile) = self.load_from_postgres(user_id).await? {
                    {
                        let mut profiles = self.profiles.write().await;
                        profiles.insert(user_id.to_string(), profile.clone());
                    }
                    {
                        let mut current = self.current_profile.write().await;
                        *current = Some(profile.clone());
                    }
                    // Persist last_active update best-effort.
                    let _ = self.save().await;
                    return Ok(profile);
                }
            }
            PersistenceMode::Memory => {}
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

        // Persist best-effort (only relevant for file/postgres modes).
        let _ = self.save().await;

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
        let mut updated: Option<UserProfile> = None;
        {
            let mut current = self.current_profile.write().await;
            if let Some(ref mut profile) = *current {
                let current_level = profile.expertise_for(domain);
                profile.update_expertise(domain, (current_level + delta).clamp(0.0, 1.0));
                profile.last_active = Utc::now();
                updated = Some(profile.clone());
            }
        }

        if let Some(profile) = updated {
            let mut profiles = self.profiles.write().await;
            profiles.insert(profile.user_id.clone(), profile);
        }

        if self.config.persistence_mode != PersistenceMode::Memory {
            if let Err(e) = self.save().await {
                tracing::warn!("Failed to persist identity profile: {}", e);
            }
        }
    }

    /// Update profile
    pub async fn update_profile<F>(&self, updater: F) -> ExocortexResult<()>
    where
        F: FnOnce(&mut UserProfile),
    {
        let mut updated: Option<UserProfile> = None;
        let mut current = self.current_profile.write().await;
        if let Some(ref mut profile) = *current {
            updater(profile);
            profile.last_active = Utc::now();
            updated = Some(profile.clone());

            // Update cache
            let mut profiles = self.profiles.write().await;
            profiles.insert(profile.user_id.clone(), profile.clone());
        }
        drop(current);

        if updated.is_some() && self.config.persistence_mode != PersistenceMode::Memory {
            self.save().await?;
        }
        Ok(())
    }

    /// Save current profile (for persistent modes)
    pub async fn save(&self) -> ExocortexResult<()> {
        match self.config.persistence_mode {
            PersistenceMode::Memory => Ok(()),
            PersistenceMode::File => {
                let current = self.current_profile.read().await;
                if let Some(ref profile) = *current {
                    self.save_to_file(profile).await?;
                }
                Ok(())
            }
            PersistenceMode::Postgres => {
                let current = self.current_profile.read().await;
                if let Some(ref profile) = *current {
                    self.save_to_postgres(profile).await?;
                }
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
        let mut system = IdentitySystem::new(IdentitySystemConfig::default()).unwrap();

        let profile = system.load_or_create("test_user").await.unwrap();
        assert_eq!(profile.user_id, "test_user");

        let current = system.get_current_profile();
        assert!(current.is_some());
    }

    #[tokio::test]
    async fn test_expertise_tracking() {
        let mut system = IdentitySystem::new(IdentitySystemConfig::default()).unwrap();
        system.load_or_create("test_user").await.unwrap();

        system.record_expertise("rust", 0.2).await;

        let profile = system.get_current_profile().unwrap();
        assert!(profile.expertise_for("rust") > 0.3);
    }

    #[tokio::test]
    async fn test_postgres_requires_database_url() {
        let err = match IdentitySystem::new(IdentitySystemConfig {
            persistence_mode: PersistenceMode::Postgres,
            database_url: None,
            ..IdentitySystemConfig::default()
        })
        {
            Ok(_) => panic!("expected Config error"),
            Err(e) => e,
        };

        match err {
            ExocortexError::Config(_) => {}
            other => panic!("expected Config error, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn test_postgres_roundtrip_if_configured() {
        let Ok(database_url) = std::env::var("BEAGLE_TEST_DATABASE_URL") else {
            return;
        };

        let user_id = format!("test_user_pg_{}", uuid::Uuid::new_v4());
        let mut system = IdentitySystem::new(IdentitySystemConfig {
            persistence_mode: PersistenceMode::Postgres,
            database_url: Some(database_url.clone()),
            ..IdentitySystemConfig::default()
        })
        .unwrap();

        let _ = system.load_or_create(&user_id).await.unwrap();
        system.record_expertise("rust", 0.2).await;

        let mut system2 = IdentitySystem::new(IdentitySystemConfig {
            persistence_mode: PersistenceMode::Postgres,
            database_url: Some(database_url),
            ..IdentitySystemConfig::default()
        })
        .unwrap();

        let loaded = system2.load_or_create(&user_id).await.unwrap();
        assert!(loaded.expertise_for("rust") > 0.3);
    }
}
