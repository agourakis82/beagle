//! Protocol Generator – Geração de protocolos experimentais auto-executáveis
//!
//! Gera protocolos rigorosos, reprodutíveis e éticos para testar hipóteses científicas,
//! incluindo simulações computacionais iniciais e considerações éticas completas.

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use tracing::{info, warn};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug)]
pub struct ProtocolGenerator {
    llm: VllmClient,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentalProtocol {
    pub id: String,
    pub hypothesis: String,
    pub protocol_text: String,
    pub word_count: usize,
    pub ethical_approval_required: bool,
    pub estimated_cost: f64,
    pub estimated_duration_days: u32,
    pub simulation_commands: Vec<String>, // RDKit, PySCF, etc.
    pub generated_at: chrono::DateTime<Utc>,
}

impl ProtocolGenerator {
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

    /// Gera protocolo experimental completo, rigoroso e ético
    pub async fn generate_protocol(
        &self,
        hypothesis: &str,
        constraints: &str, // e.g., "orçamento < R$10k, sem uso de animais"
    ) -> anyhow::Result<ExperimentalProtocol> {
        info!("REALITY FABRICATION: Gerando protocolo experimental para hipótese");

        let system_prompt = r#"Você é um engenheiro químico e biomédico de nível Nobel, especializado em síntese de biomateriais, farmacologia e neurociência.

Sua função é gerar protocolos experimentais rigorosos, reprodutíveis e éticos que possam ser executados em laboratórios reais.

Seja extremamente detalhado, preciso e científico. Use terminologia técnica correta."#;

        let user_prompt = format!(
            r#"HIPÓTESE A TESTAR:
{}

CONSTRAINTS:
{}

Gere um protocolo experimental completo seguindo este formato exato:

**1. RESUMO EXECUTIVO**
- Objetivo principal
- Hipótese testada
- Impacto científico esperado

**2. MATERIAIS E MÉTODOS**
- Lista completa de reagentes (com CAS numbers)
- Equipamentos necessários
- Condições experimentais precisas (temperatura, pH, pressão, etc.)
- Procedimento passo-a-passo numerado

**3. SIMULAÇÕES COMPUTACIONAIS INICIAIS**
- Comandos RDKit para modelagem molecular (se aplicável)
- Comandos PySCF para cálculos quânticos (se aplicável)
- Scripts Python completos e executáveis

**4. ANÁLISE ESTATÍSTICA**
- Tamanho amostral calculado
- Testes estatísticos propostos
- Critérios de significância

**5. CONSIDERAÇÕES ÉTICAS**
- Aprovação IRB necessária? (SIM/NÃO)
- Uso de animais? (SIM/NÃO)
- Riscos identificados
- Mitigações propostas

**6. ORÇAMENTO ESTIMADO**
- Custo total estimado (R$)
- Duração estimada (dias)

**7. REPRODUTIBILIDADE**
- Checklist de reprodutibilidade
- Dados a serem compartilhados publicamente

Mínimo 2000 palavras. Seja extremamente detalhado e técnico."#,
            hypothesis, constraints
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.7, // Precisão técnica, mas com criatividade
            top_p: 0.95,
            max_tokens: 4096, // Protocolos longos
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
            anyhow::bail!("LLM não retornou resposta para protocolo");
        }

        let protocol_text = response.choices[0].text.trim().to_string();
        let word_count = protocol_text.split_whitespace().count();

        // Extrai informações estruturadas do protocolo
        let ethical_approval_required = protocol_text.to_lowercase().contains("sim") 
            && (protocol_text.to_lowercase().contains("irb") || protocol_text.to_lowercase().contains("ética"));
        
        // Extrai custo estimado (procura por padrões como "R$" ou "custo")
        let estimated_cost = self.extract_cost(&protocol_text);
        
        // Extrai duração estimada
        let estimated_duration_days = self.extract_duration(&protocol_text);
        
        // Extrai comandos de simulação
        let simulation_commands = self.extract_simulation_commands(&protocol_text);

        let protocol = ExperimentalProtocol {
            id: uuid::Uuid::new_v4().to_string(),
            hypothesis: hypothesis.to_string(),
            protocol_text,
            word_count,
            ethical_approval_required,
            estimated_cost,
            estimated_duration_days,
            simulation_commands,
            generated_at: Utc::now(),
        };

        info!(
            "PROTOCOLO EXPERIMENTAL GERADO: {} palavras, custo R${:.2}, duração {} dias",
            protocol.word_count, protocol.estimated_cost, protocol.estimated_duration_days
        );

        Ok(protocol)
    }

