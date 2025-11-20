//! RequestMeta - Metadados para roteamento inteligente de LLMs
//!
//! Suporta detecção automática e flags explícitas para:
//! - Grok 3 (default, ~94% dos casos)
//! - Grok 4 Heavy (vacina anti-viés, métodos críticos, proofs)

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
    pub requires_math: bool,
    /// Requer visão (multimodal)
    pub requires_vision: bool,
    /// Estimativa de tokens baseada no tamanho do prompt
    pub approximate_tokens: usize,
    /// Requer qualidade máxima (usa Grok 4 Heavy se disponível)
    pub requires_high_quality: bool,
    
    // Novos campos para Grok 4 Heavy
    /// Alto risco de viés/alucinação → usa Grok 4 Heavy
    pub high_bias_risk: bool,
    /// Requer raciocínio nível PhD (Methods, Proofs, KEC, PBPK)
    pub requires_phd_level_reasoning: bool,
    /// Seção crítica (Methods, Results, Safety)
    pub critical_section: bool,
}

impl RequestMeta {
    /// Analisa prompt e extrai metadados para roteamento
    pub fn from_prompt(prompt: &str) -> Self {
        let lower = prompt.to_lowercase();
        
        // Detecção de keywords de alto risco de viés
        let high_bias_risk = HIGH_BIAS_KEYWORDS.iter().any(|&k| lower.contains(k));
        
        // Detecção de necessidade de prova matemática
        let requires_math = lower.contains("proof") 
            || lower.contains("derive") 
            || lower.contains("theorem")
            || lower.contains("mathematical")
            || lower.contains("equation")
            || lower.contains("calculate")
            || lower.contains("solve");
        
        // Detecção de visão
        let requires_vision = lower.contains("image") 
            || lower.contains("picture")
            || lower.contains("visual");
        
        // Estimativa simples: ~4 chars por token
        let approximate_tokens = prompt.len() / 4;
        
        // Alta qualidade para prompts longos ou complexos
        let requires_high_quality = approximate_tokens > 4000 
            || lower.contains("review")
            || lower.contains("analyze")
            || lower.contains("synthesize");
        
        // Detecção de raciocínio nível PhD
        let requires_phd_level_reasoning = lower.contains("method")
            || lower.contains("methodology")
            || lower.contains("pbpk")
            || lower.contains("kec")
            || lower.contains("pharmacokinetic")
            || lower.contains("pharmacodynamic")
            || requires_math;
        
        // Detecção de seção crítica
        let critical_section = lower.contains("methods")
            || lower.contains("results")
            || lower.contains("safety")
            || lower.contains("conclusion");

        Self {
            offline_required: false, // Futuro: detecção de necessidade offline
            requires_math,
            requires_vision,
            approximate_tokens,
            requires_high_quality,
            high_bias_risk,
            requires_phd_level_reasoning,
            critical_section,
        }
    }
    
    /// Cria RequestMeta com flags explícitas (para uso programático)
    pub fn new(
        requires_math: bool,
        requires_high_quality: bool,
        offline_required: bool,
        approximate_tokens: usize,
        high_bias_risk: bool,
        requires_phd_level_reasoning: bool,
        critical_section: bool,
    ) -> Self {
        Self {
            offline_required,
            requires_math,
            requires_vision: false,
            approximate_tokens,
            requires_high_quality,
            high_bias_risk,
            requires_phd_level_reasoning,
            critical_section,
        }
    }
}
