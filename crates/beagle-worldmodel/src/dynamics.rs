// crates/beagle-worldmodel/src/dynamics.rs
//! World dynamics modeling and physics simulation

use nalgebra as na;
use rapier3d::prelude::*;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::state::{Entity, SpatialInfo, WorldState};
use crate::WorldModelError;

/// Dynamics model for physical simulation
pub struct DynamicsModel {
    /// Physics engine
    physics: PhysicsEngine,

    /// Dynamics parameters
    params: DynamicsParameters,
}

/// Physics engine wrapper
pub struct PhysicsEngine {
    /// Rigid body set
    bodies: RigidBodySet,

    /// Collider set
    colliders: ColliderSet,

    /// Integration parameters
    integration_params: IntegrationParameters,

    /// Physics pipeline
    physics_pipeline: PhysicsPipeline,

    /// Island manager
    islands: IslandManager,

    /// Broad phase
    broad_phase: DefaultBroadPhase,

    /// Narrow phase
    narrow_phase: NarrowPhase,

    /// Joint set
    impulse_joints: ImpulseJointSet,

    /// Multibody joint set
    multibody_joints: MultibodyJointSet,

    /// CCD solver
    ccd_solver: CCDSolver,
}

/// Dynamics parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DynamicsParameters {
    /// Gravity vector
    pub gravity: na::Vector3<f32>,

    /// Time step (seconds)
    pub dt: f32,

    /// Maximum velocity
    pub max_velocity: f32,

    /// Friction coefficient
    pub friction: f32,

    /// Restitution coefficient
    pub restitution: f32,
}

impl Default for DynamicsParameters {
    fn default() -> Self {
        Self {
            gravity: na::Vector3::new(0.0, -9.81, 0.0),
            dt: 1.0 / 60.0,
            max_velocity: 100.0,
            friction: 0.5,
            restitution: 0.3,
        }
    }
}

impl PhysicsEngine {
    pub fn new(params: &DynamicsParameters) -> Self {
        let mut integration_params = IntegrationParameters::default();
        integration_params.dt = params.dt;

        Self {
            bodies: RigidBodySet::new(),
            colliders: ColliderSet::new(),
            integration_params,
            physics_pipeline: PhysicsPipeline::new(),
            islands: IslandManager::new(),
            broad_phase: DefaultBroadPhase::new(),
            narrow_phase: NarrowPhase::new(),
            impulse_joints: ImpulseJointSet::new(),
            multibody_joints: MultibodyJointSet::new(),
            ccd_solver: CCDSolver::new(),
        }
    }

    pub fn step(&mut self, gravity: na::Vector3<f32>) {
        self.physics_pipeline.step(
            &gravity,
            &self.integration_params,
            &mut self.islands,
            &mut self.broad_phase,
            &mut self.narrow_phase,
            &mut self.bodies,
            &mut self.colliders,
            &mut self.impulse_joints,
            &mut self.multibody_joints,
            &mut self.ccd_solver,
            None,
            &(),
            &(),
        );
    }

    pub fn add_entity(
        &mut self,
        entity: &Entity,
        params: &DynamicsParameters,
    ) -> Option<RigidBodyHandle> {
        if let Some(spatial) = &entity.spatial {
            // Create rigid body
            let rigid_body = RigidBodyBuilder::dynamic()
                .translation(vector![
                    spatial.position.x as f32,
                    spatial.position.y as f32,
                    spatial.position.z as f32
                ])
                .linvel(vector![
                    spatial.velocity.x as f32,
                    spatial.velocity.y as f32,
                    spatial.velocity.z as f32
                ])
                .build();

            let handle = self.bodies.insert(rigid_body);

            // Add collider
            let collider = ColliderBuilder::ball(1.0)
                .friction(params.friction)
                .restitution(params.restitution)
                .build();

            self.colliders
                .insert_with_parent(collider, handle, &mut self.bodies);

            Some(handle)
        } else {
            None
        }
    }

    pub fn update_entity(&mut self, handle: RigidBodyHandle, spatial: &SpatialInfo) {
        if let Some(body) = self.bodies.get_mut(handle) {
            body.set_translation(
                vector![
                    spatial.position.x as f32,
                    spatial.position.y as f32,
                    spatial.position.z as f32
                ],
                true,
            );

            body.set_linvel(
                vector![
                    spatial.velocity.x as f32,
                    spatial.velocity.y as f32,
                    spatial.velocity.z as f32
                ],
                true,
            );
        }
    }

    pub fn get_position(&self, handle: RigidBodyHandle) -> Option<na::Point3<f64>> {
        self.bodies.get(handle).map(|body| {
            let pos = body.translation();
            na::Point3::new(pos.x as f64, pos.y as f64, pos.z as f64)
        })
    }

    pub fn get_velocity(&self, handle: RigidBodyHandle) -> Option<na::Vector3<f64>> {
        self.bodies.get(handle).map(|body| {
            let vel = body.linvel();
            na::Vector3::new(vel.x as f64, vel.y as f64, vel.z as f64)
        })
    }
}

impl DynamicsModel {
    pub fn new() -> Self {
        let params = DynamicsParameters::default();
        Self {
            physics: PhysicsEngine::new(&params),
            params,
        }
    }

    /// Simulate dynamics forward
    pub fn simulate(
        &mut self,
        state: &mut WorldState,
        timesteps: usize,
    ) -> Result<(), WorldModelError> {
        // Add entities to physics engine
        let mut handles = std::collections::HashMap::new();

        for (id, entity) in &state.entities {
            if let Some(handle) = self.physics.add_entity(entity, &self.params) {
                handles.insert(*id, handle);
            }
        }

        // Simulate timesteps
        for _ in 0..timesteps {
            self.physics.step(self.params.gravity);
        }

        // Update entity positions
        for (id, handle) in handles {
            if let Some(entity) = state.entities.get_mut(&id) {
                if let Some(mut spatial) = entity.spatial.as_mut() {
                    if let Some(pos) = self.physics.get_position(handle) {
                        spatial.position = pos;
                    }
                    if let Some(vel) = self.physics.get_velocity(handle) {
                        spatial.velocity = vel;
                    }
                }
            }
        }

        Ok(())
    }
}
