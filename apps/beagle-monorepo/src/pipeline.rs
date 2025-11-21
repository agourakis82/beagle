//! Pipeline BEAGLE v0.1 - pergunta → draft.md + draft.pdf + run_report.json
//!
//! Fluxo completo:
//! 1. Darwin: contexto semântico (GraphRAG)
//! 2. Observer: estado fisiológico (HealthKit/HRV)
//! 3. HERMES: síntese de paper
//! 4. Escrita de artefatos (MD, PDF, JSON)

use beagle_core::BeagleContext;
use beagle_llm::stats::LlmCallsStats;
use beagle_config::{classify_hrv, load as load_config};
use beagle_feedback::{append_event, create_pipeline_event};
use beagle_llm::{RequestMeta, ProviderTier};
use beagle_observer::UniversalObserver;
use beagle_serendipity::SerendipityInjector;
use beagle_quantum::{HypothesisSet, SuperpositionAgent};
use crate::pipeline_void::{DeadlockState, handle_deadlock};
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

/// Executa pipeline completo BEAGLE v0.1
#[instrument(skip(ctx, observer), fields(run_id = %run_id))]
pub async fn run_beagle_pipeline(
    ctx: &mut BeagleContext,
    question: &str,
    run_id: &str,
    observer: Option<Arc<UniversalObserver>>,
    science_job_ids: Option<Vec<String>>,
) -> anyhow::Result<PipelinePaths> {
    info!("🚀 Pipeline BEAGLE v0.1 iniciado: {}", question);

    // 0) Memory RAG injection (opcional)
    let mut memory_context = String::new();
    #[cfg(feature = "memory")]
    {
        if std::env::var("BEAGLE_MEMORY_RETRIEVAL")
            .unwrap_or_else(|_| "false".to_string())
            .parse::<bool>()
            .unwrap_or(false)
        {
            info!("🧠 Fase 0: Memory RAG injection");
            if let Ok(mem_result) = ctx.memory_query(beagle_memory::MemoryQuery {
                query: question.to_string(),
                scope: Some("scientific".to_string()),
                max_items: Some(3),
            }).await {
                memory_context = format!(
                    "\n\n=== Contexto Prévio Relevante ===\n{}\n\n",
                    mem_result.summary
                );
                if !mem_result.highlights.is_empty() {
                    memory_context.push_str("=== Destaques ===\n");
                    for (i, h) in mem_result.highlights.iter().take(3).enumerate() {
                        memory_context.push_str(&format!("{}. [{}] {}\n", i + 1, h.source, h.snippet));
                    }
                    memory_context.push_str("\n");
                }
                info!("Memory RAG: {} highlights encontrados", mem_result.highlights.len());
            }
        }
    }

    // 1) Darwin: contexto semântico (GraphRAG)
    info!("📊 Fase 1: Darwin GraphRAG");
    let mut context = darwin_enhanced_cycle(ctx, question, run_id).await?;
    info!(chunks = context.len(), "Contexto Darwin gerado");
    
    // Prepend memory context if available
    if !memory_context.is_empty() {
        context = format!("{}{}", memory_context, context);
    }
    
    // 1.5) Serendipity: descoberta de conexões interdisciplinares (opcional)
    let mut serendipity_score: Option<f64> = None;
    let mut serendipity_accidents: Vec<String> = Vec::new();
    
    if ctx.cfg.profile() == beagle_config::Profile::Lab || ctx.cfg.profile() == beagle_config::Profile::Prod {
        if std::env::var("BEAGLE_SERENDIPITY_ENABLE")
            .unwrap_or_else(|_| "false".to_string())
            .parse::<bool>()
            .unwrap_or(false)
        {
            info!("🔮 Fase 1.5: Serendipity (descoberta de conexões)");
            
            // Cria HypothesisSet a partir do contexto atual
            let mut hyp_set = HypothesisSet::new();
            // Extrai hipóteses implícitas do contexto (simplificado)
            let context_chunks: Vec<&str> = context.split("\n\n").collect();
            for (i, chunk) in context_chunks.iter().take(5).enumerate() {
                if chunk.len() > 50 {
                    hyp_set.add(format!("Hipótese {}: {}", i + 1, chunk.chars().take(200).collect::<String>()), None);
                }
            }
            
            // Se não houver hipóteses suficientes, cria uma baseada na pergunta
            if hyp_set.hypotheses.is_empty() {
                hyp_set.add(format!("Hipótese principal: {}", question), None);
            }
            
            // Inicializa SerendipityInjector
            let injector = if let Some(ref vllm_url) = ctx.cfg.llm.vllm_url {
                SerendipityInjector::with_vllm_url(vllm_url.clone())
            } else {
                SerendipityInjector::new()
            };
            
            // Injeta acidentes férteis
            match injector.inject_fertile_accident(&hyp_set, &format!("{} {}", question, context)).await {
                Ok(accidents) => {
                    if !accidents.is_empty() {
                        serendipity_accidents = accidents.clone();
                        serendipity_score = Some(accidents.len() as f64 * 0.2); // Score baseado em quantidade
                        
                        // Integra acidentes no contexto
                        let serendipity_text = format!(
                            "\n\n=== Conexões Serendipitosas (Interdisciplinares) ===\n{}\n\n",
                            accidents.join("\n\n")
                        );
                        context.push_str(&serendipity_text);
                        
                        info!("✅ Serendipity: {} acidentes férteis injetados (score: {:.2})", 
                              accidents.len(), serendipity_score.unwrap_or(0.0));
                    } else {
                        info!("Serendipity: nenhum acidente fértil gerado");
                    }
                }
                Err(e) => {
                    warn!("Falha ao injetar Serendipity: {}", e);
                }
            }
        }
    }

    // 2) Observer: estado fisiológico (HealthKit / HRV)
    info!("🏥 Fase 2: Observer (estado fisiológico)");
    let (physio, hrv_level) = if let Some(ref obs) = observer {
        let physio_state = obs.current_physio_state().await;
        let physio_str = if let Some(hrv) = physio_state.hrv_ms {
            let level = physio_state.hrv_level.clone()
                .unwrap_or_else(|| classify_hrv(hrv, None));
            format!(
                "Estado fisiológico: HRV {:.1}ms ({}), HR {:.0}bpm",
                hrv,
                level,
                physio_state.heart_rate_bpm.unwrap_or(0.0)
            )
        } else {
            "Estado fisiológico: HRV não disponível".to_string()
        };
        let hrv_level = physio_state.hrv_level;
        
        // Adiciona observação fisiológica à timeline do run_id
        let physio_obs = beagle_observer::Observation {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: Utc::now().to_rfc3339(),
            source: "pipeline_physio".to_string(),
            path: None,
            content_preview: physio_str.clone(),
            metadata: serde_json::json!({
                "hrv_ms": physio_state.hrv_ms,
                "hrv_level": hrv_level,
                "heart_rate_bpm": physio_state.heart_rate_bpm,
            }),
        };
        obs.add_to_timeline(run_id, physio_obs).await;
        
        (physio_str, hrv_level)
    } else {
        (observer_physiological_insight(ctx).await?, None)
    };
    info!(physio = %physio, ?hrv_level, "Estado fisiológico capturado");

    // 3) HERMES: síntese de paper (com detecção de deadlock)
    info!("📝 Fase 3: HERMES (síntese)");
    let mut deadlock_state = DeadlockState::new(run_id.to_string());
    let mut draft = hermes_synthesize_paper(ctx, question, &context, &physio, run_id, hrv_level.as_deref()).await?;
    
    // Verifica deadlock e aplica Void se necessário
    if ctx.cfg.profile() == beagle_config::Profile::Lab || ctx.cfg.profile() == beagle_config::Profile::Prod {
        if std::env::var("BEAGLE_VOID_ENABLE")
            .unwrap_or_else(|_| "false".to_string())
            .parse::<bool>()
            .unwrap_or(false)
        {
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

    // PDF (placeholder - implementar renderização real)
    render_to_pdf(&draft, &draft_pdf).await?;
    info!("✅ Draft PDF salvo: {}", draft_pdf.display());

    // 5) Run report (inclui science_job_ids se fornecidos)
    let run_report = create_run_report(
        ctx, run_id, question, &context, &physio, &draft, 
        hrv_level.as_deref(), science_job_ids.clone(), serendipity_score
    ).await?;
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
async fn darwin_enhanced_cycle(
    ctx: &BeagleContext,
    question: &str,
    run_id: &str,
) -> anyhow::Result<String> {
    // Usa router para obter contexto via Grok 3
    let prompt = format!(
        "Tu és o Darwin RAG++ dentro do BEAGLE.\n\
        Pergunta do usuário: {}\n\
        Usa o knowledge graph inteiro (neo4j) + vector store (qdrant) + entity extraction.\n\
        Responde com raciocínio estruturado + citações reais do graph.\n\
        Se não souber, diz 'preciso de mais dados'.",
        question
    );

    let meta = RequestMeta {
        offline_required: false,
        requires_math: false,
        requires_vision: false,
        approximate_tokens: prompt.len() / 4,
        requires_high_quality: true,
        high_bias_risk: false,
        requires_phd_level_reasoning: false,
        critical_section: false,
    };

    call_llm_with_stats(ctx, run_id, &prompt, meta).await
}

/// Observer: insight fisiológico
async fn observer_physiological_insight(ctx: &BeagleContext) -> anyhow::Result<String> {
    // Placeholder - em produção, chamaria observer real
    // Por enquanto, retorna insight mock
    Ok("Estado fisiológico: HRV normal, HR 72bpm, SpO2 98%".to_string())
}

/// HERMES: síntese de paper
async fn hermes_synthesize_paper(
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
        Use formatação Markdown apropriada."
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

/// Renderiza Markdown para PDF
async fn render_to_pdf(markdown: &str, pdf_path: &PathBuf) -> anyhow::Result<()> {
    // Placeholder - em produção, usar pandoc ou biblioteca Rust
    // Por enquanto, apenas copia markdown como placeholder
    std::fs::write(pdf_path, format!("PDF placeholder\n\n{}", markdown))?;
    Ok(())
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

