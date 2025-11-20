//! beagle-triad - Honest AI Triad
//!
//! Sistema adversarial de revisão:
//! - ATHENA: agente "literatura" (pontos fortes/fracos, sugestões)
//! - HERMES: revisor (reescreve mantendo estilo/autoria)
//! - ARGOS: crítico (falhas lógicas, claims sem suporte)
//! - Juiz final: arbitra versões finais

use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, ProviderTier};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::info;

/// Input para a Triad
#[derive(Debug, Clone)]
pub struct TriadInput {
    pub run_id: String,
    pub draft_path: PathBuf,
    pub context_summary: Option<String>, // pode ser JSON com top-k chunks, etc.
}

/// Opinião de um agente da Triad
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriadOpinion {
    pub agent: String,      // "ATHENA" | "HERMES" | "ARGOS"
    pub summary: String,
    pub suggestions_md: String, // markdown
    pub score: f32,         // 0.0–1.0
    pub provider_tier: String, // "grok-3" | "grok-4-heavy" | etc.
}

/// Relatório final da Triad
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriadReport {
    pub run_id: String,
    pub original_draft: String,
    pub final_draft: String,
    pub opinions: Vec<TriadOpinion>,
    pub created_at: DateTime<Utc>,
    pub llm_stats: LlmCallsStats,
}

/// Estatísticas de chamadas LLM
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LlmCallsStats {
    pub grok3_calls: usize,
    pub grok3_tokens_est: usize,
    pub heavy_calls: usize,
    pub heavy_tokens_est: usize,
}

/// Executa a Triad completa
pub async fn run_triad(
    input: &TriadInput,
    ctx: &BeagleContext,
) -> anyhow::Result<TriadReport> {
    info!("🔍 Iniciando Triad para run_id: {}", input.run_id);

    // 1) Ler draft
    let original_draft = std::fs::read_to_string(&input.draft_path)?;
    info!("📄 Draft lido: {} chars", original_draft.len());

    let mut stats = LlmCallsStats::default();

    // 2) ATHENA (agente literatura)
    info!("🔬 Executando ATHENA...");
    let (athena, tier) = run_athena(&original_draft, &input.context_summary, ctx).await?;
    update_stats(&mut stats, &tier, &original_draft);
    info!("✅ ATHENA concluído - Score: {:.2} | Provider: {}", athena.score, tier.as_str());

    // 3) HERMES (revisor)
    info!("✍️  Executando HERMES...");
    let (hermes, tier) = run_hermes(&original_draft, &athena, ctx).await?;
    update_stats(&mut stats, &tier, &original_draft);
    info!("✅ HERMES concluído - Score: {:.2} | Provider: {}", hermes.score, tier.as_str());

    // 4) ARGOS (crítico)
    info!("⚔️  Executando ARGOS...");
    let (argos, tier) = run_argos(&original_draft, &hermes, &athena, ctx).await?;
    update_stats(&mut stats, &tier, &original_draft);
    info!("✅ ARGOS concluído - Score: {:.2} | Provider: {}", argos.score, tier.as_str());

    // 5) Juiz final (arbitra versões)
    info!("⚖️  Executando Juiz Final...");
    let (final_draft, tier) = arbitrate_final(
        &original_draft,
        &hermes,
        &athena,
        &argos,
        ctx,
    )
    .await?;
    update_stats(&mut stats, &tier, &original_draft);
    info!("✅ Juiz Final concluído - Draft final: {} chars | Provider: {}", final_draft.len(), tier.as_str());

    Ok(TriadReport {
        run_id: input.run_id.clone(),
        original_draft,
        final_draft,
        opinions: vec![athena, hermes, argos],
        created_at: Utc::now(),
        llm_stats: stats,
    })
}

