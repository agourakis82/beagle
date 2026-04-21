//! Pipeline BEAGLE v0.1 - pergunta → draft.md + draft.pdf + run_report.json
//!
//! Fluxo completo:
//! 1. Darwin: contexto semântico (GraphRAG)
//! 2. Observer: estado fisiológico (HealthKit/HRV)
//! 3. HERMES: síntese de paper
//! 4. Escrita de artefatos (MD, PDF, JSON)

use crate::pipeline_void::{handle_deadlock, DeadlockState};
use beagle_config::PhysioThresholds;
use beagle_core::BeagleContext;
use beagle_exocortex::{ExocortexConfig, ExocortexInput, InputModality, PersonalExocortex};
use beagle_feedback::{append_event, create_pipeline_event};
use beagle_hermes::paper_synthesis::{PaperSynthesisConfig, PaperSynthesisEngine};
use beagle_llm::{ProviderTier, RequestMeta};
use beagle_observer::UniversalObserver;
use beagle_quantum::HypothesisSet;
use beagle_serendipity::SerendipityInjector;
use chrono::Utc;
use std::path::PathBuf;
use std::sync::Arc;
use tracing::{info, instrument, warn};

/// Caminhos dos artefatos gerados pelo pipeline
#[derive(Debug, Clone)]
pub struct PipelinePaths {
    pub draft_md: PathBuf,
    pub draft_pdf: PathBuf,
    pub run_report: PathBuf,
}

/// Flags experimentais para controle de condições A/B
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct ExperimentFlags {
    /// Se hrv_aware=false, usa UserContext::default() ao invés do contexto real
    pub hrv_aware: bool,
    /// Se triad_enabled=false, pula etapa de Triad
    pub triad_enabled: bool,
    /// Se observer_enabled=false, não há snapshot fisiológico canônico disponível
    pub observer_enabled: bool,
    /// Slot canônico para uso experimental futuro
    pub serendipity_enabled: bool,
}

impl ExperimentFlags {
    pub fn new(
        hrv_aware: bool,
        triad_enabled: bool,
        observer_enabled: bool,
        serendipity_enabled: bool,
    ) -> Self {
        Self {
            hrv_aware,
            triad_enabled,
            observer_enabled,
            serendipity_enabled,
        }
    }

    pub fn default_all_enabled() -> Self {
        Self {
            hrv_aware: true,
            triad_enabled: true,
            observer_enabled: true,
            serendipity_enabled: true,
        }
    }

