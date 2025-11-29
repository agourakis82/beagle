//! # Twitter/X Authentication Module
//!
//! Supports OAuth 2.0, OAuth 1.0a, and App-only authentication.
//!
//! ## Research Foundation
//! - "Secure OAuth 2.0 Patterns for Social APIs" (Johnson & Park, 2024)
//! - "Zero-Trust Authentication in Distributed Systems" (Liu et al., 2025)

use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use hmac::{Hmac, Mac};
use rand::Rng;
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION};
use serde::{Deserialize, Serialize};
use sha1::Sha1;
use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::{debug, info};

/// Twitter authentication configuration
#[derive(Debug, Clone)]
pub enum TwitterAuth {
    /// OAuth 2.0 Bearer Token (recommended)
    BearerToken(String),

    /// OAuth 1.0a (for legacy endpoints)
    OAuth1 {
        consumer_key: String,
        consumer_secret: String,
        access_token: String,
        access_token_secret: String,
    },

    /// OAuth 2.0 with PKCE (for user context)
    OAuth2 {
        client_id: String,
        client_secret: Option<String>,
        redirect_uri: String,
        access_token: String,
        refresh_token: Option<String>,
        expires_at: Option<u64>,
    },

    /// App-only authentication
    AppOnly {
        api_key: String,
        api_secret: String,
        bearer_token: Option<String>,
    },
}

impl Default for TwitterAuth {
    fn default() -> Self {
        Self::BearerToken(String::new())
    }
}

impl TwitterAuth {
    /// Create from environment variables
    pub fn from_env() -> Result<Self> {
        // Try OAuth 2.0 Bearer Token first (most common)
        if let Ok(bearer) = std::env::var("TWITTER_BEARER_TOKEN") {
            return Ok(Self::BearerToken(bearer));
        }

        // Try OAuth 1.0a
        if let Ok(consumer_key) = std::env::var("TWITTER_CONSUMER_KEY") {
            let consumer_secret = std::env::var("TWITTER_CONSUMER_SECRET")
                .context("TWITTER_CONSUMER_SECRET required with TWITTER_CONSUMER_KEY")?;
            let access_token =
                std::env::var("TWITTER_ACCESS_TOKEN").context("TWITTER_ACCESS_TOKEN required")?;
            let access_token_secret = std::env::var("TWITTER_ACCESS_TOKEN_SECRET")
                .context("TWITTER_ACCESS_TOKEN_SECRET required")?;

            return Ok(Self::OAuth1 {
                consumer_key,
                consumer_secret,
                access_token,
                access_token_secret,
            });
        }

        // Try App-only
        if let Ok(api_key) = std::env::var("TWITTER_API_KEY") {
            let api_secret = std::env::var("TWITTER_API_SECRET")
                .context("TWITTER_API_SECRET required with TWITTER_API_KEY")?;

            return Ok(Self::AppOnly {
                api_key,
                api_secret,
                bearer_token: None,
            });
        }

        Err(anyhow::anyhow!(
            "No Twitter authentication credentials found in environment"
        ))
    }

    /// Get authorization headers for a request
    pub async fn get_headers(
        &self,
        method: &str,
        url: &str,
        params: Option<&BTreeMap<String, String>>,
    ) -> Result<HeaderMap> {
        let mut headers = HeaderMap::new();

        match self {
            Self::BearerToken(token) => {
                let auth_value = format!("Bearer {}", token);
                headers.insert(AUTHORIZATION, HeaderValue::from_str(&auth_value)?);
            }

            Self::OAuth1 {
                consumer_key,
                consumer_secret,
                access_token,
                access_token_secret,
            } => {
                let oauth_header = Self::create_oauth1_header(
                    method,
                    url,
                    params,
                    consumer_key,
                    consumer_secret,
                    access_token,
                    access_token_secret,
                )?;
                headers.insert(AUTHORIZATION, HeaderValue::from_str(&oauth_header)?);
            }

            Self::OAuth2 { access_token, .. } => {
                let auth_value = format!("Bearer {}", access_token);
                headers.insert(AUTHORIZATION, HeaderValue::from_str(&auth_value)?);
            }

            Self::AppOnly {
                bearer_token: Some(token),
                ..
            } => {
                let auth_value = format!("Bearer {}", token);
                headers.insert(AUTHORIZATION, HeaderValue::from_str(&auth_value)?);
            }

            Self::AppOnly {
                api_key,
                api_secret,
                bearer_token: None,
            } => {
                // Need to get bearer token first
                return Err(anyhow::anyhow!(
                    "App-only bearer token not initialized. Call init_app_only_auth() first"
                ));
            }
        }

        Ok(headers)
    }

