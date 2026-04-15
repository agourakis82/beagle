use crate::result_catalog::{DarwinHpcGatewayClient, DarwinHpcGatewayError};
use reqwest::Method;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobArtifactManifest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_mime_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_sha256: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_size: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cleanup_boundary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
    pub job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub job_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node_list: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retention_scope: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stderr_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stdout_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub submit_time: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectPublishedArtifact {
    pub artifact_kind: String,
    pub content_type: String,
    pub object_key: String,
    pub published_checksum: String,
    pub size_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectResultManifest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_source: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gateway_retrieval_time: Option<String>,
    pub job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub job_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub manifest_format: Option<String>,
    pub manifest_object_key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node_list: Option<String>,
    pub object_bucket: String,
    pub object_key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub object_manifest_resolved_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub object_retrieval_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partition: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publication_target_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publication_time: Option<String>,
    pub published_checksum: String,
    #[serde(default)]
    pub published_objects: Vec<ObjectPublishedArtifact>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_source: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_manifest_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_phase: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_time: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub submit_time: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HpcTextArtifact {
    pub job_id: u64,
    pub stream: String,
    pub text: String,
}

impl DarwinHpcGatewayClient {
    pub async fn job_artifact_manifest(
        &self,
        job_id: u64,
    ) -> std::result::Result<JobArtifactManifest, DarwinHpcGatewayError> {
        self.request_json(
            Method::GET,
            &format!("/jobs/{job_id}/artifact-manifest"),
            None::<&()>,
            None,
        )
        .await
    }

    pub async fn result_manifest(
        &self,
        job_id: u64,
    ) -> std::result::Result<ObjectResultManifest, DarwinHpcGatewayError> {
        self.request_json(
            Method::GET,
            &format!("/results/{job_id}/manifest"),
            None::<&()>,
            None,
        )
        .await
    }

    pub async fn job_stdout(
        &self,
        job_id: u64,
    ) -> std::result::Result<HpcTextArtifact, DarwinHpcGatewayError> {
        let text = self
            .request_text(
                Method::GET,
                &format!("/jobs/{job_id}/stdout"),
                None::<&()>,
                None,
            )
            .await?;

        Ok(HpcTextArtifact {
            job_id,
            stream: "stdout".to_string(),
            text,
        })
    }

    pub async fn job_stderr(
        &self,
        job_id: u64,
    ) -> std::result::Result<HpcTextArtifact, DarwinHpcGatewayError> {
        let text = self
            .request_text(
                Method::GET,
                &format!("/jobs/{job_id}/stderr"),
                None::<&()>,
                None,
            )
            .await?;

        Ok(HpcTextArtifact {
            job_id,
            stream: "stderr".to_string(),
            text,
        })
    }
}
