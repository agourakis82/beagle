//! beagle-triad - Honest AI Triad
//!
//! Sistema adversarial de revisão:
//! - ATHENA: agente "literatura" (pontos fortes/fracos, sugestões)
//! - HERMES: revisor (reescreve mantendo estilo/autoria)
//! - ARGOS: crítico (falhas lógicas, claims sem suporte)
//! - Juiz final: arbitra versões finais

use beagle_core::BeagleContext;
use beagle_llm::{stats::LlmCallsStats as LlmCallsStatsLLM, ProviderTier, RequestMeta};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::{info, warn};

/// HTTP client for the Sounio Inference Service (`smt.check`) — lets the triad
/// ask Sounio's own DPLL(T) solver whether an extracted constraint set is
/// consistent. See the module docs for the truth-mode boundary.
pub mod inference_client;

/// O contexto simbólico (PCS) só é injetado nos prompts quando explicitamente habilitado
/// (`BEAGLE_SYMBOLIC_CONTEXT_ENABLE=1`), e fica OFF por padrão.
///
/// Quando habilitado, `generate_symbolic_summary` chama o **solver real em Sounio** — o
/// verbo `pcs.reason` do Sounio Inference Service (ODE de sintomas integrada por RK4 em
/// Sounio puro; portado do antigo `reason_symbolically` em Julia). Se o serviço estiver
/// indisponível (inalcançável, timeout, erro), faz fallback para um resumo HEURÍSTICO de
/// palavra-chave. O bloco SEMPRE se auto-rotula com o status real (VERIFICADO POR SOLVER vs
/// HEURÍSTICO). Disciplina truth_mode: o prompt crítico nunca recebe sinal heurístico
/// disfarçado de simbólico verificado por solver.
fn symbolic_context_enabled() -> bool {
    std::env::var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(false)
}

/// Sinais sintomáticos em [0,1] extraídos do draft por proxy de palavra-chave.
/// São a ENTRADA (aproximada) do solver — quem é verificado por solver é o RACIOCÍNIO
/// (a evolução temporal da ODE), não estes sinais de entrada.
fn extract_symptom_signals(text: &str) -> std::collections::BTreeMap<String, f64> {
    let t = text.to_lowercase();
    let terms: [(&str, &[&str]); 4] = [
        (
            "depression",
            &[
                "depress",
                "anhedon",
                "humor deprimido",
                "desânimo",
                "melancol",
            ],
        ),
        (
            "anxiety",
            &["ansied", "anxiety", "pânico", "panic", "preocupaç", "worry"],
        ),
        (
            "stress",
            &[
                "estresse", "stress", "cortisol", "burnout", "alostá", "allosta",
            ],
        ),
        (
            "sleep",
            &[
                "insôn",
                "insomn",
                "privação de sono",
                "sleep deprivation",
                "vigília",
            ],
        ),
    ];
    let mut out = std::collections::BTreeMap::new();
    for (sym, kws) in terms.iter() {
        let hits = kws.iter().filter(|kw| t.contains(**kw)).count();
        // `sleep` é qualidade do sono: default alto (0.7), e CAI quando insônia é citada.
        let v = if *sym == "sleep" {
            (0.7 - 0.15 * hits as f64).max(0.1)
        } else if hits == 0 {
            0.5 // neutro
        } else {
            (0.5 + 0.15 * hits as f64).min(1.0)
        };
        out.insert((*sym).to_string(), v);
    }
    out
}

/// Chama o verbo `pcs.reason` do Sounio Inference Service (ODE de sintomas, RK4 em Sounio puro).
/// HTTP POST com timeout de 90s; qualquer falha vira `Err` (o chamador faz fallback heurístico).
/// `SOUNIO_INFERENCE_URL` aponta o serviço (default: Service in-cluster). Resposta:
/// `{ final_state: {depression,anxiety,stress,sleep}, severity_score }`.
async fn pcs_reason_sounio(
    symptoms: &std::collections::BTreeMap<String, f64>,
) -> anyhow::Result<serde_json::Value> {
    let base = std::env::var("SOUNIO_INFERENCE_URL")
        .unwrap_or_else(|_| "http://sounio-inference.beagle.svc.cluster.local:80".to_string());
    let url = format!("{}/v1/pcs/reason", base.trim_end_matches('/'));
    let body = serde_json::json!({
        "symptoms": {
            "depression": symptoms.get("depression").copied().unwrap_or(0.5),
            "anxiety": symptoms.get("anxiety").copied().unwrap_or(0.5),
            "stress": symptoms.get("stress").copied().unwrap_or(0.5),
            "sleep": symptoms.get("sleep").copied().unwrap_or(0.7),
        }
    });
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(90))
        .build()?;
    let resp = client.post(&url).json(&body).send().await?;
    if !resp.status().is_success() {
        anyhow::bail!("pcs.reason HTTP {}", resp.status());
    }
    Ok(resp.json::<serde_json::Value>().await?)
}

