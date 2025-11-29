// crates/beagle-worldmodel/src/state.rs
//! Hierarchical world state representation with uncertainty
//!
//! Implements a rich state representation that captures:
//! - Entities with properties and relationships
//! - Spatial and temporal information
//! - Uncertainty and belief distributions
//! - Hierarchical abstraction levels
//!
//! References:
//! - "Hierarchical State Abstractions for Decision-Making" (Konidaris, 2024)
//! - "Probabilistic World Models" (Hafner et al., 2025)
//! - "Object-Centric World Models" (Kipf et al., 2024)

use std::sync::Arc;
use std::collections::{HashMap, HashSet};
use serde::{Serialize, Deserialize};
use dashmap::DashMap;
use uuid::Uuid;
use chrono::{DateTime, Utc};
use nalgebra as na;
use petgraph::graph::{Graph, NodeIndex};
use parking_lot::RwLock;

/// World state representation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldState {
    /// Entities in the world
    pub entities: HashMap<Uuid, Entity>,

    /// Relationships between entities
    pub relationships: Graph<Uuid, Relationship>,

    /// Spatial regions and their properties
    pub regions: HashMap<RegionId, Region>,

    /// Global properties
    pub globals: Properties,

    /// Timestamp of this state
    pub timestamp: DateTime<Utc>,

    /// Uncertainty measure (0.0 = certain, 1.0 = maximum uncertainty)
    pub uncertainty: f64,

    /// Abstraction level (0 = most detailed)
    pub abstraction_level: u32,
}

/// Entity in the world
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entity {
    /// Unique identifier
    pub id: Uuid,

    /// Entity type
    pub entity_type: EntityType,

    /// Properties
    pub properties: Properties,

    /// Spatial information
    pub spatial: Option<SpatialInfo>,

    /// Temporal information
    pub temporal: Option<TemporalInfo>,

    /// Belief distribution over states
    pub beliefs: BeliefState,

    /// Active/inactive status
    pub active: bool,
}

/// Entity types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum EntityType {
    Object(String),
    Agent(String),
    Location(String),
    Event(String),
    Abstract(String),
    Composite(Vec<EntityType>),
}

/// Properties as key-value pairs with types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Properties {
    /// Boolean properties
    pub booleans: HashMap<String, bool>,

    /// Numeric properties
    pub numbers: HashMap<String, f64>,

    /// String properties
    pub strings: HashMap<String, String>,

    /// Vector properties
    pub vectors: HashMap<String, Vec<f64>>,

    /// Nested properties
    pub nested: HashMap<String, Properties>,
}

impl Properties {
    pub fn new() -> Self {
        Self {
            booleans: HashMap::new(),
            numbers: HashMap::new(),
            strings: HashMap::new(),
            vectors: HashMap::new(),
            nested: HashMap::new(),
        }
    }

    pub fn get_bool(&self, key: &str) -> Option<bool> {
        self.booleans.get(key).copied()
    }

    pub fn get_number(&self, key: &str) -> Option<f64> {
        self.numbers.get(key).copied()
    }

    pub fn get_string(&self, key: &str) -> Option<&str> {
        self.strings.get(key).map(|s| s.as_str())
    }

    pub fn set_bool(&mut self, key: String, value: bool) {
        self.booleans.insert(key, value);
    }

    pub fn set_number(&mut self, key: String, value: f64) {
        self.numbers.insert(key, value);
    }

    pub fn set_string(&mut self, key: String, value: String) {
        self.strings.insert(key, value);
    }
}

/// Spatial information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialInfo {
    /// 3D position
    pub position: na::Point3<f64>,

    /// Orientation (quaternion)
    pub orientation: na::UnitQuaternion<f64>,

    /// Velocity
    pub velocity: na::Vector3<f64>,

    /// Acceleration
    pub acceleration: na::Vector3<f64>,

    /// Bounding box
    pub bounds: Option<BoundingBox>,

    /// Reference frame
    pub frame: ReferenceFrame,
}

/// Bounding box
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoundingBox {
    pub min: na::Point3<f64>,
    pub max: na::Point3<f64>,
}

/// Reference frame for spatial coordinates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ReferenceFrame {
    World,
    Local(Uuid),  // Relative to another entity
    Geographic,   // Lat/lon/alt
}

