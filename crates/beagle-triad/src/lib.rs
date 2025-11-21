//! beagle-triad - Honest AI Triad
//!
//! Sistema adversarial de revisão:
//! - ATHENA: agente "literatura" (pontos fortes/fracos, sugestões)
//! - HERMES: revisor (reescreve mantendo estilo/autoria)
//! - ARGOS: crítico (falhas lógicas, claims sem suporte)
//! - Juiz final: arbitra versões finais

use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, ProviderTier, stats::LlmCallsStats as LlmCallsStatsLLM};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::{info, warn};

/// Gera resumo simbólico do draft usando PCS (Symbolic Computational Psychiatry)
/// Extrai conceitos-chave, relações lógicas e estrutura semântica
pub async fn generate_symbolic_summary(draft: &str, ctx: &BeagleContext) -> anyhow::Result<String> {
    info!("Gerando resumo simbólico do draft");
    
    // Por enquanto, usa heurísticas simples para extrair conceitos
    // TODO: Integrar com PCS real via Julia quando disponível
    let concepts = extract_key_concepts(draft);
    let logical_structure = analyze_logical_structure(draft);
    
    let summary = format!(
        "## Resumo Simbólico (PCS)\n\n\
        **Conceitos-chave**: {}\n\n\
        **Estrutura lógica**: {}\n\n\
        **Nota**: Este resumo foi gerado usando heurísticas básicas. \
        Integração completa com PCS Symbolic Psychiatry será implementada via Julia.",
        concepts.join(", "),
        logical_structure
    );
    
    Ok(summary)
}

fn extract_key_concepts(text: &str) -> Vec<String> {
    // Heurística simples: palavras em maiúsculas, termos técnicos comuns
    let keywords = [
        "entropia", "curvatura", "scaffold", "biomaterial", "PBPK", "KEC",
        "psiquiatria", "computacional", "neurociência", "filosofia", "consciência",
        "geometria", "não-comutativa", "fractal", "holográfico"
    ];
    
    let mut found = Vec::new();
    let text_lower = text.to_lowercase();
    
    for keyword in &keywords {
        if text_lower.contains(keyword) {
            found.push(keyword.to_string());
        }
    }
    
    found
}

fn analyze_logical_structure(text: &str) -> String {
    // Heurística simples: conta seções, referências, equações
    let sections = text.matches("##").count();
    let references = text.matches("@").count() + text.matches("\\cite").count();
    let equations = text.matches("$$").count() / 2; // pares
    
    format!(
        "{} seções principais, {} referências, {} equações",
        sections, references, equations
    )
}

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
    pub llm_stats: LlmCallsStatsLLM,
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

    // 2) ATHENA (agente literatura)
    info!("🔬 Executando ATHENA...");
    let (athena, tier) = run_athena(&original_draft, &input.context_summary, ctx, &input.run_id).await?;
    info!("✅ ATHENA concluído - Score: {:.2} | Provider: {}", athena.score, tier.as_str());

    // 3) HERMES (revisor)
    info!("✍️  Executando HERMES...");
    let (hermes, tier) = run_hermes(&original_draft, &athena, ctx, &input.run_id).await?;
    info!("✅ HERMES concluído - Score: {:.2} | Provider: {}", hermes.score, tier.as_str());

    // 4) ARGOS (crítico)
    info!("⚔️  Executando ARGOS...");
    let (argos, tier) = run_argos(&original_draft, &hermes, &athena, ctx, &input.run_id).await?;
    info!("✅ ARGOS concluído - Score: {:.2} | Provider: {}", argos.score, tier.as_str());

    // 5) Juiz final (arbitra versões)
    info!("⚖️  Executando Juiz Final...");
    let (final_draft, tier) = arbitrate_final(
        &original_draft,
        &hermes,
        &athena,
        &argos,
        ctx,
        &input.run_id,
    )
    .await?;
    info!("✅ Juiz Final concluído - Draft final: {} chars | Provider: {}", final_draft.len(), tier.as_str());

    // Obtém stats finais do contexto
    let llm_stats = ctx.llm_stats.get(&input.run_id).unwrap_or_default();
    let llm_stats_converted = LlmCallsStatsLLM {
        grok3_calls: llm_stats.grok3_calls,
        grok3_tokens_in: llm_stats.grok3_tokens_in,
        grok3_tokens_out: llm_stats.grok3_tokens_out,
        grok4_calls: llm_stats.grok4_calls,
        grok4_tokens_in: llm_stats.grok4_tokens_in,
        grok4_tokens_out: llm_stats.grok4_tokens_out,
    };

    Ok(TriadReport {
        run_id: input.run_id.clone(),
        original_draft,
        final_draft,
        opinions: vec![athena, hermes, argos],
        created_at: Utc::now(),
        llm_stats: llm_stats_converted,
    })
}