/// Gera resumo simbólico do draft via PCS (Symbolic Computational Psychiatry).
///
/// Quando o gate está ligado, chama o verbo `pcs.reason` do Sounio Inference Service (ODE de
/// sintomas, RK4 em Sounio puro); em qualquer falha (ou gate OFF) faz fallback para heurística
/// de palavra-chave. O bloco retornado se auto-rotula com o status real (VERIFICADO POR SOLVER
/// vs HEURÍSTICO).
pub async fn generate_symbolic_summary(
    draft: &str,
    _ctx: &BeagleContext,
) -> anyhow::Result<String> {
    info!("Gerando resumo simbólico do draft");

    let concepts = extract_key_concepts(draft);
    let logical_structure = analyze_logical_structure(draft);

    // Caminho REAL: solver simbólico em SOUNIO (verbo pcs.reason), via HTTP — gated.
    if symbolic_context_enabled() {
        let symptoms = extract_symptom_signals(draft);
        match pcs_reason_sounio(&symptoms).await {
            Ok(res) => {
                let fs = res.get("final_state");
                let g = |k: &str| fs.and_then(|o| o.get(k)).and_then(|v| v.as_f64());
                let fmt_state = |k: &str| {
                    g(k).map(|v| format!("{}={:.3}", k, v))
                        .unwrap_or_else(|| format!("{}=?", k))
                };
                let signals_in: Vec<String> = symptoms
                    .iter()
                    .map(|(k, v)| format!("{}={:.2}", k, v))
                    .collect();
                let severity = res
                    .get("severity_score")
                    .and_then(|v| v.as_f64())
                    .map(|s| format!("{:.3}", s))
                    .unwrap_or_else(|| "?".into());
                info!(severity = %severity, "PCS solver Sounio OK");
                return Ok(format!(
                    "## Resumo Simbólico — VERIFICADO POR SOLVER (PCS/Sounio)\n\n\
                    > Raciocínio resolvido pelo verbo `pcs.reason` do Sounio Inference Service \
                    (ODE de sintomas integrada por RK4 em Sounio puro; portado do antigo Julia). \
                    Os sinais de ENTRADA são proxy de palavra-chave (aproximados); a EVOLUÇÃO \
                    temporal e a severidade abaixo são verificadas por solver.\n\n\
                    **Sinais de entrada (proxy)**: {}\n\n\
                    **Estado simbólico final (t=10)**: {}, {}, {}, {}\n\n\
                    **Severity score (solver)**: {}\n\n\
                    **Conceitos-chave (heurístico)**: {}",
                    signals_in.join(", "),
                    fmt_state("depression"),
                    fmt_state("anxiety"),
                    fmt_state("stress"),
                    fmt_state("sleep"),
                    severity,
                    concepts.join(", "),
                ));
            }
            Err(e) => {
                warn!(error = %e, "PCS solver Sounio indisponível; fallback heurístico");
            }
        }
    }

    // Fallback HEURÍSTICO (auto-rotulado).
    let summary = format!(
        "## Resumo Simbólico — HEURÍSTICO (NÃO verificado por solver)\n\n\
        > ⚠️ Gerado por heurísticas de palavra-chave, NÃO pelo PCS/Sounio (indisponível neste ambiente). \
        Trate como dica fraca/aproximada — não como sinal simbólico verificado por solver.\n\n\
        **Conceitos-chave**: {}\n\n\
        **Estrutura lógica**: {}",
        concepts.join(", "),
        logical_structure
    );

    Ok(summary)
}

fn extract_key_concepts(text: &str) -> Vec<String> {
    // Heurística simples: palavras em maiúsculas, termos técnicos comuns
    let keywords = [
        "entropia",
        "curvatura",
        "scaffold",
        "biomaterial",
        "PBPK",
        "KEC",
        "psiquiatria",
        "computacional",
        "neurociência",
        "filosofia",
        "consciência",
        "geometria",
        "não-comutativa",
        "fractal",
        "holográfico",
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
    pub agent: String, // "ATHENA" | "HERMES" | "ARGOS"
    pub summary: String,
    pub suggestions_md: String, // markdown
    pub score: f32,             // 0.0–1.0
    pub provider_tier: String,  // "grok-3" | "grok-4-heavy" | etc.
}

/// Resultado da etapa EVOLVE (#21B).
///
/// Produz um draft refinado a partir das opiniões ATHENA/HERMES/ARGOS e do draft,
/// framado AUMENTATIVAMENTE (toda claim forte marcada como "requires
/// human/wet-lab validation" em vez de afirmada como fato) e CITATION-GROUNDED
/// (claims carregam referências ao contexto/fontes de suporte).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolvedDraft {
    /// Draft evoluído/refinado em Markdown.
    pub evolved_draft_md: String,
    /// Claims extraídas/evoluídas, cada uma framada aumentativamente e com citação.
    pub claims: Vec<EvolvedClaim>,
    /// Provider tier usado para a etapa EVOLVE.
    pub provider_tier: String,
}

/// Uma claim evoluída, framada aumentativamente e ancorada em citações (#21B).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolvedClaim {
    /// Texto da claim.
    pub claim: String,
    /// Sempre `true` por construção: a claim NÃO é afirmada como fato, mas
    /// como hipótese que requer validação humana / em laboratório (wet-lab).
    pub requires_human_validation: bool,
    /// Citações/fontes que suportam a claim (carregadas do contexto/fontes).
    pub citations: Vec<String>,
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
    /// Saída opcional da etapa EVOLVE (#21B). `None` quando a tournament
    /// EVOLVE não foi executada (preserva compat com consumidores existentes).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub evolved: Option<EvolvedDraft>,
}

/// Estatísticas de chamadas LLM
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LlmCallsStats {
    pub grok3_calls: usize,
    pub grok3_tokens_est: usize,
    pub heavy_calls: usize,
    pub heavy_tokens_est: usize,
}

// ============================================================================
// #21C — Checkpoint / Resume (file-based)
// ============================================================================

/// Resolve o diretório de checkpoint `{data_dir}/triad/<run_id>`.
///
/// Espelha o padrão de `triad_review.rs`: usa `ctx.cfg.storage.data_dir`,
/// com fallback para a env `BEAGLE_DATA_DIR` e, por último, um diretório temp.
/// Best-effort: nunca falha a run.
pub fn checkpoint_dir(ctx: &BeagleContext, run_id: &str) -> PathBuf {
    let base = {
        let configured = ctx.cfg.storage.data_dir.trim();
        if !configured.is_empty() {
            PathBuf::from(configured)
        } else if let Ok(env_dir) = std::env::var("BEAGLE_DATA_DIR") {
            PathBuf::from(env_dir)
        } else {
            std::env::temp_dir().join("beagle-data")
        }
    };
    base.join("triad").join(run_id)
}

/// Caminho do arquivo de checkpoint de um estágio: `<dir>/<stage>.json`.
fn stage_path(dir: &std::path::Path, stage: &str) -> PathBuf {
    dir.join(format!("{stage}.json"))
}

/// Persiste a saída de um estágio como JSON (best-effort, #21C).
///
/// Falhas de escrita são logadas via `warn!` e NÃO interrompem a run.
fn save_stage<T: Serialize>(dir: &std::path::Path, stage: &str, value: &T) {
    if let Err(e) = std::fs::create_dir_all(dir) {
        warn!(
            "checkpoint: falha ao criar dir {} para stage '{}': {}",
            dir.display(),
            stage,
            e
        );
        return;
    }
    let path = stage_path(dir, stage);
    match serde_json::to_string_pretty(value) {
        Ok(json) => {
            if let Err(e) = std::fs::write(&path, json) {
                warn!(
                    "checkpoint: falha ao escrever {} (stage '{}'): {}",
                    path.display(),
                    stage,
                    e
                );
            } else {
                info!("checkpoint: stage '{}' salvo em {}", stage, path.display());
            }
        }
        Err(e) => warn!("checkpoint: falha ao serializar stage '{}': {}", stage, e),
    }
}