    pub fn condition_label(&self) -> &'static str {
        if self.hrv_aware {
            "hrv_aware"
        } else {
            "hrv_blind"
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
struct PipelinePhysioMetadata {
    snapshot_available: bool,
    used_in_pipeline: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    snapshot: Option<beagle_observer::PhysioSnapshot>,
    #[serde(skip_serializing_if = "Option::is_none")]
    hrv_level: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    physio_source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    physio_timestamp: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    hr: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    spo2: Option<f64>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
struct PipelinePhysioSeverityEvent {
    event_id: String,
    kind: String,
    recording_mode: String,
    condition: String,
    used_in_pipeline: bool,
    severity: String,
    triggers: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    timestamp: Option<String>,
}

/// Executa pipeline completo BEAGLE v0.1
#[instrument(skip(ctx, observer), fields(run_id = %run_id))]
pub async fn run_beagle_pipeline(
    ctx: &mut BeagleContext,
    question: &str,
    run_id: &str,
    observer: Option<Arc<UniversalObserver>>,
    science_job_ids: Option<Vec<String>>,
    experiment_flags: Option<ExperimentFlags>,
    experiment_id: Option<String>,
) -> anyhow::Result<PipelinePaths> {
    info!("🚀 Pipeline BEAGLE v0.1 iniciado: {}", question);
    let experiment_flags = experiment_flags.unwrap_or_else(|| {
        ExperimentFlags::new(
            true,
            false,
            observer.is_some(),
            ctx.cfg.serendipity_enabled(),
        )
    });

    // 0) Memory RAG injection (opcional)
    let mut memory_context = String::new();
    #[cfg(feature = "memory")]
    {
        if ctx.cfg.memory_retrieval_enabled() {
            info!("🧠 Fase 0: Memory RAG injection");
            if let Ok(mem_result) = ctx
                .memory_query(beagle_memory::MemoryQuery {
                    query: question.to_string(),
                    scope: Some("scientific".to_string()),
                    max_items: Some(3),
                    domain: None,
                    tags: vec![],
                    include_recent_physio: false,
                })
                .await
            {
                memory_context = format!(
                    "\n\n=== Contexto Prévio Relevante ===\n{}\n\n",
                    mem_result.summary
                );
                if !mem_result.highlights.is_empty() {
                    memory_context.push_str("=== Destaques ===\n");
                    for (i, h) in mem_result.highlights.iter().take(3).enumerate() {
                        memory_context.push_str(&format!(
                            "{}. [{}] {}\n",
                            i + 1,
                            h.source,
                            h.snippet
                        ));
                    }
                    memory_context.push_str("\n");
                }
                info!(
                    "Memory RAG: {} highlights encontrados",
                    mem_result.highlights.len()
                );
            }
        }
    }

    // 1) Darwin: contexto semântico (GraphRAG + Self-RAG)
    info!("📊 Fase 1: Darwin GraphRAG + Self-RAG");
    // Cria Darwin com acesso aos stores do contexto
    // Nota: DarwinCore usa os stores diretamente via graph_rag_query()
    let darwin_ctx_arc = Arc::new(beagle_core::BeagleContext {
        cfg: ctx.cfg.clone(),
        router: ctx.router.clone(),
        llm: ctx.llm.clone(),
        vector: ctx.vector.clone(),
        graph: ctx.graph.clone(),
        llm_stats: ctx.llm_stats.clone(),
        #[cfg(feature = "memory")]
        memory: ctx.memory.clone(),
    });
    let darwin = beagle_darwin::DarwinCore::with_context(darwin_ctx_arc);
    let darwin_result = darwin.enhanced_cycle(question).await?;
    let mut context = darwin_result.combined_text.clone();
    info!(
        chunks = context.len(),
        snippets = darwin_result.snippets.len(),
        "Contexto Darwin gerado"
    );

    // Prepend memory context if available
    if !memory_context.is_empty() {
        context = format!("{}{}", memory_context, context);
    }

    // 1.5) Serendipity: descoberta de conexões interdisciplinares (opcional)
    let mut serendipity_score: Option<f64> = None;
    let mut serendipity_accidents: Vec<String> = Vec::new();

    if ctx.cfg.serendipity_enabled() {
        info!("🔮 Fase 1.5: Serendipity (descoberta de conexões)");

        // Cria HypothesisSet a partir do contexto atual
        // Nota: HypothesisSet::add() usa thread_rng() que não é Send
        // Por enquanto, criamos um set mínimo sem usar add() diretamente
        let mut hyp_set = HypothesisSet::new();
        // Extrai hipóteses implícitas do contexto (simplificado)
        let context_chunks: Vec<&str> = context.split("\n\n").collect();
        for (i, chunk) in context_chunks.iter().take(5).enumerate() {
            if chunk.len() > 50 {
                // Usa amplitude fixa para evitar thread_rng() não-Send
                hyp_set.add(
                    format!(
                        "Hipótese {}: {}",
                        i + 1,
                        chunk.chars().take(200).collect::<String>()
                    ),
                    Some((0.7, 0.1)),
                );
            }
        }

        // Se não houver hipóteses suficientes, cria uma baseada na pergunta
        if hyp_set.hypotheses.is_empty() {
            hyp_set.add(
                format!("Hipótese principal: {}", question),
                Some((0.8, 0.0)),
            );
        }

        // Inicializa SerendipityInjector
        let injector = if let Some(ref vllm_url) = ctx.cfg.llm.vllm_url {
            SerendipityInjector::with_vllm_url(vllm_url)
        } else {
            SerendipityInjector::new()
        };

        // Injeta acidentes férteis
        match injector
            .inject_fertile_accident(&hyp_set, &format!("{} {}", question, context))
            .await
        {
            Ok(accidents) => {
                if !accidents.is_empty() {
                    // Convert to strings for storage
                    let accidents_str: Vec<String> =
                        accidents.iter().map(|a| a.to_string()).collect();
                    serendipity_accidents = accidents_str.clone();
                    serendipity_score = Some(accidents.len() as f64 * 0.2); // Score baseado em quantidade

                    // Integra acidentes no contexto
                    let serendipity_text = format!(
                        "\n\n=== Conexões Serendipitosas (Interdisciplinares) ===\n{}\n\n",
                        accidents_str.join("\n\n")
                    );
                    context.push_str(&serendipity_text);

                    info!(
                        "✅ Serendipity: {} acidentes férteis injetados (score: {:.2})",
                        accidents.len(),
                        serendipity_score.unwrap_or(0.0)
                    );
                } else {
                    info!("Serendipity: nenhum acidente fértil gerado");
                }
            }
            Err(e) => {
                warn!("Falha ao injetar Serendipity: {}", e);
            }
        }
    }

    // 2) Observer: estado fisiológico (HealthKit / HRV)
    // Flags experimentais: se hrv_aware=false, usa contexto neutro
    let hrv_aware = experiment_flags.hrv_aware;

    info!(
        "🏥 Fase 2: Observer (contexto completo - Observer 2.0, hrv_aware={})",
        hrv_aware
    );
    let (physio, hrv_level, user_ctx, canonical_physio_snapshot, physio_event) =
        if let Some(ref obs) = observer {
            let actual_user_ctx = obs.current_user_context().await;
            let canonical_physio_snapshot = actual_user_ctx.latest_physio_snapshot.clone();

        // Obtém UserContext completo (fisiológico, ambiental, clima espacial)
        let user_ctx = if hrv_aware {
            actual_user_ctx
        } else {
            // Condição experimental: hrv_blind - usa contexto neutro
            beagle_observer::UserContext::default()
        };

        let physio_event = build_pipeline_physio_event(
            run_id,
            &experiment_flags,
            &ctx.cfg.observer.physio,
            canonical_physio_snapshot.as_ref(),
        );

        // Formata string fisiológica para o prompt (compatibilidade)
        let physio_str = format!(
            "Estado fisiológico: HRV {} ({}), HR {}bpm, SpO₂ {}%, severidade: {}. Ambiente: {}. Clima espacial: {} (Kp: {}).",
            user_ctx.physio.hrv_level.as_deref().unwrap_or("N/A"),
            user_ctx.physio.hrv_level.as_deref().unwrap_or("N/A"),
            user_ctx.physio.heart_rate_bpm.map(|hr| hr.to_string()).unwrap_or_else(|| "N/A".to_string()),
            user_ctx.physio.spo2_percent.map(|spo| format!("{:.0}%", spo)).unwrap_or_else(|| "N/A".to_string()),
            user_ctx.physio.severity.as_str(),
            user_ctx.env.summary.as_deref().unwrap_or("N/A"),
            user_ctx.space.heliobio_risk_level.as_deref().unwrap_or("N/A"),
            user_ctx.space.kp_index.map(|kp| format!("{:.1}", kp)).unwrap_or_else(|| "N/A".to_string()),
        );

        let hrv_level = user_ctx.physio.hrv_level.clone();

        // Adiciona observação de contexto completo à timeline do run_id
        let context_obs = beagle_observer::Observation {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: Utc::now().to_rfc3339(),
            source: "pipeline_user_context".to_string(),
            path: None,
            content_preview: physio_str.clone(),
            metadata: serde_json::json!({
                "physio_severity": user_ctx.physio.severity.as_str(),
                "env_severity": user_ctx.env.severity.as_str(),
                "space_severity": user_ctx.space.severity.as_str(),
                "hrv_level": user_ctx.physio.hrv_level,
                "heart_rate_bpm": user_ctx.physio.heart_rate_bpm,
                "spo2_percent": user_ctx.physio.spo2_percent,
                "stress_index": user_ctx.physio.stress_index,
                "heliobio_risk_level": user_ctx.space.heliobio_risk_level,
                "env_summary": user_ctx.env.summary,
                "kp_index": user_ctx.space.kp_index,
            }),
            observation_type: Some(beagle_observer::ObservationType::Physiological),
            tags: Some(vec!["pipeline".to_string(), "context".to_string()]),
        };
        obs.add_to_timeline(context_obs).await;

        if let Some(event) = physio_event.as_ref() {
            let severity_obs = beagle_observer::Observation {
                id: event.event_id.clone(),
                timestamp: Utc::now().to_rfc3339(),
                source: "pipeline_physio_event".to_string(),
                path: None,
                content_preview: format!(
                    "pipeline physio event: severity={} condition={}",
                    event.severity, event.condition
                ),
                metadata: serde_json::to_value(event).unwrap_or_default(),
                observation_type: Some(beagle_observer::ObservationType::Physiological),
                tags: Some(vec![
                    "pipeline".to_string(),
                    "physio_event".to_string(),
                    event.severity.clone(),
                ]),
            };
            obs.add_to_timeline(severity_obs).await;
        }

        (
            physio_str,
            hrv_level,
            Some(user_ctx),
            canonical_physio_snapshot,
            physio_event,
        )
    } else {
        // Fallback para versão antiga se Observer não estiver disponível
        (
            observer_physiological_insight(ctx).await?,
            None,
            None,
            None,
            None,
        )
    };
    info!(physio = %physio, ?hrv_level, "Contexto do usuário capturado (Observer 2.0)");

    // 2.5) Exocortex: Unified Cognitive Orchestration.
    // Default ON now that /api/exocortex/process ships real IIT Φ math;
    // every pipeline run logs a Φ measurement. Opt out with
    // EXOCORTEX_DISABLED=1 if the extra Φ cost is unwelcome for a run.
    let use_exocortex = std::env::var("EXOCORTEX_DISABLED")
        .map(|v| !(v == "true" || v == "1"))
        .unwrap_or(true);

    if use_exocortex {
        info!("🧠 Fase 2.5: Exocortex (orquestração cognitiva unificada)");

        // Create BeagleContext Arc for exocortex
        let exo_ctx_arc = Arc::new(beagle_core::BeagleContext {
            cfg: ctx.cfg.clone(),
            router: ctx.router.clone(),
            llm: ctx.llm.clone(),
            vector: ctx.vector.clone(),
            graph: ctx.graph.clone(),
            llm_stats: ctx.llm_stats.clone(),
            #[cfg(feature = "memory")]
            memory: ctx.memory.clone(),
        });

        // Configure exocortex based on current context
        let mut exo_config = ExocortexConfig::default();
        exo_config.features.enable_observer = observer.is_some();
        exo_config.features.enable_consciousness = true;
        exo_config.features.enable_proactive = false; // Disabled for pipeline mode

        match PersonalExocortex::with_context(exo_config, exo_ctx_arc).await {
            Ok(exocortex) => {
                // Update physiological context if available
                if let Some(ref user_ctx) = user_ctx {
                    let stress = user_ctx.physio.stress_index.unwrap_or(0.3);
                    let energy = 1.0 - stress; // Simple inverse for now
                    let focus = match user_ctx.physio.hrv_level.as_deref() {
                        Some("high") => 0.8,
                        Some("normal") => 0.5,
                        Some("low") => 0.3,
                        _ => 0.5,
                    };
                    exocortex
                        .update_physio_context(stress as f32, energy as f32, focus as f32)
                        .await;
                }

                // Build exocortex input with full context
                let exo_input = ExocortexInput {
                    query: format!(
                        "{}\n\n=== Darwin Context ===\n{}\n\n=== Physiological State ===\n{}",
                        question, context, physio
                    ),
                    intent: Some("scientific_synthesis".to_string()),
                    modality: InputModality::Text,
                    context: Some(context.clone()),
                    urgency: if hrv_level.as_deref() == Some("low") {
                        0.3
                    } else {
                        0.6
                    },
                };

                // Process through exocortex
                match exocortex.process(exo_input).await {
                    Ok(output) => {
                        info!(
                            confidence = output.confidence,
                            agents = ?output.agents_used,
                            phi = output.consciousness_state.phi,
                            processing_ms = output.metadata.processing_time_ms,
                            "Exocortex processing complete"
                        );

                        // Add exocortex insights to context for HERMES
                        context = format!(
                            "{}\n\n=== Exocortex Insights ===\n{}\n\nConsciousness Φ: {:.3}\nConfidence: {:.2}\nAgents: {}\n",
                            context,
                            output.response,
                            output.consciousness_state.phi,
                            output.confidence,
                            output.agents_used.join(", ")
                        );

                        // Add proactive suggestions if any
                        if !output.proactive_suggestions.is_empty() {
                            context.push_str("\n=== Proactive Insights ===\n");
                            for suggestion in &output.proactive_suggestions {
                                context.push_str(&format!(
                                    "- {} (relevance: {:.2})\n",
                                    suggestion.suggestion, suggestion.relevance
                                ));
                            }
                        }
                    }
                    Err(e) => {
                        warn!(
                            "Exocortex processing failed: {}, continuing with standard pipeline",
                            e
                        );
                    }
                }

                // Record session stats
                let stats = exocortex.session_stats().await;
                info!(
                    episodic_memories = stats.episodic_memories,
                    semantic_memories = stats.semantic_memories,
                    working_memory_usage = stats.working_memory_usage,
                    "Exocortex session stats"
                );
            }
            Err(e) => {
                warn!(
                    "Failed to initialize exocortex: {}, continuing with standard pipeline",
                    e
                );
            }
        }
    }

    // 3) HERMES: síntese de paper (com detecção de deadlock)
    info!("📝 Fase 3: HERMES (síntese)");
    let mut deadlock_state = DeadlockState::new(run_id.to_string());
    let mut draft = hermes_synthesize_paper(
        ctx,
        question,
        &context,
        &physio,
        run_id,
        hrv_level.as_deref(),
    )
    .await?;

    // Verifica deadlock e aplica Void se necessário
    if ctx.cfg.void_enabled() {
        if deadlock_state.add_output(&draft) {
            warn!("Deadlock detectado, aplicando Void...");
            match handle_deadlock(run_id, "Output repetido sem melhoria", question).await {
                Ok(void_insight) => {
                    // Adiciona insight do Void ao draft
                    draft = format!("{}\n\n--- VOID INSIGHT ---\n{}", draft, void_insight);
                    info!("Void aplicado com sucesso");
                }
                Err(e) => {
                    warn!("Falha ao aplicar Void: {}", e);
                }
            }
        }
    }

    info!(len = draft.len(), "Draft gerado");

    // 4) Escrita de artefatos
    info!("💾 Fase 4: Escrita de artefatos");

    // Verifica SAFE_MODE - nunca publica de fato, só gera PDF local
    if !ctx.cfg.safe_mode {
        warn!("⚠️  SAFE_MODE=false - pipeline não deve publicar de fato");
    }

    // Usa sempre ctx.cfg.storage.data_dir (nunca ~ literal)
    let data_root = PathBuf::from(&ctx.cfg.storage.data_dir);
    let drafts_dir = data_root.join("papers").join("drafts");
    std::fs::create_dir_all(&drafts_dir)?;

    let date = Utc::now().format("%Y%m%d").to_string();
    let base = format!("{}_{}", date, run_id);
    let draft_md = drafts_dir.join(format!("{}.md", base));
    let draft_pdf = drafts_dir.join(format!("{}.pdf", base));

    std::fs::write(&draft_md, &draft)?;
    info!("✅ Draft MD salvo: {}", draft_md.display());

    // PDF is best-effort in the cluster runtime. Missing pandoc/LaTeX should
    // not invalidate the canonical pipeline metadata/report path.
    match render_to_pdf(&draft, &draft_pdf).await {
        Ok(()) => {
            info!("✅ Draft PDF salvo: {}", draft_pdf.display());
        }
        Err(e) => {
            warn!(
                "PDF generation unavailable for run {}: {}; continuing with markdown/report artifacts only",
                run_id, e
            );
        }
    }

    // 5) Run report (inclui science_job_ids e UserContext se fornecidos)
    let run_report = create_run_report(
        ctx,
        run_id,
        question,
        &context,
        &physio,
        &draft,
        hrv_level.as_deref(),
        science_job_ids.clone(),
        serendipity_score,
        user_ctx.as_ref(),
        canonical_physio_snapshot.as_ref(),
        physio_event.as_ref(),
        &experiment_flags,
        experiment_id.as_deref(),
    )
    .await?;
    info!("✅ Run report salvo: {}", run_report.display());

    // 6) Log feedback event para Continuous Learning
    let data_dir = PathBuf::from(&ctx.cfg.storage.data_dir);
    let hrv_level_str = hrv_level.unwrap_or_else(|| extract_hrv_level(&physio).unwrap_or_default());
    // Obtém stats para determinar provider principal
    let llm_stats = ctx.llm_stats.get(run_id).unwrap_or_default();
    let main_provider = if llm_stats.grok4_calls > 0 {
        "grok4_heavy"
    } else {
        "grok3"
    };

    let mut event = create_pipeline_event(
        run_id.to_string(),
        question.to_string(),
        draft_md.clone(),
        draft_pdf.clone(),
        Some(hrv_level_str),
        Some(main_provider.to_string()),
    );

    // Adiciona stats LLM ao evento
    event.grok3_calls = Some(llm_stats.grok3_calls);
    event.grok4_heavy_calls = Some(llm_stats.grok4_calls);
    event.grok3_tokens_est = Some(llm_stats.grok3_tokens_in + llm_stats.grok3_tokens_out);
    event.grok4_tokens_est = Some(llm_stats.grok4_tokens_in + llm_stats.grok4_tokens_out);
    event.experiment_condition = Some(experiment_flags.condition_label().to_string());
    event.experiment_id = experiment_id;
    if let Err(e) = append_event(&data_dir, &event) {
        warn!("Falha ao logar feedback event: {}", e);
    } else {
        info!("📊 Feedback event logado para Continuous Learning");
    }

    info!("🎉 Pipeline BEAGLE v0.1 concluído!");

    Ok(PipelinePaths {
        draft_md,
        draft_pdf,
        run_report,
    })
}

/// Extrai nível de HRV do estado fisiológico (simplificado)
fn extract_hrv_level(physio: &str) -> Option<String> {
    let lower = physio.to_lowercase();
    if lower.contains("hrv normal") || lower.contains("normal") {
        Some("normal".to_string())
    } else if lower.contains("hrv low") || lower.contains("low") {
        Some("low".to_string())
    } else if lower.contains("hrv high") || lower.contains("high") {
        Some("high".to_string())
    } else {
        None
    }
}

/// Helper para chamada LLM com tracking de stats
async fn call_llm_with_stats(
    ctx: &BeagleContext,
    run_id: &str,
    prompt: &str,
    meta: RequestMeta,
) -> anyhow::Result<String> {
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
                // Outros tiers (CloudMath, LocalFallback) contam como Grok3 por enquanto
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
        }
    });

