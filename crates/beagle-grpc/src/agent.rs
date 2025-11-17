use crate::generated::agent_service_server::AgentService;
use crate::generated::*;
use crate::{GrpcError, Result};
use tonic::{Request, Response, Status};

/// Agent service implementation
pub struct AgentServiceImpl {}

impl AgentServiceImpl {
    pub fn new() -> Self {
        Self {}
    }
}

#[tonic::async_trait]
impl AgentService for AgentServiceImpl {
    async fn dispatch_task(
        &self,
        request: Request<DispatchTaskRequest>,
    ) -> std::result::Result<Response<DispatchTaskResponse>, Status> {
        let req = request.into_inner();
        tracing::info!(
            agent_id = %req.agent_id,
            task_id = %req.task_id,
            "Dispatching task"
        );
        Ok(Response::new(DispatchTaskResponse {
            task_id: req.task_id,
            status: "queued".to_string(),
        }))
    }

    async fn get_agent_status(
        &self,
        request: Request<GetAgentStatusRequest>,
    ) -> std::result::Result<Response<AgentStatus>, Status> {
        let req = request.into_inner();
        Ok(Response::new(AgentStatus {
            agent_id: req.agent_id.clone(),
            state: "idle".to_string(),
            tasks_completed: 0,
            tasks_failed: 0,
            current_task_id: String::new(),
        }))
    }

    type StreamAgentOutputStream =
        tokio_stream::wrappers::ReceiverStream<std::result::Result<AgentOutput, Status>>;

    async fn stream_agent_output(
        &self,
        _request: Request<StreamAgentOutputRequest>,
    ) -> std::result::Result<Response<Self::StreamAgentOutputStream>, Status> {
        Err(Status::unimplemented("Streaming not yet implemented"))
    }
}

/// Agent gRPC client
pub struct AgentClient {
    client: crate::generated::agent_service_client::AgentServiceClient<tonic::transport::Channel>,
}

impl AgentClient {
    pub async fn connect(addr: impl Into<String>) -> Result<Self> {
        let client =
            crate::generated::agent_service_client::AgentServiceClient::connect(addr.into())
                .await
                .map_err(|e| GrpcError::InternalError(e.to_string()))?;
        Ok(Self { client })
    }

    pub async fn dispatch_task(
        &mut self,
        agent_id: String,
        task_id: String,
        task_type: String,
        parameters: std::collections::HashMap<String, String>,
    ) -> Result<DispatchTaskResponse> {
        let request = tonic::Request::new(DispatchTaskRequest {
            agent_id,
            task_id,
            task_type,
            parameters,
        });
        let response = self
            .client
            .dispatch_task(request)
            .await
            .map_err(|e| GrpcError::InternalError(e.to_string()))?;
        Ok(response.into_inner())
    }

    pub async fn get_agent_status(&mut self, agent_id: String) -> Result<AgentStatus> {
        let request = tonic::Request::new(GetAgentStatusRequest { agent_id });
        let response = self
            .client
            .get_agent_status(request)
            .await
            .map_err(|e| GrpcError::InternalError(e.to_string()))?;
        Ok(response.into_inner())
    }
}
