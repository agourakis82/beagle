use crate::{
    detector::ContextDetector,
    domain::Domain,
    loader::{global_loader, ProfileLoader},
};
use tracing::{debug, info};

/// Personality Engine - associa contexto ao profile apropriado
pub struct PersonalityEngine {
    detector: ContextDetector,
    loader: &'static ProfileLoader,
}

impl PersonalityEngine {
    /// Instancia engine com detector padrão e loader global
    pub fn new() -> Self {
        Self {
            detector: ContextDetector::new(),
            loader: global_loader(),
        }
    }

    /// Instancia engine definindo limiar customizado para detector
    pub fn with_threshold(threshold: f32) -> Self {
        Self {
            detector: ContextDetector::with_threshold(threshold),
            loader: global_loader(),
        }
    }

    /// Detecta domínio predominante
    pub fn detect_domain(&self, query: &str) -> Domain {
        let domain = self.detector.detect(query);
        debug!("🎯 Domínio detectado: {:?}", domain);
        domain
    }

    /// Detecta múltiplos domínios (interdisciplinaridade)
    pub fn detect_domains(&self, query: &str, max: usize) -> Vec<(Domain, f32)> {
        self.detector.detect_multiple(query, max)
    }

    /// Monta system prompt adaptado ao texto (detecção automática)
    pub fn system_prompt_for(&self, query: &str) -> String {
        let domain = self.detect_domain(query);
        self.system_prompt_for_domain(domain)
    }

    /// Monta system prompt para domínio específico
    pub fn system_prompt_for_domain(&self, domain: Domain) -> String {
        match self.loader.get(domain) {
            Some(profile) => {
                info!("✅ Usando profile {:?}", domain);
                profile.build_system_prompt()
            }
            None => {
                info!("⚠️ Profile {:?} não encontrado, usando General", domain);
                self.loader
                    .get(Domain::General)
                    .map(|p| p.build_system_prompt())
                    .unwrap_or_else(|| "You are a helpful assistant.".to_string())
            }
        }
    }

    /// Retorna metadados do profile
    pub fn profile_info(&self, domain: Domain) -> Option<String> {
        self.loader.get(domain).map(|p| {
            format!(
                "{} v{} - {}",
                p.profile.name, p.profile.version, p.profile.domain
            )
        })
    }

    /// Lista domínios carregados
    pub fn available_domains(&self) -> Vec<Domain> {
        self.loader.loaded_domains()
    }
}

impl Default for PersonalityEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_and_adapt() {
        let engine = PersonalityEngine::new();

        let query = "Calcule clearance renal e meia-vida do antibiótico";
        let domain = engine.detect_domain(query);
        assert_eq!(domain, Domain::PBPK);

        let prompt = engine.system_prompt_for(query);
        assert!(prompt.to_lowercase().contains("farmacocin"));
    }

    #[test]
    fn test_clinical_medicine() {
        let engine = PersonalityEngine::new();

        let query = "Paciente com hipertensão e diabetes apresenta dispneia";
        let domain = engine.detect_domain(query);
        assert_eq!(domain, Domain::ClinicalMedicine);

        let prompt = engine.system_prompt_for(query);
        assert!(prompt.len() > 100);
    }

    #[test]
    fn test_psychiatry() {
        let engine = PersonalityEngine::new();

        let query = "Iniciar SSRI para depressão maior";
        let domain = engine.detect_domain(query);
        assert_eq!(domain, Domain::Psychiatry);

        let prompt = engine.system_prompt_for(query);
        assert!(prompt.to_lowercase().contains("psiquiat"));
    }

    #[test]
    fn test_fallback_general() {
        let engine = PersonalityEngine::new();

        let query = "Qual é a capital da França?";
        let domain = engine.detect_domain(query);
        assert_eq!(domain, Domain::General);
    }

    #[test]
    fn test_interdisciplinary() {
        let engine = PersonalityEngine::new();

        let query = "Ajuste de dose de antidepressivo considerando clearance renal";
        let domains = engine.detect_domains(query, 3);

        assert!(domains.len() >= 2);
    }
}