/// ATHENA: leitura crítica + literatura
pub async fn run_athena(
    draft: &str,
    context_summary: &Option<String>,
    ctx: &BeagleContext,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let mut prompt = String::from(
        "Você é ATHENA, agente de leitura crítica e contexto científico do sistema BEAGLE.\n\n",
    );

    prompt.push_str("Analise o rascunho de artigo abaixo, identifique:\n");
    prompt.push_str("- Pontos fortes conceituais\n");
    prompt.push_str("- Fragilidades metodológicas ou conceituais\n");
    prompt.push_str("- Possíveis referências/literatura adicional a serem consultadas.\n\n");
    prompt.push_str("Responda em três seções Markdown: ## Pontos Fortes, ## Fragilidades, ## Referências Sugeridas.\n\n");

    if let Some(ctx_sum) = context_summary {
        prompt.push_str("=== CONTEXTO (Darwin / GraphRAG) ===\n");
        prompt.push_str(ctx_sum);
        prompt.push_str("\n\n");
    }

    prompt.push_str("=== DRAFT ===\n");
    prompt.push_str(draft);

    let meta = RequestMeta::new(
        false, // requires_math
        true,  // requires_high_quality
        false, // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        false, // high_bias_risk (ATHENA não precisa de Heavy normalmente)
        true,  // requires_phd_level_reasoning (avalia ciência)
        false, // critical_section
    );

    let (client, tier) = ctx.router.choose(&meta);
    let text = client.complete(&prompt).await?;

    // Extrai score (pode pedir ao modelo explicitamente no futuro)
    let score = extract_score(&text).unwrap_or(0.8);

    Ok((
        TriadOpinion {
            agent: "ATHENA".into(),
            summary: "Leitura crítica e mapeamento de literatura sugerida".into(),
            suggestions_md: text,
            score,
            provider_tier: tier.as_str().to_string(),
        },
        tier,
    ))
}

/// HERMES: reescrita orientada
pub async fn run_hermes(
    draft: &str,
    athena: &TriadOpinion,
    ctx: &BeagleContext,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let mut prompt = String::from(
        "Você é HERMES, agente de síntese textual do sistema BEAGLE.\n\n",
    );

    prompt.push_str("Você receberá:\n");
    prompt.push_str("- Um rascunho de artigo (DRAFT)\n");
    prompt.push_str("- Uma análise crítica de ATHENA com sugestões (ATHENA_FEEDBACK)\n\n");
    prompt.push_str("Sua tarefa:\n");
    prompt.push_str("1. Reescrever o texto deixando-o mais claro, coeso e lógico.\n");
    prompt.push_str("2. Incorporar as sugestões relevantes de ATHENA.\n");
    prompt.push_str("3. NÃO inventar dados ou resultados; só reorganizar e melhorar o texto.\n\n");
    prompt.push_str("Responda apenas com o novo texto em Markdown, sem comentários fora do texto.\n\n");

    prompt.push_str("=== ATHENA_FEEDBACK ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== DRAFT ===\n");
    prompt.push_str(draft);

    let meta = RequestMeta::new(
        false, // requires_math
        true,  // requires_high_quality
        false, // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        false, // high_bias_risk (HERMES não precisa de Heavy)
        false, // requires_phd_level_reasoning (reescrita, não análise crítica)
        false, // critical_section
    );

    let (client, tier) = ctx.router.choose(&meta);
    let text = client.complete(&prompt).await?;

    let score = extract_score(&text).unwrap_or(0.85);

    Ok((
        TriadOpinion {
            agent: "HERMES".into(),
            summary: "Reescrita coerente e estilisticamente melhorada".into(),
            suggestions_md: text.clone(), // aqui o 'suggestions_md' é o próprio rascunho reescrito
            score,
            provider_tier: tier.as_str().to_string(),
        },
        tier,
    ))
}

/// ARGOS: crítico adversarial
pub async fn run_argos(
    original_draft: &str,
    hermes: &TriadOpinion,
    athena: &TriadOpinion,
    ctx: &BeagleContext,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let mut prompt = String::from(
        "Você é ARGOS, agente crítico adversarial do sistema BEAGLE.\n\n",
    );

    prompt.push_str("Você recebeu:\n");
    prompt.push_str("- O DRAFT original de um artigo\n");
    prompt.push_str("- Um DRAFT reescrito por HERMES\n");
    prompt.push_str("- Comentários de ATHENA\n\n");
    prompt.push_str("Sua função é ser um revisor exigente (nível periódico Q1). Faça:\n");
    prompt.push_str("1. Liste problemas graves de coerência lógica, extrapolações não suportadas, ambiguidade.\n");
    prompt.push_str("2. Aponte onde HERMES melhorou o texto e onde piorou.\n");
    prompt.push_str("3. Sugira correções pontuais.\n\n");
    prompt.push_str("Responda em Markdown com seções: ## Problemas Graves, ## Melhorias de HERMES, ## Sugestões Pontuais.\n\n");

    prompt.push_str("=== ATHENA_FEEDBACK ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== DRAFT_ORIGINAL ===\n");
    prompt.push_str(original_draft);
    prompt.push_str("\n\n=== DRAFT_HERMES ===\n");
    prompt.push_str(&hermes.suggestions_md);

    // ARGOS usa Heavy: crítica sobre claims científicos
    let meta = RequestMeta::new(
        false, // requires_math (ou true se for Methods de KEC/PBPK)
        true,  // requires_high_quality
        false, // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,  // high_bias_risk (crítica sobre claims científicos)
        true,  // requires_phd_level_reasoning
        true,  // critical_section (revisão crítica)
    );

    let (client, tier) = ctx.router.choose(&meta);
    let text = client.complete(&prompt).await?;

    let score = extract_score(&text).unwrap_or(0.9);

    Ok((
        TriadOpinion {
            agent: "ARGOS".into(),
            summary: "Crítica adversarial e apontamento de falhas lógicas".into(),
            suggestions_md: text,
            score,
            provider_tier: tier.as_str().to_string(),
        },
        tier,
    ))
}

