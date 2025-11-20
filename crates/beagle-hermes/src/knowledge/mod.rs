//! Knowledge Graph Integration (Neo4j)
//!
//! Stores insights, concepts, and relationships for:
//! - Concept clustering
//! - Cross-domain discovery
//! - Temporal analysis
//! - Paper synthesis triggering

pub mod concepts;
pub mod graph;
pub mod graph_client;
pub mod graph_store_wrapper;
pub mod models;
pub mod queries;
pub mod temporal_analysis;

pub use concepts::{ClusterAnalyzer, ClusteredInsight, ConceptCluster};
pub use graph::KnowledgeGraph as GraphKnowledgeGraph;
pub use graph_client::KnowledgeGraph;
pub use graph_store_wrapper::KnowledgeGraphWrapper;
pub use models::{
    ConceptNode, ConceptRelation, InsightConceptRel, InsightNode, PaperNode, PaperStatus,
};
