// crates/beagle-server/src/api/routes/worldmodel.rs
//! World model API routes

use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

use crate::state::AppState;

/// Create world model routes
pub fn create_routes() -> Router<Arc<AppState>> {
    Router::new()
        .route("/worldmodel/state", get(get_world_state))
        .route("/worldmodel/update", post(update_observations))
        .route("/worldmodel/predict", post(predict_future))
        .route("/worldmodel/causal", post(causal_query))
        .route("/worldmodel/counterfactual", post(counterfactual_reasoning))
        .route("/worldmodel/query", post(natural_language_query))
}

/// Get current world state
async fn get_world_state(
    State(state): State<Arc<AppState>>,
) -> Result<Json<WorldStateResponse>, StatusCode> {
    #[cfg(feature = "worldmodel")]
    {
        if let Some(ref worldmodel) = state.context.worldmodel {
            let world_state = worldmodel.current_state().await;

            return Ok(Json(WorldStateResponse {
                entities: world_state.entities.len(),
                uncertainty: world_state.uncertainty,
                abstraction_level: world_state.abstraction_level,
                timestamp: world_state.timestamp.to_rfc3339(),
            }));
        }
    }

    Err(StatusCode::SERVICE_UNAVAILABLE)
}

/// Update world model with observations
async fn update_observations(
    State(state): State<Arc<AppState>>,
    Json(request): Json<UpdateRequest>,
) -> Result<Json<UpdateResponse>, StatusCode> {
    #[cfg(feature = "worldmodel")]
    {
        use beagle_worldmodel::perception::{Modality, Observation, ObservationData};

        if let Some(ref worldmodel) = state.context.worldmodel {
            // Convert request to observations
            let mut observations = Vec::new();

            for obs in request.observations {
                let data = match obs.modality.as_str() {
                    "text" => ObservationData::Text(obs.data),
                    "structured" => {
                        if let Ok(map) = serde_json::from_str(&obs.data) {
                            ObservationData::Structured(map)
                        } else {
                            ObservationData::Text(obs.data)
                        }
                    }
                    _ => ObservationData::Text(obs.data),
                };

                observations.push(Observation {
                    id: Uuid::new_v4(),
                    modality: match obs.modality.as_str() {
                        "visual" => Modality::Visual,
                        "auditory" => Modality::Auditory,
                        "textual" => Modality::Textual,
                        "proprioceptive" => Modality::Proprioceptive,
                        _ => Modality::Textual,
                    },
                    data,
                    timestamp: chrono::Utc::now(),
                    source: obs.source,
                    confidence: obs.confidence,
                    metadata: std::collections::HashMap::new(),
                });
            }

            match worldmodel.update(observations).await {
                Ok(_) => {
                    return Ok(Json(UpdateResponse {
                        success: true,
                        message: "World state updated".to_string(),
                    }));
                }
                Err(e) => {
                    return Ok(Json(UpdateResponse {
                        success: false,
                        message: format!("Update failed: {}", e),
                    }));
                }
            }
        }
    }

    Err(StatusCode::SERVICE_UNAVAILABLE)
}

/// Predict future world states
async fn predict_future(
    State(state): State<Arc<AppState>>,
    Json(request): Json<PredictRequest>,
) -> Result<Json<PredictResponse>, StatusCode> {
    #[cfg(feature = "worldmodel")]
    {
        if let Some(ref worldmodel) = state.context.worldmodel {
            match worldmodel.predict(request.horizon).await {
                Ok(predictions) => {
                    let pred_summaries: Vec<_> = predictions
                        .into_iter()
                        .map(|p| PredictionSummary {
                            horizon: p.horizon,
                            confidence: p.confidence,
                            uncertainty: p.uncertainty_bounds.total,
                        })
                        .collect();

                    return Ok(Json(PredictResponse {
                        predictions: pred_summaries,
                    }));
                }
                Err(e) => {
                    return Err(StatusCode::INTERNAL_SERVER_ERROR);
                }
            }
        }
    }

    Err(StatusCode::SERVICE_UNAVAILABLE)
}

/// Causal query
async fn causal_query(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CausalRequest>,
) -> Result<Json<CausalResponse>, StatusCode> {
    #[cfg(feature = "worldmodel")]
    {
        use beagle_worldmodel::causal::CausalQuery;

        if let Some(ref worldmodel) = state.context.worldmodel {
            let query = match request.query_type.as_str() {
                "direct" => CausalQuery::DirectEffect {
                    cause: request.cause,
                    effect: request.effect,
                },
                "total" => CausalQuery::TotalEffect {
                    cause: request.cause,
                    effect: request.effect,
                },
                _ => {
                    return Err(StatusCode::BAD_REQUEST);
                }
            };

            match worldmodel.causal_query(query).await {
                Ok(strength) => {
                    return Ok(Json(CausalResponse {
                        strength,
                        confidence: 0.8, // Placeholder
                    }));
                }
                Err(_) => {
                    return Err(StatusCode::INTERNAL_SERVER_ERROR);
                }
            }
        }
    }

    Err(StatusCode::SERVICE_UNAVAILABLE)
}