/// Juiz final: arbitragem do draft
pub async fn arbitrate_final(
    original_draft: &str,
    hermes: &TriadOpinion,
    athena: &TriadOpinion,
    argos: &TriadOpinion,
    ctx: &BeagleContext,
) -> anyhow::Result<(String, ProviderTier)> {
    let mut prompt = String::from(
        "Você é o JUIZ FINAL do sistema BEAGLE (HONEST AI TRIAD).\n\n",
    );

    prompt.push_str("Você recebeu:\n");
    prompt.push_str("- DRAFT_ORIGINAL: rascunho original do artigo.\n");
    prompt.push_str("- DRAFT_HERMES: versão reescrita por HERMES.\n");
    prompt.push_str("- FEEDBACK_ATHENA: análise crítica e sugestões.\n");
    prompt.push_str("- FEEDBACK_ARGOS: crítica adversarial.\n\n");
    prompt.push_str("Sua tarefa:\n");
    prompt.push_str("1. Produzir uma versão FINAL do texto, em Markdown, incorporando o melhor de cada um.\n");
    prompt.push_str("2. Corrigir problemas graves apontados por ARGOS.\n");
    prompt.push_str("3. Manter a voz autoral e evitar inventar dados.\n\n");
    prompt.push_str("Responda **apenas** com o texto final em Markdown.\n\n");

    prompt.push_str("=== FEEDBACK_ATHENA ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== FEEDBACK_ARGOS ===\n");
    prompt.push_str(&argos.suggestions_md);
    prompt.push_str("\n\n=== DRAFT_ORIGINAL ===\n");
    prompt.push_str(original_draft);
    prompt.push_str("\n\n=== DRAFT_HERMES ===\n");
    prompt.push_str(&hermes.suggestions_md);

    // Juiz Final usa Heavy: decisão final sobre texto científico
    let meta = RequestMeta::new(
        false, // requires_math
        true,  // requires_high_quality
        false, // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,  // high_bias_risk (decisão final sobre texto científico)
        true,  // requires_phd_level_reasoning
        true,  // critical_section (versão final)
    );

    let (client, tier) = ctx.router.choose(&meta);
    let text = client.complete(&prompt).await?;

    Ok((text, tier))
}

/// Atualiza estatísticas de chamadas LLM
fn update_stats(stats: &mut LlmCallsStats, tier: &ProviderTier, prompt: &str) {
    let tokens_est = prompt.len() / 4;
    
    match tier {
        ProviderTier::Grok3 => {
            stats.grok3_calls += 1;
            stats.grok3_tokens_est += tokens_est;
        }
        ProviderTier::Grok4Heavy => {
            stats.heavy_calls += 1;
            stats.heavy_tokens_est += tokens_est;
        }
        _ => {
            // Outros providers (futuro)
        }
    }
}

/// Extrai score de resposta (simplificado)
fn extract_score(response: &str) -> Option<f32> {
    // Procura por padrões como "Score: 0.85" ou "0.85"
    let re = regex::Regex::new(r"score[:\s]+([0-9]+\.[0-9]+)").ok()?;
    let binding = response.to_lowercase();
    let caps = re.captures(binding.as_str())?;
    caps.get(1)?.as_str().parse().ok()
}