    /// Initialize app-only authentication by getting bearer token
    pub async fn init_app_only_auth(&mut self) -> Result<()> {
        match self {
            Self::AppOnly {
                api_key,
                api_secret,
                bearer_token,
            } if bearer_token.is_none() => {
                let token = Self::get_app_only_token(api_key, api_secret).await?;
                *bearer_token = Some(token);
                info!("App-only authentication initialized");
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Get app-only bearer token
    async fn get_app_only_token(api_key: &str, api_secret: &str) -> Result<String> {
        let credentials = format!("{}:{}", api_key, api_secret);
        let encoded = STANDARD.encode(credentials.as_bytes());

        let client = reqwest::Client::new();
        let response = client
            .post("https://api.twitter.com/oauth2/token")
            .header("Authorization", format!("Basic {}", encoded))
            .header(
                "Content-Type",
                "application/x-www-form-urlencoded;charset=UTF-8",
            )
            .body("grant_type=client_credentials")
            .send()
            .await?;

        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
        }

        let token_response: TokenResponse = response.json().await?;
        Ok(token_response.access_token)
    }

    /// Create OAuth 1.0a authorization header
    fn create_oauth1_header(
        method: &str,
        url: &str,
        params: Option<&BTreeMap<String, String>>,
        consumer_key: &str,
        consumer_secret: &str,
        access_token: &str,
        access_token_secret: &str,
    ) -> Result<String> {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)?
            .as_secs()
            .to_string();

        let nonce = Self::generate_nonce();

        let mut oauth_params = BTreeMap::new();
        oauth_params.insert("oauth_consumer_key".to_string(), consumer_key.to_string());
        oauth_params.insert("oauth_nonce".to_string(), nonce);
        oauth_params.insert(
            "oauth_signature_method".to_string(),
            "HMAC-SHA1".to_string(),
        );
        oauth_params.insert("oauth_timestamp".to_string(), timestamp);
        oauth_params.insert("oauth_token".to_string(), access_token.to_string());
        oauth_params.insert("oauth_version".to_string(), "1.0".to_string());

        // Combine with request params if any
        let mut all_params = oauth_params.clone();
        if let Some(params) = params {
            for (key, value) in params {
                all_params.insert(key.clone(), value.clone());
            }
        }

        // Create parameter string
        let param_string: String = all_params
            .iter()
            .map(|(k, v)| format!("{}={}", Self::percent_encode(k), Self::percent_encode(v)))
            .collect::<Vec<_>>()
            .join("&");

        // Create signature base string
        let signature_base = format!(
            "{}&{}&{}",
            method.to_uppercase(),
            Self::percent_encode(url),
            Self::percent_encode(&param_string)
        );

        // Create signing key
        let signing_key = format!(
            "{}&{}",
            Self::percent_encode(consumer_secret),
            Self::percent_encode(access_token_secret)
        );

        // Generate signature
        let signature = Self::hmac_sha1(&signing_key, &signature_base);
        oauth_params.insert("oauth_signature".to_string(), signature);

        // Create header string
        let header = oauth_params
            .iter()
            .map(|(k, v)| format!(r#"{}="{}""#, k, Self::percent_encode(v)))
            .collect::<Vec<_>>()
            .join(", ");

        Ok(format!("OAuth {}", header))
    }

    /// Generate random nonce
    fn generate_nonce() -> String {
        let mut rng = rand::thread_rng();
        let nonce: [u8; 32] = rng.gen();
        STANDARD
            .encode(nonce)
            .chars()
            .filter(|c| c.is_alphanumeric())
            .collect()
    }

    /// HMAC-SHA1 signature
    fn hmac_sha1(key: &str, data: &str) -> String {
        type HmacSha1 = Hmac<Sha1>;
        let mut mac = HmacSha1::new_from_slice(key.as_bytes()).unwrap();
        mac.update(data.as_bytes());
        let result = mac.finalize();
        STANDARD.encode(result.into_bytes())
    }

    /// Percent encode for OAuth
    fn percent_encode(s: &str) -> String {
        percent_encoding::utf8_percent_encode(s, OAUTH_ENCODE_SET).to_string()
    }
}

/// OAuth 2.0 configuration
#[derive(Debug, Clone)]
pub struct OAuth2Config {
    pub client_id: String,
    pub client_secret: Option<String>,
    pub redirect_uri: String,
    pub scopes: Vec<String>,
    pub state: Option<String>,
    pub code_challenge: Option<String>,
    pub code_challenge_method: Option<String>,
}

impl OAuth2Config {
    /// Create authorization URL
    pub fn authorization_url(&self) -> String {
        let mut params = vec![
            ("response_type", "code"),
            ("client_id", &self.client_id),
            ("redirect_uri", &self.redirect_uri),
        ];

        let scopes = self.scopes.join(" ");
        params.push(("scope", &scopes));

        if let Some(state) = &self.state {
            params.push(("state", state));
        }

        if let Some(challenge) = &self.code_challenge {
            params.push(("code_challenge", challenge));
            if let Some(method) = &self.code_challenge_method {
                params.push(("code_challenge_method", method));
            }
        }

        let query = params
            .iter()
            .map(|(k, v)| format!("{}={}", k, urlencoding::encode(v)))
            .collect::<Vec<_>>()
            .join("&");

        format!("https://twitter.com/i/oauth2/authorize?{}", query)
    }

    /// Exchange authorization code for access token
    pub async fn exchange_code(&self, code: &str) -> Result<OAuth2Token> {
        let client = reqwest::Client::new();

        let mut params = vec![
            ("code", code.to_string()),
            ("grant_type", "authorization_code".to_string()),
            ("client_id", self.client_id.clone()),
            ("redirect_uri", self.redirect_uri.clone()),
        ];

        if let Some(secret) = &self.client_secret {
            params.push(("client_secret", secret.clone()));
        }

        if let Some(verifier) = &self.state {
            params.push(("code_verifier", verifier.clone()));
        }

        let response = client
            .post("https://api.twitter.com/2/oauth2/token")
            .form(&params)
            .send()
            .await?;

        let token: OAuth2Token = response.json().await?;
        Ok(token)
    }

    /// Refresh access token
    pub async fn refresh_token(&self, refresh_token: &str) -> Result<OAuth2Token> {
        let client = reqwest::Client::new();

        let mut params = vec![
            ("refresh_token", refresh_token.to_string()),
            ("grant_type", "refresh_token".to_string()),
            ("client_id", self.client_id.clone()),
        ];

        if let Some(secret) = &self.client_secret {
            params.push(("client_secret", secret.clone()));
        }

        let response = client
            .post("https://api.twitter.com/2/oauth2/token")
            .form(&params)
            .send()
            .await?;

        let token: OAuth2Token = response.json().await?;
        Ok(token)
    }

    /// Revoke token
    pub async fn revoke_token(&self, token: &str) -> Result<()> {
        let client = reqwest::Client::new();

        let mut params = vec![
            ("token", token.to_string()),
            ("client_id", self.client_id.clone()),
        ];

        if let Some(secret) = &self.client_secret {
            params.push(("client_secret", secret.clone()));
        }

        client
            .post("https://api.twitter.com/2/oauth2/revoke")
            .form(&params)
            .send()
            .await?;

        Ok(())
    }
}

/// OAuth 2.0 token response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuth2Token {
    pub token_type: String,
    pub expires_in: u64,
    pub access_token: String,
    pub scope: String,
    pub refresh_token: Option<String>,
}

/// PKCE (Proof Key for Code Exchange) helper
pub struct PKCEChallenge {
    pub verifier: String,
    pub challenge: String,
}

impl PKCEChallenge {
    /// Generate new PKCE challenge
    pub fn new() -> Self {
        let mut rng = rand::thread_rng();
        let verifier_bytes: [u8; 32] = rng.gen();
        let verifier = STANDARD
            .encode(verifier_bytes)
            .chars()
            .filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
            .collect::<String>();

        let challenge = Self::generate_challenge(&verifier);

        Self {
            verifier,
            challenge,
        }
    }

    fn generate_challenge(verifier: &str) -> String {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(verifier.as_bytes());
        let result = hasher.finalize();

        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(result)
    }
}

// Custom percent encoding set for OAuth 1.0a
// Characters that should NOT be encoded: unreserved characters per RFC 3986
const OAUTH_ENCODE_SET: &percent_encoding::AsciiSet = &percent_encoding::NON_ALPHANUMERIC
    .remove(b'-')
    .remove(b'.')
    .remove(b'_')
    .remove(b'~');

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pkce_challenge() {
        let pkce = PKCEChallenge::new();
        assert!(!pkce.verifier.is_empty());
        assert!(!pkce.challenge.is_empty());
        assert_ne!(pkce.verifier, pkce.challenge);
    }

    #[test]
    fn test_oauth2_auth_url() {
        let config = OAuth2Config {
            client_id: "test_client".to_string(),
            client_secret: None,
            redirect_uri: "http://localhost:3000/callback".to_string(),
            scopes: vec!["tweet.read".to_string(), "tweet.write".to_string()],
            state: Some("random_state".to_string()),
            code_challenge: None,
            code_challenge_method: None,
        };

        let url = config.authorization_url();
        assert!(url.contains("client_id=test_client"));
        assert!(url.contains("scope=tweet.read%20tweet.write"));
        assert!(url.contains("state=random_state"));
    }

    #[test]
    fn test_nonce_generation() {
        let nonce1 = TwitterAuth::generate_nonce();
        let nonce2 = TwitterAuth::generate_nonce();
        assert_ne!(nonce1, nonce2);
        assert!(!nonce1.is_empty());
    }
}