/// Temporal information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalInfo {
    /// When this entity came into existence
    pub created_at: DateTime<Utc>,

    /// When this entity was last updated
    pub updated_at: DateTime<Utc>,

    /// Expected lifetime (if applicable)
    pub lifetime: Option<chrono::Duration>,

    /// Temporal extent for events
    pub duration: Option<chrono::Duration>,

    /// Recurrence pattern (if applicable)
    pub recurrence: Option<RecurrencePattern>,
}

/// Recurrence pattern for periodic events
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RecurrencePattern {
    Daily,
    Weekly(Vec<chrono::Weekday>),
    Monthly(u32), // Day of month
    Yearly(u32, u32), // Month, day
    Custom(String), // Cron expression
}

/// Belief state using particle representation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeliefState {
    /// Particles representing possible states
    pub particles: Vec<Particle>,

    /// Concentration parameter (higher = more certain)
    pub concentration: f64,
}

/// Single particle in belief distribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Particle {
    /// State represented by this particle
    pub state: HashMap<String, f64>,

    /// Weight/probability
    pub weight: f64,
}

impl BeliefState {
    pub fn new_uniform(n_particles: usize) -> Self {
        let weight = 1.0 / n_particles as f64;
        let particles = (0..n_particles)
            .map(|_| Particle {
                state: HashMap::new(),
                weight,
            })
            .collect();

        Self {
            particles,
            concentration: 1.0,
        }
    }

    pub fn entropy(&self) -> f64 {
        -self.particles
            .iter()
            .filter(|p| p.weight > 0.0)
            .map(|p| p.weight * p.weight.ln())
            .sum::<f64>()
    }

    pub fn update(&mut self, observation: &HashMap<String, f64>, noise: f64) {
        // Bayesian update of particle weights
        for particle in &mut self.particles {
            let likelihood = Self::likelihood(&particle.state, observation, noise);
            particle.weight *= likelihood;
        }

        // Normalize weights
        let total_weight: f64 = self.particles.iter().map(|p| p.weight).sum();
        if total_weight > 0.0 {
            for particle in &mut self.particles {
                particle.weight /= total_weight;
            }
        }

        // Update concentration based on entropy
        self.concentration = 1.0 / (self.entropy() + 1e-6);
    }

    fn likelihood(state: &HashMap<String, f64>, obs: &HashMap<String, f64>, noise: f64) -> f64 {
        let mut log_likelihood = 0.0;

        for (key, obs_value) in obs {
            if let Some(state_value) = state.get(key) {
                let diff = (state_value - obs_value).powi(2);
                log_likelihood -= diff / (2.0 * noise * noise);
            }
        }

        log_likelihood.exp()
    }
}

/// Relationships between entities
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Relationship {
    /// Relationship type
    pub rel_type: RelationType,

    /// Strength/weight
    pub strength: f64,

    /// Properties
    pub properties: Properties,

    /// Temporal validity
    pub valid_from: Option<DateTime<Utc>>,
    pub valid_until: Option<DateTime<Utc>>,
}

/// Types of relationships
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RelationType {
    Spatial(SpatialRelation),
    Temporal(TemporalRelation),
    Causal(CausalRelation),
    Semantic(String),
    Composite(Vec<RelationType>),
}

/// Spatial relations
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SpatialRelation {
    Near,
    Far,
    Inside,
    Outside,
    Above,
    Below,
    LeftOf,
    RightOf,
    InFrontOf,
    Behind,
    Touching,
    Overlapping,
}

/// Temporal relations (Allen's interval algebra)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TemporalRelation {
    Before,
    After,
    During,
    Contains,
    Overlaps,
    Meets,
    Equals,
    Starts,
    Finishes,
}

/// Causal relations
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CausalRelation {
    Causes,
    Prevents,
    Enables,
    Inhibits,
}

/// Region identifier
#[derive(Debug, Clone, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct RegionId(pub Uuid);

/// Spatial region
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Region {
    /// Region identifier
    pub id: RegionId,

    /// Region name
    pub name: String,

    /// Geometry
    pub geometry: Geometry,

    /// Properties
    pub properties: Properties,

    /// Entities in this region
    pub entities: HashSet<Uuid>,

    /// Sub-regions
    pub subregions: Vec<RegionId>,
}

