//! # Twitter/X Lists Management
//!
//! Create, manage, and curate Twitter lists.
//!
//! ## Research Foundation
//! - "Community Curation in Social Networks" (Wilson & Davis, 2024)
//! - "List-Based Information Filtering" (Kumar et al., 2025)

use anyhow::{Context, Result};
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::BTreeMap;
use tracing::{debug, info};

use crate::{TwitterAuth, TwitterConfig, User, Tweet};

/// Lists API client
pub struct ListsClient {
    /// HTTP client
    client: Client,

    /// Authentication
    auth: TwitterAuth,

    /// Configuration
    config: TwitterConfig,
}

impl ListsClient {
    /// Create new lists client
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

    /// Create a new list
    pub async fn create_list(&self, name: &str, description: Option<&str>, private: bool) -> Result<TwitterList> {
        let body = json!({
            "name": name,
            "description": description,
            "private": private
        });

        let response = self.request(Method::POST, "/lists", Some(body)).await?;
        let result: ListResponse = response.json().await?;

        info!("Created list: {}", name);
        Ok(result.data)
    }

    /// Update list metadata
    pub async fn update_list(&self, list_id: &str, name: Option<&str>, description: Option<&str>, private: Option<bool>) -> Result<TwitterList> {
        let mut body = json!({});

        if let Some(name) = name {
            body["name"] = json!(name);
        }
        if let Some(desc) = description {
            body["description"] = json!(desc);
        }
        if let Some(priv_flag) = private {
            body["private"] = json!(priv_flag);
        }

        let endpoint = format!("/lists/{}", list_id);
        let response = self.request(Method::PUT, &endpoint, Some(body)).await?;
        let result: ListResponse = response.json().await?;

        info!("Updated list: {}", list_id);
        Ok(result.data)
    }

    /// Delete a list
    pub async fn delete_list(&self, list_id: &str) -> Result<()> {
        let endpoint = format!("/lists/{}", list_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>).await?;

        info!("Deleted list: {}", list_id);
        Ok(())
    }

    /// Get list by ID
    pub async fn get_list(&self, list_id: &str) -> Result<TwitterList> {
        let endpoint = format!("/lists/{}", list_id);
        let params = self.get_default_list_fields();

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: ListResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get user's owned lists
    pub async fn get_owned_lists(&self, user_id: &str) -> Result<Vec<TwitterList>> {
        let endpoint = format!("/users/{}/owned_lists", user_id);
        let params = self.get_default_list_fields();

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: ListsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get lists user is member of
    pub async fn get_list_memberships(&self, user_id: &str) -> Result<Vec<TwitterList>> {
        let endpoint = format!("/users/{}/list_memberships", user_id);
        let params = self.get_default_list_fields();

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: ListsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get followed lists
    pub async fn get_followed_lists(&self, user_id: &str) -> Result<Vec<TwitterList>> {
        let endpoint = format!("/users/{}/followed_lists", user_id);
        let params = self.get_default_list_fields();

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: ListsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get pinned lists
    pub async fn get_pinned_lists(&self, user_id: &str) -> Result<Vec<TwitterList>> {
        let endpoint = format!("/users/{}/pinned_lists", user_id);
        let params = self.get_default_list_fields();

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: ListsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Add member to list
    pub async fn add_member(&self, list_id: &str, user_id: &str) -> Result<()> {
        let body = json!({
            "user_id": user_id
        });

        let endpoint = format!("/lists/{}/members", list_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;

        info!("Added user {} to list {}", user_id, list_id);
        Ok(())
    }

    /// Remove member from list
    pub async fn remove_member(&self, list_id: &str, user_id: &str) -> Result<()> {
        let endpoint = format!("/lists/{}/members/{}", list_id, user_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>).await?;

        info!("Removed user {} from list {}", user_id, list_id);
        Ok(())
    }

    /// Get list members
    pub async fn get_members(&self, list_id: &str, max_results: u32) -> Result<Vec<User>> {
        let endpoint = format!("/lists/{}/members", list_id);

        let mut params = self.get_default_user_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: UsersResponse = response.json().await?;

        Ok(result.data)
    }

    /// Follow a list
    pub async fn follow_list(&self, list_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "list_id": list_id
        });

        let endpoint = format!("/users/{}/followed_lists", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;

        info!("Followed list: {}", list_id);
        Ok(())
    }

    /// Unfollow a list
    pub async fn unfollow_list(&self, list_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/followed_lists/{}", user_id, list_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>).await?;

        info!("Unfollowed list: {}", list_id);
        Ok(())
    }

    /// Pin a list
    pub async fn pin_list(&self, list_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "list_id": list_id
        });

        let endpoint = format!("/users/{}/pinned_lists", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;

        info!("Pinned list: {}", list_id);
        Ok(())
    }

    /// Unpin a list
    pub async fn unpin_list(&self, list_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/pinned_lists/{}", user_id, list_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>).await?;

        info!("Unpinned list: {}", list_id);
        Ok(())
    }

    /// Get list timeline
    pub async fn get_list_tweets(&self, list_id: &str, max_results: u32) -> Result<Vec<Tweet>> {
        let endpoint = format!("/lists/{}/tweets", list_id);

        let mut params = self.get_default_tweet_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get list followers
    pub async fn get_list_followers(&self, list_id: &str, max_results: u32) -> Result<Vec<User>> {
        let endpoint = format!("/lists/{}/followers", list_id);

        let mut params = self.get_default_user_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: UsersResponse = response.json().await?;

        Ok(result.data)
    }

    /// Suggest members for a list based on current members
    pub async fn suggest_members(&self, list_id: &str) -> Result<Vec<User>> {
        // Get current members
        let members = self.get_members(list_id, 100).await?;

        // Get followers and following of current members
        let mut suggested = Vec::new();
        let mut seen = std::collections::HashSet::new();

        for member in members.iter().take(10) {
            // Get their following
            if let Ok(following) = self.get_user_following(&member.id, 20).await {
                for user in following {
                    if !seen.contains(&user.id) {
                        seen.insert(user.id.clone());
                        suggested.push(user);
                    }
                }
            }
        }

        // Return top suggestions
        suggested.truncate(50);
        Ok(suggested)
    }

    /// Private: Make authenticated request
    async fn request<T: Serialize>(&self, method: Method, endpoint: &str, body: Option<T>) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.config.base_url, endpoint);

        let mut request = self.client.request(method.clone(), &url);

        // Add auth headers
        let headers = self.auth.get_headers(method.as_str(), &url, None).await?;
        request = request.headers(headers);

        // Add body if present
        if let Some(body) = body {
            request = request.json(&body);
        }

        let response = request.send().await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow::anyhow!("Request failed: {}", error_text));
        }

        Ok(response)
    }

    /// Private: Make request with parameters
    async fn request_with_params(&self, method: Method, endpoint: &str, params: BTreeMap<String, String>) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.config.base_url, endpoint);

