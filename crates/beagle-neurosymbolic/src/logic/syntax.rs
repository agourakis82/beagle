use serde::{Deserialize, Serialize};
use std::fmt;

/// Term in FOL (constants, variables, functions)
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Term {
    /// Constant: "john", "5", "biomaterial_scaffold"
    Constant(String),
    /// Variable: X, Y, Z
    Variable(String),
    /// Function: f(t1, t2, ..., tn)
    Function { name: String, args: Vec<Term> },
}

impl fmt::Display for Term {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Term::Constant(c) => write!(f, "{}", c),
            Term::Variable(v) => write!(f, "{}", v),
            Term::Function { name, args } => {
                write!(f, "{}(", name)?;
                for (i, arg) in args.iter().enumerate() {
                    if i > 0 {
                        write!(f, ", ")?;
                    }
                    write!(f, "{}", arg)?;
                }
                write!(f, ")")
            }
        }
    }
}

/// Predicate: P(t1, t2, ..., tn)
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Predicate {
    pub name: String,
    pub args: Vec<Term>,
}

impl fmt::Display for Predicate {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}(", self.name)?;
        for (i, arg) in self.args.iter().enumerate() {
            if i > 0 {
                write!(f, ", ")?;
            }
            write!(f, "{}", arg)?;
        }
        write!(f, ")")
    }
}

/// Formula in FOL
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Formula {
    /// Atomic: P(t1, ..., tn)
    Atom(Predicate),
    /// Negation: ¬φ
    Not(Box<Formula>),
    /// Conjunction: φ ∧ ψ
    And(Box<Formula>, Box<Formula>),
    /// Disjunction: φ ∨ ψ
    Or(Box<Formula>, Box<Formula>),
    /// Implication: φ → ψ
    Implies(Box<Formula>, Box<Formula>),
    /// Equivalence: φ ↔ ψ
    Iff(Box<Formula>, Box<Formula>),
    /// Universal: ∀x φ
    ForAll { variable: String, body: Box<Formula> },
    /// Existential: ∃x φ
    Exists { variable: String, body: Box<Formula> },
}

impl fmt::Display for Formula {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Formula::Atom(p) => write!(f, "{}", p),
            Formula::Not(phi) => write!(f, "¬({})", phi),
            Formula::And(phi, psi) => write!(f, "({} ∧ {})", phi, psi),
            Formula::Or(phi, psi) => write!(f, "({} ∨ {})", phi, psi),
            Formula::Implies(phi, psi) => write!(f, "({} → {})", phi, psi),
            Formula::Iff(phi, psi) => write!(f, "({} ↔ {})", phi, psi),
            Formula::ForAll { variable, body } => write!(f, "∀{}.{}", variable, body),
            Formula::Exists { variable, body } => write!(f, "∃{}.{}", variable, body),
        }
    }
}

// Helper constructors
impl Formula {
    pub fn atom(name: impl Into<String>, args: Vec<Term>) -> Self {
        Formula::Atom(Predicate {
            name: name.into(),
            args,
        })
    }
    pub fn not(self) -> Self {
        Formula::Not(Box::new(self))
    }
    pub fn and(self, other: Self) -> Self {
        Formula::And(Box::new(self), Box::new(other))
    }
    pub fn or(self, other: Self) -> Self {
        Formula::Or(Box::new(self), Box::new(other))
    }
    pub fn implies(self, other: Self) -> Self {
        Formula::Implies(Box::new(self), Box::new(other))
    }
}