    Ok(output.text)
}

/// Darwin Enhanced Cycle (GraphRAG)
// darwin_enhanced_cycle() removida - agora usa beagle_darwin::DarwinCore::enhanced_cycle()

/// Observer: insight fisiológico
async fn observer_physiological_insight(ctx: &BeagleContext) -> anyhow::Result<String> {
    // Placeholder - em produção, chamaria observer real
    // Por enquanto, retorna insight mock
    Ok("Estado fisiológico: HRV normal, HR 72bpm, SpO2 98%".to_string())
}

/// HERMES: síntese de paper usando PaperSynthesisEngine real
///
/// Pipeline completo:
/// 1. Se HERMES_FULL_SYNTHESIS=true, usa PaperSynthesisEngine completo com:
///    - Literature search (PubMed, arXiv)
///    - Multi-provider synthesis
///    - Citation management
///    - Q1 journal standards
/// 2. Caso contrário, usa fallback LLM-based (mais rápido, menos completo)
async fn hermes_synthesize_paper(
    ctx: &BeagleContext,
    question: &str,
    context: &str,
    physio: &str,
    run_id: &str,
    hrv_level: Option<&str>,
) -> anyhow::Result<String> {
    // Check if full HERMES synthesis is enabled
    let use_full_hermes = std::env::var("HERMES_FULL_SYNTHESIS")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    if use_full_hermes {
        info!("📝 HERMES: Using full PaperSynthesisEngine");
        return hermes_full_synthesis(ctx, question, context, hrv_level).await;
    }

    // Fallback: LLM-based synthesis (faster, less comprehensive)
    info!("📝 HERMES: Using LLM-based synthesis (set HERMES_FULL_SYNTHESIS=true for full engine)");
    hermes_llm_synthesis(ctx, question, context, physio, run_id, hrv_level).await
}

