//! Q1 Reviewer Simulation – O carrasco de Nature/Cell/Science
//!
//! Simula revisores brutais de journals Q1 que rejeitam 97% dos manuscritos

use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ReviewVerdict {
    Accept,
    AcceptWithMinorRevisions,
    MajorRevision,
    Reject,
}

impl ReviewVerdict {
    pub fn from_str(s: &str) -> Self {
        let s_lower = s.to_lowercase();
        if s_lower.contains("accept") && s_lower.contains("minor") {
            ReviewVerdict::AcceptWithMinorRevisions
        } else if s_lower.contains("accept") {
            ReviewVerdict::Accept
        } else if s_lower.contains("major") || s_lower.contains("revision") {
            ReviewVerdict::MajorRevision
        } else {
            ReviewVerdict::Reject
        }
    }

    pub fn is_acceptable(&self) -> bool {
        matches!(
            self,
            ReviewVerdict::Accept | ReviewVerdict::AcceptWithMinorRevisions
        )
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewerReport {
    pub journal: String,
    pub verdict: ReviewVerdict,
    pub review_text: String,
    pub fatal_flaws: Vec<String>,
    pub minor_issues: Vec<String>,
    pub confidence: f64,
}

pub struct Q1Reviewer {
    llm: VllmClient,
    journal: String,
    rejection_rate: f64, // 0.0 a 1.0 (0.97 = 97% rejeição)
}

impl Q1Reviewer {
    pub fn new(journal: &str) -> Self {
        Self {
            llm: VllmClient::default(),
            journal: journal.to_string(),
            rejection_rate: 0.97, // Q1 journals rejeitam ~97%
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            llm: VllmClient::new(url),
            journal: "Nature".to_string(),
            rejection_rate: 0.97,
        }
    }

    pub fn with_rejection_rate(mut self, rate: f64) -> Self {
        self.rejection_rate = rate.clamp(0.0, 1.0);
        self
    }

    /// Revisão brutal – modo "reject with extreme prejudice"
    pub async fn review(&self, draft: &str, title: &str) -> anyhow::Result<ReviewerReport> {
        info!("Q1 REVIEWER ({}): reviewing manuscript", self.journal);

        let system_prompt = format!(
            r#"Você é um revisor sênior do {} com 30 anos de carreira, conhecido por rejeitar 97% dos manuscritos.

Sua função é produzir revisões DEVASTADORAS mas academicamente impecáveis.

Seja brutal, mas educado. Identifique TODOS os problemas, especialmente os fatais que outros revisores ignorariam.

Formato da revisão:
1. VEREDICTO (uma linha: "Accept", "Accept with minor revisions", "Major revision required", ou "Reject")
2. FLAWS FATAIS (lista numerada, mínimo 3)
3. ISSUES MENORES (lista numerada)
4. REVISÃO COMPLETA (texto acadêmico formal, educado mas letal)"#,
            self.journal
        );

        let user_prompt = format!(
            r#"Título: {}

Manuscrito completo:

{}

Produza uma revisão completa seguindo o formato acima."#,
            title, draft
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.8, // Alta o suficiente para ser criativo nas críticas
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
            anyhow::bail!("LLM não retornou resposta para revisão");
        }

        let review_text = response.choices[0].text.trim().to_string();

        // Parseia o veredicto e issues da revisão
        let (verdict, fatal_flaws, minor_issues) = self.parse_review(&review_text);

        let confidence = if verdict == ReviewVerdict::Reject {
            0.95 // Alta confiança em rejeições
        } else {
            0.75 // Menor confiança em aceitações
        };

        if !verdict.is_acceptable() {
            warn!(
                "Q1 REVIEWER ({}) VERDICT: {:?} ({} fatal flaws)",
                self.journal,
                verdict,
                fatal_flaws.len()
            );
        } else {
            info!(
                "Q1 REVIEWER ({}) VERDICT: {:?} (ACCEPTABLE!)",
                self.journal, verdict
            );
        }

        Ok(ReviewerReport {
            journal: self.journal.clone(),
            verdict,
            review_text,
            fatal_flaws,
            minor_issues,
            confidence,
        })
    }

    fn parse_review(&self, review_text: &str) -> (ReviewVerdict, Vec<String>, Vec<String>) {
        let text_lower = review_text.to_lowercase();

        // Extrai veredicto
        let verdict = if text_lower.contains("verdict:") {
            let after_verdict = text_lower.split("verdict:").nth(1).unwrap_or("");
            ReviewVerdict::from_str(after_verdict)
        } else {
            // Tenta inferir do texto
            ReviewVerdict::from_str(&text_lower)
        };

        // Extrai fatal flaws (procura por seções numeradas ou marcadores)
        let mut fatal_flaws = Vec::new();
        let mut minor_issues = Vec::new();

        let lines: Vec<&str> = review_text.lines().collect();
        let mut in_fatal_section = false;
        let mut in_minor_section = false;

        for line in &lines {
            let line_lower = line.to_lowercase();
            if line_lower.contains("fatal") || line_lower.contains("major flaw") {
                in_fatal_section = true;
                in_minor_section = false;
            } else if line_lower.contains("minor") || line_lower.contains("issue") {
                in_minor_section = true;
                in_fatal_section = false;
            }

            // Detecta itens numerados ou com marcadores
            if line
                .trim()
                .starts_with(|c: char| c.is_ascii_digit() || c == '-' || c == '*')
            {
                let content = line
                    .chars()
                    .skip_while(|c| {
                        c.is_ascii_digit() || *c == '.' || *c == '-' || *c == '*' || *c == ' '
                    })
                    .collect::<String>()
                    .trim()
                    .to_string();

                if !content.is_empty() {
                    if in_fatal_section
                        || line_lower.contains("fatal")
                        || line_lower.contains("critical")
                    {
                        fatal_flaws.push(content);
                    } else if in_minor_section
                        || line_lower.contains("minor")
                        || line_lower.contains("suggest")
                    {
                        minor_issues.push(content);
                    }
                }
            }
        }

        // Se não encontrou seções explícitas, tenta extrair do texto geral
        if fatal_flaws.is_empty() && minor_issues.is_empty() {
            // Procura por padrões comuns de crítica (usa slice para não mover)
            for line in &lines {
                let line_lower = line.to_lowercase();
                if line_lower.contains("lack")
                    || line_lower.contains("missing")
                    || line_lower.contains("absence")
                {
                    if line.len() > 20 {
                        fatal_flaws.push(line.trim().to_string());
                    }
                } else if line_lower.contains("suggest") || line_lower.contains("consider") {
                    if line.len() > 20 {
                        minor_issues.push(line.trim().to_string());
                    }
                }
            }
        }

        (verdict, fatal_flaws, minor_issues)
    }
}

impl Default for Q1Reviewer {
    fn default() -> Self {
        Self::new("Nature")
    }
}