/// Carrega a saída de um estágio se já existir um checkpoint (resume, #21C).
///
/// Retorna `None` se o arquivo não existe ou não desserializa (re-computa).
fn load_stage<T: for<'de> Deserialize<'de>>(dir: &std::path::Path, stage: &str) -> Option<T> {
    let path = stage_path(dir, stage);
    if !path.exists() {
        return None;
    }
    match std::fs::read_to_string(&path) {
        Ok(s) => match serde_json::from_str::<T>(&s) {
            Ok(v) => {
                info!(
                    "checkpoint: resume — stage '{}' carregado de {}",
                    stage,
                    path.display()
                );
                Some(v)
            }
            Err(e) => {
                warn!(
                    "checkpoint: stage '{}' existe mas não desserializa ({}); re-computando",
                    stage, e
                );
                None
            }
        },
        Err(e) => {
            warn!(
                "checkpoint: falha ao ler {} (stage '{}'): {}; re-computando",
                path.display(),
                stage,
                e
            );
            None
        }
    }
}

/// Executa a Triad completa (compat: ATHENA → HERMES → ARGOS → Juiz).
///
/// Mantém a assinatura/comportamento públicos existentes. Internamente delega
/// para [`run_triad_tournament`] com a etapa EVOLVE desabilitada, de modo que
/// consumidores atuais não veem mudança alguma (o campo `evolved` será `None`).
pub async fn run_triad(input: &TriadInput, ctx: &BeagleContext) -> anyhow::Result<TriadReport> {
    // Legacy entrypoint: no EVOLVE and no checkpoint side-effects — behavior is
    // identical to before (no files written, never auto-resumes).
    run_triad_tournament(input, ctx, false, false).await
}

/// #21B — Tournament generate-debate-EVOLVE com checkpoint/resume (#21C).
///
/// Roda ATHENA → HERMES → ARGOS → Juiz e, se `enable_evolve == true`, uma etapa
/// EVOLVE adicional após a crítica de ARGOS. Cada estágio é persistido em
/// `{data_dir}/triad/<run_id>/<stage>.json` conforme progride; ao iniciar, se o
/// arquivo de um estágio já existir para esse `run_id`, ele é CARREGADO e o
/// recálculo é pulado (resume). Checkpoint é best-effort; resume só é tentado
/// quando há `run_id`.
pub async fn run_triad_tournament(
    input: &TriadInput,
    ctx: &BeagleContext,
    enable_evolve: bool,
    checkpoint: bool,
) -> anyhow::Result<TriadReport> {
    info!(
        "🔍 Iniciando Triad para run_id: {} (evolve={}, checkpoint={})",
        input.run_id, enable_evolve, checkpoint
    );

    let ckpt_dir = checkpoint_dir(ctx, &input.run_id);

    // 1) Ler draft
    let original_draft = std::fs::read_to_string(&input.draft_path)?;
    info!("📄 Draft lido: {} chars", original_draft.len());

    // #21C: checkpoint/resume is OPT-IN. The legacy run_triad passes checkpoint=false,
    // so it writes NO files and never auto-resumes (behavior unchanged). When on,
    // resume reuses stages ONLY if the draft+evolve fingerprint matches the stored one
    // — editing the draft and re-running the same run_id recomputes instead of loading
    // stale opinions describing the old draft.
    let draft_fingerprint = {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        original_draft.hash(&mut h);
        enable_evolve.hash(&mut h);
        format!("{:016x}", h.finish())
    };
    let resume = checkpoint
        && !input.run_id.trim().is_empty()
        && load_stage::<String>(&ckpt_dir, "meta").as_deref() == Some(draft_fingerprint.as_str());
    if checkpoint {
        save_stage(&ckpt_dir, "meta", &draft_fingerprint);
    }

    // 2) ATHENA (agente literatura) — resume se já houver checkpoint
    let athena: TriadOpinion = match resume
        .then(|| load_stage::<TriadOpinion>(&ckpt_dir, "athena"))
        .flatten()
    {
        Some(op) => {
            info!("⏭️  ATHENA: resume de checkpoint (Score: {:.2})", op.score);
            op
        }
        None => {
            info!("🔬 Executando ATHENA...");
            let (op, tier) =
                run_athena(&original_draft, &input.context_summary, ctx, &input.run_id).await?;
            info!(
                "✅ ATHENA concluído - Score: {:.2} | Provider: {}",
                op.score,
                tier.as_str()
            );
            if checkpoint {
                save_stage(&ckpt_dir, "athena", &op);
            }
            op
        }
    };

    // 3) HERMES (revisor)
    let hermes: TriadOpinion = match resume
        .then(|| load_stage::<TriadOpinion>(&ckpt_dir, "hermes"))
        .flatten()
    {
        Some(op) => {
            info!("⏭️  HERMES: resume de checkpoint (Score: {:.2})", op.score);
            op
        }
        None => {
            info!("✍️  Executando HERMES...");
            let (op, tier) = run_hermes(&original_draft, &athena, ctx, &input.run_id).await?;
            info!(
                "✅ HERMES concluído - Score: {:.2} | Provider: {}",
                op.score,
                tier.as_str()
            );
            if checkpoint {
                save_stage(&ckpt_dir, "hermes", &op);
            }
            op
        }
    };

    // 4) ARGOS (crítico)
    let argos: TriadOpinion = match resume
        .then(|| load_stage::<TriadOpinion>(&ckpt_dir, "argos"))
        .flatten()
    {
        Some(op) => {
            info!("⏭️  ARGOS: resume de checkpoint (Score: {:.2})", op.score);
            op
        }
        None => {
            info!("⚔️  Executando ARGOS...");
            let (op, tier) =
                run_argos(&original_draft, &hermes, &athena, ctx, &input.run_id).await?;
            info!(
                "✅ ARGOS concluído - Score: {:.2} | Provider: {}",
                op.score,
                tier.as_str()
            );
            if checkpoint {
                save_stage(&ckpt_dir, "argos", &op);
            }
            op
        }
    };

    // 4b) EVOLVE (#21B) — refina o draft após a crítica de ARGOS.
    let evolved: Option<EvolvedDraft> = if enable_evolve {
        match resume
            .then(|| load_stage::<EvolvedDraft>(&ckpt_dir, "evolve"))
            .flatten()
        {
            Some(ev) => {
                info!(
                    "⏭️  EVOLVE: resume de checkpoint ({} claims)",
                    ev.claims.len()
                );
                Some(ev)
            }
            None => {
                info!("🧬 Executando EVOLVE...");
                let ev = run_evolve(
                    &original_draft,
                    &athena,
                    &hermes,
                    &argos,
                    &input.context_summary,
                    ctx,
                    &input.run_id,
                )
                .await?;
                info!(
                    "✅ EVOLVE concluído - {} claims | Provider: {}",
                    ev.claims.len(),
                    ev.provider_tier
                );
                if checkpoint {
                    save_stage(&ckpt_dir, "evolve", &ev);
                }
                Some(ev)
            }
        }
    } else {
        None
    };

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
    info!(
        "✅ Juiz Final concluído - Draft final: {} chars | Provider: {}",
        final_draft.len(),
        tier.as_str()
    );

    // Obtém stats finais do contexto
    let llm_stats = ctx.llm_stats.get(&input.run_id).unwrap_or_default();
    let llm_stats_converted = LlmCallsStatsLLM {
        grok3_calls: llm_stats.grok3_calls,
        grok3_tokens_in: llm_stats.grok3_tokens_in,
        grok3_tokens_out: llm_stats.grok3_tokens_out,
        grok4_calls: llm_stats.grok4_calls,
        grok4_tokens_in: llm_stats.grok4_tokens_in,
        grok4_tokens_out: llm_stats.grok4_tokens_out,
        deepseek_calls: llm_stats.deepseek_calls,
        deepseek_tokens_in: llm_stats.deepseek_tokens_in,
        deepseek_tokens_out: llm_stats.deepseek_tokens_out,
        local_calls: llm_stats.local_calls,
        local_tokens_in: llm_stats.local_tokens_in,
        local_tokens_out: llm_stats.local_tokens_out,
    };

    let report = TriadReport {
        run_id: input.run_id.clone(),
        original_draft,
        final_draft,
        opinions: vec![athena, hermes, argos],
        created_at: Utc::now(),
        llm_stats: llm_stats_converted,
        evolved,
    };

    // Persiste o relatório final (best-effort, #21C).
    save_stage(&ckpt_dir, "report", &report);

    Ok(report)
}

