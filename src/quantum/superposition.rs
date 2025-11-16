use super::hypothesis::QuantumHypothesis;

/// State containing multiple hypotheses in superposition
pub struct SuperpositionState {
    hypotheses: Vec<QuantumHypothesis>,
    is_collapsed: bool,
}

impl SuperpositionState {
    pub fn new(hypotheses: Vec<QuantumHypothesis>) -> Self {
        Self {
            hypotheses,
            is_collapsed: false,
        }
    }
    
    pub fn add_hypothesis(&mut self, hypothesis: QuantumHypothesis) {
        if !self.is_collapsed {
            self.hypotheses.push(hypothesis);
            self.normalize();
        }
    }
    
    /// Normalize amplitudes so sum of probabilities = 1
    pub fn normalize(&mut self) {
        let total_prob: f64 = self.hypotheses.iter()
            .map(|h| h.probability)
            .sum();
        
        if total_prob > 0.0 {
            let norm_factor = (1.0 / total_prob).sqrt();
            for hyp in &mut self.hypotheses {
                let new_amp = hyp.amplitude * norm_factor;
                hyp.update_amplitude(new_amp);
            }
        }
    }
    
    pub fn get_hypotheses(&self) -> &[QuantumHypothesis] {
        &self.hypotheses
    }
    
    pub fn is_collapsed(&self) -> bool {
        self.is_collapsed
    }
    
    pub fn set_collapsed(&mut self) {
        self.is_collapsed = true;
    }
    
    /// Get entropy (measure of uncertainty)
    pub fn entropy(&self) -> f64 {
        self.hypotheses.iter()
            .map(|h| {
                if h.probability > 0.0 {
                    -h.probability * h.probability.ln()
                } else {
                    0.0
                }
            })
            .sum()
    }
    
    /// Get mutable reference to hypotheses (for interference operations)
    pub fn get_hypotheses_mut(&mut self) -> &mut Vec<QuantumHypothesis> {
        &mut self.hypotheses
    }
}