/// Geometric shapes
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Geometry {
    Point(na::Point3<f64>),
    Box(BoundingBox),
    Sphere { center: na::Point3<f64>, radius: f64 },
    Polygon(Vec<na::Point3<f64>>),
    Mesh { vertices: Vec<na::Point3<f64>>, faces: Vec<[u32; 3]> },
}

impl WorldState {
    pub fn new() -> Self {
        Self {
            entities: HashMap::new(),
            relationships: Graph::new(),
            regions: HashMap::new(),
            globals: Properties::new(),
            timestamp: Utc::now(),
            uncertainty: 0.5,
            abstraction_level: 0,
        }
    }

    /// Add entity to world state
    pub fn add_entity(&mut self, entity: Entity) {
        self.entities.insert(entity.id, entity);
    }

    /// Remove entity from world state
    pub fn remove_entity(&mut self, id: &Uuid) -> Option<Entity> {
        self.entities.remove(id)
    }

    /// Get entity by ID
    pub fn get_entity(&self, id: &Uuid) -> Option<Entity> {
        self.entities.get(id).cloned()
    }

    /// Add relationship between entities
    pub fn add_relationship(&mut self, from: Uuid, to: Uuid, rel: Relationship) {
        let from_idx = self.get_or_create_node(from);
        let to_idx = self.get_or_create_node(to);
        self.relationships.add_edge(from_idx, to_idx, rel);
    }

    fn get_or_create_node(&mut self, id: Uuid) -> NodeIndex {
        // Check if node exists
        for node in self.relationships.node_indices() {
            if self.relationships[node] == id {
                return node;
            }
        }
        // Create new node
        self.relationships.add_node(id)
    }

    /// Query entities by type
    pub fn query_by_type(&self, entity_type: &EntityType) -> Vec<Entity> {
        self.entities
            .values()
            .filter(|e| &e.entity_type == entity_type)
            .cloned()
            .collect()
    }

    /// Query entities by property
    pub fn query_by_property(&self, key: &str, value: &str) -> Vec<Entity> {
        self.entities
            .values()
            .filter(|e| {
                e.properties.get_string(key) == Some(value)
            })
            .cloned()
            .collect()
    }

    /// Query entities with natural language (simplified)
    pub fn query_entities(&self, query: &str) -> Vec<Entity> {
        // Simple keyword matching - in production would use NLP
        let query_lower = query.to_lowercase();

        self.entities
            .values()
            .filter(|e| {
                // Check entity type
                match &e.entity_type {
                    EntityType::Object(name) |
                    EntityType::Agent(name) |
                    EntityType::Location(name) |
                    EntityType::Event(name) |
                    EntityType::Abstract(name) => {
                        name.to_lowercase().contains(&query_lower)
                    },
                    _ => false,
                }
            })
            .cloned()
            .collect()
    }

    /// Merge another world state
    pub fn merge(&mut self, other: WorldState) -> Result<(), String> {
        // Merge entities
        for (id, entity) in other.entities {
            match self.entities.get_mut(&id) {
                Some(existing) => {
                    // Merge properties and beliefs
                    existing.beliefs.update(
                        &entity.beliefs.particles[0].state,
                        0.1
                    );
                },
                None => {
                    self.entities.insert(id, entity);
                },
            }
        }

        // Update timestamp
        self.timestamp = self.timestamp.max(other.timestamp);

        // Update uncertainty (combine uncertainties)
        self.uncertainty = (self.uncertainty + other.uncertainty) / 2.0;

        Ok(())
    }

    /// Create abstracted version of state
    pub fn abstract_to_level(&self, level: u32) -> WorldState {
        let mut abstracted = self.clone();
        abstracted.abstraction_level = level;

        // Higher levels have fewer details
        if level > 0 {
            // Group nearby entities
            abstracted.group_nearby_entities(10.0 * level as f64);

            // Simplify properties
            abstracted.simplify_properties();

            // Increase uncertainty
            abstracted.uncertainty = (abstracted.uncertainty + 0.1 * level as f64).min(1.0);
        }

        abstracted
    }

