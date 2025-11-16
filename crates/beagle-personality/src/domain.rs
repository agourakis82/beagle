use serde::{Deserialize, Serialize};
use std::fmt;

/// Domínios de conhecimento suportados pelo Beagle
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Domain {
    // === Ciências Médicas ===
    /// Farmacocinética, PBPK modeling, análise farmacológica
    PBPK,
    /// Medicina clínica geral, diagnóstico, semiologia
    ClinicalMedicine,
    /// Psiquiatria, psicofarmacologia, saúde mental
    Psychiatry,
    /// Neurociência básica, neurobiologia
    Neuroscience,

    // === Ciências Exatas ===
    /// Física geral e aplicada
    Physics,
    /// Mecânica quântica, física quântica
    Quantum,
    /// Química geral, orgânica, inorgânica
    Chemistry,

    // === Ciências Interdisciplinares ===
    /// Biomateriais, engenharia de tecidos, nanomedicina
    Biomaterials,
    /// Heliobiologia, cronobiologia, ritmos circadianos
    Heliobiology,
    /// Sistemas complexos, teoria do caos, fractais
    ComplexSystems,

    // === Filosofia e Metacognição ===
    /// Filosofia, consciência, teoria simbólica
    Philosophy,

    // === Meta-Pesquisa ===
    /// Publicação científica Q1, revisão por pares
    Q1Scholar,
    /// Meta-discovery, pesquisa de pesquisa
    MetaDiscovery,
    /// Pesquisa exploratória, discovery science
    Discovery,

    // === Engenharia ===
    /// Desenvolvimento Beagle, arquitetura, código
    BeagleEngine,
    /// Engenharia química, processos, modelagem
    ChemicalEngineering,

    // === Direito e Artes ===
    /// Direito médico, bioética, regulatório
    MedicalLaw,
    /// Teoria musical, composição, análise harmônica
    Music,

    // === Fallback ===
    /// Conversação geral
    General,
}

impl Domain {
    /// Retorna todos os domínios especializados (exceto General)
    pub fn specialized() -> Vec<Self> {
        vec![
            // Medical
            Self::PBPK,
            Self::ClinicalMedicine,
            Self::Psychiatry,
            Self::Neuroscience,
            // Exact Sciences
            Self::Physics,
            Self::Quantum,
            Self::Chemistry,
            // Interdisciplinary
            Self::Biomaterials,
            Self::Heliobiology,
            Self::ComplexSystems,
            // Philosophy & Meta
            Self::Philosophy,
            Self::Q1Scholar,
            Self::MetaDiscovery,
            Self::Discovery,
            // Engineering
            Self::BeagleEngine,
            Self::ChemicalEngineering,
            // Law & Arts
            Self::MedicalLaw,
            Self::Music,
        ]
    }

    /// Nome do arquivo de profile TOML
    pub fn profile_file(&self) -> &'static str {
        match self {
            Self::PBPK => "pbpk.toml",
            Self::ClinicalMedicine => "clinical_medicine.toml",
            Self::Psychiatry => "psychiatry.toml",
            Self::Neuroscience => "neuroscience.toml",
            Self::Physics => "physics.toml",
            Self::Quantum => "quantum.toml",
            Self::Chemistry => "chemistry.toml",
            Self::Biomaterials => "biomaterials.toml",
            Self::Heliobiology => "heliobiology.toml",
            Self::ComplexSystems => "complex_systems.toml",
            Self::Philosophy => "philosophy.toml",
            Self::Q1Scholar => "q1_scholar.toml",
            Self::MetaDiscovery => "meta_discovery.toml",
            Self::Discovery => "discovery.toml",
            Self::BeagleEngine => "beagle.toml",
            Self::ChemicalEngineering => "chemical_engineering.toml",
            Self::MedicalLaw => "medical_law.toml",
            Self::Music => "music.toml",
            Self::General => "general.toml",
        }
    }

    /// Descrição curta do domínio
    pub fn description(&self) -> &'static str {
        match self {
            Self::PBPK => "Pharmacokinetics and PBPK modeling",
            Self::ClinicalMedicine => "Clinical medicine and diagnosis",
            Self::Psychiatry => "Psychiatry and psychopharmacology",
            Self::Neuroscience => "Basic neuroscience",
            Self::Physics => "Physics and applied physics",
            Self::Quantum => "Quantum mechanics",
            Self::Chemistry => "Chemistry (organic, inorganic, analytical)",
            Self::Biomaterials => "Biomaterials and tissue engineering",
            Self::Heliobiology => "Heliobiology and chronobiology",
            Self::ComplexSystems => "Complex systems and chaos theory",
            Self::Philosophy => "Philosophy and symbolic theory",
            Self::Q1Scholar => "Q1 scientific publishing",
            Self::MetaDiscovery => "Meta-discovery and research methodology",
            Self::Discovery => "Exploratory research",
            Self::BeagleEngine => "Beagle engine development",
            Self::ChemicalEngineering => "Chemical engineering",
            Self::MedicalLaw => "Medical law and bioethics",
            Self::Music => "Music theory and composition",
            Self::General => "General conversation",
        }
    }
}

impl fmt::Display for Domain {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl Default for Domain {
    fn default() -> Self {
        Self::General
    }
}
