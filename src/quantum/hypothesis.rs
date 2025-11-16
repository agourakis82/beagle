use num_complex::Complex64;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuantumHypothesis {
    pub id: Uuid,
    pub content: String,
    
    /// Complex amplitude (like quantum wavefunction)
    #[serde(skip)]
    pub amplitude: Complex64,
    
    /// Probability = |amplitude|²
    pub probability: f64,
    
    /// Phase (for interference)
    pub phase: f64,
    
    /// Evidence supporting this hypothesis
    pub evidence_count: usize,
}

impl QuantumHypothesis {
    pub fn new(content: String, amplitude: Complex64) -> Self {
        let probability = amplitude.norm_sqr();
        let phase = amplitude.arg();
        
        Self {
            id: Uuid::new_v4(),
            content,
            amplitude,
            probability,
            phase,
            evidence_count: 0,
        }
    }
    
    pub fn update_amplitude(&mut self, new_amplitude: Complex64) {
        self.amplitude = new_amplitude;
        self.probability = new_amplitude.norm_sqr();
        self.phase = new_amplitude.arg();
    }
    
    pub fn add_evidence(&mut self) {
        self.evidence_count += 1;
        
        // Evidence increases amplitude magnitude
        let magnitude = self.amplitude.norm() * 1.1;
        self.amplitude = Complex64::from_polar(magnitude, self.phase);
        self.probability = self.amplitude.norm_sqr();
    }
}



