use anyhow::{Context, Result};
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use reqwest::{Client, Method};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::Duration;

pub const DEFAULT_DARWIN_HPC_GATEWAY_BASE_URL: &str =
    "http://darwin-hpc-gateway.darwin-platform.svc.cluster.local";
const DEFAULT_GATEWAY_TIMEOUT_SECONDS: u64 = 30;

#[derive(Debug, Clone)]
pub struct DarwinHpcGatewayClient {
    client: Client,
    base_url: String,
}

#[derive(Debug, Clone)]
pub struct DarwinHpcGatewayError {
    pub status_code: Option<u16>,
    pub message: String,
}

impl std::fmt::Display for DarwinHpcGatewayError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if let Some(status_code) = self.status_code {
            write!(f, "darwin hpc gateway error {}: {}", status_code, self.message)
        } else {
            write!(f, "darwin hpc gateway error: {}", self.message)
        }
    }
}

impl std::error::Error for DarwinHpcGatewayError {}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HpcProfileCatalog {
    #[serde(default)]
    pub profiles: Vec<HpcProfile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HpcProfile {
    pub id: String,
    #[serde(default)]
    pub description: String,
    pub kind: String,
    #[serde(default)]
    pub single_node: bool,
    #[serde(default)]
    pub gpu: bool,
    pub partition: String,
    pub max_walltime: String,
    pub artifact_mode: String,
    #[serde(default)]
    pub allowed_parameters: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HpcSubmitRequest {
    pub profile_id: String,
    #[serde(default)]
    pub parameters: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HpcSubmitResponse {
    pub job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub job_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partition: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub remote_workdir: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub submitted_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HpcJobStatus {
    pub job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub job_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partition: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node_list: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub submit_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_ready: Option<bool>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ResultCatalogQuery {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node_list: Option<String>,
}

impl ResultCatalogQuery {
    pub fn as_query_pairs(&self) -> Vec<(String, String)> {
        let mut pairs = Vec::new();

        if let Some(profile_id) = &self.profile_id {
            pairs.push(("profile_id".to_string(), profile_id.clone()));
        }
        if let Some(run_label) = &self.run_label {
            pairs.push(("run_label".to_string(), run_label.clone()));
        }
        if let Some(state) = &self.state {
            pairs.push(("state".to_string(), state.clone()));
        }
        if let Some(node_list) = &self.node_list {
            pairs.push(("node_list".to_string(), node_list.clone()));
        }

        pairs
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResultCatalogResponse {
    pub catalog_format: String,
    #[serde(default)]
    pub filters: Value,
    pub result_source: String,
    #[serde(default)]
    pub results: Vec<ResultCatalogEntry>,
    pub total: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResultCatalogEntry {
    pub artifact_bucket: String,
    pub artifact_manifest_key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_object_key: Option<String>,
    pub artifact_prefix: String,
    pub artifact_sha256: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
    pub job_id: u64,
    pub job_name: String,
    pub node_list: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partition: Option<String>,
    pub profile_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publication_time: Option<String>,
    pub retention_scope: String,
    pub run_label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_phase: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_time: Option<String>,
    pub state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub submit_time: Option<String>,
}

impl DarwinHpcGatewayClient {
    pub fn from_env() -> Result<Self> {
        let base_url =
            std::env::var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL").unwrap_or_else(|_| {
                DEFAULT_DARWIN_HPC_GATEWAY_BASE_URL.to_string()
            });

        let timeout_seconds = std::env::var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(DEFAULT_GATEWAY_TIMEOUT_SECONDS);

        let mut headers = HeaderMap::new();
        if let Some((name, value)) = parse_optional_header(
            std::env::var("BEAGLE_DARWIN_HPC_GATEWAY_AUTH_HEADER").ok(),
        )? {
            headers.insert(name, value);
        }

        let client = Client::builder()
            .default_headers(headers)
            .timeout(Duration::from_secs(timeout_seconds))
            .build()
            .context("failed to build Darwin HPC gateway HTTP client")?;

        Ok(Self {
            client,
            base_url: base_url.trim_end_matches('/').to_string(),
        })
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    pub async fn profiles(&self) -> std::result::Result<HpcProfileCatalog, DarwinHpcGatewayError> {
        self.request_json(Method::GET, "/profiles", None::<&()>, None)
            .await
    }

    pub async fn submit_job(
        &self,
        request: &HpcSubmitRequest,
    ) -> std::result::Result<HpcSubmitResponse, DarwinHpcGatewayError> {
        self.request_json(Method::POST, "/jobs/submit", Some(request), None)
            .await
    }

    pub async fn job_status(
        &self,
        job_id: u64,
    ) -> std::result::Result<HpcJobStatus, DarwinHpcGatewayError> {
        self.request_json(
            Method::GET,
            &format!("/jobs/{job_id}"),
            None::<&()>,
            None,
        )
        .await
    }

    pub async fn results(
        &self,
        query: &ResultCatalogQuery,
    ) -> std::result::Result<ResultCatalogResponse, DarwinHpcGatewayError> {
        let query_pairs = query.as_query_pairs();
        self.request_json(
            Method::GET,
            "/results",
            None::<&()>,
            Some(query_pairs.as_slice()),
        )
        .await
    }

    pub async fn result_by_job(
        &self,
        job_id: u64,
    ) -> std::result::Result<ResultCatalogEntry, DarwinHpcGatewayError> {
        self.request_json(
            Method::GET,
            &format!("/results/{job_id}"),
            None::<&()>,
            None,
        )
        .await
    }

    pub(crate) async fn request_json<Req, Resp>(
        &self,
        method: Method,
        path: &str,
        body: Option<&Req>,
        query: Option<&[(String, String)]>,
    ) -> std::result::Result<Resp, DarwinHpcGatewayError>
    where
        Req: Serialize + ?Sized,
        Resp: DeserializeOwned,
    {
        let response = self.request(method, path, body, query).await?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(|error| DarwinHpcGatewayError {
            status_code: Some(status.as_u16()),
            message: format!("failed to read gateway response body: {error}"),
        })?;

        if !status.is_success() {
            return Err(build_error_from_bytes(status, &bytes));
        }

        serde_json::from_slice::<Resp>(&bytes).map_err(|error| DarwinHpcGatewayError {
            status_code: Some(status.as_u16()),
            message: format!("failed to decode gateway JSON response: {error}"),
        })
    }

    pub(crate) async fn request_text<Req>(
        &self,
        method: Method,
        path: &str,
        body: Option<&Req>,
        query: Option<&[(String, String)]>,
    ) -> std::result::Result<String, DarwinHpcGatewayError>
    where
        Req: Serialize + ?Sized,
    {
        let response = self.request(method, path, body, query).await?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(|error| DarwinHpcGatewayError {
            status_code: Some(status.as_u16()),
            message: format!("failed to read gateway response body: {error}"),
        })?;

        if !status.is_success() {
            return Err(build_error_from_bytes(status, &bytes));
        }

        String::from_utf8(bytes.to_vec()).map_err(|error| DarwinHpcGatewayError {
            status_code: Some(status.as_u16()),
            message: format!("gateway text response was not valid UTF-8: {error}"),
        })
    }

    async fn request<Req>(
        &self,
        method: Method,
        path: &str,
        body: Option<&Req>,
        query: Option<&[(String, String)]>,
    ) -> std::result::Result<reqwest::Response, DarwinHpcGatewayError>
    where
        Req: Serialize + ?Sized,
    {
        let url = format!("{}{}", self.base_url, path);
        let mut request = self.client.request(method, &url);

        if let Some(query_pairs) = query {
            request = request.query(query_pairs);
        }

        if let Some(body_value) = body {
            request = request.json(body_value);
        }

        request.send().await.map_err(|error| DarwinHpcGatewayError {
            status_code: None,
            message: format!("request to Darwin HPC gateway failed: {error}"),
        })
    }
}

fn parse_optional_header(
    raw: Option<String>,
) -> Result<Option<(HeaderName, HeaderValue)>> {
    let Some(raw) = raw.map(|value| value.trim().to_string()) else {
        return Ok(None);
    };

    if raw.is_empty() {
        return Ok(None);
    }

    let (name, value) = raw
        .split_once(':')
        .ok_or_else(|| anyhow::anyhow!("invalid BEAGLE_DARWIN_HPC_GATEWAY_AUTH_HEADER"))?;

    let header_name = HeaderName::from_bytes(name.trim().as_bytes())
        .context("invalid auth header name for Darwin HPC gateway")?;
    let header_value = HeaderValue::from_str(value.trim())
        .context("invalid auth header value for Darwin HPC gateway")?;

    Ok(Some((header_name, header_value)))
}

fn build_error_from_bytes(status: reqwest::StatusCode, bytes: &[u8]) -> DarwinHpcGatewayError {
    let text = String::from_utf8_lossy(bytes).trim().to_string();
    if text.is_empty() {
        return DarwinHpcGatewayError {
            status_code: Some(status.as_u16()),
            message: format!("gateway returned HTTP {}", status.as_u16()),
        };
    }

    if let Ok(value) = serde_json::from_slice::<Value>(bytes) {
        return DarwinHpcGatewayError {
            status_code: Some(status.as_u16()),
            message: value.to_string(),
        };
    }

    DarwinHpcGatewayError {
        status_code: Some(status.as_u16()),
        message: text,
    }
}