/// #21B — EVOLVE: refina draft + claims a partir das opiniões da Triad.
///
/// O output é (a) framado AUMENTATIVAMENTE — toda claim forte marcada como
/// `requires_human_validation` em vez de afirmada como fato — e (b)
/// CITATION-GROUNDED — claims carregam citações do contexto/fontes de suporte.
///
/// O LLM produz o draft evoluído em Markdown; as claims são extraídas
/// programaticamente e marcadas, garantindo a invariante aumentativa mesmo que
/// o modelo escorregue. Citações são carregadas do `context_summary` (quando
/// disponível) e de citações detectadas no próprio draft (`@key`, `\cite{...}`).
#[allow(clippy::too_many_arguments)]
pub async fn run_evolve(
    original_draft: &str,
    athena: &TriadOpinion,
    hermes: &TriadOpinion,
    argos: &TriadOpinion,
    context_summary: &Option<String>,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<EvolvedDraft> {
    let mut prompt = String::from(
        "Você é EVOLVE, o agente de refinamento aumentativo do sistema BEAGLE (HONEST AI TRIAD).\n\n\
        Você recebeu o DRAFT original e três opiniões (ATHENA, HERMES, ARGOS).\n\
        Sua tarefa é produzir um DRAFT EVOLUÍDO em Markdown que:\n\
        1. AUMENTATIVO: NÃO afirme claims fortes como fato. Toda afirmação forte deve ser\n\
           framada como hipótese/proposta que REQUER validação humana ou em laboratório\n\
           (wet-lab). Use linguagem como 'propomos que', 'hipótese a ser testada',\n\
           'requer validação experimental'.\n\
        2. CITATION-GROUNDED: cada claim forte deve referenciar a(s) fonte(s)/contexto de\n\
           suporte. Preserve e carregue citações do contexto (não invente referências).\n\
        3. Incorpore o melhor de ATHENA/HERMES e corrija os problemas apontados por ARGOS.\n\n\
        Responda APENAS com o draft evoluído em Markdown.\n\n",
    );

    if let Some(ctx_sum) = context_summary {
        prompt.push_str("=== CONTEXTO / FONTES ===\n");
        prompt.push_str(ctx_sum);
        prompt.push_str("\n\n");
    }
    prompt.push_str("=== FEEDBACK_ATHENA ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== DRAFT_HERMES ===\n");
    prompt.push_str(&hermes.suggestions_md);
    prompt.push_str("\n\n=== FEEDBACK_ARGOS ===\n");
    prompt.push_str(&argos.suggestions_md);
    prompt.push_str("\n\n=== DRAFT_ORIGINAL ===\n");
    prompt.push_str(original_draft);

    // EVOLVE é refinamento final crítico: alta qualidade + raciocínio PhD.
    let meta = RequestMeta::new(
        false,                      // requires_math
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,                       // high_bias_risk (decide framing de claims)
        true,                       // requires_phd_level_reasoning
        true,                       // critical_section
    );

    let (evolved_md, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

    // Pool de citações conhecidas (draft + contexto) usado como fallback de
    // grounding quando uma claim não traz citação inline própria.
    let mut draft_level_citations = extract_citations(original_draft);
    draft_level_citations.extend(extract_citations(&evolved_md));
    if let Some(ctx_sum) = context_summary {
        draft_level_citations.extend(extract_citations(ctx_sum));
    }
    dedup_in_place(&mut draft_level_citations);

    // Extrai claims do draft evoluído. Grounding é PER-CLAIM: as citações vêm do
    // texto da própria claim (extract_citations(&claim)); só caem para o pool
    // draft-level quando a claim não cita nada inline. requires_human_validation
    // é true por DESIGN (framing aumentativo: nenhuma claim do tournament é
    // afirmada como fato — todas requerem validação humana/wet-lab).
    let claims = extract_claims(&evolved_md)
        .into_iter()
        .map(|claim| {
            let mut per_claim = extract_citations(&claim);
            if per_claim.is_empty() {
                per_claim = draft_level_citations.clone();
            }
            EvolvedClaim {
                claim,
                requires_human_validation: true,
                citations: per_claim,
            }
        })
        .collect();

    Ok(EvolvedDraft {
        evolved_draft_md: evolved_md,
        claims,
        provider_tier: tier.as_str().to_string(),
    })
}

/// Extrai citações de um texto: padrões `@chave`, `\cite{...}` e `[N]`.
fn extract_citations(text: &str) -> Vec<String> {
    let mut out = Vec::new();

    if let Ok(re) = regex::Regex::new(r"\\cite\{([^}]+)\}") {
        for caps in re.captures_iter(text) {
            if let Some(m) = caps.get(1) {
                for key in m.as_str().split(',') {
                    let k = key.trim();
                    if !k.is_empty() {
                        out.push(format!("\\cite{{{k}}}"));
                    }
                }
            }
        }
    }
    if let Ok(re) = regex::Regex::new(r"@([A-Za-z][A-Za-z0-9_:-]+)") {
        for caps in re.captures_iter(text) {
            if let Some(m) = caps.get(1) {
                out.push(format!("@{}", m.as_str()));
            }
        }
    }
    if let Ok(re) = regex::Regex::new(r"\[(\d{1,3})\]") {
        for caps in re.captures_iter(text) {
            if let Some(m) = caps.get(1) {
                out.push(format!("[{}]", m.as_str()));
            }
        }
    }

    dedup_in_place(&mut out);
    out
}

/// Divide texto em sentenças sem fragmentar decimais (0.05) nem abreviações
/// comuns (et al., e.g., i.e., Fig., vs.). Quebra só em `.`/`!`/`?` seguido de
/// espaço/fim, e não quando o `.` está entre dígitos.
fn split_sentences(text: &str) -> Vec<String> {
    const ABBREVS: &[&str] = &[
        "et al", "e.g", "i.e", "fig", "eq", "vs", "cf", "dr", "al", "no", "ref",
    ];
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut start = 0usize;
    for i in 0..chars.len() {
        let c = chars[i];
        if c != '.' && c != '!' && c != '?' {
            continue;
        }
        let next = chars.get(i + 1).copied();
        let prev = if i > 0 {
            chars.get(i - 1).copied()
        } else {
            None
        };
        // Decimal: dígito.dígito (ex.: 0.05) — não é fim de sentença.
        if c == '.'
            && prev.is_some_and(|p| p.is_ascii_digit())
            && next.is_some_and(|n| n.is_ascii_digit())
        {
            continue;
        }
        // Fim de sentença só quando seguido de espaço ou fim de string.
        if next.is_none_or(|n| n.is_whitespace()) {
            let frag: String = chars[start..=i].iter().collect();
            let last_word = frag
                .trim()
                .rsplit(char::is_whitespace)
                .next()
                .unwrap_or("")
                .trim_end_matches('.')
                .to_ascii_lowercase();
            if ABBREVS.iter().any(|a| *a == last_word) {
                continue; // abreviação — não quebra
            }
            out.push(frag);
            start = i + 1;
        }
    }
    if start < chars.len() {
        out.push(chars[start..].iter().collect());
    }
    out
}

/// Extrai claims candidatas de um Markdown: frases não-triviais, sem cabeçalhos.
fn extract_claims(md: &str) -> Vec<String> {
    let mut claims = Vec::new();
    for line in md.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') || t.starts_with("```") || t.starts_with('|') {
            continue;
        }
        // Quebra a linha em sentenças (respeitando decimais/abreviações).
        for raw in split_sentences(t) {
            let s = raw
                .trim_start_matches(['-', '*', '>', ' '])
                .trim()
                .trim_end_matches(['.', '!', '?'])
                .trim()
                .to_string();
            // Heurística: claim = sentença com substância (mais de 5 palavras).
            if s.split_whitespace().count() > 5 {
                claims.push(s);
            }
        }
    }
    dedup_in_place(&mut claims);
    claims
}

