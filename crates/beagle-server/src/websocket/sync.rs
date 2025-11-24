use std::sync::Arc;

use beagle_hypergraph::{storage::StorageRepository, Hyperedge, HypergraphError, Node};
use futures_util::{SinkExt, StreamExt};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::{
    net::TcpStream,
    sync::broadcast::{self, error::RecvError},
};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use tracing::{debug, instrument, warn};
use uuid::Uuid;

static HUB: Lazy<SyncHub> = Lazy::new(SyncHub::default);

/// Hub global responsável por multiplexar eventos para todos os clientes conectados.
struct SyncHub {
    sender: broadcast::Sender<SyncEvent>,
}

impl Default for SyncHub {
    fn default() -> Self {
        let (sender, _) = broadcast::channel(1024);
        Self { sender }
    }
}

impl SyncHub {
    fn subscribe(&self) -> broadcast::Receiver<SyncEvent> {
        self.sender.subscribe()
    }

    fn publish(&self, event: SyncEvent) -> Result<()> {
        self.sender.send(event).map(|_| ()).map_err(SyncError::from)
    }
}

/// Resultado especializado para operações de sincronização.
pub type Result<T> = std::result::Result<T, SyncError>;

/// Eventos de sincronização suportados pelo protocolo WebSocket.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", content = "payload", rename_all = "snake_case")]
pub enum SyncEvent {
    /// Um novo nó foi criado.
    NodeCreated(Node),
    /// Um nó existente foi atualizado.
    NodeUpdated(Node),
    /// Um nó foi removido logicamente.
    NodeDeleted(NodeTombstone),
    /// Um novo hiperedge foi criado.
    HyperedgeCreated(Hyperedge),
}

/// Payload mínimo necessário para sinalizar remoção de nós.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NodeTombstone {
    pub id: Uuid,
}

