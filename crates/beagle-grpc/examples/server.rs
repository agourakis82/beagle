use beagle_grpc::generated::agent_service_server::AgentServiceServer;
use beagle_grpc::tonic::transport::Server;
use beagle_grpc::AgentServiceImpl;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "0.0.0.0:50051".parse()?;
    let agent_service = AgentServiceImpl::new();

    println!("Starting gRPC server on {}", addr);
    Server::builder()
        .add_service(AgentServiceServer::new(agent_service))
        .serve(addr)
        .await?;
    Ok(())
}
