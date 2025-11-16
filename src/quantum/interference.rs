use super::{
    hypothesis::QuantumHypothesis,
    superposition::SuperpositionState,
};
use num_complex::Complex64;
use tracing::info;
use uuid;

/// Handles quantum-like interference between hypotheses
pub struct InterferenceEngine {
    coupling_strength: f64,
}

impl InterferenceEngine {
    pub fn new(coupling_strength: f64) -> Self {
        Self { coupling_strength }
    }
    
    /// Constructive interference: hypotheses with similar phases reinforce
    pub fn apply_constructive_interference(
        &self,
        state: &mut SuperpositionState,
        hypothesis_ids: &[uuid::Uuid],
    ) {
        let hypotheses = state.get_hypotheses_mut();
        
        // Find hypotheses by IDs
        let mut target_indices = Vec::new();
        for (idx, hyp) in hypotheses.iter().enumerate() {
            if hypothesis_ids.contains(&hyp.id) {
                target_indices.push(idx);
            }
        }
        
        if target_indices.len() < 2 {
            return;
        }
        
        // Calculate average phase
        let avg_phase: f64 = target_indices.iter()
            .map(|&idx| hypotheses[idx].phase)
            .sum::<f64>() / target_indices.len() as f64;
        
        // Increase amplitudes with constructive interference
        for &idx in &target_indices {
            let hyp = &mut hypotheses[idx];
            let magnitude = hyp.amplitude.norm() * (1.0 + self.coupling_strength);
            let phase_diff = (hyp.phase - avg_phase).abs();
            let phase_factor = (1.0 - phase_diff / std::f64::consts::PI).max(0.0);
            
            let new_magnitude = magnitude * (1.0 + phase_factor * self.coupling_strength);
            hyp.update_amplitude(Complex64::from_polar(new_magnitude, hyp.phase));
        }
        
        state.normalize();
        
        info!("⚛️ Constructive interference applied to {} hypotheses", 
              target_indices.len());
    }
    
    /// Destructive interference: hypotheses with opposite phases cancel
    pub fn apply_destructive_interference(
        &self,
        state: &mut SuperpositionState,
        hypothesis_ids: &[uuid::Uuid],
    ) {
        let hypotheses = state.get_hypotheses_mut();
        
        // Find hypotheses by IDs
        let mut target_indices = Vec::new();
        for (idx, hyp) in hypotheses.iter().enumerate() {
            if hypothesis_ids.contains(&hyp.id) {
                target_indices.push(idx);
            }
        }
        
        if target_indices.len() < 2 {
            return;
        }
        
        // Calculate phase differences
        for i in 0..target_indices.len() {
            for j in (i + 1)..target_indices.len() {
                let idx_i = target_indices[i];
                let idx_j = target_indices[j];
                
                let phase_diff = (hypotheses[idx_i].phase - hypotheses[idx_j].phase).abs();
                
                // Destructive interference when phases are ~π apart
                if phase_diff > std::f64::consts::PI * 0.5 && phase_diff < std::f64::consts::PI * 1.5 {
                    let reduction = self.coupling_strength * (1.0 - (phase_diff - std::f64::consts::PI).abs() / (std::f64::consts::PI * 0.5));
                    
                    // Reduce both amplitudes
                    let mag_i = hypotheses[idx_i].amplitude.norm() * (1.0 - reduction);
                    let mag_j = hypotheses[idx_j].amplitude.norm() * (1.0 - reduction);
                    
                    hypotheses[idx_i].update_amplitude(
                        Complex64::from_polar(mag_i.max(0.0), hypotheses[idx_i].phase)
                    );
                    hypotheses[idx_j].update_amplitude(
                        Complex64::from_polar(mag_j.max(0.0), hypotheses[idx_j].phase)
                    );
                }
            }
        }
        
        state.normalize();
        
        info!("⚛️ Destructive interference applied to {} hypotheses", 
              target_indices.len());
    }
}

