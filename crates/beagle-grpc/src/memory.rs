use crate::generated::memory_service_server::MemoryService;
use crate::generated::*;
use crate::{GrpcError, Result};
use tonic::{Request, Response, Status};

pub struct MemoryServiceImpl {}

impl MemoryServiceImpl {
    pub fn new() -> Self {
        Self {}
    }
}

#[tonic::async_trait]
impl MemoryService for MemoryServiceImpl {
    async fn store_memory(
        &self,
        request: Request<StoreMemoryRequest>,
    ) -> std::result::Result<Response<StoreMemoryResponse>, Status> {
        let _req = request.into_inner();
        Ok(Response::new(StoreMemoryResponse {
            memory_id: "mem-1".into(),
            success: true,
        }))
    }

    async fn retrieve_memory(
        &self,
        request: Request<RetrieveMemoryRequest>,
    ) -> std::result::Result<Response<MemoryEntry>, Status> {
        let req = request.into_inner();
        Ok(Response::new(MemoryEntry {
            memory_id: req.memory_id,
            content: String::new(),
            metadata: Default::default(),
            embedding: vec![],
            created_at: 0,
        }))
    }

    async fn semantic_search(
        &self,
        _request: Request<SemanticSearchRequest>,
    ) -> std::result::Result<Response<SemanticSearchResponse>, Status> {
        Ok(Response::new(SemanticSearchResponse { results: vec![] }))
    }
}

pub struct MemoryClient {
    client: crate::generated::memory_service_client::MemoryServiceClient<tonic::transport::Channel>,
}

impl MemoryClient {
    pub async fn connect(addr: impl Into<String>) -> Result<Self> {
        let client =
            crate::generated::memory_service_client::MemoryServiceClient::connect(addr.into())
                .await
                .map_err(|e| GrpcError::InternalError(e.to_string()))?;
        Ok(Self { client })
    }
}
