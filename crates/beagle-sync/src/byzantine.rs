/// # Byzantine Fault Detection and Consensus
///
/// Byzantine fault-tolerant synchronization
use anyhow::{Context, Result};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

/// Byzantine fault detector
pub struct ByzantineDetector {
    threshold: f64,
    fault_history: Arc<RwLock<HashMap<String, Vec<Fault>>>>,
    reputation_scores: Arc<RwLock<HashMap<String, f64>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Fault {
    timestamp: u64,
    fault_type: crate::FaultType,
    severity: f64,
}

impl ByzantineDetector {
    pub fn new(threshold: f64) -> Self {
        Self {
            threshold,
            fault_history: Arc::new(RwLock::new(HashMap::new())),
            reputation_scores: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn check_operation(&self, op: &crate::Operation) -> Result<bool> {
        // Check various Byzantine conditions

        // 1. Timestamp validation (not too far in future/past)
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs();

        if op.timestamp > now + 300 || op.timestamp < now - 86400 {
            self.record_fault(&op.node_id, crate::FaultType::TimeViolation)
                .await;
            return Ok(true);
        }

        // 2. Check reputation
        let reputation = self.get_reputation(&op.node_id);
        if reputation < self.threshold {
            return Ok(true);
        }

        // 3. Signature validation would go here
        // 4. State consistency checks would go here

        Ok(false)
    }

    pub async fn report_fault(&self, node_id: &str) {
        self.record_fault(node_id, crate::FaultType::InconsistentState)
            .await;
    }

    async fn record_fault(&self, node_id: &str, fault_type: crate::FaultType) {
        let fault = Fault {
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            fault_type,
            severity: 1.0,
        };

        let mut history = self.fault_history.write();
        history
            .entry(node_id.to_string())
            .or_insert_with(Vec::new)
            .push(fault);

        // Update reputation
        let mut scores = self.reputation_scores.write();
        let score = scores.entry(node_id.to_string()).or_insert(1.0);
        *score *= 0.9; // Decrease reputation
    }

    fn get_reputation(&self, node_id: &str) -> f64 {
        self.reputation_scores
            .read()
            .get(node_id)
            .copied()
            .unwrap_or(1.0)
    }
}

/// Consensus protocol abstraction
pub trait ConsensusProtocol: Send + Sync {
    fn propose(&self, value: Vec<u8>) -> Result<()>;
    fn vote(&self, proposal_id: &str, approve: bool) -> Result<()>;
    fn decide(&self) -> Result<Option<Vec<u8>>>;
}

/// PBFT (Practical Byzantine Fault Tolerance) implementation
pub struct PBFTEngine {
    node_id: String,
    nodes: Vec<String>,
    view: Arc<RwLock<u64>>,
    phase: Arc<RwLock<PBFTPhase>>,
    proposals: Arc<RwLock<HashMap<String, Proposal>>>,
}

#[derive(Debug, Clone, PartialEq)]
enum PBFTPhase {
    PrePrepare,
    Prepare,
    Commit,
    Reply,
}

#[derive(Debug, Clone)]
struct Proposal {
    id: String,
    value: Vec<u8>,
    prepares: HashSet<String>,
    commits: HashSet<String>,
}

impl PBFTEngine {
    pub fn new(node_id: String, nodes: Vec<String>) -> Self {
        Self {
            node_id,
            nodes,
            view: Arc::new(RwLock::new(0)),
            phase: Arc::new(RwLock::new(PBFTPhase::PrePrepare)),
            proposals: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    fn is_primary(&self) -> bool {
        let view = *self.view.read();
        let primary_idx = (view as usize) % self.nodes.len();
        self.nodes[primary_idx] == self.node_id
    }

    fn quorum_size(&self) -> usize {
        (self.nodes.len() * 2 + 1) / 3
    }
}

impl ConsensusProtocol for PBFTEngine {
    fn propose(&self, value: Vec<u8>) -> Result<()> {
        if !self.is_primary() {
            return Err(anyhow::anyhow!("Only primary can propose"));
        }

        let proposal_id = format!("{}-{}", self.view.read(), uuid::Uuid::new_v4());

        let proposal = Proposal {
            id: proposal_id.clone(),
            value,
            prepares: HashSet::new(),
            commits: HashSet::new(),
        };

        self.proposals.write().insert(proposal_id, proposal);
        *self.phase.write() = PBFTPhase::Prepare;

        Ok(())
    }

    fn vote(&self, proposal_id: &str, approve: bool) -> Result<()> {
        if !approve {
            return Ok(());
        }

        let phase = self.phase.read().clone();
        let mut proposals = self.proposals.write();

        if let Some(proposal) = proposals.get_mut(proposal_id) {
            match phase {
                PBFTPhase::Prepare => {
                    proposal.prepares.insert(self.node_id.clone());

                    if proposal.prepares.len() >= self.quorum_size() {
                        *self.phase.write() = PBFTPhase::Commit;
                    }
                }
                PBFTPhase::Commit => {
                    proposal.commits.insert(self.node_id.clone());

                    if proposal.commits.len() >= self.quorum_size() {
                        *self.phase.write() = PBFTPhase::Reply;
                    }
                }
                _ => {}
            }
        }

        Ok(())
    }

    fn decide(&self) -> Result<Option<Vec<u8>>> {
        let phase = self.phase.read().clone();

        if phase != PBFTPhase::Reply {
            return Ok(None);
        }

        let proposals = self.proposals.read();

        // Find proposal with enough commits
        for proposal in proposals.values() {
            if proposal.commits.len() >= self.quorum_size() {
                return Ok(Some(proposal.value.clone()));
            }
        }

        Ok(None)
    }
}

