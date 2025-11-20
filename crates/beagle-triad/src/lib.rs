//! beagle-triad - Honest AI Triad
//!
//! Sistema adversarial de revisão:
//! - ATHENA: agente "literatura" (pontos fortes/fracos, sugestões)
//! - HERMES: revisor (reescreve mantendo estilo/autoria)
//! - ARGOS: crítico (falhas lógicas, claims sem suporte)
//! - Juiz final: arbitra versões finais

use beagle_core::BeagleContext;
use beagle_llm::RequestMeta;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Input para a Triad
#[derive(Debug, Clone)]
pub struct TriadInput {
    pub run_id: String,
    pub draft_path: PathBuf,
    pub context_summary: String,
}

/// Opinião de um agente da Triad
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriadOpinion {
    pub agent: String,       // "ATHENA" | "HERMES" | "ARGOS"
    pub summary: String,
    pub suggestions: String, // markdown
    pub score: f32,          // 0.0–1.0
}

/// Relatório final da Triad
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriadReport {
    pub run_id: String,
    pub original_draft: String,
    pub final_draft: String,
    pub opinions: Vec<TriadOpinion>,
    pub timestamp: String,
}

/// Executa a Triad completa
pub async fn run_triad(
    input: TriadInput,
    ctx: &mut BeagleContext,
) -> anyhow::Result<TriadReport> {
    // 1) Ler draft
    let draft = std::fs::read_to_string(&input.draft_path)?;

    // 2) ATHENA (agente literatura)
    let athena_opinion = run_athena(&draft, &input.context_summary, ctx).await?;

    // 3) HERMES (revisor)
    let hermes_opinion = run_hermes_rewrite(&draft, &athena_opinion, ctx).await?;

    // 4) ARGOS (crítico)
    let argos_opinion = run_argos_review(&draft, &hermes_opinion, &athena_opinion, ctx).await?;

    // 5) Juiz final (arbitra versões)
    let final_draft = arbitrate_final(
        &draft,
        &athena_opinion,
        &hermes_opinion,
        &argos_opinion,
        ctx,
    )
    .await?;

    Ok(TriadReport {
        run_id: input.run_id,
        original_draft: draft,
        final_draft,
        opinions: vec![athena_opinion, hermes_opinion, argos_opinion],
        timestamp: chrono::Utc::now().to_rfc3339(),
    })
}

/// ATHENA: agente literatura
async fn run_athena(
    draft: &str,
    context_summary: &str,
    ctx: &BeagleContext,
) -> anyhow::Result<TriadOpinion> {
    let prompt = format!(
        "Tu és ATHENA, agente de literatura científica do BEAGLE.\n\n\
        Draft:\n{}\n\n\
        Contexto (GraphRAG):\n{}\n\n\
        Analisa o draft e fornece:\n\
        1. Pontos fortes (3-5)\n\
        2. Pontos fracos (3-5)\n\
        3. Sugestões de literatura adicional\n\
        4. Score 0.0-1.0 de qualidade científica\n\n\
        Responde em formato estruturado.",
        draft, context_summary
    );

    let meta = RequestMeta {
        requires_math: false,
        requires_high_quality: true, // ATHENA usa alta qualidade
        offline_required: false,
        requires_vision: false,
        approximate_tokens: draft.len() / 4,
    };

    let client = ctx.router.choose(&meta);
    let response = client.complete(&prompt).await?;

    // Parse response (simplificado - em produção, usar JSON estruturado)
    let score = extract_score(&response).unwrap_or(0.7);

    Ok(TriadOpinion {
        agent: "ATHENA".to_string(),
        summary: response.clone(),
        suggestions: response,
        score,
    })
}

