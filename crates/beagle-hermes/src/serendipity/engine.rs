//! Serendipity Engine: Cross-domain discovery via ABC model

use crate::knowledge::graph_client::KnowledgeGraph;
use crate::serendipity::domain_classifier::DomainClassifier;
use anyhow::Result;
use serde::{Deserialize, Serialize};

pub struct SerendipityEngine {
    graph: KnowledgeGraph,
    embeddings: EmbeddingStore,
    novelty_threshold: f64,
    domain_classifier: DomainClassifier,
}

impl SerendipityEngine {
    pub async fn new(
        neo4j_uri: &str,
        user: &str,
        password: &str,
        novelty_threshold: f64,
    ) -> Result<Self> {
        Ok(Self {
            graph: KnowledgeGraph::new(neo4j_uri, user, password).await?,
            embeddings: EmbeddingStore::new()?,
            novelty_threshold,
            domain_classifier: DomainClassifier::new(),
        })
    }
    
    /// Discover hidden connections (ABC model)
    pub async fn discover_connections(
        &self,
        concept_a: &str,
        max_discoveries: usize,
    ) -> Result<Vec<Discovery>> {
        let mut discoveries = Vec::new();
        
        // Step 1: Find all B concepts connected to A
        let b_concepts = self.find_bridging_concepts(concept_a).await?;
        
        tracing::info!("Found {} bridging concepts for '{}'", b_concepts.len(), concept_a);
        
        // Step 2: For each B, find C concepts
        for b_concept in &b_concepts {
            let c_concepts = self.find_target_concepts(&b_concept.name).await?;
            
            // Step 3: Check if A→C is novel (not in literature)
            for c_concept in c_concepts {
                if self.is_novel_connection(concept_a, &c_concept.name).await? {
                    let discovery = Discovery {
                        concept_a: concept_a.to_string(),
                        concept_b: b_concept.name.clone(),
                        concept_c: c_concept.name.clone(),
                        path_strength: b_concept.strength * c_concept.strength,
                        novelty_score: self.calculate_novelty(concept_a, &c_concept.name).await?,
                        supporting_papers_ab: b_concept.papers.clone(),
                        supporting_papers_bc: c_concept.papers.clone(),
                    };
                    
                    if discovery.novelty_score >= self.novelty_threshold {
                        discoveries.push(discovery);
                    }
                }
            }
        }
        
        // Step 4: Rank by novelty and path strength
        discoveries.sort_by(|a, b| {
            let score_a = a.novelty_score * a.path_strength;
            let score_b = b.novelty_score * b.path_strength;
            score_b.partial_cmp(&score_a).unwrap()
        });
        
        Ok(discoveries.into_iter().take(max_discoveries).collect())
    }
    
    async fn find_bridging_concepts(&self, concept_a: &str) -> Result<Vec<BridgingConcept>> {
        // Query knowledge graph for concepts related to A
        // Use Neo4j to find concepts with strong relationships
        
        // For now, return placeholder
        Ok(Vec::new())
    }
    
    async fn find_target_concepts(&self, concept_b: &str) -> Result<Vec<TargetConcept>> {
        // Similar to find_bridging_concepts, but for B→C
        Ok(Vec::new())
    }
    
    async fn is_novel_connection(&self, concept_a: &str, concept_c: &str) -> Result<bool> {
        // Check if A→C already exists in literature
        // Query Neo4j for direct relationship
        Ok(true) // Placeholder
    }
    
    async fn calculate_novelty(&self, concept_a: &str, concept_c: &str) -> Result<f64> {
        // Novelty = 1 - (semantic similarity of A and C)
        // High novelty = very different domains
        
        let embedding_a = self.embeddings.get(concept_a).await?;
        let embedding_c = self.embeddings.get(concept_c).await?;
        
        let similarity = cosine_similarity(&embedding_a, &embedding_c);
        
        Ok(1.0 - similarity)
    }
    
    /// Generate hypothesis from discovery
    pub fn generate_hypothesis(&self, discovery: &Discovery) -> Hypothesis {
        let _domain_classifier = DomainClassifier::new();
        let hypothesis_text = format!(
            "Based on the connection between '{}' and '{}' (via '{}'), \
             we hypothesize that {} may influence {}. \
             \n\nSupporting evidence: \
             \n- A→B: {} papers show relationship between {} and {} \
             \n- B→C: {} papers show relationship between {} and {} \
             \n- A→C: No direct evidence found (novel connection) \
             \n\nRecommended experiments: \
             \n1. Literature review of {} and {} \
             \n2. Experimental validation of A→C relationship \
             \n3. Mechanistic studies via B",
            discovery.concept_a,
            discovery.concept_c,
            discovery.concept_b,
            discovery.concept_a,
            discovery.concept_c,
            discovery.supporting_papers_ab.len(),
            discovery.concept_a,
            discovery.concept_b,
            discovery.supporting_papers_bc.len(),
            discovery.concept_b,
            discovery.concept_c,
            discovery.concept_a,
            discovery.concept_c,
        );
        
        Hypothesis {
            discovery: discovery.clone(),
            hypothesis_text,
            confidence: discovery.path_strength * discovery.novelty_score,
            testability: self.assess_testability(discovery),
            impact_score: self.estimate_impact(discovery),
        }
    }
    
    fn assess_testability(&self, discovery: &Discovery) -> f64 {
        // Heuristic: More papers = easier to test
        let total_papers = discovery.supporting_papers_ab.len() + 
                          discovery.supporting_papers_bc.len();
        
        (total_papers as f64 / 100.0).min(1.0)
    }
    
    fn estimate_impact(&self, discovery: &Discovery) -> f64 {
        // Impact = novelty * (domain diversity)
        // High impact = connecting very different fields
        
        discovery.novelty_score * 0.8 // Simplified
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Discovery {
    pub concept_a: String,
    pub concept_b: String,
    pub concept_c: String,
    pub path_strength: f64,
    pub novelty_score: f64,
    pub supporting_papers_ab: Vec<String>,
    pub supporting_papers_bc: Vec<String>,
}

#[derive(Debug, Clone)]
struct BridgingConcept {
    name: String,
    strength: f64,
    papers: Vec<String>,
}

#[derive(Debug, Clone)]
struct TargetConcept {
    name: String,
    strength: f64,
    papers: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hypothesis {
    pub discovery: Discovery,
    pub hypothesis_text: String,
    pub confidence: f64,
    pub testability: f64,
    pub impact_score: f64,
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f64 {
    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
    
    if norm_a == 0.0 || norm_b == 0.0 {
        return 0.0;
    }
    
    (dot / (norm_a * norm_b)) as f64
}

use crate::embeddings::BGEEmbedder;

struct EmbeddingStore {
    embedder: BGEEmbedder,
}

impl EmbeddingStore {
    pub fn new() -> Result<Self> {
        Ok(Self {
            embedder: BGEEmbedder::new()?,
        })
    }
    
    pub async fn get(&self, concept: &str) -> Result<Vec<f32>> {
        self.embedder.embed(concept)
    }
}