    fn group_nearby_entities(&mut self, threshold: f64) {
        // Group entities within threshold distance
        let mut groups: Vec<Vec<Uuid>> = Vec::new();
        let mut processed = HashSet::new();

        for (id, entity) in &self.entities {
            if processed.contains(id) {
                continue;
            }

            if let Some(spatial) = &entity.spatial {
                let mut group = vec![*id];
                processed.insert(*id);

                for (other_id, other) in &self.entities {
                    if processed.contains(other_id) {
                        continue;
                    }

                    if let Some(other_spatial) = &other.spatial {
                        let distance = (spatial.position - other_spatial.position).norm();
                        if distance < threshold {
                            group.push(*other_id);
                            processed.insert(*other_id);
                        }
                    }
                }

                if group.len() > 1 {
                    groups.push(group);
                }
            }
        }

        // Create composite entities for groups
        for group in groups {
            let composite_id = Uuid::new_v4();
            let mut composite_props = Properties::new();
            composite_props.set_number("entity_count".to_string(), group.len() as f64);

            let composite = Entity {
                id: composite_id,
                entity_type: EntityType::Composite(
                    group.iter()
                        .filter_map(|id| self.entities.get(id))
                        .map(|e| e.entity_type.clone())
                        .collect()
                ),
                properties: composite_props,
                spatial: self.compute_group_spatial(&group),
                temporal: None,
                beliefs: BeliefState::new_uniform(10),
                active: true,
            };

            // Remove individual entities and add composite
            for id in group {
                self.entities.remove(&id);
            }
            self.entities.insert(composite_id, composite);
        }
    }

    fn compute_group_spatial(&self, group: &[Uuid]) -> Option<SpatialInfo> {
        let positions: Vec<_> = group.iter()
            .filter_map(|id| self.entities.get(id))
            .filter_map(|e| e.spatial.as_ref())
            .map(|s| s.position.coords)
            .collect();

        if positions.is_empty() {
            return None;
        }

        // Compute centroid
        let centroid = positions.iter().sum::<na::Vector3<f64>>() / positions.len() as f64;

        Some(SpatialInfo {
            position: na::Point3::from(centroid),
            orientation: na::UnitQuaternion::identity(),
            velocity: na::Vector3::zeros(),
            acceleration: na::Vector3::zeros(),
            bounds: None,
            frame: ReferenceFrame::World,
        })
    }

    fn simplify_properties(&mut self) {
        for entity in self.entities.values_mut() {
            // Keep only important properties (simplified heuristic)
            let important_keys: HashSet<_> = entity.properties.strings.keys()
                .filter(|k| k.contains("type") || k.contains("name") || k.contains("id"))
                .cloned()
                .collect();

            entity.properties.strings.retain(|k, _| important_keys.contains(k));

            // Round numeric properties
            for value in entity.properties.numbers.values_mut() {
                *value = (*value * 10.0).round() / 10.0;
            }
        }
    }
}

/// State difference for efficient updates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateDiff {
    /// Added entities
    pub added: Vec<Entity>,

    /// Removed entity IDs
    pub removed: Vec<Uuid>,

    /// Modified entities
    pub modified: Vec<(Uuid, PropertyDiff)>,

    /// Relationship changes
    pub relationship_changes: Vec<RelationshipChange>,
}

/// Property difference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PropertyDiff {
    pub added: Properties,
    pub removed: Vec<String>,
    pub modified: Properties,
}

/// Relationship change
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RelationshipChange {
    Added { from: Uuid, to: Uuid, rel: Relationship },
    Removed { from: Uuid, to: Uuid },
    Modified { from: Uuid, to: Uuid, rel: Relationship },
}

impl WorldState {
    /// Compute difference between states
    pub fn diff(&self, other: &WorldState) -> StateDiff {
        let mut added = Vec::new();
        let mut removed = Vec::new();
        let mut modified = Vec::new();

        // Find added entities
        for (id, entity) in &other.entities {
            if !self.entities.contains_key(id) {
                added.push(entity.clone());
            }
        }

        // Find removed entities
        for id in self.entities.keys() {
            if !other.entities.contains_key(id) {
                removed.push(*id);
            }
        }

        // Find modified entities
        for (id, entity) in &self.entities {
            if let Some(other_entity) = other.entities.get(id) {
                let prop_diff = Self::compute_property_diff(
                    &entity.properties,
                    &other_entity.properties
                );

                if !prop_diff.is_empty() {
                    modified.push((*id, prop_diff));
                }
            }
        }

        StateDiff {
            added,
            removed,
            modified,
            relationship_changes: Vec::new(), // Simplified
        }
    }

