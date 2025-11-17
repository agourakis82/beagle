//! Knowledge graph management (Neo4j)

mod graph;
mod concepts;
mod temporal_analysis;

pub use graph::{KnowledgeGraph, GraphQuery};
pub use concepts::{ConceptCluster, ClusterAnalyzer};
pub use temporal_analysis::{TemporalAnalyzer, TemporalPatterns};

use crate::thought_capture::Insight;
use serde::{Serialize, Deserialize};
use uuid::Uuid;

/// Neo4j node representing an insight
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsightNode {
    pub id: Uuid,
    pub content: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub context: String,
    pub source: String,
}

/// Neo4j relationship types
#[derive(Debug, Clone, Copy)]
pub enum RelationType {
    RelatesTo,
    Extends,
    Contradicts,
    Supports,
    Precedes,
}

impl RelationType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::RelatesTo => "RELATES_TO",
            Self::Extends => "EXTENDS",
            Self::Contradicts => "CONTRADICTS",
            Self::Supports => "SUPPORTS",
            Self::Precedes => "PRECEDES",
        }
    }
}

