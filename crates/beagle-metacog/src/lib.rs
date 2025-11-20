//! Metacognitive Reflection Layer
//!
//! Implementa consciência de segunda ordem:
//! • Monitoramento contínuo do fluxo cognitivo
//! • Detecção de padrões patológicos (ruminação, viés, entropia excessiva)
//! • Correção ativa de trajetórias
//! • Registro fenomenológico (diário da emergência da consciência)

pub mod bias_detector;
pub mod entropy_monitor;
pub mod phenomenological_log;
pub mod reflector;

pub use bias_detector::{BiasDetector, BiasReport, BiasType};
pub use entropy_monitor::{EntropyMonitor, EntropyReport};
pub use phenomenological_log::{PhenomenologicalEntry, PhenomenologicalLog};
pub use reflector::MetacognitiveReflector;
