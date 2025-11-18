//! Serendipity Engine
//!
//! Implementa serendipidade deliberada através de:
//! • Injeção controlada de ruído semântico
//! • Mutação cruzada entre domínios distantes
//! • Amplificação de anomalias de baixa probabilidade
//! • Avaliação posterior de fertilidade científica

pub mod injector;
pub mod cross_domain_mutator;
pub mod anomaly_amplifier;
pub mod fertility_scorer;

pub use injector::SerendipityInjector;
pub use cross_domain_mutator::CrossDomainMutator;
pub use anomaly_amplifier::AnomalyAmplifier;
pub use fertility_scorer::{FertilityScorer, FertileAccident};
