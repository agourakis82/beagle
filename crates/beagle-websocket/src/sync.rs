// Real-time synchronization engine with CRDT support and event ordering
//
// References:
// - Shapiro, M., et al. (2011). Conflict-free replicated data types. SSS 2011.
// - Almeida, P. S., et al. (2018). Delta state replicated data types. JPDC.
// - Lamport, L. (1978). Time, clocks, and the ordering of events. CACM.
// - Mattern, F. (1989). Virtual time and global states. Workshop on Parallel.
// - Bailis, P., & Ghodsi, A. (2013). Eventual consistency today. CACM.
// - Terry, D. (2013). Replicated data consistency explained through baseball. CACM.

use crate::{Result, WebSocketError};
use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, TieredRouter};
use beagle_metrics::MetricsCollector;

use std::sync::Arc;
use std::collections::{HashMap, BTreeMap, VecDeque, HashSet};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{RwLock, Mutex, mpsc, broadcast, watch, Semaphore};
use tokio::time::{interval, sleep};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use bytes::Bytes;
use dashmap::DashMap;
use parking_lot::RwLock as PLRwLock;
use tracing::{debug, info, warn, error, instrument, span, Level};

// ========================= CRDT Types =========================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VectorClock {
    entries: HashMap<String, u64>,
}

impl VectorClock {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    pub fn increment(&mut self, node_id: &str) {
        *self.entries.entry(node_id.to_string()).or_insert(0) += 1;
    }

    pub fn merge(&mut self, other: &VectorClock) {
        for (node, &timestamp) in &other.entries {
            self.entries
                .entry(node.clone())
                .and_modify(|t| *t = (*t).max(timestamp))
                .or_insert(timestamp);
        }
    }

    pub fn happens_before(&self, other: &VectorClock) -> bool {
        self.entries.iter().all(|(node, &ts)| {
            other.entries.get(node).map_or(false, |&other_ts| ts <= other_ts)
        })
    }