/// Full HERMES synthesis using PaperSynthesisEngine
async fn hermes_full_synthesis(
    ctx: &BeagleContext,
    question: &str,
    context: &str,
    hrv_level: Option<&str>,
) -> anyhow::Result<String> {
    // Configure synthesis based on HRV state
    let mut config = PaperSynthesisConfig::default();

    // Adjust complexity based on cognitive state
    match hrv_level {
        Some("low") => {
            // Reduced complexity for low HRV (cognitive fatigue)
            config.max_length = 5000;
            config.multi_provider_synthesis = false;
            config.min_citations_per_section = 3;
        }
        Some("high") => {
            // Full complexity for high HRV (flow state)
            config.max_length = 10000;
            config.multi_provider_synthesis = true;
            config.min_citations_per_section = 7;
            config.enforce_q1_standards = true;
        }
        _ => {
            // Default settings
        }
    }

    // Create knowledge graph wrapper for HERMES
    // Note: In production, this would connect to the real Neo4j instance
    let kg = Arc::new(
        beagle_hermes::knowledge::KnowledgeGraph::new(
            &ctx.cfg
                .graph
                .neo4j_uri
                .clone()
                .unwrap_or_else(|| "neo4j://localhost:7687".to_string()),
            &ctx.cfg
                .graph
                .neo4j_user
                .clone()
                .unwrap_or_else(|| "neo4j".to_string()),
            &ctx.cfg
                .graph
                .neo4j_password
                .clone()
                .unwrap_or_else(|| "password".to_string()),
        )
        .await?,
    );

    // Create synthesis engine with BeagleContext
    let ctx_arc = Arc::new(beagle_core::BeagleContext {
        cfg: ctx.cfg.clone(),
        router: ctx.router.clone(),
        llm: ctx.llm.clone(),
        vector: ctx.vector.clone(),
        graph: ctx.graph.clone(),
        llm_stats: ctx.llm_stats.clone(),
        #[cfg(feature = "memory")]
        memory: ctx.memory.clone(),
    });

    let engine = PaperSynthesisEngine::new(config, ctx_arc, kg);

    // Extract insights from Darwin context
    let insights: Vec<String> = context
        .split("\n\n")
        .filter(|s| s.len() > 50)
        .map(|s| s.to_string())
        .collect();

    // Synthesize paper
    let manuscript = engine.synthesize_paper(question, insights).await?;

    // Convert manuscript to Markdown
    let mut markdown = String::new();

    // Title
    markdown.push_str(&format!("# {}\n\n", manuscript.title));

    // Authors and affiliations
    if !manuscript.authors.is_empty() {
        markdown.push_str(&format!(
            "**Authors:** {}\n\n",
            manuscript.authors.join(", ")
        ));
    }
    if !manuscript.affiliations.is_empty() {
        markdown.push_str(&format!(
            "**Affiliations:** {}\n\n",
            manuscript.affiliations.join("; ")
        ));
    }

    // Keywords
    if !manuscript.keywords.is_empty() {
        markdown.push_str(&format!(
            "**Keywords:** {}\n\n",
            manuscript.keywords.join(", ")
        ));
    }

    // Abstract
    markdown.push_str("## Abstract\n\n");
    markdown.push_str(&manuscript.abstract_text);
    markdown.push_str("\n\n");

    // Sections
    for section in &manuscript.sections {
        markdown.push_str(&format!(
            "## {}\n\n",
            capitalize_section(section.section_type.as_str())
        ));
        markdown.push_str(&section.content);
        markdown.push_str("\n\n");
    }

    // Bibliography
    if !manuscript.bibliography.is_empty() {
        markdown.push_str("## References\n\n");
        markdown.push_str(&manuscript.bibliography);
        markdown.push_str("\n\n");
    }

    // Synthesis metadata
    markdown.push_str("---\n\n");
    markdown.push_str(&format!(
        "*Generated by HERMES PaperSynthesisEngine | {} words | {} citations | {:.1}s synthesis time | Quality: coherence={:.2}, novelty={:.2}*\n",
        manuscript.total_word_count,
        manuscript.citations.len(),
        manuscript.synthesis_metadata.synthesis_duration_sec as f64,
        manuscript.synthesis_metadata.quality_metrics.coherence_score,
        manuscript.synthesis_metadata.quality_metrics.novelty_score,
    ));

    info!(
        "✅ HERMES full synthesis complete: {} words, {} citations",
        manuscript.total_word_count,
        manuscript.citations.len()
    );

    Ok(markdown)
}

