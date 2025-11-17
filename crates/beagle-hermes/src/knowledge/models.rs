//! Neo4j Data Models

use crate::thought_capture::InsightSource;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Insight node in Neo4j
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsightNode {
    pub id: Uuid,
    pub text: String,
    pub source: InsightSource,
    pub timestamp: DateTime<Utc>,
    pub confidence: f64,
    pub embedding: Vec<f32>,
    pub metadata: serde_json::Value,
}

/// Concept node in Neo4j
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConceptNode {
    pub name: String,
    pub concept_type: String,
    pub count: i64,
    pub embedding: Vec<f32>,
    pub last_updated: DateTime<Utc>,
    pub metadata: serde_json::Value,
}

/// Paper node in Neo4j
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaperNode {
    pub id: Uuid,
    pub title: String,
    pub status: PaperStatus,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub sections: serde_json::Value,
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PaperStatus {
    Draft,
    Review,
    Refining,
    Ready,
    Published,
}

/// Relationship: (Insight)-[:CONTAINS]->(Concept)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsightConceptRel {
    pub insight_id: Uuid,
    pub concept_name: String,
    pub confidence: f64,
}

/// Relationship: (Concept)-[:RELATED_TO]->(Concept)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConceptRelation {
    pub from_concept: String,
    pub to_concept: String,
    pub weight: f64,
}
