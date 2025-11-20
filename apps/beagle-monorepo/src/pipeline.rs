//! Pipeline BEAGLE v0.1 - pergunta → draft.md + draft.pdf + run_report.json
//!
//! Fluxo completo:
//! 1. Darwin: contexto semântico (GraphRAG)
//! 2. Observer: estado fisiológico (HealthKit/HRV)
//! 3. HERMES: síntese de paper
//! 4. Escrita de artefatos (MD, PDF, JSON)

use beagle_core::BeagleContext;
use beagle_config::load as load_config;
use chrono::Utc;
use std::path::PathBuf;
use tracing::{info, instrument, warn};

/// Caminhos dos artefatos gerados pelo pipeline
#[derive(Debug, Clone)]
pub struct PipelinePaths {
    pub draft_md: PathBuf,
    pub draft_pdf: PathBuf,
    pub run_report: PathBuf,
}

/// Executa pipeline completo BEAGLE v0.1
#[instrument(skip(ctx), fields(run_id = %run_id))]
pub async fn run_beagle_pipeline(
    ctx: &mut BeagleContext,
    question: &str,
    run_id: &str,
) -> anyhow::Result<PipelinePaths> {
    info!("🚀 Pipeline BEAGLE v0.1 iniciado: {}", question);

    // 1) Darwin: contexto semântico (GraphRAG)
    info!("📊 Fase 1: Darwin GraphRAG");
    let context = darwin_enhanced_cycle(ctx, question).await?;
    info!(chunks = context.len(), "Contexto Darwin gerado");

    // 2) Observer: estado fisiológico (HealthKit / HRV)
    info!("🏥 Fase 2: Observer (estado fisiológico)");
    let physio = observer_physiological_insight(ctx).await?;
    info!(?physio, "Estado fisiológico capturado");

    // 3) HERMES: síntese de paper
    info!("📝 Fase 3: HERMES (síntese)");
    let draft = hermes_synthesize_paper(ctx, question, &context, &physio).await?;
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

    // 5) Run report
    let run_report = create_run_report(ctx, run_id, question, &context, &physio, &draft).await?;
    info!("✅ Run report salvo: {}", run_report.display());

    info!("🎉 Pipeline BEAGLE v0.1 concluído!");

    Ok(PipelinePaths {
        draft_md,
        draft_pdf,
        run_report,
    })
}

/// Darwin Enhanced Cycle (GraphRAG)
async fn darwin_enhanced_cycle(ctx: &BeagleContext, question: &str) -> anyhow::Result<String> {
    // Usa router para obter contexto via Grok 3
    let prompt = format!(
        "Tu és o Darwin RAG++ dentro do BEAGLE.\n\
        Pergunta do usuário: {}\n\
        Usa o knowledge graph inteiro (neo4j) + vector store (qdrant) + entity extraction.\n\
        Responde com raciocínio estruturado + citações reais do graph.\n\
        Se não souber, diz 'preciso de mais dados'.",
        question
    );

    ctx.router.complete(&prompt).await
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
) -> anyhow::Result<String> {
    let prompt = format!(
        "Tu és o HERMES, sistema de síntese de papers científicos do BEAGLE.\n\n\
        Pergunta/Tópico: {}\n\n\
        Contexto Darwin (GraphRAG):\n{}\n\n\
        Estado Fisiológico:\n{}\n\n\
        Gera um draft de paper científico completo em Markdown com:\n\
        1. Título\n\
        2. Abstract\n\
        3. Introdução\n\
        4. Metodologia\n\
        5. Resultados\n\
        6. Discussão\n\
        7. Conclusões\n\
        8. Referências\n\n\
        Use formatação Markdown apropriada.",
        question, context, physio
    );

    ctx.router.complete(&prompt).await
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
) -> anyhow::Result<PathBuf> {
    let report = serde_json::json!({
        "run_id": run_id,
        "timestamp": Utc::now().to_rfc3339(),
        "question": question,
        "context_chunks": context.len(),
        "physiological_state": physio,
        "draft_length": draft.len(),
        "profile": ctx.cfg.profile,
        "safe_mode": ctx.cfg.safe_mode,
    });

    let data_root = PathBuf::from(&ctx.cfg.storage.data_dir);
    let report_dir = data_root.join("logs").join("beagle-pipeline");
    std::fs::create_dir_all(&report_dir)?;

    let date = Utc::now().format("%Y%m%d").to_string();
    let report_path = report_dir.join(format!("{}_{}.json", date, run_id));
    std::fs::write(&report_path, serde_json::to_string_pretty(&report)?)?;

    Ok(report_path)
}