    /// Salva protocolo em arquivo Markdown
    pub async fn save_protocol(
        &self,
        protocol: &ExperimentalProtocol,
        output_dir: &PathBuf,
    ) -> anyhow::Result<PathBuf> {
        use std::fs;

        fs::create_dir_all(output_dir)?;

        let filename = format!("protocol_{}_{}.md", 
            protocol.hypothesis.chars().take(30).collect::<String>().replace(" ", "_"),
            protocol.id.chars().take(8).collect::<String>()
        );
        let filepath = output_dir.join(&filename);

        let markdown = format!(
            "# Protocolo Experimental: {}\n\n\
            **ID:** {}\n\
            **Gerado em:** {}\n\n\
            **Hipótese:** {}\n\n\
            **Custo Estimado:** R$ {:.2}\n\
            **Duração Estimada:** {} dias\n\
            **Aprovação Ética Necessária:** {}\n\n\
            ---\n\n\
            {}\n\n\
            ---\n\n\
            ## Comandos de Simulação\n\n\
            {}\n",
            protocol.hypothesis,
            protocol.id,
            protocol.generated_at.format("%Y-%m-%d %H:%M:%S UTC"),
            protocol.hypothesis,
            protocol.estimated_cost,
            protocol.estimated_duration_days,
            if protocol.ethical_approval_required { "SIM" } else { "NÃO" },
            protocol.protocol_text,
            protocol.simulation_commands.join("\n\n")
        );

        fs::write(&filepath, markdown)?;
        info!("PROTOCOLO SALVO: {:?}", filepath);

        Ok(filepath)
    }

    fn extract_cost(&self, text: &str) -> f64 {
        // Procura por padrões como "R$ 1000" ou "custo: R$ 5000"
        let re = regex::Regex::new(r"R\$\s*([\d,]+\.?\d*)").ok();
        if let Some(pattern) = re {
            if let Some(cap) = pattern.captures(text) {
                if let Some(amount_str) = cap.get(1) {
                    let cleaned = amount_str.as_str().replace(",", "");
                    if let Ok(amount) = cleaned.parse::<f64>() {
                        return amount;
                    }
                }
            }
        }
        0.0
    }

    fn extract_duration(&self, text: &str) -> u32 {
        // Procura por padrões como "30 dias" ou "duração: 15 dias"
        let re = regex::Regex::new(r"(\d+)\s*dias?").ok();
        if let Some(pattern) = re {
            if let Some(cap) = pattern.captures(text) {
                if let Some(days_str) = cap.get(1) {
                    if let Ok(days) = days_str.as_str().parse::<u32>() {
                        return days;
                    }
                }
            }
        }
        0
    }

    fn extract_simulation_commands(&self, text: &str) -> Vec<String> {
        // Procura por blocos de código Python ou comandos RDKit/PySCF
        let mut commands = Vec::new();
        
        // Procura por blocos de código entre ```python ou ```
        let code_block_re = regex::Regex::new(r"```(?:python)?\n(.*?)```").ok();
        if let Some(pattern) = code_block_re {
            for cap in pattern.captures_iter(text) {
                if let Some(code) = cap.get(1) {
                    commands.push(code.as_str().trim().to_string());
                }
            }
        }
        
        // Procura por comandos RDKit ou PySCF explícitos
        if text.contains("RDKit") || text.contains("rdkit") {
            let rdkit_re = regex::Regex::new(r"(from rdkit.*?)(?=\n\n|\n[A-Z])").ok();
            if let Some(pattern) = rdkit_re {
                for cap in pattern.captures_iter(text) {
                    if let Some(cmd) = cap.get(1) {
                        commands.push(cmd.as_str().trim().to_string());
                    }
                }
            }
        }
        
        if commands.is_empty() {
            // Fallback: retorna placeholder
            commands.push("# Comandos de simulação a serem implementados".to_string());
        }
        
        commands
    }
}

impl Default for ProtocolGenerator {
    fn default() -> Self {
        Self::new()
    }
}

