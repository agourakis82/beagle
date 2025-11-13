use super::{
    hypothesis::QuantumHypothesis,
    superposition::SuperpositionState,
};
use rand::Rng;
use tracing::info;

/// Performs "measurement" to collapse superposition
pub struct MeasurementOperator {
    threshold: f64,
}

impl MeasurementOperator {
    pub fn new(threshold: f64) -> Self {
        Self { threshold }
    }
    
    /// Collapse superposition to single hypothesis
    pub fn measure(&self, state: &mut SuperpositionState) -> Option<QuantumHypothesis> {
        if state.is_collapsed() {
            return None;
        }
        
        let hypotheses = state.get_hypotheses();
        
        if hypotheses.is_empty() {
            return None;
        }
        
        // Check if any hypothesis has probability above threshold
        let max_prob = hypotheses.iter()
            .map(|h| h.probability)
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(0.0);
        
        if max_prob < self.threshold {
            info!("⚛️ Superposition maintained (max_prob: {:.3} < threshold: {:.3})", 
                  max_prob, self.threshold);
            return None;
        }
        
        // Collapse to hypothesis with highest probability
        let selected = hypotheses.iter()
            .max_by(|a, b| a.probability.partial_cmp(&b.probability).unwrap())
            .unwrap()
            .clone();
        
        state.set_collapsed();
        
        info!("⚛️ Wavefunction collapsed to: {} (prob: {:.3})", 
              &selected.content[..50.min(selected.content.len())], 
              selected.probability);
        
        Some(selected)
    }
    
    /// Stochastic measurement (like quantum mechanics)
    pub fn measure_stochastic(&self, state: &mut SuperpositionState) -> Option<QuantumHypothesis> {
        if state.is_collapsed() {
            return None;
        }
        
        let hypotheses = state.get_hypotheses();
        
        if hypotheses.is_empty() {
            return None;
        }
        
        // Random selection weighted by probabilities
        let mut rng = rand::thread_rng();
        let r: f64 = rng.gen();
        
        let mut cumulative = 0.0;
        for hyp in hypotheses {
            cumulative += hyp.probability;
            if r <= cumulative {
                let selected = hyp.clone();
                state.set_collapsed();
                
                info!("⚛️ Stochastic collapse to: {} (prob: {:.3}, r: {:.3})", 
                      &selected.content[..50.min(selected.content.len())], 
                      selected.probability,
                      r);
                
                return Some(selected);
            }
        }
        
        // Fallback to highest probability (shouldn't happen if normalized)
        self.measure(state)
    }
}