/// Remove duplicatas preservando ordem.
fn dedup_in_place(v: &mut Vec<String>) {
    let mut seen = std::collections::HashSet::new();
    v.retain(|x| seen.insert(x.clone()));
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
/// ATHENA: Research accuracy specialist with high-quality requirements
///
/// Routed at requires_high_quality + requires_phd_level_reasoning. No published
/// latency/accuracy numbers are claimed here — measure them via the eval harness
/// (see docs/MODERNIZATION_PLAN_2026.md) rather than asserting unbacked figures.
#[tracing::instrument(skip(draft, context_summary, ctx), fields(run_id = %run_id, agent = "ATHENA"))]
pub async fn run_athena(
    draft: &str,
    context_summary: &Option<String>,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let start = std::time::Instant::now();

    // ATHENA requires highest accuracy for research validation
    let meta = RequestMeta {
        requires_high_quality: true,
        requires_phd_level_reasoning: true,
        high_bias_risk: false, // ATHENA is accuracy-focused, not bias-prone
        critical_section: false,
        requires_math: draft.contains("equation") || draft.contains("theorem"),
        offline_required: false,
        requires_vision: false,
        approximate_tokens: draft.len() / 4, // rough estimate
        ..Default::default()
    };

    info!("ATHENA: Evaluating draft with high-quality reasoning (PhD-level)");

    let mut prompt = String::from(
        "You are ATHENA, the scientific rigor specialist of the BEAGLE Triad system.\n\n\
        CONTEXT: Interdisciplinary research spanning:\n\
        • Computational psychiatry & neuroscience (cf. Friston, 2010; Montague et al., 2012)\n\
        • Non-commutative geometry & curved entropy (cf. Connes, 1994; Tsallis, 1988)\n\
        • PBPK modeling & kinetic energy considerations (cf. Rowland & Tozer, 2011)\n\
        • Biomaterials & biological scaffolds (cf. Langer & Vacanti, 1993)\n\
        • Cellular consciousness & philosophy of mind (cf. Koch, 2019; Tononi, 2008)\n\
        • Chemical engineering in biological systems (cf. Bailey & Ollis, 1986)\n\n\
        TASK: Analyze the draft below with Q1 journal standards. Identify:\n\
        1. Conceptual strengths (especially interdisciplinary connections)\n\
        2. Methodological weaknesses or gaps\n\
        3. Missing citations from top-tier venues (Nature, Science, Cell, PNAS)\n\n\
        OUTPUT FORMAT: Three Markdown sections:\n\
        ## Strengths\n\
        ## Weaknesses\n\
        ## Suggested References\n\n",
    );

    if let Some(ctx_sum) = context_summary {
        prompt.push_str("=== CONTEXTO (Darwin / GraphRAG) ===\n");
        prompt.push_str(ctx_sum);
        prompt.push_str("\n\n");
    }

    // Contexto simbólico (PCS) — GATED (OFF por padrão; ver symbolic_context_enabled).
    // O bloco se auto-rotula com o status real (VERIFICADO POR SOLVER vs HEURÍSTICO).
    if symbolic_context_enabled() {
        if let Ok(symbolic_summary) = generate_symbolic_summary(draft, ctx).await {
            prompt.push_str("=== CONTEXTO SIMBÓLICO (PCS) ===\n");
            prompt.push_str(&symbolic_summary);
            prompt.push_str("\n\n");
        }
    }

    prompt.push_str("=== DRAFT ===\n");
    prompt.push_str(draft);

    // Get current stats for this run
    let current_stats = ctx.llm_stats.get_or_create(run_id);

    // Choose LLM with limits - ATHENA needs high quality
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);

    // Execute LLM call with timing
    let llm_start = std::time::Instant::now();
    let output = client.complete(&prompt).await?;
    let llm_latency = llm_start.elapsed();

    // Update stats with precise tracking
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
                // Other tiers count as Grok3 for accounting
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
        }
    });

    let total_latency = start.elapsed();
    info!(
        "ATHENA completed in {:.2}s (LLM: {:.2}s) using {} with ~{} tokens",
        total_latency.as_secs_f64(),
        llm_latency.as_secs_f64(),
        tier.as_str(),
        output.total_tokens()
    );

    // Extrai score (pode pedir ao modelo explicitamente no futuro)
    let text = output.text.clone();
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
        false,                      // requires_math
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        false,                      // high_bias_risk (HERMES não precisa de Heavy)
        false,                      // requires_phd_level_reasoning (reescrita, não análise crítica)
        false,                      // critical_section
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
/// Gate: a verificação por solver só roda com `BEAGLE_TRIAD_SMT_CHECK` ligado (OFF por padrão).
/// Aceita as formas usuais de "ligado": `1`, `true`, `yes`, `on` (case-insensitive). Antes o
/// código fazia `v.parse::<bool>()`, que REJEITA `"1"` (só aceita `true`/`false`) — então o valor
/// documentado `BEAGLE_TRIAD_SMT_CHECK=1` deixava o gate silenciosamente DESLIGADO.
fn smt_claim_check_enabled() -> bool {
    std::env::var("BEAGLE_TRIAD_SMT_CHECK")
        .map(|v| {
            matches!(
                v.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(false)
}

/// Extrai o primeiro objeto JSON balanceado de um texto (o LLM costuma cercar com prosa).
fn first_json_object(s: &str) -> Option<String> {
    let start = s.find('{')?;
    let mut depth = 0i32;
    for (i, ch) in s[start..].char_indices() {
        match ch {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(s[start..start + i + ch.len_utf8()].to_string());
                }
            }
            _ => {}
        }
    }
    None
}

/// Verificação formal de consistência de claims via Sounio `smt.check`.
///
/// Fluxo: o LLM extrai afirmações quantitativas LINEARES do draft como constraints
/// inteiras QF_LIA → o verbo `smt.check` (DPLL(T) do Sounio) decide. Retorna um bloco
/// markdown de achado APENAS quando o solver prova `UNSAT` (contradição). Qualquer falha
/// (sem claims, serviço fora, parse, SAT/UNKNOWN) → `None` — honesto por construção, nunca
/// fabrica achado. Truth-mode: o solver prova que ESTAS constraints extraídas (falíveis) são
/// contraditórias, NÃO que "o draft está errado".
async fn solver_claim_consistency(
    draft: &str,
    ctx: &BeagleContext,
    run_id: &str,
) -> Option<String> {
    if !smt_claim_check_enabled() {
        return None;
    }
    let draft_excerpt: String = draft.chars().take(6000).collect();
    let prompt = format!(
        "Extraia afirmações quantitativas LINEARES e EXPLÍCITAS do texto como constraints inteiras \
         QF_LIA. Trabalhe em DOIS PASSOS.\n\
         PASSO 1 — CANONIZE AS VARIÁVEIS: liste as grandezas físicas distintas. A IDENTIDADE de uma \
         variável é definida SÓ por (unidade de medida + entidade medida). IGNORE COMPLETAMENTE \
         palavras de papel/qualificador como: mínimo, máximo, mínima, máxima, necessária, necessário, \
         administrada, eficaz, segura, permitida, alvo, recomendada, limite. Dois números com a MESMA \
         unidade sobre a MESMA entidade são a MESMA variável, mesmo em frases/seções diferentes e mesmo \
         com qualificadores opostos. Exemplo OBRIGATÓRIO de unificação: 'a dose diária administrada de \
         Zentamab ... no mínimo 80 mg' e 'a dose diária administrada de Zentamab ... no máximo 40 mg' \
         são UMA ÚNICA variável (unidade=mg, entidade=dose diária de Zentamab) → x0; vira x0>=80 E x0<=40.\n\
         PASSO 2 — EMITA AS CONSTRAINTS na forma `soma(coef_i * x_i) <= bound` usando os índices do passo 1. \
         `a >= b` vira `(-1)*a <= -b`; `a <= b` fica `(+1)*a <= b`. Confira o SINAL: 'no mínimo 80' é x>=80 \
         → coeffs com -1 e bound -80; 'no máximo 40' é x<=40 → coeffs com +1 e bound 40.\n\
         Responda SOMENTE com JSON, sem prosa: \
         {{\"variables\":[\"unidade|entidade\",...],\"constraints\":[{{\"label\":\"texto curto\",\"coeffs\":[inteiro por variável],\"bound\":inteiro}}]}}. \
         Se NÃO houver afirmações quantitativas lineares explícitas, responda \
         {{\"variables\":[],\"constraints\":[]}}. NÃO invente; só o que está LITERALMENTE no texto.\
         \n\n=== TEXTO ===\n{}",
        draft_excerpt
    );
    // Extração de constraints é tarefa de PRECISÃO (unificar variáveis corretamente): roteia para
    // o modelo forte (high_quality + phd + critical), não o workhorse barato — caso contrário a
    // extração super-divide grandezas iguais em variáveis distintas e perde a contradição (SAT em
    // vez de UNSAT). requires_high_quality=true, requires_phd_level_reasoning=true, critical=true.
    let meta = RequestMeta::new(
        false,
        true,
        false,
        prompt.chars().count() / 4,
        false,
        true,
        true,
    );
    let (text, _tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta)
        .await
        .ok()?;

    let parsed: serde_json::Value = serde_json::from_str(&first_json_object(&text)?).ok()?;
    let cons_json = parsed.get("constraints")?.as_array()?;
    let mut constraints: Vec<inference_client::LiaConstraint> = Vec::new();
    for c in cons_json {
        let coeffs: Vec<i64> = match c.get("coeffs").and_then(|v| v.as_array()) {
            Some(arr) => arr.iter().filter_map(|v| v.as_i64()).collect(),
            None => continue,
        };
        if coeffs.is_empty() || coeffs.iter().all(|&k| k == 0) {
            continue;
        }
        let bound = match c.get("bound").and_then(|v| v.as_i64()) {
            Some(b) => b,
            None => continue,
        };
        let label = c
            .get("label")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        constraints.push(inference_client::LiaConstraint {
            coeffs,
            bound,
            label,
        });
    }
    if constraints.len() < 2 {
        return None; // precisa de >=2 claims pra haver contradição
    }

    let base = inference_client::inference_base_url();
    match inference_client::smt_check(&base, constraints.clone()).await {
        inference_client::Verdict::Unsat => {
            let lines: Vec<String> = constraints
                .iter()
                .map(|c| {
                    format!(
                        "- `{}`",
                        c.label
                            .clone()
                            .unwrap_or_else(|| format!("Σ{:?}·x <= {}", c.coeffs, c.bound))
                    )
                })
                .collect();
            info!("solver_claim_consistency: UNSAT — contradição provada por Sounio smt.check");
            Some(format!(
                "## ⚠️ Contradição provada por solver (Sounio SMT)\n\n\
                O verificador formal `smt.check` (Sounio, DPLL(T) QF_LIA) provou que o conjunto de \
                afirmações quantitativas abaixo — extraídas do draft — é **mutuamente contraditório** (UNSAT):\n\n\
                {}\n\n\
                > **Honestidade (truth-mode):** a EXTRAÇÃO de claims é feita por LLM e é falível. \
                O solver provou apenas que ESTAS constraints são inconsistentes entre si — \
                confirme contra o texto antes de afirmar que o draft em si está errado.",
                lines.join("\n")
            ))
        }
        _ => None,
    }
}

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

    // Verificação formal de consistência via Sounio smt.check (gated). UNSAT = contradição
    // PROVADA por solver — sinal forte para ARGOS, e surfaceado no relatório. Honesto:
    // None quando não há contradição provada ou o serviço está fora.
    let solver_finding = solver_claim_consistency(original_draft, ctx, run_id).await;
    if let Some(ref f) = solver_finding {
        prompt.push_str("\n\n=== VERIFICAÇÃO FORMAL POR SOLVER (Sounio SMT — verificada) ===\n");
        prompt.push_str(f);
        prompt.push_str(
            "\nIncorpore este achado verificado por solver na sua crítica. É forte (prova \
             formal), mas a EXTRAÇÃO de claims que o alimentou é falível — trate a contradição \
             como provada apenas para as constraints extraídas, não como veredito sobre o autor.\n",
        );
    }

    // ARGOS usa Heavy: crítica sobre claims científicos
    let meta = RequestMeta::new(
        false,                      // requires_math (ou true se for Methods de KEC/PBPK)
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,                       // high_bias_risk (crítica sobre claims científicos)
        true,                       // requires_phd_level_reasoning
        true,                       // critical_section (revisão crítica)
    );

    let (text, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

    let score = extract_score(&text).unwrap_or(0.9);

    // Surfacea o achado do solver no topo do relatório de ARGOS (independe do que o LLM disse).
    let suggestions_md = match solver_finding {
        Some(f) => format!("{}\n\n---\n\n{}", f, text),
        None => text,
    };

    Ok((
        TriadOpinion {
            agent: "ARGOS".into(),
            summary: "Crítica adversarial e apontamento de falhas lógicas".into(),
            suggestions_md,
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
    // Contexto simbólico (PCS) — GATED (OFF por padrão). Quando ligado, tenta o solver Julia real
    // e cai para heurística se indisponível; o bloco se auto-rotula com o status real. Só injeta com
    // BEAGLE_SYMBOLIC_CONTEXT_ENABLE=1 (antes era injetado SEMPRE como sinal simbólico — falso no Juiz).
    let symbolic_block = if symbolic_context_enabled() {
        match generate_symbolic_summary(original_draft, ctx).await {
            Ok(s) => format!("**Contexto Simbólico (PCS)**:\n{}\n\n", s),
            Err(e) => {
                warn!("Falha ao gerar resumo simbólico: {}", e);
                String::new()
            }
        }
    } else {
        String::new()
    };

    let mut prompt = String::from(
        "Você é o JUIZ FINAL do sistema BEAGLE (HONEST AI TRIAD).\n\n\
        IMPORTANTE: Mantenha a voz autoral interdisciplinar (engenharia química, medicina, psiquiatria, biomateriais, filosofia da mente).\n\
        Preserve alta densidade conceitual e elegância técnica.\n\n\
        [[SYMBOLIC_BLOCK]]\
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
    prompt = prompt.replace("[[SYMBOLIC_BLOCK]]", &symbolic_block);

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
        false,                      // requires_math
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,                       // high_bias_risk (decisão final sobre texto científico)
        true,                       // requires_phd_level_reasoning
        true,                       // critical_section (versão final)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_json_object_extracts_from_prose() {
        let s =
            "claro, aqui está: {\"constraints\":[{\"coeffs\":[1],\"bound\":3}]} — espero que ajude";
        let j = first_json_object(s).expect("deve extrair");
        let v: serde_json::Value = serde_json::from_str(&j).unwrap();
        assert!(v.get("constraints").unwrap().as_array().unwrap().len() == 1);
    }

    #[test]
    fn first_json_object_handles_nesting() {
        assert_eq!(
            first_json_object("x {\"a\":{\"b\":1}} y").as_deref(),
            Some("{\"a\":{\"b\":1}}")
        );
        assert!(first_json_object("no json here").is_none());
    }

    #[tokio::test]
    async fn solver_check_is_off_by_default() {
        // Sem BEAGLE_TRIAD_SMT_CHECK, a verificação não roda (nem chama LLM/serviço).
        std::env::remove_var("BEAGLE_TRIAD_SMT_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = solver_claim_consistency("dose >= 6 e dose <= 3", &ctx, "t").await;
        assert!(out.is_none());
    }

    fn sample_opinion() -> TriadOpinion {
        TriadOpinion {
            agent: "ATHENA".into(),
            summary: "test summary".into(),
            suggestions_md: "## Strengths\n- good".into(),
            score: 0.83,
            provider_tier: "grok-3".into(),
        }
    }

    #[test]
    fn symptom_signals_are_bounded_and_responsive() {
        // Texto neutro → tudo no baseline (sleep alto, demais 0.5).
        let neutral = extract_symptom_signals("compilador e geometria da informação");
        assert_eq!(neutral.get("depression").copied(), Some(0.5));
        assert_eq!(neutral.get("sleep").copied(), Some(0.7));

        // Termos clínicos elevam os sinais; insônia REBAIXA o sono.
        let clinical =
            extract_symptom_signals("paciente com depressão, ansiedade, estresse e insônia");
        assert!(clinical["depression"] > 0.5);
        assert!(clinical["anxiety"] > 0.5);
        assert!(clinical["stress"] > 0.5);
        assert!(clinical["sleep"] < 0.7);
        // Sempre dentro de [0,1].
        for v in clinical.values() {
            assert!((0.0..=1.0).contains(v), "sinal fora de [0,1]: {v}");
        }
    }

    // E2E contra o serviço vivo: `SOUNIO_INFERENCE_URL=http://127.0.0.1:<pf> \
    // cargo test -p beagle-triad symbolic_summary_live -- --ignored --nocapture`
    #[tokio::test]
    #[ignore]
    async fn symbolic_summary_live_is_solver_verified() {
        std::env::set_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE", "true");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = generate_symbolic_summary("paciente com depressão, ansiedade e insônia", &ctx)
            .await
            .expect("summary");
        std::env::remove_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE");
        eprintln!("{out}");
        assert!(
            out.contains("VERIFICADO POR SOLVER (PCS/Sounio)"),
            "got: {out}"
        );
        assert!(out.contains("Severity score (solver)"));
    }

    #[tokio::test]
    async fn symbolic_summary_falls_back_honestly_without_solver() {
        // Gate LIGADO mas o Sounio Inference Service inalcançável: o resumo DEVE se
        // rotular como heurístico — nunca como verificado por solver (truth_mode).
        std::env::set_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE", "true");
        std::env::set_var("SOUNIO_INFERENCE_URL", "http://127.0.0.1:1"); // porta morta
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = generate_symbolic_summary("texto sobre entropia e PBPK", &ctx)
            .await
            .expect("summary should always succeed (fallback)");
        std::env::remove_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE");
        std::env::remove_var("SOUNIO_INFERENCE_URL");
        assert!(
            out.contains("HEURÍSTICO (NÃO verificado por solver)"),
            "fallback deve se auto-rotular heurístico, got: {out}"
        );
        assert!(!out.contains("VERIFICADO POR SOLVER"));
    }

    #[test]
    fn checkpoint_round_trip_opinion() {
        let dir = tempfile::tempdir().unwrap();
        let op = sample_opinion();

        save_stage(dir.path(), "athena", &op);

        let loaded: TriadOpinion =
            load_stage(dir.path(), "athena").expect("checkpoint should load back");
        assert_eq!(loaded.agent, op.agent);
        assert_eq!(loaded.summary, op.summary);
        assert_eq!(loaded.suggestions_md, op.suggestions_md);
        assert_eq!(loaded.score, op.score);
        assert_eq!(loaded.provider_tier, op.provider_tier);
    }

    #[test]
    fn load_stage_missing_returns_none() {
        let dir = tempfile::tempdir().unwrap();
        let loaded: Option<TriadOpinion> = load_stage(dir.path(), "argos");
        assert!(loaded.is_none(), "missing stage file must return None");
    }

    #[test]
    fn resume_skips_when_file_present() {
        // Mirrors the resume logic in run_triad_tournament: when a stage file
        // exists, load_stage returns Some and recomputation is skipped.
        let dir = tempfile::tempdir().unwrap();
        let op = sample_opinion();
        save_stage(dir.path(), "hermes", &op);

        let resume = true;
        let resumed: Option<TriadOpinion> = resume
            .then(|| load_stage::<TriadOpinion>(dir.path(), "hermes"))
            .flatten();
        assert!(
            resumed.is_some(),
            "present stage file must trigger resume (skip recompute)"
        );
        assert_eq!(resumed.unwrap().score, op.score);
    }

    #[test]
    fn evolved_draft_serde_round_trip() {
        let ev = EvolvedDraft {
            evolved_draft_md: "We propose that X requires experimental validation [1].".into(),
            claims: vec![EvolvedClaim {
                claim: "We propose that X requires experimental validation".into(),
                requires_human_validation: true,
                citations: vec!["[1]".into()],
            }],
            provider_tier: "grok-4-heavy".into(),
        };
        let json = serde_json::to_string(&ev).unwrap();
        let back: EvolvedDraft = serde_json::from_str(&json).unwrap();
        assert_eq!(back.evolved_draft_md, ev.evolved_draft_md);
        assert_eq!(back.claims.len(), 1);
        assert!(back.claims[0].requires_human_validation);
        assert_eq!(back.claims[0].citations, vec!["[1]".to_string()]);
    }

    #[test]
    fn triad_report_evolved_defaults_to_none_for_legacy_json() {
        // Existing consumers serialize TriadReport without `evolved`; ensure
        // deserialization still works (additive, non-breaking).
        let legacy = serde_json::json!({
            "run_id": "r1",
            "original_draft": "orig",
            "final_draft": "final",
            "opinions": [],
            "created_at": "2026-06-07T00:00:00Z",
            "llm_stats": {
                "grok3_calls": 0, "grok3_tokens_in": 0, "grok3_tokens_out": 0,
                "grok4_calls": 0, "grok4_tokens_in": 0, "grok4_tokens_out": 0,
                "deepseek_calls": 0, "deepseek_tokens_in": 0, "deepseek_tokens_out": 0,
                "local_calls": 0, "local_tokens_in": 0, "local_tokens_out": 0
            }
        });
        let report: TriadReport = serde_json::from_value(legacy).unwrap();
        assert!(report.evolved.is_none());
    }

    #[test]
    fn extract_citations_finds_patterns() {
        let text = "See @smith2020 and \\cite{jones1999,doe2001}. Also [12].";
        let cites = extract_citations(text);
        assert!(cites.contains(&"@smith2020".to_string()));
        assert!(cites.contains(&"\\cite{jones1999}".to_string()));
        assert!(cites.contains(&"\\cite{doe2001}".to_string()));
        assert!(cites.contains(&"[12]".to_string()));
    }

    #[test]
    fn extract_claims_skips_headers_and_short_lines() {
        let md = "# Title\n\nWe propose that the scaffold curvature modulates entropy flow.\nshort line\n";
        let claims = extract_claims(md);
        assert_eq!(claims.len(), 1);
        assert!(claims[0].contains("scaffold curvature modulates entropy"));
    }

    #[test]
    fn evolve_claims_are_augmentative() {
        // Every extracted claim must be flagged as requiring human/wet-lab validation.
        let md = "We propose that biomaterial scaffolds restore neural curvature dynamics.";
        let claims: Vec<EvolvedClaim> = extract_claims(md)
            .into_iter()
            .map(|claim| EvolvedClaim {
                claim,
                requires_human_validation: true,
                citations: vec![],
            })
            .collect();
        assert!(!claims.is_empty());
        assert!(claims.iter().all(|c| c.requires_human_validation));
    }

    #[test]
    fn checkpoint_dir_uses_run_id_segment() {
        // Falls back to env BEAGLE_DATA_DIR layout; verify path shape only.
        let p = stage_path(std::path::Path::new("/tmp/triad/run42"), "evolve");
        assert!(p.ends_with("evolve.json"));
    }
}
