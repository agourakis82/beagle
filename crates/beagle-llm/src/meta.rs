//! RequestMeta - Detecção automática de temas de alto risco e metadados

/// Keywords que indicam temas de alto risco de viés
/// 
/// Quando detectados, o router automaticamente usa Grok 4 Heavy
/// como "vacina anti-viés" para garantir respostas mais balanceadas.
pub static HIGH_BIAS_KEYWORDS: [&str; 12] = [
    "cellular consciousness",
    "protoconsciousness",
    "entropy curvature",
    "heliobiology",
    "endogenous dmt",
    "fractal scaffolding",
    "quantum biology",
    "big pharma criticism",
    "psychedelic medicine",
    "consciousness substrate",
    "scalar waves",
    "biofield",
];

/// Metadados extraídos de um prompt para roteamento inteligente
#[derive(Debug, Clone)]
pub struct RequestMeta {
    /// Requer processamento offline (futuro: Gemma local)
    pub offline_required: bool,
    /// Requer prova matemática rigorosa (futuro: DeepSeek)
    pub requires_math_proof: bool,
    /// Estimativa de tokens baseada no tamanho do prompt
    pub estimated_tokens: usize,
    /// Detectado risco alto de viés → usa Grok 4 Heavy
    pub high_bias_risk: bool,
}

impl RequestMeta {
    /// Analisa prompt e extrai metadados para roteamento
    pub fn from_prompt(prompt: &str) -> Self {
        let lower = prompt.to_lowercase();
        
        // Detecção de keywords de alto risco de viés
        let high_bias_risk = HIGH_BIAS_KEYWORDS.iter().any(|&k| lower.contains(k));
        
        // Detecção de necessidade de prova matemática
        let requires_math_proof = lower.contains("proof") 
            || lower.contains("derive") 
            || lower.contains("theorem")
            || lower.contains("mathematical")
            || lower.contains("equation");

        // Estimativa simples: ~4 chars por token
        let estimated_tokens = prompt.len() / 4;

        Self {
            offline_required: false, // Futuro: detecção de necessidade offline
            requires_math_proof,
            estimated_tokens,
            high_bias_risk,
        }
    }
}