/// Helper para chamada LLM com tracking de stats na Triad
async fn call_llm_with_stats_triad(
    ctx: &BeagleContext,
    run_id: &str,
    prompt: &str,
    meta: RequestMeta,
) -> anyhow::Result<(String, ProviderTier)> {
    // Obtém stats atuais do run
    let current_stats = ctx.llm_stats.get_or_create(run_id);
    
    // Escolhe client com limites
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);
    
    // Chama LLM
    let output = client.complete(prompt).await?;
    
    // Atualiza stats
    ctx.llm_stats.update(run_id, |stats| {
        match tier {
            ProviderTier::Grok3 => {
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
            ProviderTier::Grok4Heavy => {
                stats.grok4_calls += 1;
                stats.grok4_tokens_in += output.tokens_in_est as u32;
                stats.grok4_tokens_out += output.tokens_out_est as u32;
            }
            _ => {
                // Outros tiers contam como Grok3 por enquanto
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
        }
    });
    
    Ok((output.text, tier))
}

/// ATHENA: leitura crítica + literatura
/// 
/// Prompts customizados para o contexto científico interdisciplinar do BEAGLE:
/// - Psiquiatria computacional, entropia/curvatura, PBPK, biomateriais, neurociência
/// - Filosofia da mente, geometria não-comutativa, consciência celular
pub async fn run_athena(
    draft: &str,
    context_summary: &Option<String>,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let mut prompt = String::from(
        "Você é ATHENA, agente de leitura crítica e contexto científico do sistema BEAGLE.\n\n\
        O contexto de pesquisa envolve áreas interdisciplinares:\n\
        - Psiquiatria computacional e neurociência\n\
        - Entropia curva e geometria não-comutativa\n\
        - Modelagem PBPK (Farmacocinética Fisiológica) e KEC\n\
        - Biomateriais e scaffolds biológicos\n\
        - Consciência celular e filosofia da mente\n\
        - Engenharia química aplicada a sistemas biológicos\n\n\
        Analise o rascunho de artigo abaixo, identifique:\n\
        - Pontos fortes conceituais (especialmente conexões interdisciplinares)\n\
        - Fragilidades metodológicas ou conceituais\n\
        - Referências/literatura adicional relevante nestas áreas (Nature, Kybernetes, Frontiers, etc.)\n\n\
        Responda em três seções Markdown: ## Pontos Fortes, ## Fragilidades, ## Referências Sugeridas.\n\n",
    );

    if let Some(ctx_sum) = context_summary {
        prompt.push_str("=== CONTEXTO (Darwin / GraphRAG) ===\n");
        prompt.push_str(ctx_sum);
        prompt.push_str("\n\n");
    }

    // Adiciona contexto simbólico se habilitado (via env ou config)
    if std::env::var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE")
        .unwrap_or_else(|_| "false".to_string())
        .parse::<bool>()
        .unwrap_or(false)
    {
        if let Ok(symbolic_summary) = generate_symbolic_summary(draft, ctx).await {
            prompt.push_str("=== CONTEXTO SIMBÓLICO (PCS) ===\n");
            prompt.push_str(&symbolic_summary);
            prompt.push_str("\n\n");
        }
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

    let (text, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

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
/// 
/// Preserva voz autoral interdisciplinar (engenharia química, medicina, psiquiatria, biomateriais, filosofia da mente).
/// Alta densidade conceitual sem simplificação infantil.
pub async fn run_hermes(
    draft: &str,
    athena: &TriadOpinion,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let mut prompt = String::from(
        "Você é HERMES, agente de síntese textual do sistema BEAGLE.\n\n\
        IMPORTANTE: Preserve a voz autoral interdisciplinar característica de um pesquisador que trabalha na intersecção de:\n\
        - Engenharia química e farmacocinética (PBPK)\n\
        - Medicina e psiquiatria computacional\n\
        - Biomateriais e scaffolds biológicos\n\
        - Neurociência e filosofia da mente\n\
        - Geometria não-comutativa e entropia curva\n\n\
        Mantenha alta densidade conceitual, clareza sem simplificação infantil, elegância técnica.\n\n\
        Você receberá:\n\
        - Um rascunho de artigo (DRAFT)\n\
        - Uma análise crítica de ATHENA com sugestões (ATHENA_FEEDBACK)\n\n\
        Sua tarefa:\n\
        1. Reescrever o texto deixando-o mais claro, coeso e lógico.\n\
        2. Incorporar as sugestões relevantes de ATHENA.\n\
        3. NÃO inventar dados ou resultados; só reorganizar e melhorar o texto.\n\
        4. Mantenha o rigor técnico e a voz autoral interdisciplinar.\n\n\
        Responda apenas com o novo texto em Markdown, sem comentários fora do texto.\n\n",
    );

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

    let (text, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

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
/// 
/// Age como revisor Q1 duro (Nature Human Behaviour, Kybernetes, Frontiers), focado em:
/// - Claims sem suporte empírico adequado
/// - Confusão entre metáfora e mecanismo
/// - Ausência de desenho empírico razoável
pub async fn run_argos(
    original_draft: &str,
    hermes: &TriadOpinion,
    athena: &TriadOpinion,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let mut prompt = String::from(
        "Você é ARGOS, agente crítico adversarial do sistema BEAGLE.\n\n\
        Você atua como revisor Q1 rigoroso (Nature Human Behaviour, Kybernetes, Frontiers in Computational Neuroscience).\n\
        Foque especialmente em:\n\
        - Claims sem suporte empírico adequado (extrapolações não suportadas)\n\
        - Confusão entre metáfora poética e mecanismo científico concreto\n\
        - Ausência de desenho empírico razoável (onde há espaço para experimentos/predictions testáveis)\n\
        - Problemas de coerência lógica e ambiguidade conceitual\n\n\
        Você recebeu:\n\
        - O DRAFT original de um artigo\n\
        - Um DRAFT reescrito por HERMES\n\
        - Comentários de ATHENA\n\n\
        Sua função:\n\
        1. Liste problemas graves de coerência lógica, extrapolações não suportadas, ambiguidade.\n\
        2. Aponte onde HERMES melhorou o texto e onde piorou.\n\
        3. Sugira correções pontuais (especialmente onde o texto precisa ser mais rigoroso cientificamente).\n\n\
        Responda em Markdown com seções: ## Problemas Graves, ## Melhorias de HERMES, ## Sugestões Pontuais.\n\n",
    );

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

    let (text, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

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
/// 
/// Combina o melhor dos três agentes (ATHENA/HERMES/ARGOS) mantendo rigor científico e estilo interdisciplinar.
/// Foca em resolver problemas críticos apontados por ARGOS enquanto preserva a voz autoral.
pub async fn arbitrate_final(
    original_draft: &str,
    hermes: &TriadOpinion,
    athena: &TriadOpinion,
    argos: &TriadOpinion,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(String, ProviderTier)> {
    // Gera resumo simbólico (PCS) do draft original
    let symbolic_summary = generate_symbolic_summary(original_draft, ctx).await
        .unwrap_or_else(|e| {
            warn!("Falha ao gerar resumo simbólico: {}", e);
            "Resumo simbólico não disponível".to_string()
        });
    
    let mut prompt = String::from(
        "Você é o JUIZ FINAL do sistema BEAGLE (HONEST AI TRIAD).\n\n\
        IMPORTANTE: Mantenha a voz autoral interdisciplinar (engenharia química, medicina, psiquiatria, biomateriais, filosofia da mente).\n\
        Preserve alta densidade conceitual e elegância técnica.\n\n\
        **Resumo Simbólico (PCS)**:\n{}\n\n\
        Você recebeu:\n\
        - DRAFT_ORIGINAL: rascunho original do artigo.\n\
        - DRAFT_HERMES: versão reescrita por HERMES.\n\
        - FEEDBACK_ATHENA: análise crítica e sugestões de literatura.\n\
        - FEEDBACK_ARGOS: crítica adversarial rigorosa (nível Q1).\n\n\
        Sua tarefa:\n\
        1. Produzir uma versão FINAL do texto, em Markdown, incorporando o melhor de cada um.\n\
        2. Corrigir problemas graves apontados por ARGOS (claims sem suporte, confusão metáfora/mecanismo, etc.).\n\
        3. Incorporar sugestões relevantes de ATHENA quando apropriado.\n\
        4. Manter a voz autoral interdisciplinar e evitar inventar dados.\n\n\
        Responda **apenas** com o texto final em Markdown.\n\n",
    );
    prompt = prompt.replace("{}", &symbolic_summary);

    prompt.push_str("=== FEEDBACK_ATHENA ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== FEEDBACK_ARGOS ===\n");
    prompt.push_str(&argos.suggestions_md);
    
    // Contexto simbólico já foi adicionado no início do prompt
    
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

    call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await
}

// update_stats removido - agora usa call_llm_with_stats_triad que atualiza ctx.llm_stats diretamente

/// Extrai score de resposta (simplificado)
fn extract_score(response: &str) -> Option<f32> {
    // Procura por padrões como "Score: 0.85" ou "0.85"
    let re = regex::Regex::new(r"score[:\s]+([0-9]+\.[0-9]+)").ok()?;
    let binding = response.to_lowercase();
    let caps = re.captures(binding.as_str())?;
    caps.get(1)?.as_str().parse().ok()
}