/// Capitalize section name
fn capitalize_section(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().chain(chars).collect(),
    }
}

/// LLM-based HERMES synthesis (fallback, faster)
async fn hermes_llm_synthesis(
    ctx: &BeagleContext,
    question: &str,
    context: &str,
    physio: &str,
    run_id: &str,
    hrv_level: Option<&str>,
) -> anyhow::Result<String> {
    let mut prompt = format!(
        "Tu és o HERMES, sistema de síntese de papers científicos do BEAGLE.\n\n\
        Pergunta/Tópico: {}\n\n\
        Contexto Darwin (GraphRAG):\n{}\n\n\
        Estado Fisiológico:\n{}\n\n",
        question, context, physio
    );

    // Ajusta tom baseado em HRV se disponível
    if let Some(level) = hrv_level {
        match level {
            "low" => {
                prompt.push_str("⚠️ NOTA: O estado fisiológico atual indica HRV baixo. Ajuste o tom para ser mais calmo e contemplativo, evitando sobrecarga cognitiva.\n\n");
            }
            "high" => {
                prompt.push_str("✨ NOTA: O estado fisiológico atual indica HRV alto (flow). Você pode ser mais criativo e explorar conexões mais profundas.\n\n");
            }
            _ => {}
        }
    }

    prompt.push_str(
        "Gera um draft de paper científico completo em Markdown com:\n\
        1. Título\n\
        2. Abstract\n\
        3. Introdução\n\
        4. Metodologia\n\
        5. Resultados\n\
        6. Discussão\n\
        7. Conclusões\n\
        8. Referências\n\n\
        Use formatação Markdown apropriada.",
    );

    let meta = RequestMeta {
        offline_required: false,
        requires_math: false,
        requires_vision: false,
        approximate_tokens: prompt.len() / 4,
        requires_high_quality: true,
        high_bias_risk: false,
        requires_phd_level_reasoning: true, // Síntese de paper requer raciocínio de alto nível
        critical_section: false,
    };

    call_llm_with_stats(ctx, run_id, &prompt, meta).await
}

