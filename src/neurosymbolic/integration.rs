use super::{
    neural::NeuralExtractor,
    symbolic::SymbolicReasoner,
    constraint::ConstraintSolver,
};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;

/// Integrates neural, symbolic, and constraint reasoning
pub struct HybridReasoner {
    neural: Arc<NeuralExtractor>,
    symbolic: SymbolicReasoner,
    constraint: ConstraintSolver,
}

impl HybridReasoner {
    pub fn new(neural: Arc<NeuralExtractor>) -> Self {
        Self {
            neural,
            symbolic: SymbolicReasoner::new(),
            constraint: ConstraintSolver::new(),
        }
    }
    
    pub async fn reason(&mut self, query: &str, text: &str) -> Result<HybridResult> {
        info!("🔬 Hybrid neuro-symbolic reasoning initiated");
        
        // Step 1: Neural extraction
        info!("📊 Extracting predicates via LLM");
        let predicates = self.neural.extract_predicates(text).await?;
        info!("✅ Extracted {} predicates", predicates.len());
        
        // Step 2: Add facts to symbolic reasoner
        for predicate in &predicates {
            self.symbolic.add_fact(predicate.clone());
        }
        
        // Step 3: Check consistency
        let consistency = self.symbolic.check_consistency();
        if !consistency.is_consistent {
            info!("⚠️  Found {} contradictions", consistency.contradictions.len());
        }
        
        // Step 4: Apply inference rules
        let inferred = self.symbolic.infer();
        info!("🧠 Inferred {} new facts", inferred.len());
        
        // Step 5: Add inferred facts
        for fact in inferred {
            self.symbolic.add_fact(fact);
        }
        
        // Step 6: Constraint satisfaction (if applicable)
        // This would be used for optimization problems
        
        Ok(HybridResult {
            extracted_predicates: predicates,
            inferred_predicates: self.symbolic.infer(),
            consistency_result: consistency,
            answer: format!("Processed {} facts with {} contradictions", 
                self.symbolic.fact_count(), 
                consistency.contradictions.len()),
        })
    }
    
    pub fn get_symbolic_reasoner(&self) -> &SymbolicReasoner {
        &self.symbolic
    }
    
    pub fn get_constraint_solver(&self) -> &ConstraintSolver {
        &self.constraint
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HybridResult {
    pub extracted_predicates: Vec<super::neural::Predicate>,
    pub inferred_predicates: Vec<super::neural::Predicate>,
    pub consistency_result: super::symbolic::ConsistencyResult,
    pub answer: String,
}

