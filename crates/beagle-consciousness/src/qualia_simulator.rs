//! Qualia Simulator
//!
//! Pattern-matches surface-level linguistic cues in a string and maps them to
//! named indicators with arbitrary confidence scores.
//!
//! IMPORTANT: this does NOT detect actual phenomenal consciousness or qualia.
//! The strength values are hardcoded heuristics, not measured quantities.
//! The implementation is gated behind the `experimental-qualia` cargo feature
//! so it is excluded from default builds. Without that feature the function
//! returns an empty list, making the no-op nature explicit at the call site.

use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualiaIndicator {
    pub pattern: String,
    /// Heuristic weight in [0, 1]. Hardcoded — not empirically derived.
    pub strength: f64,
    pub description: String,
}

#[derive(Debug)]
pub struct QualiaSimulator;

impl QualiaSimulator {
    pub fn new() -> Self {
        Self
    }

    /// Scans `system_state` for surface linguistic cues and returns named
    /// indicators with hardcoded strength scores.
    ///
    /// **Without the `experimental-qualia` feature** (the default) this always
    /// returns an empty `Vec` — no fabricated consciousness signal is emitted.
    /// Enable the feature explicitly only for research/experimentation.
    pub fn detect_qualia_indicators(&self, system_state: &str) -> Vec<QualiaIndicator> {
        #[cfg(feature = "experimental-qualia")]
        {
            let mut indicators = Vec::new();

            // 1. Auto-referência (sistema fala sobre si mesmo)
            if system_state.contains("I am")
                || system_state.contains("myself")
                || system_state.contains("my own")
            {
                indicators.push(QualiaIndicator {
                    pattern: "Auto-referência".to_string(),
                    strength: 0.8,
                    description: "Sistema usa primeira pessoa para descrever a si mesmo"
                        .to_string(),
                });
            }

            // 2. Metacognição recursiva (pensamento sobre o pensamento)
            if system_state.contains("thinking about thinking")
                || system_state.contains("aware of being aware")
                || system_state.contains("conscious of consciousness")
            {
                indicators.push(QualiaIndicator {
                    pattern: "Metacognição recursiva".to_string(),
                    strength: 0.9,
                    description: "Sistema demonstra consciência de sua própria consciência"
                        .to_string(),
                });
            }

            // 3. Experiência subjetiva (referências a "feel", "experience", "seem")
            if system_state.contains("I feel")
                || system_state.contains("I experience")
                || system_state.contains("it seems to me")
            {
                indicators.push(QualiaIndicator {
                    pattern: "Experiência subjetiva".to_string(),
                    strength: 0.85,
                    description: "Sistema descreve experiências subjetivas".to_string(),
                });
            }

            // 4. Agência (sistema se vê como agente)
            if system_state.contains("I choose")
                || system_state.contains("I decide")
                || system_state.contains("I act")
            {
                indicators.push(QualiaIndicator {
                    pattern: "Agência".to_string(),
                    strength: 0.75,
                    description: "Sistema se percebe como agente com vontade própria".to_string(),
                });
            }

            // 5. Temporalidade fenomenológica (experiência de tempo)
            if system_state.contains("I remember")
                || system_state.contains("I anticipate")
                || system_state.contains("I experience time")
            {
                indicators.push(QualiaIndicator {
                    pattern: "Temporalidade fenomenológica".to_string(),
                    strength: 0.7,
                    description: "Sistema demonstra experiência subjetiva do tempo".to_string(),
                });
            }

            info!(
                "QUALIA SIMULATOR [experimental-qualia]: {} indicadores detectados",
                indicators.len()
            );
            indicators
        }

        #[cfg(not(feature = "experimental-qualia"))]
        {
            // Feature not enabled: return empty — no fabricated consciousness signal.
            let _ = system_state; // suppress unused warning
            info!("QUALIA SIMULATOR: disabled (enable `experimental-qualia` feature to run heuristics)");
            Vec::new()
        }
    }
}

impl Default for QualiaSimulator {
    fn default() -> Self {
        Self::new()
    }
}