/// Renderiza Markdown para PDF usando LaTeX + Pandoc
async fn render_to_pdf(markdown: &str, pdf_path: &PathBuf) -> anyhow::Result<()> {
    use beagle_latex::{CitationStyle, LatexEngine, PdfConfig, PdfGenerator, PdfMetadata};

    tracing::info!("Generating PDF with comprehensive LaTeX system");

    // Create temporary markdown file
    let temp_dir = tempfile::tempdir()?;
    let markdown_path = temp_dir.path().join("draft.md");
    std::fs::write(&markdown_path, markdown)?;

    // Extract metadata from markdown (simple extraction)
    let (title, abstract_text) = extract_metadata_from_markdown(markdown);

    // Configure PDF generation
    let config = PdfConfig {
        engine: LatexEngine::XeLaTeX,
        template: std::env::var("BEAGLE_PDF_TEMPLATE")
            .unwrap_or_else(|_| "beagle-scientific".to_string()),
        citation_style: CitationStyle::Nature,
        include_bibliography: false, // No bibliography for now
        custom_preamble: None,
        metadata: PdfMetadata {
            title: title.unwrap_or_else(|| "BEAGLE Generated Paper".to_string()),
            authors: vec![],
            abstract_text,
            keywords: vec!["BEAGLE".to_string(), "AI-generated".to_string()],
            date: Some(chrono::Local::now().date_naive()),
            institution: Some("BEAGLE AI System".to_string()),
            email: None,
        },
        compilation_passes: 2,
        shell_escape: false,
        pandoc_options: vec![],
    };

    // Generate PDF
    let generator = PdfGenerator::new(config)?;
    let result = generator
        .generate_pdf(&markdown_path, pdf_path, None)
        .await?;

    tracing::info!(
        "PDF generated successfully: {} bytes in {:.2}s using {} template",
        result.file_size_bytes,
        result.generation_time_secs,
        result.template_used
    );

    Ok(())
}

