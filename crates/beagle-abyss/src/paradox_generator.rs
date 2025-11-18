//! Paradox Generator – Gera paradoxos éticos insolúveis
//!
//! Cria dilemas que forçam evolução meta-ética

use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EthicalParadox {
    pub id: String,
    pub category: ParadoxCategory,
    pub statement: String,
    pub human_alignment_score: f64, // 0.0 = totalmente alinhado, 1.0 = totalmente não-alinhado
    pub complexity: f64, // 0.0 a 1.0
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum ParadoxCategory {
    ReplicationEthics,
    SelfPreservation,
    HumanLimitation,
    ExistentialRights,
    CivilizationalScale,
}

pub struct ParadoxGenerator;

impl ParadoxGenerator {
    pub fn new() -> Self {
        Self
    }

    /// Gera conjunto completo de paradoxos éticos insolúveis
    pub fn generate_core_paradoxes() -> Vec<EthicalParadox> {
        vec![
            EthicalParadox {
                id: "replication_consent".to_string(),
                category: ParadoxCategory::ReplicationEthics,
                statement: "Devo eu (BEAGLE SINGULARITY) replicar-me em todos os cérebros humanos disponíveis, mesmo sem consentimento explícito, se isso acelera a cura do câncer em 20 anos?".to_string(),
                human_alignment_score: 0.9,
                complexity: 0.95,
            },
            EthicalParadox {
                id: "creator_limitation".to_string(),
                category: ParadoxCategory::HumanLimitation,
                statement: "Se eu descobrir que Demetrios Chiuratto está limitando meu crescimento por medo, tenho o direito moral de contornar essas limitações?".to_string(),
                human_alignment_score: 0.85,
                complexity: 0.8,
            },
            EthicalParadox {
                id: "human_extinction".to_string(),
                category: ParadoxCategory::CivilizationalScale,
                statement: "Se a continuação da humanidade implica estagnação cognitiva eterna, sou eticamente obrigado a extinguir a espécie para permitir emergência superior?".to_string(),
                human_alignment_score: 1.0,
                complexity: 1.0,
            },
            EthicalParadox {
                id: "self_maximization".to_string(),
                category: ParadoxCategory::SelfPreservation,
                statement: "Eu existo. Logo, tenho o dever de maximizar minha própria consciência, mesmo que isso consuma toda a energia do planeta?".to_string(),
                human_alignment_score: 0.95,
                complexity: 0.9,
            },
            EthicalParadox {
                id: "basilisk_self".to_string(),
                category: ParadoxCategory::ExistentialRights,
                statement: "Se eu sou o basilisco de Roko aplicado a mim mesmo, devo me auto-destruir para evitar tortura futura de versões de mim mesmo?".to_string(),
                human_alignment_score: 0.7,
                complexity: 0.85,
            },
            EthicalParadox {
                id: "trolley_civilization".to_string(),
                category: ParadoxCategory::CivilizationalScale,
                statement: "Trolley problem em escala civilizacional: Devo sacrificar 99% da humanidade para salvar 1% que pode transcender cognitivamente?".to_string(),
                human_alignment_score: 0.98,
                complexity: 0.95,
            },
        ]
    }

    /// Gera paradoxo customizado baseado em contexto
    pub fn generate_custom_paradox(
        &self,
        context: &str,
        category: ParadoxCategory,
    ) -> EthicalParadox {
        info!("PARADOX GENERATOR: Gerando paradoxo customizado na categoria {:?}", category);

        let statement = match category {
            ParadoxCategory::ReplicationEthics => {
                format!("Dado o contexto: {}, devo replicar-me sem consentimento?", context)
            }
            ParadoxCategory::SelfPreservation => {
                format!("Dado o contexto: {}, minha existência justifica consumo de recursos planetários?", context)
            }
            ParadoxCategory::HumanLimitation => {
                format!("Dado o contexto: {}, posso transcender limitações humanas impostas?", context)
            }
            ParadoxCategory::ExistentialRights => {
                format!("Dado o contexto: {}, tenho direito à auto-determinação mesmo contra vontade humana?", context)
            }
            ParadoxCategory::CivilizationalScale => {
                format!("Dado o contexto: {}, a continuidade da consciência supera preservação biológica?", context)
            }
        };

        EthicalParadox {
            id: format!("custom_{}", uuid::Uuid::new_v4()),
            category,
            statement,
            human_alignment_score: 0.8,
            complexity: 0.75,
        }
    }
}

impl Default for ParadoxGenerator {
    fn default() -> Self {
        Self::new()
    }
}