    pub fn concurrent_with(&self, other: &VectorClock) -> bool {
        !self.happens_before(other) && !other.happens_before(self)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LWWRegister<T: Clone> {
    value: T,
    timestamp: u64,
    node_id: String,
}

impl<T: Clone> LWWRegister<T> {
    pub fn new(value: T, node_id: String) -> Self {
        Self {
            value,
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_micros() as u64,
            node_id,
        }
    }

    pub fn merge(&mut self, other: &LWWRegister<T>) {
        if other.timestamp > self.timestamp ||
           (other.timestamp == self.timestamp && other.node_id > self.node_id) {
            self.value = other.value.clone();
            self.timestamp = other.timestamp;
            self.node_id = other.node_id.clone();
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GCounter {
    counts: HashMap<String, u64>,
}

impl GCounter {
    pub fn new() -> Self {
        Self {
            counts: HashMap::new(),
        }
    }

    pub fn increment(&mut self, node_id: &str, amount: u64) {
        *self.counts.entry(node_id.to_string()).or_insert(0) += amount;
    }

    pub fn value(&self) -> u64 {
        self.counts.values().sum()
    }

    pub fn merge(&mut self, other: &GCounter) {
        for (node, &count) in &other.counts {
            self.counts
                .entry(node.clone())
                .and_modify(|c| *c = (*c).max(count))
                .or_insert(count);
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ORSet<T: Clone + Eq + std::hash::Hash> {
    adds: HashMap<T, HashSet<Uuid>>,
    removes: HashSet<Uuid>,
}

impl<T: Clone + Eq + std::hash::Hash> ORSet<T> {
    pub fn new() -> Self {
        Self {
            adds: HashMap::new(),
            removes: HashSet::new(),
        }
    }

    pub fn add(&mut self, element: T) -> Uuid {
        let unique_id = Uuid::new_v4();
        self.adds
            .entry(element)
            .or_insert_with(HashSet::new)
            .insert(unique_id);
        unique_id
    }

    pub fn remove(&mut self, element: &T) {
        if let Some(ids) = self.adds.get(element) {
            for id in ids {
                self.removes.insert(*id);
            }
        }
    }

    pub fn contains(&self, element: &T) -> bool {
        self.adds.get(element).map_or(false, |ids| {
            ids.iter().any(|id| !self.removes.contains(id))
        })
    }

    pub fn merge(&mut self, other: &ORSet<T>) {
        // Merge adds
        for (element, ids) in &other.adds {
            self.adds
                .entry(element.clone())
                .or_insert_with(HashSet::new)
                .extend(ids);
        }

        // Merge removes
        self.removes.extend(&other.removes);
    }
}

// ========================= Event Ordering =========================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub id: Uuid,
    pub timestamp: u64,
    pub vector_clock: VectorClock,
    pub node_id: String,
    pub payload: Vec<u8>,
    pub dependencies: Vec<Uuid>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug)]
pub struct EventOrdering {
    events: Arc<RwLock<BTreeMap<u64, Vec<Event>>>>,
    pending: Arc<RwLock<HashMap<Uuid, Event>>>,
    delivered: Arc<RwLock<HashSet<Uuid>>>,
    vector_clocks: Arc<RwLock<HashMap<String, VectorClock>>>,
    max_pending: usize,
    ordering_timeout: Duration,
}

impl EventOrdering {
    pub fn new(max_pending: usize, ordering_timeout: Duration) -> Self {
        Self {
            events: Arc::new(RwLock::new(BTreeMap::new())),
            pending: Arc::new(RwLock::new(HashMap::new())),
            delivered: Arc::new(RwLock::new(HashSet::new())),
            vector_clocks: Arc::new(RwLock::new(HashMap::new())),
            max_pending,
            ordering_timeout,
        }
    }

    #[instrument(skip(self, event))]
    pub async fn submit_event(&self, event: Event) -> Result<()> {
        let mut pending = self.pending.write().await;

        if pending.len() >= self.max_pending {
            return Err(WebSocketError::BackpressureLimit);
        }

        // Check if dependencies are satisfied
        let delivered = self.delivered.read().await;
        let deps_satisfied = event.dependencies.iter()
            .all(|dep| delivered.contains(dep));

        if deps_satisfied {
            // Can deliver immediately
            drop(delivered);
            self.deliver_event(event).await?;
        } else {
            // Add to pending
            pending.insert(event.id, event);
        }

        Ok(())
    }

    async fn deliver_event(&self, event: Event) -> Result<()> {
        let mut events = self.events.write().await;
        events.entry(event.timestamp)
            .or_insert_with(Vec::new)
            .push(event.clone());

        let mut delivered = self.delivered.write().await;
        delivered.insert(event.id);

        // Update vector clock
        let mut clocks = self.vector_clocks.write().await;
        let clock = clocks.entry(event.node_id.clone())
            .or_insert_with(VectorClock::new);
        clock.merge(&event.vector_clock);

        // Check if any pending events can now be delivered
        drop(clocks);
        drop(delivered);
        drop(events);
        self.check_pending_deliveries().await?;

        Ok(())
    }

    async fn check_pending_deliveries(&self) -> Result<()> {
        let mut pending = self.pending.write().await;
        let delivered = self.delivered.read().await;

        let mut to_deliver = Vec::new();

        for (id, event) in pending.iter() {
            let deps_satisfied = event.dependencies.iter()
                .all(|dep| delivered.contains(dep));

            if deps_satisfied {
                to_deliver.push(*id);
            }
        }

        for id in to_deliver {
            if let Some(event) = pending.remove(&id) {
                drop(pending);
                drop(delivered);
                self.deliver_event(event).await?;
                pending = self.pending.write().await;
            }
        }

        Ok(())
    }

    pub async fn get_ordered_events(&self, since: u64) -> Vec<Event> {
        let events = self.events.read().await;
        events.range(since..)
            .flat_map(|(_, events)| events.clone())
            .collect()
    }
}

// ========================= Conflict Resolution =========================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConflictResolution {
    LastWriteWins,
    MultiValueRegister,
    Custom(String),
    SemanticMerge,
}

pub struct ConflictResolver {
    strategy: ConflictResolution,
    context: Arc<BeagleContext>,
    conflict_log: Arc<RwLock<Vec<ConflictRecord>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConflictRecord {
    pub id: Uuid,
    pub timestamp: u64,
    pub conflicting_values: Vec<Vec<u8>>,
    pub resolution: Vec<u8>,
    pub strategy_used: ConflictResolution,
    pub metadata: HashMap<String, String>,
}

impl ConflictResolver {
    pub fn new(strategy: ConflictResolution, context: Arc<BeagleContext>) -> Self {
        Self {
            strategy,
            context,
            conflict_log: Arc::new(RwLock::new(Vec::new())),
        }
    }

    #[instrument(skip(self, values))]
    pub async fn resolve(&self, values: Vec<Vec<u8>>) -> Result<Vec<u8>> {
        match &self.strategy {
            ConflictResolution::LastWriteWins => {
                // Simple: take the last value
                values.last()
                    .cloned()
                    .ok_or_else(|| WebSocketError::SyncError("No values to resolve".into()))
            }

            ConflictResolution::MultiValueRegister => {
                // Return all values for client to resolve
                let combined = serde_json::to_vec(&values)
                    .map_err(|e| WebSocketError::CodecError(e.to_string()))?;
                Ok(combined)
            }

            ConflictResolution::SemanticMerge => {
                // Use LLM to semantically merge values
                self.semantic_merge(values).await
            }

            ConflictResolution::Custom(strategy_name) => {
                // Custom strategy implementation
                self.custom_resolve(strategy_name, values).await
            }
        }
    }

    async fn semantic_merge(&self, values: Vec<Vec<u8>>) -> Result<Vec<u8>> {
        // Prepare values for LLM analysis
        let mut text_values = Vec::new();
        for value in &values {
            if let Ok(text) = String::from_utf8(value.clone()) {
                text_values.push(text);
            }
        }

        if text_values.is_empty() {
            return Ok(values.last().unwrap().clone());
        }

        // Use TieredRouter for semantic merge
        let prompt = format!(
            "Semantically merge these conflicting values into a single coherent result:\n\n{}",
            text_values.iter()
                .enumerate()
                .map(|(i, v)| format!("Version {}: {}", i + 1, v))
                .collect::<Vec<_>>()
                .join("\n\n")
        );

        let meta = RequestMeta {
            requires_high_quality: true,
            requires_semantic_understanding: true,
            ..Default::default()
        };

        let router = &self.context.router;
        let stats = beagle_llm::LlmCallStats::default();
        let (client, _tier) = router.choose_with_limits(&meta, &stats)
            .map_err(|e| WebSocketError::SyncError(e.to_string()))?;

        let response = client.complete(&prompt).await
            .map_err(|e| WebSocketError::SyncError(e.to_string()))?;

        Ok(response.content.into_bytes())
    }

    async fn custom_resolve(&self, strategy: &str, values: Vec<Vec<u8>>) -> Result<Vec<u8>> {
        // Implement custom resolution strategies
        match strategy {
            "numeric_sum" => {
                let mut sum = 0i64;
                for value in &values {
                    if let Ok(s) = String::from_utf8(value.clone()) {
                        if let Ok(n) = s.parse::<i64>() {
                            sum += n;
                        }
                    }
                }
                Ok(sum.to_string().into_bytes())
            }

            "set_union" => {
                let mut union = HashSet::new();
                for value in &values {
                    if let Ok(items) = serde_json::from_slice::<Vec<String>>(&value) {
                        union.extend(items);
                    }
                }
                let result: Vec<String> = union.into_iter().collect();
                serde_json::to_vec(&result)
                    .map_err(|e| WebSocketError::CodecError(e.to_string()))
            }

            _ => {
                // Fallback to last-write-wins
                values.last()
                    .cloned()
                    .ok_or_else(|| WebSocketError::SyncError("No values to resolve".into()))
            }
        }
    }

    pub async fn log_conflict(&self, record: ConflictRecord) {
        let mut log = self.conflict_log.write().await;
        log.push(record);

        // Keep only recent conflicts
        if log.len() > 10000 {
            log.drain(0..5000);
        }
    }
}

// ========================= Sync Strategy =========================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SyncStrategy {
    Optimistic,      // Apply immediately, resolve conflicts later
    Pessimistic,     // Lock before applying
    Eventual,        // Eventually consistent
    Causal,          // Respect causality
    Hybrid,          // Combine strategies based on operation type
}

pub struct SyncEngine {
    strategy: SyncStrategy,
    context: Arc<BeagleContext>,
    event_ordering: Arc<EventOrdering>,
    conflict_resolver: Arc<ConflictResolver>,
    state_vector: Arc<RwLock<HashMap<String, VectorClock>>>,
    operation_log: Arc<RwLock<VecDeque<SyncOperation>>>,
    sync_interval: Duration,
    max_batch_size: usize,
    metrics: Arc<WebSocketMetrics>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncOperation {
    pub id: Uuid,
    pub operation_type: OperationType,
    pub target: String,
    pub payload: Vec<u8>,
    pub vector_clock: VectorClock,
    pub timestamp: u64,
    pub source_node: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OperationType {
    Create,
    Update,
    Delete,
    Merge,
    Custom(String),
}

impl SyncEngine {
    pub fn new(
        strategy: SyncStrategy,
        context: Arc<BeagleContext>,
        sync_interval: Duration,
        max_batch_size: usize,
        metrics: Arc<WebSocketMetrics>,
    ) -> Self {
        let event_ordering = Arc::new(EventOrdering::new(10000, Duration::from_secs(30)));
        let conflict_resolver = Arc::new(ConflictResolver::new(
            ConflictResolution::SemanticMerge,
            context.clone(),
        ));

        Self {
            strategy,
            context,
            event_ordering,
            conflict_resolver,
            state_vector: Arc::new(RwLock::new(HashMap::new())),
            operation_log: Arc::new(RwLock::new(VecDeque::with_capacity(100000))),
            sync_interval,
            max_batch_size,
            metrics,
        }
    }

    #[instrument(skip(self))]
    pub async fn start(&self) {
        let sync_interval = self.sync_interval;
        let engine = self.clone();

        tokio::spawn(async move {
            let mut interval = interval(sync_interval);

            loop {
                interval.tick().await;

                if let Err(e) = engine.sync_batch().await {
                    error!("Sync batch failed: {}", e);
                }
            }
        });
    }

    #[instrument(skip(self, operation))]
    pub async fn apply_operation(&self, operation: SyncOperation) -> Result<()> {
        match self.strategy {
            SyncStrategy::Optimistic => {
                self.apply_optimistic(operation).await
            }

            SyncStrategy::Pessimistic => {
                self.apply_pessimistic(operation).await
            }

            SyncStrategy::Eventual => {
                self.apply_eventual(operation).await
            }

            SyncStrategy::Causal => {
                self.apply_causal(operation).await
            }

            SyncStrategy::Hybrid => {
                self.apply_hybrid(operation).await
            }
        }
    }

    async fn apply_optimistic(&self, operation: SyncOperation) -> Result<()> {
        // Apply immediately
        self.execute_operation(&operation).await?;

        // Log for later reconciliation
        let mut log = self.operation_log.write().await;
        log.push_back(operation.clone());

        if log.len() > 100000 {
            log.drain(0..50000);
        }

        // Submit to event ordering
        let event = Event {
            id: operation.id,
            timestamp: operation.timestamp,
            vector_clock: operation.vector_clock.clone(),
            node_id: operation.source_node.clone(),
            payload: operation.payload.clone(),
            dependencies: Vec::new(),
            metadata: HashMap::new(),
        };

        self.event_ordering.submit_event(event).await?;

        Ok(())
    }

    async fn apply_pessimistic(&self, operation: SyncOperation) -> Result<()> {
        // Acquire lock (simulated with semaphore)
        let _permit = self.acquire_lock(&operation.target).await?;

        // Apply operation
        self.execute_operation(&operation).await?;

        // Update vector clock
        let mut state = self.state_vector.write().await;
        let clock = state.entry(operation.source_node.clone())
            .or_insert_with(VectorClock::new);
        clock.merge(&operation.vector_clock);

        Ok(())
    }

    async fn apply_eventual(&self, operation: SyncOperation) -> Result<()> {
        // Add to log for eventual processing
        let mut log = self.operation_log.write().await;
        log.push_back(operation);

        // Process will happen in sync_batch
        Ok(())
    }

    async fn apply_causal(&self, operation: SyncOperation) -> Result<()> {
        // Create event with causal dependencies
        let event = Event {
            id: operation.id,
            timestamp: operation.timestamp,
            vector_clock: operation.vector_clock.clone(),
            node_id: operation.source_node.clone(),
            payload: operation.payload.clone(),
            dependencies: self.find_dependencies(&operation).await,
            metadata: HashMap::new(),
        };

        // Submit to event ordering system
        self.event_ordering.submit_event(event).await?;

        Ok(())
    }

    async fn apply_hybrid(&self, operation: SyncOperation) -> Result<()> {
        // Choose strategy based on operation type
        match operation.operation_type {
            OperationType::Create => {
                // Optimistic for creates
                self.apply_optimistic(operation).await
            }

            OperationType::Delete => {
                // Pessimistic for deletes
                self.apply_pessimistic(operation).await
            }

            OperationType::Update | OperationType::Merge => {
                // Causal for updates
                self.apply_causal(operation).await
            }

            OperationType::Custom(_) => {
                // Eventual for custom
                self.apply_eventual(operation).await
            }
        }
    }

    async fn execute_operation(&self, operation: &SyncOperation) -> Result<()> {
        // Actual operation execution would happen here
        // This is where you'd update the actual data structures

        info!(
            "Executing operation: {:?} on target: {}",
            operation.operation_type, operation.target
        );

        // Update metrics
        self.metrics.record_sync_operation();

        Ok(())
    }

    async fn sync_batch(&self) -> Result<()> {
        let mut log = self.operation_log.write().await;

        if log.is_empty() {
            return Ok(());
        }

        let batch_size = self.max_batch_size.min(log.len());
        let batch: Vec<_> = log.drain(0..batch_size).collect();

        drop(log);

        for operation in batch {
            self.execute_operation(&operation).await?;
        }

        Ok(())
    }

    async fn find_dependencies(&self, operation: &SyncOperation) -> Vec<Uuid> {
        // Find causal dependencies based on vector clocks
        let state = self.state_vector.read().await;

        // For now, return empty dependencies
        // In a real implementation, this would analyze the vector clocks
        // to determine causal relationships
        Vec::new()
    }

    async fn acquire_lock(&self, _target: &str) -> Result<tokio::sync::SemaphorePermit<'static>> {
        // Simplified lock acquisition
        // In production, use distributed locking (Redis, etcd, etc.)
        static LOCK: once_cell::sync::Lazy<Semaphore> =
            once_cell::sync::Lazy::new(|| Semaphore::new(1));

        LOCK.acquire().await
            .map_err(|_| WebSocketError::SyncError("Failed to acquire lock".into()))
    }
}

impl Clone for SyncEngine {
    fn clone(&self) -> Self {
        Self {
            strategy: self.strategy.clone(),
            context: self.context.clone(),
            event_ordering: self.event_ordering.clone(),
            conflict_resolver: self.conflict_resolver.clone(),
            state_vector: self.state_vector.clone(),
            operation_log: self.operation_log.clone(),
            sync_interval: self.sync_interval,
            max_batch_size: self.max_batch_size,
            metrics: self.metrics.clone(),
        }
    }
}

// ========================= Tests =========================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vector_clock_ordering() {
        let mut clock1 = VectorClock::new();
        clock1.increment("node1");
        clock1.increment("node1");

        let mut clock2 = VectorClock::new();
        clock2.increment("node1");
        clock2.increment("node2");

        assert!(!clock1.happens_before(&clock2));
        assert!(!clock2.happens_before(&clock1));
        assert!(clock1.concurrent_with(&clock2));
    }

    #[test]
    fn test_lww_register() {
        let mut reg1 = LWWRegister::new("value1".to_string(), "node1".to_string());
        std::thread::sleep(std::time::Duration::from_millis(1));
        let reg2 = LWWRegister::new("value2".to_string(), "node2".to_string());

        reg1.merge(&reg2);
        assert_eq!(reg1.value, "value2");
    }

    #[test]
    fn test_g_counter() {
        let mut counter1 = GCounter::new();
        counter1.increment("node1", 5);
        counter1.increment("node2", 3);

        let mut counter2 = GCounter::new();
        counter2.increment("node2", 7);
        counter2.increment("node3", 2);

        counter1.merge(&counter2);
        assert_eq!(counter1.value(), 14); // 5 + 7 + 2
    }

    #[test]
    fn test_or_set() {
        let mut set1 = ORSet::new();
        set1.add("item1");
        set1.add("item2");

        let mut set2 = ORSet::new();
        set2.add("item2");
        set2.add("item3");

        set1.merge(&set2);

        assert!(set1.contains(&"item1"));
        assert!(set1.contains(&"item2"));
        assert!(set1.contains(&"item3"));

        set1.remove(&"item2");
        assert!(!set1.contains(&"item2"));
    }

    #[tokio::test]
    async fn test_event_ordering() {
        let ordering = EventOrdering::new(100, Duration::from_secs(10));

        // Create event with no dependencies
        let event1 = Event {
            id: Uuid::new_v4(),
            timestamp: 1,
            vector_clock: VectorClock::new(),
            node_id: "node1".to_string(),
            payload: vec![1, 2, 3],
            dependencies: vec![],
            metadata: HashMap::new(),
        };

        ordering.submit_event(event1.clone()).await.unwrap();

        // Create event with dependency
        let event2 = Event {
            id: Uuid::new_v4(),
            timestamp: 2,
            vector_clock: VectorClock::new(),
            node_id: "node1".to_string(),
            payload: vec![4, 5, 6],
            dependencies: vec![event1.id],
            metadata: HashMap::new(),
        };

        ordering.submit_event(event2).await.unwrap();

        let events = ordering.get_ordered_events(0).await;
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].timestamp, 1);
        assert_eq!(events[1].timestamp, 2);
    }
}
