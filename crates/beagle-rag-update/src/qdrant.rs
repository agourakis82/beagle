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
        if self
            .get_collection_points_count(collection)
            .await?
            .is_some()
        {
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
        let url = format!("{}/collections/{}/points/search", self.base_url, collection);
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

    /// Idempotently ensure a NAMED hybrid collection (dense + sparse w/ IDF modifier).
    /// Like `ensure_collection`, this is a no-op if the collection already has points.
    pub async fn ensure_hybrid_collection(
        &self,
        collection: &str,
        vector_size: usize,
    ) -> Result<()> {
        if self
            .get_collection_points_count(collection)
            .await?
            .is_some()
        {
            return Ok(());
        }
        let url = format!("{}/collections/{}", self.base_url, collection);
        let body = json!({
            "vectors": { "dense": { "size": vector_size, "distance": "Cosine" } },
            "sparse_vectors": { "text": { "modifier": "idf" } }
        });
        let resp = self.client.put(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("qdrant create_hybrid_collection error {status}: {body}");
        }
        Ok(())
    }

    /// Upsert points already shaped with named vectors, e.g.
    /// `{"id":..,"vector":{"dense":[...],"text":{"indices":[...],"values":[...]}},"payload":..}`.
    pub async fn upsert_hybrid_points(
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
            anyhow::bail!("qdrant upsert_hybrid error {status}: {body}");
        }
        Ok(())
    }

    /// Hybrid dense + sparse retrieval fused server-side with RRF via /points/query.
    pub async fn query_hybrid(
        &self,
        collection: &str,
        dense: &[f32],
        sparse_indices: &[u32],
        sparse_values: &[f32],
        limit: usize,
        with_payload: bool,
    ) -> Result<Vec<serde_json::Value>> {
        let url = format!("{}/collections/{}/points/query", self.base_url, collection);
        let body = build_hybrid_query_body(
            dense,
            sparse_indices,
            sparse_values,
            limit,
            with_payload,
        );
        let resp = self.client.post(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("qdrant query_hybrid error {status}: {body}");
        }
        let v: serde_json::Value = resp.json().await?;
        Ok(parse_query_points(&v))
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

/// Deterministic, model-free sparse encoder (hash-TF) used at BOTH index and
/// query time so the sparse spaces agree. Returns `(indices, values)` where each
/// distinct token maps to a unique u32 index (stable blake3 hash, first 4 bytes
/// as little-endian u32) and the value is the token's term frequency.
///
/// Rules: lowercase, tokenize on non-alphanumeric (unicode-aware), drop tokens
/// shorter than 2 chars, count term frequencies, one entry per distinct token.
pub fn sparse_from_text(text: &str) -> (Vec<u32>, Vec<f32>) {
    use std::collections::HashMap;

    // Preserve first-seen order so output is fully deterministic.
    let mut order: Vec<String> = Vec::new();
    let mut counts: HashMap<String, f32> = HashMap::new();

    let lowered = text.to_lowercase();
    for token in lowered.split(|c: char| !c.is_alphanumeric()) {
        if token.chars().count() < 2 {
            continue;
        }
        let entry = counts.entry(token.to_string()).or_insert_with(|| {
            order.push(token.to_string());
            0.0
        });
        *entry += 1.0;
    }

    let mut indices = Vec::with_capacity(order.len());
    let mut values = Vec::with_capacity(order.len());
    for token in &order {
        let hash = blake3::hash(token.as_bytes());
        let idx = u32::from_le_bytes(hash.as_bytes()[0..4].try_into().unwrap());
        indices.push(idx);
        values.push(counts[token]);
    }
    (indices, values)
}

/// Build the `/points/query` request body for hybrid RRF fusion. Factored out so
/// the body shape is unit-testable without a live Qdrant.
pub fn build_hybrid_query_body(
    dense: &[f32],
    sparse_indices: &[u32],
    sparse_values: &[f32],
    limit: usize,
    with_payload: bool,
) -> serde_json::Value {
    json!({
        "prefetch": [
            { "query": dense, "using": "dense", "limit": limit * 2 },
            {
                "query": { "indices": sparse_indices, "values": sparse_values },
                "using": "text",
                "limit": limit * 2
            }
        ],
        "query": { "fusion": "rrf" },
        "limit": limit,
        "with_payload": with_payload,
        "with_vector": false,
    })
}

/// Parse the points array from a `/points/query` response. That endpoint returns
/// `{"result":{"points":[...]}}`; fall back to `{"result":[...]}` for robustness.
fn parse_query_points(v: &serde_json::Value) -> Vec<serde_json::Value> {
    if let Some(points) = v
        .get("result")
        .and_then(|r| r.get("points"))
        .and_then(|p| p.as_array())
    {
        return points.clone();
    }
    v.get("result")
        .and_then(|r| r.as_array())
        .cloned()
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sparse_from_text_is_deterministic() {
        let a = sparse_from_text("Hello world foo");
        let b = sparse_from_text("Hello world foo");
        assert_eq!(a, b);
    }

    #[test]
    fn sparse_from_text_distinct_tokens_distinct_indices() {
        let (indices, values) = sparse_from_text("alpha beta gamma");
        assert_eq!(indices.len(), 3);
        assert_eq!(values, vec![1.0, 1.0, 1.0]);
        let mut sorted = indices.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), 3, "indices must be unique per distinct token");
    }

    #[test]
    fn sparse_from_text_repeated_token_has_tf_two() {
        let (indices, values) = sparse_from_text("repeat repeat once");
        // Two distinct tokens: "repeat" (tf=2) and "once" (tf=1).
        assert_eq!(indices.len(), 2);
        // "repeat" was seen first, so it is index 0 with value 2.0.
        assert_eq!(values[0], 2.0);
        assert_eq!(values[1], 1.0);
    }

    #[test]
    fn sparse_from_text_drops_short_tokens() {
        // "a" and "I" are < 2 chars and must be dropped; "ok" stays.
        let (indices, _values) = sparse_from_text("a I ok");
        assert_eq!(indices.len(), 1);
    }

    #[test]
    fn sparse_from_text_is_case_insensitive() {
        let upper = sparse_from_text("WORD");
        let lower = sparse_from_text("word");
        assert_eq!(upper, lower);
    }

    #[test]
    fn sparse_from_text_unicode_aware() {
        // Unicode alphanumerics should be kept as token characters.
        let (indices, _values) = sparse_from_text("café über");
        assert_eq!(indices.len(), 2);
    }

    #[test]
    fn hybrid_query_body_shape() {
        let body = build_hybrid_query_body(&[0.1, 0.2], &[7, 9], &[1.0, 2.0], 5, true);
        let prefetch = body
            .get("prefetch")
            .and_then(|p| p.as_array())
            .expect("prefetch array");
        assert_eq!(prefetch.len(), 2);
        assert_eq!(prefetch[0].get("using").unwrap(), "dense");
        assert_eq!(prefetch[1].get("using").unwrap(), "text");
        assert_eq!(
            body.get("query").unwrap().get("fusion").unwrap(),
            "rrf"
        );
        // limit*2 applied to prefetch, limit to outer query.
        assert_eq!(prefetch[0].get("limit").unwrap(), 10);
        assert_eq!(body.get("limit").unwrap(), 5);
    }

    #[test]
    fn parse_query_points_handles_both_shapes() {
        let nested = json!({ "result": { "points": [ {"id": 1}, {"id": 2} ] } });
        assert_eq!(parse_query_points(&nested).len(), 2);

        let flat = json!({ "result": [ {"id": 1} ] });
        assert_eq!(parse_query_points(&flat).len(), 1);

        let empty = json!({ "status": "ok" });
        assert_eq!(parse_query_points(&empty).len(), 0);
    }
}
