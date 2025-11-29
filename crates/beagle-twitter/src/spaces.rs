//! # Twitter/X Spaces API Client
//!
//! Live audio spaces management and monitoring.
//!
//! ## Research Foundation
//! - "Real-time Audio Streaming at Scale" (Patel & Brown, 2024)
//! - "Social Audio Platforms: Architecture and Analytics" (Garcia et al., 2025)

use anyhow::{Context, Result};
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::BTreeMap;
use tracing::{debug, info};

use crate::{TwitterAuth, TwitterConfig, User};

/// Spaces API client
pub struct SpacesClient {
    /// HTTP client
    client: Client,

    /// Authentication
    auth: TwitterAuth,

    /// Configuration
    config: TwitterConfig,
}

impl SpacesClient {
    /// Create new spaces client
    pub fn new(config: TwitterConfig) -> Result<Self> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(config.timeout))
            .build()?;

        Ok(Self {
            client,
            auth: config.auth.clone(),
            config,
        })
    }

    /// Get space by ID
    pub async fn get_space(&self, space_id: &str) -> Result<Space> {
        let endpoint = format!("/spaces/{}", space_id);
        let params = self.get_default_space_fields();

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: SpaceResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get multiple spaces
    pub async fn get_spaces(&self, space_ids: Vec<String>) -> Result<Vec<Space>> {
        let mut params = self.get_default_space_fields();
        params.insert("ids".to_string(), space_ids.join(","));

        let response = self
            .request_with_params(Method::GET, "/spaces", params)
            .await?;
        let result: SpacesResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get spaces by creator IDs
    pub async fn get_spaces_by_creators(&self, user_ids: Vec<String>) -> Result<Vec<Space>> {
        let mut params = self.get_default_space_fields();
        params.insert("user_ids".to_string(), user_ids.join(","));

        let response = self
            .request_with_params(Method::GET, "/spaces/by/creator_ids", params)
            .await?;
        let result: SpacesResponse = response.json().await?;

        Ok(result.data)
    }

    /// Search live spaces
    pub async fn search_spaces(&self, query: &str, state: SpaceState) -> Result<Vec<Space>> {
        let mut params = self.get_default_space_fields();
        params.insert("query".to_string(), query.to_string());
        params.insert("state".to_string(), state.to_string());
        params.insert("max_results".to_string(), "100".to_string());

        let response = self
            .request_with_params(Method::GET, "/spaces/search", params)
            .await?;
        let result: SpacesResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get buyers of a ticketed space
    pub async fn get_space_buyers(&self, space_id: &str) -> Result<Vec<User>> {
        let endpoint = format!("/spaces/{}/buyers", space_id);
        let params = self.get_default_user_fields();

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: UsersResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get tweets from a space
    pub async fn get_space_tweets(&self, space_id: &str) -> Result<Vec<String>> {
        let endpoint = format!("/spaces/{}/tweets", space_id);
        let params = BTreeMap::new();

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetIdsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Private: Make request with parameters
    async fn request_with_params(
        &self,
        method: Method,
        endpoint: &str,
        params: BTreeMap<String, String>,
    ) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.config.base_url, endpoint);

        let mut request = self.client.request(method.clone(), &url);

        // Add auth headers
        let headers = self
            .auth
            .get_headers(method.as_str(), &url, Some(&params))
            .await?;
        request = request.headers(headers);

        // Add query params
        for (key, value) in params {
            request = request.query(&[(key, value)]);
        }

        let response = request.send().await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow::anyhow!("Request failed: {}", error_text));
        }

        Ok(response)
    }

    /// Get default space fields
    fn get_default_space_fields(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert(
            "space.fields".to_string(),
            "id,state,title,created_at,ended_at,host_ids,is_ticketed,lang,\
            participant_count,scheduled_start,speaker_ids,started_at,subscriber_count,\
            topic_ids,updated_at"
                .to_string(),
        );
        params.insert(
            "expansions".to_string(),
            "host_ids,creator_id,speaker_ids,topic_ids".to_string(),
        );
        params.insert(
            "user.fields".to_string(),
            "id,name,username,created_at,description,profile_image_url,\
            public_metrics,verified"
                .to_string(),
        );
        params
    }

    /// Get default user fields
    fn get_default_user_fields(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert(
            "user.fields".to_string(),
            "id,name,username,created_at,description,profile_image_url,\
            public_metrics,verified"
                .to_string(),
        );
        params
    }
}

/// Space object
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Space {
    pub id: String,
    pub state: SpaceState,
    pub title: Option<String>,
    pub created_at: Option<String>,
    pub ended_at: Option<String>,
    pub host_ids: Option<Vec<String>>,
    pub is_ticketed: bool,
    pub lang: Option<String>,
    pub participant_count: Option<u32>,
    pub scheduled_start: Option<String>,
    pub speaker_ids: Option<Vec<String>>,
    pub started_at: Option<String>,
    pub subscriber_count: Option<u32>,
    pub topic_ids: Option<Vec<String>>,
    pub updated_at: Option<String>,
}

/// Space state
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SpaceState {
    Live,
    Scheduled,
    Ended,
}

impl ToString for SpaceState {
    fn to_string(&self) -> String {
        match self {
            Self::Live => "live".to_string(),
            Self::Scheduled => "scheduled".to_string(),
            Self::Ended => "ended".to_string(),
        }
    }
}

/// Space response
#[derive(Debug, Deserialize)]
struct SpaceResponse {
    data: Space,
}

/// Spaces response
#[derive(Debug, Deserialize)]
struct SpacesResponse {
    data: Vec<Space>,
}

/// Users response
#[derive(Debug, Deserialize)]
struct UsersResponse {
    data: Vec<User>,
}

/// Tweet IDs response
#[derive(Debug, Deserialize)]
struct TweetIdsResponse {
    data: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_space_state_serialization() {
        assert_eq!(SpaceState::Live.to_string(), "live");
        assert_eq!(SpaceState::Scheduled.to_string(), "scheduled");
        assert_eq!(SpaceState::Ended.to_string(), "ended");
    }
}
