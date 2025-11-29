// crates/beagle-worldmodel/examples/worldmodel_demo.rs
//! BEAGLE WorldModel demonstration

use beagle_worldmodel::{
    causal::CausalQuery,
    counterfactual::{Intervention, InterventionTarget},
    perception::{Modality, Observation, ObservationData},
    planning::{Goal, GoalType, Planner, PlanningAlgorithm},
    state::{Entity, EntityType, Properties, SpatialInfo},
    WorldModel,
};
use chrono::Utc;
use nalgebra as na;
use std::collections::HashMap;
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("=== BEAGLE WorldModel Demo ===\n");

    // Create world model
    let model = WorldModel::new().await;
    println!("✓ World model initialized");

    // 1. Add some entities to the world
    println!("\n1. Creating world entities...");

    let mut state = model.current_state().await;

    // Add a robot entity
    let robot = Entity {
        id: Uuid::new_v4(),
        entity_type: EntityType::Agent("robot".to_string()),
        properties: {
            let mut props = Properties::new();
            props.set_string("name".to_string(), "BEAGLE-1".to_string());
            props.set_number("battery".to_string(), 0.8);
            props.set_bool("active".to_string(), true);
            props
        },
        spatial: Some(SpatialInfo {
            position: na::Point3::new(0.0, 0.0, 0.0),
            orientation: na::UnitQuaternion::identity(),
            velocity: na::Vector3::new(1.0, 0.0, 0.0),
            acceleration: na::Vector3::zeros(),
            bounds: None,
            frame: beagle_worldmodel::state::ReferenceFrame::World,
        }),
        temporal: None,
        beliefs: beagle_worldmodel::state::BeliefState::new_uniform(100),
        active: true,
    };

    // Add an object entity
    let object = Entity {
        id: Uuid::new_v4(),
        entity_type: EntityType::Object("cube".to_string()),
        properties: {
            let mut props = Properties::new();
            props.set_string("color".to_string(), "red".to_string());
            props.set_number("mass".to_string(), 1.5);
            props
        },
        spatial: Some(SpatialInfo {
            position: na::Point3::new(5.0, 0.0, 0.0),
            orientation: na::UnitQuaternion::identity(),
            velocity: na::Vector3::zeros(),
            acceleration: na::Vector3::zeros(),
            bounds: None,
            frame: beagle_worldmodel::state::ReferenceFrame::World,
        }),
        temporal: None,
        beliefs: beagle_worldmodel::state::BeliefState::new_uniform(100),
        active: true,
    };

    // Create observations
    let observations = vec![
        Observation {
            id: Uuid::new_v4(),
            modality: Modality::Textual,
            data: ObservationData::Text(
                "Robot BEAGLE-1 is moving towards the red cube".to_string(),
            ),
            timestamp: Utc::now(),
            source: "narrator".to_string(),
            confidence: 0.9,
            metadata: HashMap::new(),
        },
        Observation {
            id: Uuid::new_v4(),
            modality: Modality::Proprioceptive,
            data: ObservationData::Structured(HashMap::from([
                ("battery_level".to_string(), 0.75),
                ("motor_temperature".to_string(), 35.0),
            ])),
            timestamp: Utc::now(),
            source: "internal_sensors".to_string(),
            confidence: 1.0,
            metadata: HashMap::new(),
        },
    ];

    // Update world model
    model.update(observations).await?;
    println!("✓ World state updated from observations");

    // 2. Predict future states
    println!("\n2. Predicting future states...");
    let predictions = model.predict(5).await?;

    for pred in &predictions {
        println!(
            "  t+{}: confidence={:.2}, uncertainty={:.2}",
            pred.horizon, pred.confidence, pred.uncertainty_bounds.total
        );
    }

    // 3. Causal queries
    println!("\n3. Causal reasoning...");

    let causal_query = CausalQuery::DirectEffect {
        cause: "velocity".to_string(),
        effect: "position".to_string(),
    };

    let effect_strength = model.causal_query(causal_query).await?;
    println!(
        "  Direct causal effect (velocity → position): {:.3}",
        effect_strength
    );

    // 4. Counterfactual reasoning
    println!("\n4. Counterfactual analysis...");
    println!("  Question: What if the robot's battery was at 100%?");

    let intervention = Intervention {
        intervention_type: beagle_worldmodel::counterfactual::InterventionType::Atomic,
        targets: HashMap::from([("battery".to_string(), InterventionTarget::SetValue(1.0))]),
        timing: beagle_worldmodel::counterfactual::InterventionTiming::Immediate,
        constraints: vec![],
    };

    let counterfactual_state = model.counterfactual(intervention).await?;
    println!(
        "  Counterfactual uncertainty: {:.3}",
        counterfactual_state.uncertainty
    );
    println!(
        "  Entities in counterfactual world: {}",
        counterfactual_state.entities.len()
    );

    // 5. Natural language queries
    println!("\n5. Natural language understanding...");

    let queries = vec![
        "what objects are in the world?",
        "predict what will happen next",
        "what causes the position to change?",
        "what if the robot stops moving?",
    ];

    for query in queries {
        println!("\n  Query: \"{}\"", query);
        let result = model.query(query).await?;

        use beagle_worldmodel::QueryResult;
        match result {
            QueryResult::Entities(entities) => {
                println!("    → Found {} entities", entities.len());
                for entity in entities.iter().take(2) {
                    match &entity.entity_type {
                        EntityType::Object(name) | EntityType::Agent(name) => {
                            println!("      - {} ({})", name, entity.id);
                        }
                        _ => {}
                    }
                }
            }
            QueryResult::Predictions(preds) => {
                println!("    → {} predictions generated", preds.len());
            }
            QueryResult::Causal(strength) => {
                println!("    → Causal strength: {:.3}", strength);
            }
            QueryResult::Counterfactual(state) => {
                println!(
                    "    → Counterfactual world with {} entities",
                    state.entities.len()
                );
            }
        }
    }

    // 6. Planning demonstration
    println!("\n6. Planning to reach goal...");

    let planner = Planner::new(PlanningAlgorithm::AStar);

    let goal = Goal {
        goal_type: GoalType::Reach,
        targets: HashMap::from([
            ("x_position".to_string(), 5.0),
            ("y_position".to_string(), 0.0),
        ]),
        tolerance: 0.1,
    };

    let current_state = model.current_state().await;
    let plan = planner.plan(&current_state, &goal).await?;

    println!("  Plan generated with {} actions", plan.actions.len());
    println!("  Expected reward: {:.3}", plan.expected_reward);
    println!("  Confidence: {:.2}", plan.confidence);

    // 7. Uncertainty quantification
    println!("\n7. Uncertainty analysis...");

    use beagle_worldmodel::uncertainty::{PropagationMethod, Uncertainty, UncertaintyPropagator};

    let uncertainty = Uncertainty::gaussian(0.0, 0.1);
    println!("  Initial uncertainty: σ={:.3}", uncertainty.total());

    // Propagate through nonlinear function
    let propagated = uncertainty.propagate(|x| x * x + 2.0 * x);
    println!("  After propagation: σ={:.3}", propagated.total());

    let propagator = UncertaintyPropagator::new(PropagationMethod::MonteCarlo { n_samples: 1000 });
    let uncertainties = HashMap::from([
        ("position".to_string(), Uncertainty::gaussian(0.0, 0.5)),
        ("velocity".to_string(), Uncertainty::gaussian(1.0, 0.1)),
    ]);

    let propagated_state = propagator.propagate_state(&current_state, &uncertainties);
    println!(
        "  State uncertainties after MC propagation: {} variables",
        propagated_state.len()
    );

    // 8. Multi-modal perception fusion
    println!("\n8. Multi-modal perception fusion...");

    let multi_modal_obs = vec![
        Observation {
            id: Uuid::new_v4(),
            modality: Modality::Visual,
            data: ObservationData::Text("Visual: Red cube detected at (5, 0)".to_string()),
            timestamp: Utc::now(),
            source: "camera".to_string(),
            confidence: 0.85,
            metadata: HashMap::new(),
        },
        Observation {
            id: Uuid::new_v4(),
            modality: Modality::Auditory,
            data: ObservationData::Text("Audio: Motor sound detected".to_string()),
            timestamp: Utc::now(),
            source: "microphone".to_string(),
            confidence: 0.7,
            metadata: HashMap::new(),
        },
    ];

    model.update(multi_modal_obs).await?;
    println!("  ✓ Fused visual and auditory observations");

    println!("\n=== Demo Complete ===");

    Ok(())
}
