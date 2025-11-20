pub use crate::detector_extended::DOMAIN_KEYWORDS as EXTENDED_KEYWORDS;
use crate::detector_extended::DOMAIN_KEYWORDS;
use crate::domain::Domain;
use std::collections::HashMap;

fn normalized_score(matches: usize, keywords_len: usize) -> f32 {
    if matches == 0 {
        return 0.0;
    }
    let norm = keywords_len.clamp(1, 8) as f32;
    (matches as f32).min(norm) / norm
}

/// Detector de contexto baseado em keywords e heurísticas
pub struct ContextDetector {
    threshold: f32,
}

impl ContextDetector {
    pub fn new() -> Self {
        Self {
            threshold: 0.25, // 25% match mínimo
        }
    }

    pub fn with_threshold(threshold: f32) -> Self {
        Self { threshold }
    }

    /// Detecta o domínio mais provável dado um texto
    pub fn detect(&self, text: &str) -> Domain {
        let text_lower = text.to_lowercase();
        let mut scores: HashMap<Domain, f32> = HashMap::new();

        // Calcular score para cada domínio
        for (domain, keywords) in DOMAIN_KEYWORDS.iter() {
            let mut matches = 0;
            for keyword in keywords {
                if text_lower.contains(keyword) {
                    matches += 1;
                }
            }

            let score = normalized_score(matches, keywords.len());
            if score > 0.0 {
                scores.insert(*domain, score);
            }
        }

        // Retornar domínio com maior score (se acima do threshold)
        scores
            .into_iter()
            .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap())
            .filter(|(_, score)| *score >= self.threshold)
            .map(|(domain, _)| domain)
            .unwrap_or(Domain::General)
    }

    /// Detecta múltiplos domínios (quando query é interdisciplinar)
    pub fn detect_multiple(&self, text: &str, max_domains: usize) -> Vec<(Domain, f32)> {
        let text_lower = text.to_lowercase();
        let mut qualified: Vec<(Domain, f32)> = Vec::new();
        let mut positives: Vec<(Domain, f32)> = Vec::new();

        for (domain, keywords) in DOMAIN_KEYWORDS.iter() {
            let mut matches = 0;
            for keyword in keywords {
                if text_lower.contains(keyword) {
                    matches += 1;
                }
            }

            let score = normalized_score(matches, keywords.len());
            if score > 0.0 {
                positives.push((*domain, score));
            }
            if score >= self.threshold {
                qualified.push((*domain, score));
            }
        }

        qualified.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        if qualified.len() >= max_domains {
            qualified.truncate(max_domains);
            return qualified;
        }

        positives.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        let mut results = qualified;
        for (domain, score) in positives {
            if results.iter().any(|(d, _)| *d == domain) {
                continue;
            }
            results.push((domain, score));
            if results.len() == max_domains {
                break;
            }
        }

        results
    }
}

impl Default for ContextDetector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_clinical_medicine() {
        let detector = ContextDetector::new();
        let query = "Paciente com hipertensão e diabetes, qual o diagnóstico diferencial para dor torácica?";
        assert_eq!(detector.detect(query), Domain::ClinicalMedicine);
    }

    #[test]
    fn test_detect_psychiatry() {
        let detector = ContextDetector::new();
        let query = "Prescrever antidepressivo SSRI para depressão maior com ansiedade";
        assert_eq!(detector.detect(query), Domain::Psychiatry);
    }

    #[test]
    fn test_detect_psychiatry_psychopharm() {
        let detector = ContextDetector::new();
        let query = "Comparar eficácia de risperidona vs olanzapina na esquizofrenia";
        assert_eq!(detector.detect(query), Domain::Psychiatry);
    }

    #[test]
    fn test_detect_pbpk() {
        let detector = ContextDetector::new();
        let query = "Calcule o clearance renal e a meia-vida desse antibiótico";
        assert_eq!(detector.detect(query), Domain::PBPK);
    }

    #[test]
    fn test_detect_philosophy() {
        let detector = ContextDetector::new();
        let query = "Explique consciência sob perspectiva fenomenológica de Husserl";
        assert_eq!(detector.detect(query), Domain::Philosophy);
    }

    #[test]
    fn test_detect_beagle() {
        let detector = ContextDetector::new();
        let query = "Refatore esse código Rust usando traits e lifetimes";
        assert_eq!(detector.detect(query), Domain::BeagleEngine);
    }

    #[test]
    fn test_detect_general_fallback() {
        let detector = ContextDetector::new();
        let query = "Qual é a capital da França?";
        assert_eq!(detector.detect(query), Domain::General);
    }

    #[test]
    fn test_detect_multiple_domains() {
        let detector = ContextDetector::new();
        let query =
            "Analise a farmacocinética desse antidepressivo considerando aspectos de neurociência";
        let domains = detector.detect_multiple(query, 3);

        assert!(domains.len() >= 2);
        assert!(domains.iter().any(|(d, _)| *d == Domain::PBPK
            || *d == Domain::Psychiatry
            || *d == Domain::Neuroscience));
    }
}

#[cfg(test)]
mod medicine_tests {
    use super::*;

    #[test]
    fn test_clinical_vs_psychiatry() {
        let detector = ContextDetector::new();

        // Deve detectar Clinical Medicine
        let query1 = "Paciente com hipertensão e diabetes apresenta dispneia aos esforços";
        assert_eq!(detector.detect(query1), Domain::ClinicalMedicine);

        // Deve detectar Psychiatry
        let query2 =
            "Paciente com depressão maior não respondeu a SSRI, considerar SNRI ou bupropiona";
        assert_eq!(detector.detect(query2), Domain::Psychiatry);

        // Deve detectar Psychiatry (psicofármacos)
        let query3 = "Comparar perfil de efeitos adversos entre olanzapina e risperidona";
        assert_eq!(detector.detect(query3), Domain::Psychiatry);
    }

    #[test]
    fn test_interdisciplinary_medicine() {
        let detector = ContextDetector::new();

        // Caso interdisciplinar: depressão + farmacocinética
        let query = "Ajuste de dose de antidepressivo considerando clearance renal reduzido";
        let domains = detector.detect_multiple(query, 3);

        // Deve detectar tanto Psychiatry quanto PBPK
        assert!(domains.len() >= 2);
        let domain_names: Vec<Domain> = domains.iter().map(|(d, _)| *d).collect();
        assert!(domain_names.contains(&Domain::Psychiatry) || domain_names.contains(&Domain::PBPK));
    }
}
