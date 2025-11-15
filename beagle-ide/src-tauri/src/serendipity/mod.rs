use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SerendipityConnection {
    pub id: String,
    pub source_project: String,
    pub target_project: String,
    pub source_concept: String,
    pub target_concept: String,
    pub similarity_score: f32,
    pub novelty_score: f32,
    pub connection_type: ConnectionType,
    pub explanation: String,
    pub potential_impact: String,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub enum ConnectionType {
    StructuralAnalogy,
    CausalSimilarity,
    MethodTransfer,
    ConceptualBridge,
    UnexpectedCorrelation,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProjectContext {
    pub id: String,
    pub domain: String,
    pub recent_concepts: Vec<String>,
    pub active_problems: Vec<String>,
}

pub struct SerendipityEngine {
    projects: HashMap<String, ProjectContext>,
    embeddings_client: reqwest::Client,
    beagle_api_url: String,
}

impl SerendipityEngine {
    pub fn new(beagle_api_url: String) -> Self {
        Self {
            projects: HashMap::new(),
            embeddings_client: reqwest::Client::new(),
            beagle_api_url,
        }
    }

    pub fn has_project(&self, id: &str) -> bool {
        self.projects.contains_key(id)
    }

    pub async fn register_project(&mut self, project: ProjectContext) {
        self.projects.insert(project.id.clone(), project);
    }

    pub async fn load_projects_from_api(&mut self) {
        let url = format!("{}/api/v1/projects/contexts", self.beagle_api_url);
        if let Ok(response) = self.embeddings_client.get(&url).send().await {
            if let Ok(projects) = response.json::<Vec<ProjectContext>>().await {
                for project in projects {
                    self.projects.insert(project.id.clone(), project);
                }
            }
        }

        if self.projects.is_empty() {
            for project in default_projects() {
                self.projects.insert(project.id.clone(), project);
            }
        }
    }

    pub async fn discover_connections(
        &self,
        focus_project: &str,
    ) -> Result<Vec<SerendipityConnection>, String> {
        let focus = self
            .projects
            .get(focus_project)
            .ok_or_else(|| "Project not found".to_string())?;

        if focus.recent_concepts.is_empty() {
            return Ok(Vec::new());
        }

        let focus_embeddings = self.get_concept_embeddings(&focus.recent_concepts).await?;

        let mut connections = Vec::new();

        for (other_id, other_project) in &self.projects {
            if other_id == focus_project || other_project.recent_concepts.is_empty() {
                continue;
            }

            let other_embeddings = self
                .get_concept_embeddings(&other_project.recent_concepts)
                .await?;

            for (i, focus_concept) in focus.recent_concepts.iter().enumerate() {
                for (j, other_concept) in other_project.recent_concepts.iter().enumerate() {
                    let Some(focus_embedding) = focus_embeddings.get(i) else {
                        continue;
                    };
                    let Some(other_embedding) = other_embeddings.get(j) else {
                        continue;
                    };

                    let similarity = cosine_similarity(focus_embedding, other_embedding);

                    if similarity > 0.7 && focus.domain != other_project.domain {
                        let novelty = calculate_novelty_score(
                            &focus.domain,
                            &other_project.domain,
                            similarity,
                        );

                        if novelty > 0.6 {
                            connections.push(SerendipityConnection {
                                id: uuid::Uuid::new_v4().to_string(),
                                source_project: focus_project.to_string(),
                                target_project: other_id.clone(),
                                source_concept: focus_concept.clone(),
                                target_concept: other_concept.clone(),
                                similarity_score: similarity,
                                novelty_score: novelty,
                                connection_type: classify_connection_type(
                                    focus_concept,
                                    other_concept,
                                ),
                                explanation: format!(
                                    "Found structural similarity between '{}' in {} and '{}' in {}",
                                    focus_concept,
                                    focus.domain,
                                    other_concept,
                                    other_project.domain
                                ),
                                potential_impact: generate_impact_assessment(
                                    focus_concept,
                                    other_concept,
                                    &focus.active_problems,
                                ),
                            });
                        }
                    }
                }
            }
        }

        connections.sort_by(|a, b| {
            let score_a = a.novelty_score * impact_to_score(&a.potential_impact);
            let score_b = b.novelty_score * impact_to_score(&b.potential_impact);
            score_b
                .partial_cmp(&score_a)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        Ok(connections)
    }

    async fn get_concept_embeddings(&self, concepts: &[String]) -> Result<Vec<Vec<f32>>, String> {
        if concepts.is_empty() {
            return Ok(Vec::new());
        }

        let url = format!("{}/api/v1/embeddings/batch", self.beagle_api_url);
        let response = self
            .embeddings_client
            .post(&url)
            .json(&concepts)
            .send()
            .await;

        match response {
            Ok(resp) => {
                if resp.status().is_success() {
                    return resp
                        .json::<Vec<Vec<f32>>>()
                        .await
                        .map_err(|e| format!("Failed to parse embeddings: {}", e));
                }
            }
            Err(_) => {}
        }

        Ok(concepts
            .iter()
            .map(|concept| fallback_embedding(concept))
            .collect())
    }

    pub async fn explain_connection(
        &self,
        connection: &SerendipityConnection,
    ) -> Result<String, String> {
        let request = ExplanationRequest {
            source_concept: connection.source_concept.clone(),
            target_concept: connection.target_concept.clone(),
            connection_type: connection.connection_type.clone(),
            context: format!(
                "Source domain: {}, Target domain: {}",
                connection.source_project, connection.target_project
            ),
        };

        let url = format!("{}/api/v1/darwin/explain-connection", self.beagle_api_url);
        let response = self
            .embeddings_client
            .post(&url)
            .json(&request)
            .send()
            .await;

        if let Ok(resp) = response {
            if resp.status().is_success() {
                if let Ok(explanation) = resp.json::<ExplanationResponse>().await {
                    return Ok(format_explanation(&explanation));
                }
            }
        }

        Ok(format!(
            "## Optimistic View\nThe connection between '{}' and '{}' could unlock a shared structure.\n\n\
## Critical View\nMore evidence is required to validate the analogy.\n\n\
## Synthesis\nPrototype a small study combining both approaches.",
            connection.source_concept, connection.target_concept
        ))
    }
}

#[derive(Serialize)]
struct ExplanationRequest {
    source_concept: String,
    target_concept: String,
    connection_type: ConnectionType,
    context: String,
}

#[derive(Deserialize)]
struct ExplanationResponse {
    thesis: String,
    antithesis: String,
    synthesis: String,
}

fn fallback_embedding(input: &str) -> Vec<f32> {
    const DIM: usize = 16;
    let mut embedding = vec![0.0; DIM];
    if input.is_empty() {
        return embedding;
    }

    for (idx, byte) in input.bytes().enumerate() {
        let slot = idx % DIM;
        embedding[slot] += (byte as f32) / 255.0;
    }

    embedding
}

fn format_explanation(explanation: &ExplanationResponse) -> String {
    format!(
        "## Optimistic View\n{}\n\n## Critical View\n{}\n\n## Synthesis\n{}",
        explanation.thesis, explanation.antithesis, explanation.synthesis
    )
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    let dot_product: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let magnitude_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let magnitude_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();

    if magnitude_a == 0.0 || magnitude_b == 0.0 {
        return 0.0;
    }

    dot_product / (magnitude_a * magnitude_b)
}

fn calculate_novelty_score(domain_a: &str, domain_b: &str, similarity: f32) -> f32 {
    let domain_distance = if domain_a == domain_b {
        0.0
    } else if are_related_domains(domain_a, domain_b) {
        0.5
    } else {
        1.0
    };

    similarity * domain_distance
}

fn are_related_domains(a: &str, b: &str) -> bool {
    let a_keywords: Vec<&str> = a.split_whitespace().collect();
    let b_keywords: Vec<&str> = b.split_whitespace().collect();

    a_keywords
        .iter()
        .any(|keyword| b_keywords.contains(keyword))
}

fn classify_connection_type(concept_a: &str, concept_b: &str) -> ConnectionType {
    let lower_a = concept_a.to_lowercase();
    let lower_b = concept_b.to_lowercase();

    if lower_a.contains("model") && lower_b.contains("model") {
        ConnectionType::StructuralAnalogy
    } else if lower_a.contains("cause") || lower_b.contains("effect") {
        ConnectionType::CausalSimilarity
    } else if lower_a.contains("method")
        || lower_a.contains("algorithm")
        || lower_b.contains("method")
    {
        ConnectionType::MethodTransfer
    } else if lower_a.contains("correlation") || lower_b.contains("correlation") {
        ConnectionType::UnexpectedCorrelation
    } else {
        ConnectionType::ConceptualBridge
    }
}

fn generate_impact_assessment(source: &str, target: &str, active_problems: &[String]) -> String {
    for problem in active_problems {
        if problem.to_lowercase().contains(&target.to_lowercase())
            || problem.to_lowercase().contains(&source.to_lowercase())
        {
            return format!(
                "HIGH: This connection might solve active problem: {}",
                problem
            );
        }
    }

    "MEDIUM: Potential for novel research direction".to_string()
}

fn impact_to_score(impact: &str) -> f32 {
    if impact.starts_with("HIGH") {
        0.9
    } else if impact.starts_with("MEDIUM") {
        0.5
    } else {
        0.3
    }
}

fn default_projects() -> Vec<ProjectContext> {
    vec![
        ProjectContext {
            id: "biomaterials".to_string(),
            domain: "materials science".to_string(),
            recent_concepts: vec![
                "scaffold degradation".to_string(),
                "mechanical reinforcement".to_string(),
            ],
            active_problems: vec!["slow healing".to_string()],
        },
        ProjectContext {
            id: "psychiatry".to_string(),
            domain: "computational psychiatry".to_string(),
            recent_concepts: vec![
                "network dynamics".to_string(),
                "adaptive control model".to_string(),
            ],
            active_problems: vec!["treatment resistance".to_string()],
        },
        ProjectContext {
            id: "climate".to_string(),
            domain: "climate systems".to_string(),
            recent_concepts: vec!["ocean mixing model".to_string()],
            active_problems: vec!["extreme weather prediction".to_string()],
        },
    ]
}

fn resolve_beagle_api_url() -> String {
    std::env::var("BEAGLE_API_URL").unwrap_or_else(|_| "http://localhost:8000".to_string())
}

#[tauri::command]
pub async fn discover_serendipity(
    focus_project: String,
) -> Result<Vec<SerendipityConnection>, String> {
    let mut engine = SerendipityEngine::new(resolve_beagle_api_url());
    engine.load_projects_from_api().await;

    if !engine.has_project(&focus_project) {
        engine
            .register_project(ProjectContext {
                id: focus_project.clone(),
                domain: "general research".to_string(),
                recent_concepts: vec![focus_project.clone()],
                active_problems: Vec::new(),
            })
            .await;
    }

    engine.discover_connections(&focus_project).await
}

#[tauri::command]
pub async fn explain_serendipity(connection: SerendipityConnection) -> Result<String, String> {
    let engine = SerendipityEngine::new(resolve_beagle_api_url());
    engine.explain_connection(&connection).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity_basic() {
        let a = vec![1.0_f32, 0.0, 0.0];
        let b = vec![1.0_f32, 0.0, 0.0];
        let c = vec![0.0_f32, 1.0, 0.0];
        assert!((cosine_similarity(&a, &b) - 1.0).abs() < 1e-6);
        assert!(cosine_similarity(&a, &c) < 0.1);
    }

    #[test]
    fn test_classify_connection_type_keywords() {
        assert_eq!(
            classify_connection_type("two-compartment model", "control model"),
            ConnectionType::StructuralAnalogy
        );
        assert_eq!(
            classify_connection_type("cause mapping", "effect estimation"),
            ConnectionType::CausalSimilarity
        );
        assert_eq!(
            classify_connection_type("new method", "novel algorithm"),
            ConnectionType::MethodTransfer
        );
        assert_eq!(
            classify_connection_type("x correlation", "signal"),
            ConnectionType::UnexpectedCorrelation
        );
    }
}