/// Erros possíveis durante o processamento do protocolo de sincronização.
#[derive(Debug, Error)]
pub enum SyncError {
    #[error("falha no handshake ou transporte WebSocket: {0}")]
    WebSocket(#[from] tokio_tungstenite::tungstenite::Error),
    #[error("falha de serialização JSON: {0}")]
    Serialization(#[from] serde_json::Error),
    #[error("falha ao acessar camada de armazenamento: {0}")]
    Storage(#[from] HypergraphError),
    #[error("não foi possível publicar evento para outros clientes: {0}")]
    Broadcast(#[from] broadcast::error::SendError<SyncEvent>),
}

/// Aceita uma conexão WebSocket e gerencia o fluxo bidirecional de eventos de sincronização entre clientes.
///
/// O protocolo garante que toda mutação confirmada no armazenamento seja reenviada para todos os clientes
/// conectados, incluindo o originador da modificação, de forma ordenada e consistente.
#[instrument(skip(stream, storage), name = "websocket.sync_connection")]
pub async fn handle_sync_connection(
    stream: TcpStream,
    storage: Arc<dyn StorageRepository>,
) -> Result<()> {
    let ws_stream = accept_async(stream).await?;
    let (mut write, mut read) = ws_stream.split();
    let mut outbound = HUB.subscribe();

    loop {
        tokio::select! {
            inbound = read.next() => {
                match inbound {
                    Some(Ok(Message::Text(payload))) => {
                        let event: SyncEvent = serde_json::from_str(&payload)?;
                        process_event(event, storage.clone()).await?;
                    }
                    Some(Ok(Message::Close(frame))) => {
                        debug!(?frame, "cliente solicitou fechamento");
                        write.send(Message::Close(frame)).await.ok();
                        break;
                    }
                    Some(Ok(Message::Ping(bytes))) => {
                        write.send(Message::Pong(bytes)).await?;
                    }
                    Some(Ok(Message::Pong(_))) => {
                        // heartbeats são ignorados, pois apenas confirmam liveness.
                    }
                    Some(Ok(Message::Binary(_))) => {
                        warn!("payload binário ignorado no canal de sincronização");
                    }
                    Some(Err(err)) => return Err(err.into()),
                    None => break,
                }
            }
            outbound_event = outbound.recv() => {
                match outbound_event {
                    Ok(event) => {
                        let serialized = serde_json::to_string(&event)?;
                        write.send(Message::Text(serialized)).await?;
                    }
                    Err(RecvError::Lagged(skipped)) => {
                        warn!(skipped, "cliente atrasado perdeu eventos; reenviando estado incremental é recomendado");
                    }
                    Err(RecvError::Closed) => break,
                }
            }
        }
    }

    Ok(())
}

#[instrument(skip(storage), fields(event = ?event_variant(&event)))]
async fn process_event(event: SyncEvent, storage: Arc<dyn StorageRepository>) -> Result<()> {
    match event {
        SyncEvent::NodeCreated(node) => {
            let persisted = storage.create_node(node).await?;
            HUB.publish(SyncEvent::NodeCreated(persisted))?;
        }
        SyncEvent::NodeUpdated(node) => {
            let persisted = storage.update_node(node).await?;
            HUB.publish(SyncEvent::NodeUpdated(persisted))?;
        }
        SyncEvent::NodeDeleted(tombstone) => {
            storage.delete_node(tombstone.id).await?;
            HUB.publish(SyncEvent::NodeDeleted(tombstone))?;
        }
        SyncEvent::HyperedgeCreated(edge) => {
            let persisted = storage.create_hyperedge(edge).await?;
            HUB.publish(SyncEvent::HyperedgeCreated(persisted))?;
        }
    }

    Ok(())
}

fn event_variant(event: &SyncEvent) -> &'static str {
    match event {
        SyncEvent::NodeCreated(_) => "node_created",
        SyncEvent::NodeUpdated(_) => "node_updated",
        SyncEvent::NodeDeleted(_) => "node_deleted",
        SyncEvent::HyperedgeCreated(_) => "hyperedge_created",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use beagle_hypergraph::{
        storage::{NodeFilters, StorageRepository},
        ContentType, HealthStatus, Hyperedge, HypergraphError, Node, Result as HyperResult,
    };
    use futures_util::{SinkExt, StreamExt};
    use serde_json::json;
    use std::collections::HashSet;
    use tokio::{
        net::TcpListener,
        sync::Mutex,
        task::JoinHandle,
        time::{timeout, Duration},
    };
    use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};
    use tracing::info;
    use uuid::Uuid;

    #[derive(Default)]
    struct RecordingStorage {
        created: Mutex<Vec<Node>>,
        updated: Mutex<Vec<Node>>,
        deleted: Mutex<HashSet<Uuid>>,
        hyperedges: Mutex<Vec<Hyperedge>>,
    }

    #[async_trait]
    impl StorageRepository for RecordingStorage {
        async fn create_node(&self, node: Node) -> HyperResult<Node> {
            self.created.lock().await.push(node.clone());
            Ok(node)
        }

        async fn get_node(&self, id: Uuid) -> HyperResult<Node> {
            // Search in created nodes
            let created = self.created.lock().await;
            if let Some(node) = created.iter().find(|n| n.id == id) {
                return Ok(node.clone());
            }

            // Search in updated nodes
            let updated = self.updated.lock().await;
            if let Some(node) = updated.iter().find(|n| n.id == id) {
                return Ok(node.clone());
            }

            Err(beagle_hypergraph::HyperError::NotFound(format!(
                "Node {} not found",
                id
            )))
        }

        async fn update_node(&self, node: Node) -> HyperResult<Node> {
            self.updated.lock().await.push(node.clone());
            Ok(node)
        }

        async fn delete_node(&self, id: Uuid) -> HyperResult<()> {
            self.deleted.lock().await.insert(id);
            Ok(())
        }

        async fn list_nodes(&self, filters: Option<NodeFilters>) -> HyperResult<Vec<Node>> {
            let mut nodes = Vec::new();

            // Collect all created nodes
            nodes.extend(self.created.lock().await.iter().cloned());

            // Collect all updated nodes (deduplicate by ID)
            for node in self.updated.lock().await.iter() {
                if !nodes.iter().any(|n| n.id == node.id) {
                    nodes.push(node.clone());
                }
            }

            // Remove deleted nodes
            let deleted = self.deleted.lock().await;
            nodes.retain(|n| !deleted.contains(&n.id));

            // Apply filters if provided
            if let Some(f) = filters {
                if let Some(node_type) = f.node_type {
                    nodes.retain(|n| n.node_type == node_type);
                }
                if let Some(labels) = f.labels {
                    nodes.retain(|n| labels.iter().all(|label| n.labels.contains(label)));
                }
            }

            Ok(nodes)
        }

        async fn batch_get_nodes(&self, ids: Vec<Uuid>) -> HyperResult<Vec<Node>> {
            let mut result = Vec::new();
            for id in ids {
                match self.get_node(id).await {
                    Ok(node) => result.push(node),
                    Err(_) => continue, // Skip nodes that don't exist
                }
            }
            Ok(result)
        }

        async fn create_hyperedge(&self, edge: Hyperedge) -> HyperResult<Hyperedge> {
            self.hyperedges.lock().await.push(edge.clone());
            Ok(edge)
        }

        async fn get_hyperedge(&self, id: Uuid) -> HyperResult<Hyperedge> {
            let hyperedges = self.hyperedges.lock().await;
            hyperedges
                .iter()
                .find(|e| e.id == id)
                .cloned()
                .ok_or_else(|| {
                    beagle_hypergraph::HyperError::NotFound(format!("Hyperedge {} not found", id))
                })
        }

        async fn update_hyperedge(&self, edge: Hyperedge) -> HyperResult<Hyperedge> {
            let mut hyperedges = self.hyperedges.lock().await;
            if let Some(existing) = hyperedges.iter_mut().find(|e| e.id == edge.id) {
                *existing = edge.clone();
                Ok(edge)
            } else {
                Err(beagle_hypergraph::HyperError::NotFound(format!(
                    "Hyperedge {} not found",
                    edge.id
                )))
            }
        }

        async fn delete_hyperedge(&self, id: Uuid) -> HyperResult<()> {
            let mut hyperedges = self.hyperedges.lock().await;
            if let Some(pos) = hyperedges.iter().position(|e| e.id == id) {
                hyperedges.remove(pos);
                Ok(())
            } else {
                Err(beagle_hypergraph::HyperError::NotFound(format!(
                    "Hyperedge {} not found",
                    id
                )))
            }
        }

        async fn list_hyperedges(&self, node_id: Option<Uuid>) -> HyperResult<Vec<Hyperedge>> {
            let hyperedges = self.hyperedges.lock().await;
            match node_id {
                Some(id) => Ok(hyperedges
                    .iter()
                    .filter(|e| e.nodes.contains(&id))
                    .cloned()
                    .collect()),
                None => Ok(hyperedges.clone()),
            }
        }

        async fn query_neighborhood(
            &self,
            start_node: Uuid,
            depth: i32,
        ) -> HyperResult<Vec<(Node, i32)>> {
            let mut result = Vec::new();
            let mut visited = std::collections::HashSet::new();
            let mut queue = std::collections::VecDeque::new();

            // Start with the initial node
            if let Ok(node) = self.get_node(start_node).await {
                queue.push_back((node, 0));
                visited.insert(start_node);
            }

            while let Some((node, current_depth)) = queue.pop_front() {
                result.push((node.clone(), current_depth));

                if current_depth < depth {
                    // Find all edges connected to this node
                    let edges = self.get_edges_for_node(node.id).await?;

                    for edge in edges {
                        for &connected_id in &edge.nodes {
                            if connected_id != node.id && !visited.contains(&connected_id) {
                                if let Ok(connected_node) = self.get_node(connected_id).await {
                                    visited.insert(connected_id);
                                    queue.push_back((connected_node, current_depth + 1));
                                }
                            }
                        }
                    }
                }
            }

            Ok(result)
        }

        async fn get_connected_nodes(&self, edge_id: Uuid) -> HyperResult<Vec<Node>> {
            let edge = self.get_hyperedge(edge_id).await?;
            let mut nodes = Vec::new();

            for node_id in edge.nodes {
                if let Ok(node) = self.get_node(node_id).await {
                    nodes.push(node);
                }
            }

            Ok(nodes)
        }

        async fn get_edges_for_node(&self, node_id: Uuid) -> HyperResult<Vec<Hyperedge>> {
            self.list_hyperedges(Some(node_id)).await
        }

        async fn semantic_search(
            &self,
            _query_embedding: Vec<f32>,
            limit: usize,
            _threshold: f32,
        ) -> HyperResult<Vec<(Node, f32)>> {
            // For test mock, just return all nodes with dummy scores
            let nodes = self.list_nodes(None).await?;
            let result = nodes
                .into_iter()
                .take(limit)
                .map(|n| (n, 0.9)) // Dummy similarity score
                .collect();
            Ok(result)
        }

        async fn health_check(&self) -> HyperResult<HealthStatus> {
            Ok(HealthStatus {
                healthy: true,
                latency_ms: 0,
                pool_size: 0,
                idle_connections: 0,
            })
        }

        async fn with_transaction<F, Fut, T>(&self, f: F) -> HyperResult<T>
        where
            F: FnOnce(&Self) -> Fut + Send,
            Fut: std::future::Future<Output = HyperResult<T>> + Send,
            T: Send,
        {
            f(self).await
        }
    }

    #[tokio::test]
    async fn broadcast_node_created_between_clients() {
        let backend = Arc::new(RecordingStorage::default());
        let storage: Arc<dyn StorageRepository> = backend.clone();

        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind listener");
        let addr = listener.local_addr().expect("local addr");
        let storage_for_accept = storage.clone();

        let server: JoinHandle<()> = tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, _)) => {
                        let storage_conn = storage_for_accept.clone();
                        tokio::spawn(async move {
                            if let Err(err) = handle_sync_connection(stream, storage_conn).await {
                                info!(error = ?err, "conexão de sincronização finalizada com erro");
                            }
                        });
                    }
                    Err(_) => break,
                }
            }
        });

        let url = format!("ws://{}", addr);
        let (mut client_a, _) = connect_async(&url).await.expect("connect client A");
        let (mut client_b, _) = connect_async(&url).await.expect("connect client B");

        let node = Node::builder()
            .content("Insight distribuído")
            .content_type(ContentType::Thought)
            .metadata(json!({"priority": 1}))
            .device_id("device-alpha")
            .build()
            .expect("node válido");

        let event = SyncEvent::NodeCreated(node.clone());
        client_a
            .send(Message::Text(
                serde_json::to_string(&event).expect("serialize event"),
            ))
            .await
            .expect("enviar evento");

        let received = timeout(Duration::from_millis(100), client_b.next())
            .await
            .expect("evento deveria chegar em <100ms")
            .expect("mensagem presente")
            .expect("payload válido");

        match received {
            Message::Text(payload) => {
                let parsed: SyncEvent =
                    serde_json::from_str(&payload).expect("payload decodificável");
                match parsed {
                    SyncEvent::NodeCreated(received_node) => {
                        assert_eq!(received_node.content, node.content);
                        assert_eq!(received_node.device_id, node.device_id);
                    }
                    other => panic!("esperava NodeCreated, recebi {other:?}"),
                }
            }
            other => panic!("esperava mensagem textual, recebi {other:?}"),
        }

        let created = backend.created.lock().await;
        assert_eq!(created.len(), 1, "deveria persistir exatamente um nó");

        server.abort();
    }
}
