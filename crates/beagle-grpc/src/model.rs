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

    type StreamQueryStream = tokio_stream::wrappers::ReceiverStream<std::result::Result<ModelChunk, Status>>;

    async fn stream_query(
        &self,
        _request: Request<ModelQueryRequest>,
    ) -> std::result::Result<Response<Self::StreamQueryStream>, Status> {
        Err(Status::unimplemented("Streaming not yet implemented"))
    }
}

pub struct ModelClient {
    client: crate::generated::model_service_client::ModelServiceClient<tonic::transport::Channel>,
}

impl ModelClient {
    pub async fn connect(addr: impl Into<String>) -> Result<Self> {
        let client = crate::generated::model_service_client::ModelServiceClient::connect(addr.into())
            .await
            .map_err(|e| GrpcError::InternalError(e.to_string()))?;
        Ok(Self { client })
    }
}


