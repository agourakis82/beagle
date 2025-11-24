//! Binário CLI para pipeline BEAGLE v0.1
//!
//! Uso:
//!   cargo run --bin pipeline --package beagle-monorepo -- [OPTIONS] "Pergunta científica..."
//!
//! Opções:
//!   --with-triad    Executa Triad review automaticamente após o pipeline

use beagle_config::load as load_config;
use beagle_core::BeagleContext;
use beagle_feedback::{append_event, create_triad_event};
use beagle_monorepo::pipeline::run_beagle_pipeline;
use beagle_triad::{run_triad, TriadInput};
use std::path::PathBuf;
use tracing::{info, warn};
use uuid::Uuid;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    // Parse arguments
    let args: Vec<String> = std::env::args().collect();

    let mut with_triad = false;
    let mut question = None;

    for arg in args.iter().skip(1) {
        if arg == "--with-triad" {
            with_triad = true;
        } else if !arg.starts_with("--") {
            question = Some(arg.clone());
        }
    }

    let question =
        question.ok_or_else(|| anyhow::anyhow!("Forneça a pergunta/tópico como argumento"))?;

    let run_id = Uuid::new_v4().to_string();
    info!("Run ID: {}", run_id);
    info!("With Triad: {}", with_triad);

    let cfg = load_config();
    let mut ctx = BeagleContext::new(cfg).await?;

    // Run pipeline
    let paths = run_beagle_pipeline(&mut ctx, &question, &run_id, None, None, None).await?;

    println!("\n=== BEAGLE PIPELINE v0.1 CONCLUÍDO ===");
    println!("Run ID:     {}", run_id);
    println!("Draft MD:   {}", paths.draft_md.display());
    println!("Draft PDF:  {}", paths.draft_pdf.display());
    println!("RunReport:  {}", paths.run_report.display());
    println!("\n✅ Pipeline executado com sucesso!");

    // Run Triad if requested
    if with_triad {
        println!("\n=== INICIANDO TRIAD REVIEW ===");
        info!("Executando Triad review para run_id: {}", run_id);

        let triad_input = TriadInput {
            run_id: run_id.clone(),
            draft_path: paths.draft_md.clone(),
            context_summary: None,
        };

        match run_triad(&triad_input, &ctx).await {
            Ok(triad_report) => {
                // Save Triad artifacts
                let data_dir = PathBuf::from(&ctx.cfg.storage.data_dir);
                let triad_dir = data_dir.join("triad").join(&run_id);
                std::fs::create_dir_all(&triad_dir)?;

                let final_draft_path = triad_dir.join("final_draft.md");
                std::fs::write(&final_draft_path, &triad_report.final_draft)?;

                let report_path = triad_dir.join("triad_report.json");
                std::fs::write(&report_path, serde_json::to_string_pretty(&triad_report)?)?;

                println!("\n=== TRIAD REVIEW CONCLUÍDO ===");
                println!("Final Draft: {}", final_draft_path.display());
                println!("Triad Report: {}", report_path.display());

                // Log Triad event to feedback
                let triad_event = create_triad_event(
                    run_id.clone(),
                    Some(question.clone()),
                    final_draft_path,
                    report_path,
                    None, // hrv_level
                );

                if let Err(e) = append_event(&data_dir, &triad_event) {
                    warn!("Falha ao logar Triad feedback event: {}", e);
                } else {
                    info!("📊 Triad feedback event logado");
                }

                println!("\n✅ Triad executado com sucesso!");
            }
            Err(e) => {
                eprintln!("\n❌ Erro ao executar Triad: {}", e);
                eprintln!("Pipeline foi concluído, mas Triad falhou.");
                eprintln!("Você pode executar Triad manualmente com:");
                eprintln!("  cargo run --bin triad_review --package beagle-triad -- \\");
                eprintln!("    --run-id {} \\", run_id);
                eprintln!("    --draft {}", paths.draft_md.display());
            }
        }
    }

    Ok(())
}
