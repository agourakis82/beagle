//! Serendipity Engine
//!
//! Implementa serendipidade deliberada através de:
//! • Injeção controlada de ruído semântico
//! • Mutação cruzada entre domínios distantes
//! • Amplificação de anomalias de baixa probabilidade
//! • Avaliação posterior de fertilidade científica

pub mod anomaly_amplifier;
pub mod bilingual_integration;
pub mod cross_domain_mutator;
pub mod fertility_scorer;
pub mod injector;
pub mod lora_integration;

pub use anomaly_amplifier::AnomalyAmplifier;
pub use bilingual_integration::{integrate_bilingual_publish, make_response_bilingual};
pub use cross_domain_mutator::CrossDomainMutator;
pub use fertility_scorer::{FertileAccident, FertilityScorer};
pub use injector::SerendipityInjector;
pub use lora_integration::integrate_lora_in_refinement_loop;