/// HERMES: revisor (reescreve)
async fn run_hermes_rewrite(
    draft: &str,
    athena_opinion: &TriadOpinion,
    ctx: &BeagleContext,
) -> anyhow::Result<TriadOpinion> {
    let prompt = format!(
        "Tu és HERMES, revisor científico do BEAGLE.\n\n\
        Draft original:\n{}\n\n\
        Feedback ATHENA:\n{}\n\n\
        Reescreve o draft mantendo:\n\
        - Estilo e autoria do autor original\n\
        - Estrutura científica\n\
        - Incorporando sugestões relevantes de ATHENA\n\n\
        Fornece:\n\
        1. Draft reescrito completo\n\
        2. Resumo das mudanças\n\
        3. Score 0.0-1.0 de melhoria",
        draft, athena_opinion.suggestions
    );

    let meta = RequestMeta {
        requires_math: false,
        requires_high_quality: true,
        offline_required: false,
        requires_vision: false,
        approximate_tokens: draft.len() / 4,
    };

    let client = ctx.router.choose(&meta);
    let response = client.complete(&prompt).await?;

    let score = extract_score(&response).unwrap_or(0.8);

    Ok(TriadOpinion {
        agent: "HERMES".to_string(),
        summary: "Draft reescrito incorporando feedback".to_string(),
        suggestions: response,
        score,
    })
}

/// ARGOS: crítico
async fn run_argos_review(
    original: &str,
    hermes_opinion: &TriadOpinion,
    athena_opinion: &TriadOpinion,
    ctx: &BeagleContext,
) -> anyhow::Result<TriadOpinion> {
    let prompt = format!(
        "Tu és ARGOS, crítico científico do BEAGLE.\n\n\
        Draft original:\n{}\n\n\
        Versão HERMES:\n{}\n\n\
        Feedback ATHENA:\n{}\n\n\
        Aponta:\n\
        1. Falhas lógicas\n\
        2. Claims sem suporte\n\
        3. Trechos fracos\n\
        4. Inconsistências\n\
        5. Score 0.0-1.0 de rigor científico",
        original, hermes_opinion.suggestions, athena_opinion.suggestions
    );

    let meta = RequestMeta {
        requires_math: false,
        requires_high_quality: true,
        offline_required: false,
        requires_vision: false,
        approximate_tokens: original.len() / 4,
    };

    let client = ctx.router.choose(&meta);
    let response = client.complete(&prompt).await?;

    let score = extract_score(&response).unwrap_or(0.75);

    Ok(TriadOpinion {
        agent: "ARGOS".to_string(),
        summary: "Análise crítica completa".to_string(),
        suggestions: response,
        score,
    })
}

/// Juiz final: arbitra versões
async fn arbitrate_final(
    original: &str,
    athena: &TriadOpinion,
    hermes: &TriadOpinion,
    argos: &TriadOpinion,
    ctx: &BeagleContext,
) -> anyhow::Result<String> {
    let prompt = format!(
        "Tu és o Juiz Final do BEAGLE Triad.\n\n\
        Draft original:\n{}\n\n\
        ATHENA (literatura):\n{}\nScore: {:.2}\n\n\
        HERMES (revisor):\n{}\nScore: {:.2}\n\n\
        ARGOS (crítico):\n{}\nScore: {:.2}\n\n\
        Gera a versão final do draft:\n\
        - Combina insights de todos os agentes\n\
        - Mantém autoria original\n\
        - Incorpora melhorias sugeridas\n\
        - Resolve críticas de ARGOS\n\n\
        Fornece apenas o draft final completo em Markdown.",
        original,
        athena.summary,
        athena.score,
        hermes.summary,
        hermes.score,
        argos.summary,
        argos.score
    );

    let meta = RequestMeta {
        requires_math: false,
        requires_high_quality: true, // Juiz usa máxima qualidade (pode usar Grok 4 Heavy)
        offline_required: false,
        requires_vision: false,
        approximate_tokens: original.len() / 4,
    };

    let client = ctx.router.choose(&meta);
    client.complete(&prompt).await
}

/// Extrai score de resposta (simplificado)
fn extract_score(response: &str) -> Option<f32> {
    // Procura por padrões como "Score: 0.85" ou "0.85"
    let re = regex::Regex::new(r"score[:\s]+([0-9]+\.[0-9]+)").ok()?;
    let binding = response.to_lowercase();
    let caps = re.captures(binding.as_str())?;
    caps.get(1)?.as_str().parse().ok()
}

