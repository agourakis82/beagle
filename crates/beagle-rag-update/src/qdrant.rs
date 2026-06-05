use anyhow::{Context, Result};
use reqwest::Client;
use serde_json::json;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct QdrantClient {
    base_url: String,
    client: Client,
}

impl QdrantClient {
    pub fn new(base_url: impl Into<String>) -> Self {
        Self {
            base_url: base_url.into().trim_end_matches('/').to_string(),
            client: Client::builder()
                .timeout(Duration::from_secs(60))
                .build()
                .expect("failed to build reqwest client"),
        }
    }

    pub async fn get_collection_points_count(&self, collection: &str) -> Result<Option<u64>> {
        let url = format!("{}/collections/{}", self.base_url, collection);
        let resp = self.client.get(&url).send().await?;
        if resp.status().as_u16() == 404 {
            return Ok(None);
        }
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("qdrant get_collection error {status}: {body}");
        }
        let v: serde_json::Value = resp.json().await?;
        Ok(v.get("result")
            .and_then(|r| r.get("points_count"))
            .and_then(|n| n.as_u64()))
    }

    pub async fn ensure_collection(&self, collection: &str, vector_size: usize) -> Result<()> {
        if self.get_collection_points_count(collection).await?.is_some() {
            return Ok(());
        }
        let url = format!("{}/collections/{}", self.base_url, collection);
        let body = json!({
            "vectors": { "size": vector_size, "distance": "Cosine" }
        });
        let resp = self.client.put(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("qdrant create_collection error {status}: {body}");
        }
        Ok(())
    }

    pub async fn delete_by_payload_match(
        &self,
        collection: &str,
        must: Vec<(&str, serde_json::Value)>,
    ) -> Result<()> {
        let url = format!(
            "{}/collections/{}/points/delete?wait=true",
            self.base_url, collection
        );
        let must_conditions: Vec<serde_json::Value> = must
            .into_iter()
            .map(|(key, value)| json!({ "key": key, "match": { "value": value } }))
            .collect();
        let body = json!({ "filter": { "must": must_conditions } });

        let resp = self.client.post(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("qdrant delete error {status}: {body}");
        }
        Ok(())
    }

    pub async fn upsert_points(
        &self,
        collection: &str,
        points: Vec<serde_json::Value>,
    ) -> Result<()> {
        let url = format!(
            "{}/collections/{}/points?wait=true",
            self.base_url, collection
        );
        let body = json!({ "points": points });
        let resp = self.client.put(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("qdrant upsert error {status}: {body}");
        }
        Ok(())
    }

    pub async fn search_points(
        &self,
        collection: &str,
        vector: &[f32],
        limit: usize,
        with_payload: bool,
    ) -> Result<Vec<serde_json::Value>> {
        let url = format!(
            "{}/collections/{}/points/search",
            self.base_url, collection
        );
        let body = json!({
            "vector": vector,
            "limit": limit,
            "with_payload": with_payload,
            "with_vector": false,
        });
        let resp = self.client.post(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("qdrant search error {status}: {body}");
        }
        let v: serde_json::Value = resp.json().await?;
        let result = v
            .get("result")
            .and_then(|r| r.as_array())
            .cloned()
            .unwrap_or_default();
        Ok(result)
    }

    pub fn stable_u64_id(parts: &[&str]) -> u64 {
        let mut hasher = blake3::Hasher::new();
        for p in parts {
            hasher.update(p.as_bytes());
            hasher.update(&[0u8]);
        }
        let hash = hasher.finalize();
        u64::from_le_bytes(hash.as_bytes()[0..8].try_into().unwrap())
    }

    pub fn client(&self) -> &Client {
        &self.client
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }
}

pub async fn post_webhook_json(url: &str, json_body: serde_json::Value) -> Result<()> {
    let client = Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .expect("failed to build reqwest client");
    let resp = client
        .post(url)
        .json(&json_body)
        .send()
        .await
        .context("failed to send webhook")?;
    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        anyhow::bail!("webhook error {status}: {body}");
    }
    Ok(())
}
