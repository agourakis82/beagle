use crate::generated::model_service_server::ModelService;
use crate::generated::*;
use crate::{GrpcError, Result};
use tonic::{Request, Response, Status};

pub struct ModelServiceImpl {}

impl ModelServiceImpl {
    pub fn new() -> Self {
        Self {}
    }
}

#[tonic::async_trait]
impl ModelService for ModelServiceImpl {
    async fn query(
        &self,
        request: Request<ModelQueryRequest>,
    ) -> std::result::Result<Response<ModelQueryResponse>, Status> {
        let req = request.into_inner();
        Ok(Response::new(ModelQueryResponse {
            response: format!("Echo: {}", req.prompt),
            tokens_used: 0,
            latency_ms: 0.0,
        }))
    }

    type StreamQueryStream =
        tokio_stream::wrappers::ReceiverStream<std::result::Result<ModelChunk, Status>>;

    async fn stream_query(
        &self,
        request: Request<ModelQueryRequest>,
    ) -> std::result::Result<Response<Self::StreamQueryStream>, Status> {
        let req = request.into_inner();

        let response_text = format!("Echo: {}", req.prompt);
        let chunk_size = req
            .parameters
            .get("chunk_size")
            .and_then(|v| v.parse::<usize>().ok())
            .unwrap_or(64)
            .max(1);

        let (tx, rx) = tokio::sync::mpsc::channel(32);

        tokio::spawn(async move {
            let bytes = response_text.as_bytes();
            for (idx, chunk) in bytes.chunks(chunk_size).enumerate() {
                let content = String::from_utf8_lossy(chunk).to_string();
                let is_final = idx == (bytes.len().saturating_sub(1) / chunk_size);
                let msg = ModelChunk { content, is_final };
                if tx.send(Ok(msg)).await.is_err() {
                    return;
                }
            }
        });

        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }
}

pub struct ModelClient {
    client: crate::generated::model_service_client::ModelServiceClient<tonic::transport::Channel>,
}

impl ModelClient {
    pub async fn connect(addr: impl Into<String>) -> Result<Self> {
        let client =
            crate::generated::model_service_client::ModelServiceClient::connect(addr.into())
                .await
                .map_err(|e| GrpcError::InternalError(e.to_string()))?;
        Ok(Self { client })
    }
}