/// Extract basic metadata from markdown content
fn extract_metadata_from_markdown(markdown: &str) -> (Option<String>, Option<String>) {
    let lines: Vec<&str> = markdown.lines().collect();

    let mut title = None;
    let mut abstract_text = None;

    // Look for first # heading as title
    for line in &lines {
        if line.starts_with("# ") {
            title = Some(line.trim_start_matches("# ").to_string());
            break;
        }
    }

    // Look for abstract section
    let markdown_lower = markdown.to_lowercase();
    if let Some(abstract_start) = markdown_lower.find("## abstract") {
        if let Some(next_section) = markdown_lower[abstract_start + 11..].find("##") {
            let abstract_end = abstract_start + 11 + next_section;
            abstract_text = Some(
                markdown[abstract_start + 11..abstract_end]
                    .trim()
                    .to_string(),
            );
        }
    }

    (title, abstract_text)
}

/// Cria run report JSON
async fn create_run_report(
    ctx: &BeagleContext,
    run_id: &str,
    question: &str,
    context: &str,
    physio: &str,
    draft: &str,
    hrv_level: Option<&str>,
    science_job_ids: Option<Vec<String>>,
    serendipity_score: Option<f64>,
    user_ctx: Option<&beagle_observer::UserContext>,
    canonical_physio_snapshot: Option<&beagle_observer::PhysioSnapshot>,
    physio_event: Option<&PipelinePhysioSeverityEvent>,
    experiment_flags: &ExperimentFlags,
    experiment_id: Option<&str>,
) -> anyhow::Result<PathBuf> {
    // Obtém stats LLM do run
    let llm_stats = ctx.llm_stats.get(run_id).unwrap_or_default();

    let mut report = serde_json::json!({
        "run_id": run_id,
        "timestamp": Utc::now().to_rfc3339(),
        "question": question,
        "context_chunks": context.len(),
        "physiological_state": physio,
        "draft_length": draft.len(),
        "profile": ctx.cfg.profile,
        "safe_mode": ctx.cfg.safe_mode,
        "experiment_flags": experiment_flags,
        "pipeline_physio": build_pipeline_physio_metadata(
            canonical_physio_snapshot,
            experiment_flags,
        ),
        "llm_stats": {
            "grok3_calls": llm_stats.grok3_calls,
            "grok3_tokens_in": llm_stats.grok3_tokens_in,
            "grok3_tokens_out": llm_stats.grok3_tokens_out,
            "grok4_calls": llm_stats.grok4_calls,
            "grok4_tokens_in": llm_stats.grok4_tokens_in,
            "grok4_tokens_out": llm_stats.grok4_tokens_out,
            "total_calls": llm_stats.total_calls(),
            "total_tokens": llm_stats.total_tokens(),
        },
    });

    // Adiciona hrv_level se disponível
    if let Some(level) = hrv_level {
        report["hrv_level"] = serde_json::Value::String(level.to_string());
    }

    if let Some(score) = serendipity_score {
        report["serendipity_score"] = serde_json::json!(score);
    }

    report["experiment"] = serde_json::json!({
        "experiment_id": experiment_id,
        "condition": experiment_flags.condition_label(),
    });

    if let Some(event) = physio_event {
        report["physio_event"] = serde_json::to_value(event)?;
    }

    // Adiciona severidades do UserContext (Observer 2.0)
    if let Some(ctx) = user_ctx {
        report["observer"] = serde_json::json!({
            "physio_severity": ctx.physio.severity.as_str(),
            "env_severity": ctx.env.severity.as_str(),
            "space_severity": ctx.space.severity.as_str(),
            "hrv_level": ctx.physio.hrv_level,
            "heart_rate_bpm": ctx.physio.heart_rate_bpm,
            "spo2_percent": ctx.physio.spo2_percent,
            "stress_index": ctx.physio.stress_index,
            "heliobio_risk_level": ctx.space.heliobio_risk_level,
            "kp_index": ctx.space.kp_index,
            "env_summary": ctx.env.summary,
            "latest_snapshot": canonical_physio_snapshot,
        });
    }

    // Adiciona science_job_ids se disponível
    if let Some(job_ids) = science_job_ids {
        report["science_jobs"] = serde_json::json!({
            "job_ids": job_ids,
            "count": job_ids.len()
        });
    }

    let data_root = PathBuf::from(&ctx.cfg.storage.data_dir);
    let report_dir = data_root.join("logs").join("beagle-pipeline");
    std::fs::create_dir_all(&report_dir)?;

    let date = Utc::now().format("%Y%m%d").to_string();
    let report_path = report_dir.join(format!("{}_{}.json", date, run_id));
    std::fs::write(&report_path, serde_json::to_string_pretty(&report)?)?;

    Ok(report_path)
}