/// Counterfactual reasoning
async fn counterfactual_reasoning(
    State(state): State<Arc<AppState>>,
    Json(request): Json<CounterfactualRequest>,
) -> Result<Json<CounterfactualResponse>, StatusCode> {
    #[cfg(feature = "worldmodel")]
    {
        use beagle_worldmodel::counterfactual::{
            Intervention, InterventionTarget, InterventionType,
        };
        use std::collections::HashMap;

        if let Some(ref worldmodel) = state.context.worldmodel {
            let mut targets = HashMap::new();

            for (var, value) in request.interventions {
                targets.insert(var, InterventionTarget::SetValue(value));
            }

            let intervention = Intervention {
                intervention_type: InterventionType::Atomic,
                targets,
                timing: beagle_worldmodel::counterfactual::InterventionTiming::Immediate,
                constraints: Vec::new(),
            };

            match worldmodel.counterfactual(intervention).await {
                Ok(counterfactual_state) => {
                    return Ok(Json(CounterfactualResponse {
                        entities_changed: counterfactual_state.entities.len(),
                        uncertainty: counterfactual_state.uncertainty,
                        message: "Counterfactual computed".to_string(),
                    }));
                }
                Err(_) => {
                    return Err(StatusCode::INTERNAL_SERVER_ERROR);
                }
            }
        }
    }

    Err(StatusCode::SERVICE_UNAVAILABLE)
}

/// Natural language query
async fn natural_language_query(
    State(state): State<Arc<AppState>>,
    Json(request): Json<QueryRequest>,
) -> Result<Json<QueryResponse>, StatusCode> {
    #[cfg(feature = "worldmodel")]
    {
        if let Some(ref worldmodel) = state.context.worldmodel {
            match worldmodel.query(&request.query).await {
                Ok(result) => {
                    use beagle_worldmodel::QueryResult;

                    let response_type = match result {
                        QueryResult::Entities(entities) => {
                            format!("Found {} entities", entities.len())
                        }
                        QueryResult::Predictions(preds) => {
                            format!("Generated {} predictions", preds.len())
                        }
                        QueryResult::Causal(strength) => {
                            format!("Causal strength: {:.3}", strength)
                        }
                        QueryResult::Counterfactual(_) => {
                            "Counterfactual state computed".to_string()
                        }
                    };

                    return Ok(Json(QueryResponse {
                        success: true,
                        result: response_type,
                    }));
                }
                Err(e) => {
                    return Ok(Json(QueryResponse {
                        success: false,
                        result: format!("Query failed: {}", e),
                    }));
                }
            }
        }
    }

    Err(StatusCode::SERVICE_UNAVAILABLE)
}

// Request/Response types

#[derive(Debug, Serialize)]
struct WorldStateResponse {
    entities: usize,
    uncertainty: f64,
    abstraction_level: u32,
    timestamp: String,
}

#[derive(Debug, Deserialize)]
struct UpdateRequest {
    observations: Vec<ObservationInput>,
}

#[derive(Debug, Deserialize)]
struct ObservationInput {
    modality: String,
    data: String,
    source: String,
    confidence: f64,
}

#[derive(Debug, Serialize)]
struct UpdateResponse {
    success: bool,
    message: String,
}

#[derive(Debug, Deserialize)]
struct PredictRequest {
    horizon: usize,
}

#[derive(Debug, Serialize)]
struct PredictResponse {
    predictions: Vec<PredictionSummary>,
}

#[derive(Debug, Serialize)]
struct PredictionSummary {
    horizon: usize,
    confidence: f64,
    uncertainty: f64,
}

#[derive(Debug, Deserialize)]
struct CausalRequest {
    query_type: String,
    cause: String,
    effect: String,
}

#[derive(Debug, Serialize)]
struct CausalResponse {
    strength: f64,
    confidence: f64,
}

#[derive(Debug, Deserialize)]
struct CounterfactualRequest {
    interventions: std::collections::HashMap<String, f64>,
}

#[derive(Debug, Serialize)]
struct CounterfactualResponse {
    entities_changed: usize,
    uncertainty: f64,
    message: String,
}

#[derive(Debug, Deserialize)]
struct QueryRequest {
    query: String,
}

#[derive(Debug, Serialize)]
struct QueryResponse {
    success: bool,
    result: String,
}

