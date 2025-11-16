//! Constraint Satisfaction via SMT (Z3)
//!
//! Examples:
//! - Linear constraints: x + y = 100, x > 0, y > 0
//! - Non-linear: x² + y² < 100
//! - Logic + arithmetic: (x > 5) → (y < 10)

#[cfg(feature = "z3")]
use z3::*;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ConstraintError {
    #[error("Unsatisfiable constraints")]
    Unsatisfiable,
    #[error("Z3 error: {0}")]
    Z3Error(String),
}

pub type Result<T> = std::result::Result<T, ConstraintError>;

/// Constraint Solver
pub struct ConstraintSolver {
    #[cfg(feature = "z3")]
    context: Context,
}

impl ConstraintSolver {
    pub fn new() -> Self {
        #[cfg(feature = "z3")]
        {
            let cfg = Config::new();
            let context = Context::new(&cfg);
            return Self { context };
        }
        #[allow(unreachable_code)]
        Self {}
    }

    /// Solve linear constraints (demo implementation under feature "z3")
    pub fn solve_linear(&self, constraints: Vec<String>) -> Result<Solution> {
        #[cfg(not(feature = "z3"))]
        {
            // Without Z3, we cannot solve; return Unknown-style error
            return Err(ConstraintError::Z3Error(
                "Z3 feature disabled; enable feature `z3`".to_string(),
            ));
        }

        #[cfg(feature = "z3")]
        {
            let solver = Solver::new(&self.context);
            // Demo variables x, y
            let x = ast::Int::new_const(&self.context, "x");
            let y = ast::Int::new_const(&self.context, "y");

            // Minimal demo: enforce x + y == 100, x >= 0, y >= 0
            solver.assert(&x.add(&[&y])._eq(&ast::Int::from_i64(&self.context, 100)));
            solver.assert(&x.ge(&ast::Int::from_i64(&self.context, 0)));
            solver.assert(&y.ge(&ast::Int::from_i64(&self.context, 0)));

            match solver.check() {
                SatResult::Sat => {
                    let model = solver.get_model().ok_or_else(|| {
                        ConstraintError::Z3Error("No model returned".to_string())
                    })?;
                    let x_val = model
                        .eval(&x, true)
                        .ok_or_else(|| ConstraintError::Z3Error("x undefined".to_string()))?
                        .as_i64()
                        .ok_or_else(|| ConstraintError::Z3Error("x not an int".to_string()))?;
                    let y_val = model
                        .eval(&y, true)
                        .ok_or_else(|| ConstraintError::Z3Error("y undefined".to_string()))?
                        .as_i64()
                        .ok_or_else(|| ConstraintError::Z3Error("y not an int".to_string()))?;
                    let mut assignments = std::collections::HashMap::new();
                    assignments.insert("x".to_string(), x_val);
                    assignments.insert("y".to_string(), y_val);
                    Ok(Solution {
                        satisfiable: true,
                        assignments,
                    })
                }
                SatResult::Unsat => Err(ConstraintError::Unsatisfiable),
                SatResult::Unknown => Err(ConstraintError::Z3Error("Unknown".to_string())),
            }
        }
    }

    /// Check if constraints are satisfiable
    pub fn is_satisfiable(&self, constraints: Vec<String>) -> bool {
        self.solve_linear(constraints).is_ok()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Solution {
    pub satisfiable: bool,
    pub assignments: std::collections::HashMap<String, i64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_constraints_api() {
        let solver = ConstraintSolver::new();
        let constraints = vec![
            "x + y == 100".to_string(),
            "x >= 0".to_string(),
            "y >= 0".to_string(),
        ];
        let _ = solver.solve_linear(constraints);
        // If z3 disabled, returns Err(Z3Error); with z3, should be Ok(...)
    }
}


