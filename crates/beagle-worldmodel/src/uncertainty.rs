// crates/beagle-worldmodel/src/uncertainty.rs
//! Uncertainty quantification and propagation

use nalgebra as na;
use serde::{Deserialize, Serialize};
use statrs::distribution::{ContinuousCDF, Normal};
use std::collections::HashMap;

use crate::state::WorldState;

/// Uncertainty quantification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Uncertainty {
    /// Aleatoric uncertainty (data noise)
    pub aleatoric: f64,

    /// Epistemic uncertainty (model uncertainty)
    pub epistemic: f64,

    /// Distribution parameters
    pub distribution: UncertaintyDistribution,

    /// Confidence intervals
    pub intervals: ConfidenceIntervals,
}

/// Uncertainty distribution types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum UncertaintyDistribution {
    Gaussian { mean: f64, std: f64 },
    Uniform { min: f64, max: f64 },
    Beta { alpha: f64, beta: f64 },
    Empirical { samples: Vec<f64> },
}

/// Confidence intervals
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfidenceIntervals {
    pub ci_50: (f64, f64),
    pub ci_90: (f64, f64),
    pub ci_95: (f64, f64),
    pub ci_99: (f64, f64),
}

impl Uncertainty {
    /// Create Gaussian uncertainty
    pub fn gaussian(mean: f64, std: f64) -> Self {
        let dist = Normal::new(mean, std).unwrap();

        Self {
            aleatoric: std * std,
            epistemic: 0.0,
            distribution: UncertaintyDistribution::Gaussian { mean, std },
            intervals: ConfidenceIntervals {
                ci_50: (dist.inverse_cdf(0.25), dist.inverse_cdf(0.75)),
                ci_90: (dist.inverse_cdf(0.05), dist.inverse_cdf(0.95)),
                ci_95: (dist.inverse_cdf(0.025), dist.inverse_cdf(0.975)),
                ci_99: (dist.inverse_cdf(0.005), dist.inverse_cdf(0.995)),
            },
        }
    }

    /// Propagate uncertainty through function
    pub fn propagate<F>(&self, f: F) -> Self
    where
        F: Fn(f64) -> f64,
    {
        match &self.distribution {
            UncertaintyDistribution::Gaussian { mean, std } => {
                // Linear approximation
                let f_mean = f(*mean);
                let delta = 0.001;
                let derivative = (f(mean + delta) - f(mean - delta)) / (2.0 * delta);
                let f_std = derivative.abs() * std;

                Self::gaussian(f_mean, f_std)
            }
            _ => self.clone(),
        }
    }

    /// Combine uncertainties
    pub fn combine(&self, other: &Uncertainty) -> Uncertainty {
        match (&self.distribution, &other.distribution) {
            (
                UncertaintyDistribution::Gaussian { mean: m1, std: s1 },
                UncertaintyDistribution::Gaussian { mean: m2, std: s2 },
            ) => {
                // Combine Gaussians
                let combined_mean = (m1 + m2) / 2.0;
                let combined_std = ((s1 * s1 + s2 * s2) / 2.0).sqrt();

                Self::gaussian(combined_mean, combined_std)
            }
            _ => self.clone(),
        }
    }

    /// Total uncertainty
    pub fn total(&self) -> f64 {
        (self.aleatoric + self.epistemic).sqrt()
    }
}

/// Uncertainty propagation through world model
pub struct UncertaintyPropagator {
    /// Propagation method
    method: PropagationMethod,
}

/// Propagation methods
#[derive(Debug, Clone)]
pub enum PropagationMethod {
    /// Monte Carlo sampling
    MonteCarlo { n_samples: usize },

    /// Unscented transform
    Unscented,

    /// Particle filter
    ParticleFilter { n_particles: usize },

    /// Analytical (for linear systems)
    Analytical,
}

impl UncertaintyPropagator {
    pub fn new(method: PropagationMethod) -> Self {
        Self { method }
    }

    /// Propagate uncertainty through world state transition
    pub fn propagate_state(
        &self,
        state: &WorldState,
        uncertainty: &HashMap<String, Uncertainty>,
    ) -> HashMap<String, Uncertainty> {
        match &self.method {
            PropagationMethod::MonteCarlo { n_samples } => {
                self.monte_carlo_propagation(state, uncertainty, *n_samples)
            }
            PropagationMethod::Unscented => self.unscented_propagation(state, uncertainty),
            _ => uncertainty.clone(),
        }
    }

    fn monte_carlo_propagation(
        &self,
        state: &WorldState,
        uncertainty: &HashMap<String, Uncertainty>,
        n_samples: usize,
    ) -> HashMap<String, Uncertainty> {
        use rand::prelude::*;
        use rand_distr::Normal;

        let mut propagated = HashMap::new();
        let mut rng = thread_rng();

        for (var, unc) in uncertainty {
            let mut samples = Vec::new();

            match &unc.distribution {
                UncertaintyDistribution::Gaussian { mean, std } => {
                    let dist = Normal::new(*mean, *std).unwrap();

                    for _ in 0..n_samples {
                        let sample = dist.sample(&mut rng);
                        // Propagate through dynamics (simplified)
                        let propagated_sample = sample * 1.1; // Example transformation
                        samples.push(propagated_sample);
                    }
                }
                _ => {}
            }

            // Compute statistics
            if !samples.is_empty() {
                let mean = samples.iter().sum::<f64>() / samples.len() as f64;
                let variance =
                    samples.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / samples.len() as f64;
                let std = variance.sqrt();

                propagated.insert(var.clone(), Uncertainty::gaussian(mean, std));
            }
        }

        propagated
    }

    fn unscented_propagation(
        &self,
        state: &WorldState,
        uncertainty: &HashMap<String, Uncertainty>,
    ) -> HashMap<String, Uncertainty> {
        // Unscented transform
        let n = uncertainty.len();
        let lambda = 1.0; // Tuning parameter
        let alpha = 0.001;
        let beta = 2.0;

        // Generate sigma points
        let mut sigma_points = Vec::new();

        // Mean point
        let mean_point: Vec<f64> = uncertainty
            .values()
            .filter_map(|u| match &u.distribution {
                UncertaintyDistribution::Gaussian { mean, .. } => Some(*mean),
                _ => None,
            })
            .collect();

        sigma_points.push(mean_point.clone());

        // Sigma points around mean
        for i in 0..n {
            let mut plus_point = mean_point.clone();
            let mut minus_point = mean_point.clone();

            if let Some(unc) = uncertainty.values().nth(i) {
                if let UncertaintyDistribution::Gaussian { std, .. } = &unc.distribution {
                    let offset = (((n as f64 + lambda) * std * std).sqrt());
                    plus_point[i] += offset;
                    minus_point[i] -= offset;
                }
            }

            sigma_points.push(plus_point);
            sigma_points.push(minus_point);
        }

        // Transform sigma points (simplified)
        let transformed: Vec<Vec<f64>> = sigma_points
            .iter()
            .map(|point| point.iter().map(|x| x * 1.1).collect())
            .collect();

        // Compute statistics
        let mut propagated = HashMap::new();

        for (i, (var, _)) in uncertainty.iter().enumerate() {
            let values: Vec<f64> = transformed.iter().map(|point| point[i]).collect();

            let mean = values.iter().sum::<f64>() / values.len() as f64;
            let variance =
                values.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / values.len() as f64;

            propagated.insert(var.clone(), Uncertainty::gaussian(mean, variance.sqrt()));
        }

        propagated
    }
}

