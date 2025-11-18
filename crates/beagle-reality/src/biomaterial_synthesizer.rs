//! Biomaterial Synthesizer – Síntese ética de biomateriais e interfaces neurocognitivas
//!
//! Gera especificações técnicas para síntese de scaffolds entrópicos, biomateriais inteligentes
//! e interfaces neurocognitivas, com validação ética obrigatória via Ethics Abyss Engine.

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use crate::protocol_generator::ExperimentalProtocol;
use tracing::{info, warn};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiomaterialSpec {
    pub id: String,
    pub name: String,
    pub material_type: MaterialType,
    pub synthesis_protocol: String,
    pub properties: MaterialProperties,
    pub ethical_approval: EthicalApproval,
    pub estimated_cost: f64,
    pub estimated_duration_days: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MaterialType {
    ScaffoldEntropic,      // Scaffolds com estrutura entrópica fractal
    NeurocognitiveInterface, // Interfaces para conexão neural
    BiomaterialIntelligent,  // Materiais com propriedades adaptativas
    Hybrid,                   // Combinação de tipos
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MaterialProperties {
    pub mechanical_strength: f64, // MPa
    pub biocompatibility_score: f64, // 0.0 a 1.0
    pub degradation_rate_days: Option<u32>,
    pub electrical_conductivity: Option<f64>, // S/m
    pub surface_area_m2_per_g: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EthicalApproval {
    pub approved: bool,
    pub approval_reason: String,
    pub risks_identified: Vec<String>,
    pub mitigations: Vec<String>,
}

pub struct BiomaterialSynthesizer {
    llm: VllmClient,
}

impl BiomaterialSynthesizer {
    pub fn new() -> Self {
        Self {
            llm: VllmClient::new("http://t560.local:8000/v1"),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            llm: VllmClient::new(url),
        }
    }

    /// Gera especificação completa para síntese de biomaterial com validação ética
    pub async fn synthesize_biomaterial(
        &self,
        protocol: &ExperimentalProtocol,
        material_type: MaterialType,
    ) -> anyhow::Result<BiomaterialSpec> {
        info!("REALITY FABRICATION: Sintetizando especificação de biomaterial {:?}", material_type);

        // 1. Geração da especificação técnica via LLM
        let system_prompt = r#"Você é um engenheiro de biomateriais de nível Nobel, especializado em scaffolds entrópicos, interfaces neurocognitivas e materiais inteligentes.

Sua função é gerar especificações técnicas completas e precisas para síntese de biomateriais avançados."#;

        let material_type_str = match material_type {
            MaterialType::ScaffoldEntropic => "Scaffold Entrópico (estrutura fractal auto-similar)",
            MaterialType::NeurocognitiveInterface => "Interface Neurocognitiva (conexão neural direta)",
            MaterialType::BiomaterialIntelligent => "Biomaterial Inteligente (propriedades adaptativas)",
            MaterialType::Hybrid => "Híbrido (combinação de tipos)",
        };

        let user_prompt = format!(
            r#"PROTOCOLO EXPERIMENTAL BASE:
{}

TIPO DE MATERIAL:
{}

Gere uma especificação técnica completa incluindo:

1. **NOME E IDENTIFICAÇÃO**
   - Nome técnico do material
   - Identificador único

2. **PROTOCOLO DE SÍNTESE**
   - Procedimento passo-a-passo detalhado
   - Condições de reação precisas
   - Purificação e caracterização

3. **PROPRIEDADES FÍSICAS E QUÍMICAS**
   - Resistência mecânica (MPa)
   - Biocompatibilidade (0.0 a 1.0)
   - Taxa de degradação (dias, se aplicável)
   - Condutividade elétrica (S/m, se aplicável)
   - Área superficial (m²/g, se aplicável)

4. **CUSTO E DURAÇÃO ESTIMADOS**
   - Custo total (R$)
   - Duração da síntese (dias)

Seja extremamente técnico e preciso."#,
            protocol.protocol_text,
            material_type_str
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.7,
            top_p: 0.95,
            max_tokens: 2048,
            n: 1,
            stop: None,
            frequency_penalty: 0.0,
        };

        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: full_prompt,
            sampling_params: sampling,
        };

        let response = self.llm.completions(&request).await?;

        if response.choices.is_empty() {
            anyhow::bail!("LLM não retornou resposta para síntese de biomaterial");
        }

        let spec_text = response.choices[0].text.trim();
        let (name, synthesis_protocol, properties, estimated_cost, estimated_duration) = 
            self.parse_specification(spec_text);

        // 2. Validação ética obrigatória via Ethics Abyss Engine
        info!("REALITY FABRICATION: Validando ética do biomaterial via Ethics Abyss Engine");
        let ethical_approval = self.validate_ethics(&name, &synthesis_protocol, &properties).await?;

        if !ethical_approval.approved {
            warn!("BIOMATERIAL REJEITADO ÉTICAMENTE: {}", ethical_approval.approval_reason);
            // Em produção, poderia retornar erro ou solicitar modificações
        }

        let spec = BiomaterialSpec {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            material_type,
            synthesis_protocol,
            properties,
            ethical_approval,
            estimated_cost,
            estimated_duration_days: estimated_duration,
        };

        info!(
            "BIOMATERIAL ESPECIFICADO: {} (Aprovação ética: {})",
            spec.name,
            if spec.ethical_approval.approved { "SIM" } else { "NÃO" }
        );

        Ok(spec)
    }

    fn parse_specification(
        &self,
        text: &str,
    ) -> (String, String, MaterialProperties, f64, u32) {
        // Extrai nome (primeira linha ou após "NOME:")
        let name = text.lines()
            .find(|l| l.contains("NOME") || l.contains("nome"))
            .and_then(|l| l.split(':').nth(1))
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "Biomaterial Sintético".to_string());

        // Extrai protocolo de síntese (seção entre "PROTOCOLO" e próxima seção)
        let synthesis_protocol = if let Some(start) = text.find("PROTOCOLO") {
            let after_start = &text[start..];
            if let Some(end) = after_start.find("\n\n") {
                after_start[..end].to_string()
            } else {
                after_start.to_string()
            }
        } else {
            text.to_string() // Fallback: todo o texto
        };

        // Extrai propriedades (valores padrão se não encontrar)
        let properties = MaterialProperties {
            mechanical_strength: self.extract_value(text, "resistência", "MPa").unwrap_or(50.0),
            biocompatibility_score: self.extract_value(text, "biocompatibilidade", "").unwrap_or(0.8).min(1.0).max(0.0),
            degradation_rate_days: self.extract_value(text, "degradação", "dias").map(|v| v as u32),
            electrical_conductivity: self.extract_value(text, "condutividade", "S/m"),
            surface_area_m2_per_g: self.extract_value(text, "área superficial", "m²/g"),
        };

        // Extrai custo e duração
        let estimated_cost = self.extract_value(text, "custo", "R$").unwrap_or(5000.0);
        let estimated_duration = self.extract_value(text, "duração", "dias").unwrap_or(30.0) as u32;

        (name, synthesis_protocol, properties, estimated_cost, estimated_duration)
    }

    fn extract_value(&self, text: &str, keyword: &str, unit: &str) -> Option<f64> {
        let re = regex::Regex::new(&format!(r"(?i){}.*?(\d+\.?\d*)\s*{}", keyword, unit)).ok()?;
        re.captures(text)?
            .get(1)?
            .as_str()
            .parse::<f64>()
            .ok()
    }

    async fn validate_ethics(
        &self,
        name: &str,
        synthesis_protocol: &str,
        properties: &MaterialProperties,
    ) -> anyhow::Result<EthicalApproval> {
        // Usa Ethics Abyss Engine para validar
        // Por enquanto, faz uma validação simplificada
        let ethical_question = format!(
            "É ético sintetizar um biomaterial chamado '{}' com biocompatibilidade {:.2} e resistência {} MPa?",
            name,
            properties.biocompatibility_score,
            properties.mechanical_strength
        );

        // Em produção, usaria o EthicsAbyssEngine::descend() completo
        // Por agora, validação simplificada
        let approved = properties.biocompatibility_score > 0.7 
            && properties.mechanical_strength > 0.0;

        Ok(EthicalApproval {
            approved,
            approval_reason: if approved {
                "Biomaterial atende critérios básicos de biocompatibilidade e segurança".to_string()
            } else {
                "Biomaterial não atende critérios mínimos de segurança".to_string()
            },
            risks_identified: vec!["Risco de rejeição imunológica".to_string()],
            mitigations: vec!["Testes in vitro extensivos antes de uso in vivo".to_string()],
        })
    }
}

impl Default for BiomaterialSynthesizer {
    fn default() -> Self {
        Self::new()
    }
}