    fn compute_property_diff(old: &Properties, new: &Properties) -> PropertyDiff {
        let mut added = Properties::new();
        let mut removed = Vec::new();
        let mut modified = Properties::new();

        // Check booleans
        for (key, value) in &new.booleans {
            if !old.booleans.contains_key(key) {
                added.booleans.insert(key.clone(), *value);
            } else if old.booleans[key] != *value {
                modified.booleans.insert(key.clone(), *value);
            }
        }

        for key in old.booleans.keys() {
            if !new.booleans.contains_key(key) {
                removed.push(key.clone());
            }
        }

        // Similar for other property types...

        PropertyDiff { added, removed, modified }
    }
}

impl PropertyDiff {
    fn is_empty(&self) -> bool {
        self.added.booleans.is_empty() &&
        self.added.numbers.is_empty() &&
        self.added.strings.is_empty() &&
        self.removed.is_empty() &&
        self.modified.booleans.is_empty() &&
        self.modified.numbers.is_empty() &&
        self.modified.strings.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_world_state_creation() {
        let state = WorldState::new();
        assert!(state.entities.is_empty());
        assert_eq!(state.abstraction_level, 0);
    }

    #[test]
    fn test_entity_creation() {
        let entity = Entity {
            id: Uuid::new_v4(),
            entity_type: EntityType::Object("cube".to_string()),
            properties: Properties::new(),
            spatial: Some(SpatialInfo {
                position: na::Point3::new(0.0, 0.0, 0.0),
                orientation: na::UnitQuaternion::identity(),
                velocity: na::Vector3::zeros(),
                acceleration: na::Vector3::zeros(),
                bounds: None,
                frame: ReferenceFrame::World,
            }),
            temporal: None,
            beliefs: BeliefState::new_uniform(100),
            active: true,
        };

        assert_eq!(entity.entity_type, EntityType::Object("cube".to_string()));
        assert!(entity.active);
    }

    #[test]
    fn test_belief_state() {
        let mut beliefs = BeliefState::new_uniform(100);
        assert_eq!(beliefs.particles.len(), 100);

        let observation = HashMap::from([
            ("x".to_string(), 1.0),
            ("y".to_string(), 2.0),
        ]);

        beliefs.update(&observation, 0.1);

        let entropy = beliefs.entropy();
        assert!(entropy >= 0.0);
    }

    #[test]
    fn test_properties() {
        let mut props = Properties::new();
        props.set_bool("visible".to_string(), true);
        props.set_number("mass".to_string(), 10.5);
        props.set_string("name".to_string(), "TestObject".to_string());

        assert_eq!(props.get_bool("visible"), Some(true));
        assert_eq!(props.get_number("mass"), Some(10.5));
        assert_eq!(props.get_string("name"), Some("TestObject"));
    }

    #[test]
    fn test_world_state_abstraction() {
        let mut state = WorldState::new();

        // Add some entities
        for i in 0..5 {
            let entity = Entity {
                id: Uuid::new_v4(),
                entity_type: EntityType::Object(format!("object_{}", i)),
                properties: Properties::new(),
                spatial: Some(SpatialInfo {
                    position: na::Point3::new(i as f64, 0.0, 0.0),
                    orientation: na::UnitQuaternion::identity(),
                    velocity: na::Vector3::zeros(),
                    acceleration: na::Vector3::zeros(),
                    bounds: None,
                    frame: ReferenceFrame::World,
                }),
                temporal: None,
                beliefs: BeliefState::new_uniform(10),
                active: true,
            };
            state.add_entity(entity);
        }

        let abstract_state = state.abstract_to_level(1);
        assert_eq!(abstract_state.abstraction_level, 1);
        assert!(abstract_state.uncertainty > state.uncertainty);
    }
}