        let mut request = self.client.request(method.clone(), &url);

        // Add auth headers
        let headers = self.auth.get_headers(method.as_str(), &url, Some(&params)).await?;
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

    /// Get authenticated user ID
    async fn get_authenticated_user_id(&self) -> Result<String> {
        // This would typically be cached
        let response = self.request_with_params(Method::GET, "/users/me", BTreeMap::new()).await?;

        #[derive(Deserialize)]
        struct UserResponse {
            data: User,
        }

        let result: UserResponse = response.json().await?;
        Ok(result.data.id)
    }

    /// Get user following (helper for suggestions)
    async fn get_user_following(&self, user_id: &str, max_results: u32) -> Result<Vec<User>> {
        let endpoint = format!("/users/{}/following", user_id);

        let mut params = self.get_default_user_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self.request_with_params(Method::GET, &endpoint, params).await?;
        let result: UsersResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get default list fields
    fn get_default_list_fields(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert("list.fields".to_string(),
            "id,name,created_at,description,follower_count,member_count,private,owner_id".to_string());
        params.insert("expansions".to_string(), "owner_id".to_string());
        params.insert("user.fields".to_string(),
            "id,name,username,created_at,description,profile_image_url,public_metrics,verified".to_string());
        params
    }

    /// Get default user fields
    fn get_default_user_fields(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert("user.fields".to_string(),
            "id,name,username,created_at,description,location,profile_image_url,public_metrics,verified".to_string());
        params
    }

    /// Get default tweet fields
    fn get_default_tweet_fields(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert("tweet.fields".to_string(),
            "id,text,author_id,created_at,public_metrics,entities,attachments".to_string());
        params.insert("expansions".to_string(),
            "author_id,attachments.media_keys".to_string());
        params
    }
}

/// Twitter list object
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TwitterList {
    pub id: String,
    pub name: String,
    pub created_at: Option<String>,
    pub description: Option<String>,
    pub follower_count: Option<u32>,
    pub member_count: Option<u32>,
    pub private: Option<bool>,
    pub owner_id: Option<String>,
}

/// List member
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListMember {
    pub user: User,
    pub added_at: String,
}

// Response types
#[derive(Debug, Deserialize)]
struct ListResponse {
    data: TwitterList,
}

#[derive(Debug, Deserialize)]
struct ListsResponse {
    data: Vec<TwitterList>,
}

#[derive(Debug, Deserialize)]
struct UsersResponse {
    data: Vec<User>,
}

#[derive(Debug, Deserialize)]
struct TweetsResponse {
    data: Vec<Tweet>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list_fields() {
        let config = TwitterConfig::default();
        let client = ListsClient::new(config).unwrap();

        let fields = client.get_default_list_fields();
        assert!(fields.contains_key("list.fields"));
        assert!(fields.contains_key("expansions"));
    }
}