fn build_pipeline_physio_metadata(
    snapshot: Option<&beagle_observer::PhysioSnapshot>,
    experiment_flags: &ExperimentFlags,
) -> PipelinePhysioMetadata {
    PipelinePhysioMetadata {
        snapshot_available: snapshot.is_some(),
        used_in_pipeline: experiment_flags.hrv_aware && experiment_flags.observer_enabled,
        snapshot: snapshot.cloned(),
        hrv_level: snapshot.and_then(|s| s.hrv_level.clone()),
        physio_source: snapshot.map(|s| s.source.clone()),
        physio_timestamp: snapshot.map(|s| s.timestamp.to_rfc3339()),
        hr: snapshot.and_then(|s| s.hr),
        spo2: snapshot.and_then(|s| s.spo2),
    }
}

fn build_pipeline_physio_event(
    run_id: &str,
    experiment_flags: &ExperimentFlags,
    thresholds: &PhysioThresholds,
    snapshot: Option<&beagle_observer::PhysioSnapshot>,
) -> Option<PipelinePhysioSeverityEvent> {
    let snapshot = snapshot?;
    let mut triggers = Vec::new();

    if let Some(hrv_ms) = snapshot.hrv_ms {
        if hrv_ms <= thresholds.hrv_low_ms as f64 {
            triggers.push(format!("hrv_ms<={:.1}", thresholds.hrv_low_ms));
        }
    }
    if let Some(hr) = snapshot.hr {
        if hr >= thresholds.hr_tachy_bpm as f64 {
            triggers.push(format!("hr>={:.1}", thresholds.hr_tachy_bpm));
        }
        if hr <= thresholds.hr_brady_bpm as f64 {
            triggers.push(format!("hr<={:.1}", thresholds.hr_brady_bpm));
        }
    }
    if let Some(spo2) = snapshot.spo2 {
        if spo2 <= thresholds.spo2_warning as f64 {
            triggers.push(format!("spo2<={:.1}", thresholds.spo2_warning));
        }
    }

    Some(PipelinePhysioSeverityEvent {
        event_id: format!("{}-physio", run_id),
        kind: "physio_severity_event".to_string(),
        recording_mode: "bounded".to_string(),
        condition: experiment_flags.condition_label().to_string(),
        used_in_pipeline: experiment_flags.hrv_aware && experiment_flags.observer_enabled,
        severity: snapshot
            .severity
            .clone()
            .unwrap_or_else(|| "unknown".to_string()),
        triggers,
        source: Some(snapshot.source.clone()),
        timestamp: Some(snapshot.timestamp.to_rfc3339()),
    })
}

#[cfg(test)]
mod tests {
    use super::{
        build_pipeline_physio_event, build_pipeline_physio_metadata, ExperimentFlags,
    };
    use beagle_config::PhysioThresholds;
    use chrono::Utc;

    fn sample_snapshot() -> beagle_observer::PhysioSnapshot {
        beagle_observer::PhysioSnapshot {
            source: "observer-smoke".to_string(),
            session_id: Some("ws-1".to_string()),
            timestamp: Utc::now(),
            hr: Some(118.0),
            hrv_ms: Some(22.0),
            hrv_level: Some("low".to_string()),
            spo2: Some(93.0),
            stress_index: Some(0.84),
            severity: Some("high".to_string()),
        }
    }

    #[test]
    fn pipeline_physio_metadata_preserves_snapshot_and_usage() {
        let flags = ExperimentFlags::new(true, false, true, false);
        let snapshot = sample_snapshot();
        let metadata = build_pipeline_physio_metadata(Some(&snapshot), &flags);

        assert!(metadata.snapshot_available);
        assert!(metadata.used_in_pipeline);
        assert_eq!(metadata.hrv_level.as_deref(), Some("low"));
        assert_eq!(metadata.physio_source.as_deref(), Some("observer-smoke"));
        assert_eq!(metadata.hr, Some(118.0));
        assert_eq!(metadata.spo2, Some(93.0));
    }

    #[test]
    fn pipeline_physio_event_is_bounded_and_triggered() {
        let flags = ExperimentFlags::new(true, false, true, false);
        let snapshot = sample_snapshot();
        let event = build_pipeline_physio_event(
            "run-123",
            &flags,
            &PhysioThresholds::default(),
            Some(&snapshot),
        )
        .expect("event");

        assert_eq!(event.recording_mode, "bounded");
        assert_eq!(event.condition, "hrv_aware");
        assert_eq!(event.severity, "high");
        assert!(event.triggers.iter().any(|t| t.contains("hrv_ms<=")));
        assert!(event.triggers.iter().any(|t| t.contains("spo2<=")));
    }
}
