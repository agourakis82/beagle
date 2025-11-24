//! BEAGLE MONOREPO — Orquestrador CLI
//! Subcomandos:
//! - doctor   : healthcheck rápido (storage/env/serviços básicos)
//! - pipeline : pipeline v0.1 (pergunta → draft.md → summary.json)
//! - ide      : orientação para abrir a IDE Tauri

use anyhow::{Context, Result};
use beagle_config::{beagle_data_dir, bootstrap, ensure_dirs, load as load_config};
use beagle_health::check_all;
// init_tracing removido - usar função local
use beagle_observability::{init_observability, shutdown_observability};
use chrono::Utc;
use clap::{Parser, Subcommand};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use tracing::{info, instrument};
use uuid::Uuid;

#[derive(Parser)]
#[command(name = "beagle-monorepo", version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Healthcheck do BEAGLE (storage/env/serviços)
    Doctor,
    /// Pipeline v0.1: pergunta → draft.md + summary.json
    Pipeline {
        /// Pergunta de pesquisa ou tema
        question: String,
    },
    /// Instruções para abrir IDE Tauri
    Ide,
}

#[derive(Debug, Serialize)]
struct StepStatus {
    name: String,
    status: String,
    notes: Option<String>,
}

#[derive(Debug, Serialize)]
struct RunSummary {
    run_id: String,
    profile: String,
    safe_mode: bool,
    question: String,
    timestamp_utc: String,
    draft_path: Option<String>,
    pdf_path: Option<String>,
    steps: Vec<StepStatus>,
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();

    let cli = Cli::parse();
    let result = match cli.command {
        Commands::Doctor => run_doctor().await,
        Commands::Pipeline { question } => run_pipeline(question).await,
        Commands::Ide => {
            show_ide_instructions();
            Ok(())
        }
    };

    // Shutdown observability antes de sair
    shutdown_observability();
    result
}

fn init_tracing() {
    // Tenta inicializar OpenTelemetry, fallback para tracing simples
    if let Err(e) = init_observability() {
        eprintln!(
            "Aviso: Falha ao inicializar OpenTelemetry: {}. Usando tracing simples.",
            e
        );
        // Usa tracing_subscriber diretamente
        tracing_subscriber::fmt()
            .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
            .init();
    }
}

async fn run_doctor() -> Result<()> {
    let cfg = load_config();
    bootstrap().context("Falha no bootstrap do BEAGLE_DATA_DIR")?;

    println!("╔══════════════════════════════════════════════╗");
    println!("║ BEAGLE Doctor                                ║");
    println!("╚══════════════════════════════════════════════╝");
    println!("Profile: {} | SAFE_MODE={}", cfg.profile, cfg.safe_mode);
    println!("Data dir: {}", cfg.storage.data_dir);

    let report = check_all(&cfg).await;
    let (ok, warn, error) = report.count_by_status();

    println!("\n📊 Health Report:");
    println!("  ✅ OK: {}  ⚠️  WARN: {}  ❌ ERROR: {}", ok, warn, error);
    println!("\n🔍 Checks:");

    for check in &report.checks {
        let icon = match check.status.as_str() {
            "ok" => "✅",
            "warn" => "⚠️ ",
            "error" => "❌",
            _ => "❓",
        };
        println!("  {} {}: {}", icon, check.name, check.status);
        if let Some(details) = &check.details {
            println!("     └─ {}", details);
        }
    }

    if report.is_healthy() {
        println!("\n✨ Sistema saudável!");
    } else {
        println!("\n⚠️  Alguns checks falharam. Revise a configuração.");
    }

    // Salva relatório JSON
    let report_json = serde_json::to_string_pretty(&report)?;
    let report_path = beagle_data_dir().join("logs").join("health_report.json");
    fs::create_dir_all(report_path.parent().unwrap())?;
    fs::write(&report_path, report_json)?;
    println!("\n📄 Relatório completo salvo em: {:?}", report_path);

    Ok(())
}

#[instrument(skip_all, fields(run_id))]
async fn run_pipeline(question: String) -> Result<()> {
    let run_id = Uuid::new_v4().to_string();
    tracing::Span::current().record("run_id", &run_id.as_str());

    let cfg = load_config();
    info!(
        "Iniciando pipeline v0.1 | run_id={} | profile={} | SAFE_MODE={}",
        run_id, cfg.profile, cfg.safe_mode
    );

    bootstrap().context("Falha no bootstrap do BEAGLE_DATA_DIR")?;

    // Diretórios de artefatos
    let draft_dir = cfg
        .storage
        .data_dir_path()
        .join("papers")
        .join("drafts")
        .join(&run_id);
    fs::create_dir_all(&draft_dir)?;

    // Step: assemble draft (placeholder inicial)
    let draft_md = draft_dir.join("draft.md");
    let mut steps = Vec::new();
    let content = format!(
        "# BEAGLE Draft\n\nRun ID: {}\nProfile: {}\nSAFE_MODE: {}\n\n## Question\n{}\n\n## Notes\n- Context: pending integration (Darwin/HERMES)\n- This is a scaffold draft generated by beagle-monorepo pipeline v0.1\n",
        run_id,
        cfg.profile,
        cfg.safe_mode,
        question
    );
    fs::write(&draft_md, content)?;
    steps.push(StepStatus {
        name: "assemble_draft".to_string(),
        status: "ok".to_string(),
        notes: Some("Draft placeholder gerado; integrar Darwin/HERMES nos próximos passos".into()),
    });

    // PDF opcional (placeholder: ainda não gerado, evita depender de pandoc aqui)
    let pdf_path: Option<String> = None;
    steps.push(StepStatus {
        name: "render_pdf".to_string(),
        status: "skipped".to_string(),
        notes: Some("Pandoc/LaTeX não chamado neste scaffold; gerar pdf em passo posterior".into()),
    });

    // Summary JSON
    let summary = RunSummary {
        run_id: run_id.clone(),
        profile: cfg.profile.clone(),
        safe_mode: cfg.safe_mode,
        question,
        timestamp_utc: Utc::now().to_rfc3339(),
        draft_path: Some(draft_md.to_string_lossy().to_string()),
        pdf_path,
        steps,
    };
    let summary_path = logs_dir().join(format!("run_{}.json", run_id));
    fs::create_dir_all(logs_dir())?;
    fs::write(&summary_path, serde_json::to_string_pretty(&summary)?)?;

    info!(
        "Pipeline concluído (scaffold). Summary em {:?}",
        summary_path
    );
    println!("Run ID: {}", run_id);
    println!(
        "Draft : {:?}",
        summary.draft_path.as_deref().unwrap_or("n/a")
    );
    println!("Summary: {:?}", summary_path);
    Ok(())
}

fn show_ide_instructions() {
    println!("IDE Tauri");
    println!("1) cd apps/beagle-ide-tauri");
    println!("2) cargo tauri dev");
    println!("Painéis: Knowledge Graph, Paper Canvas (Yjs), Agent Console, Quantum View.");
}

fn logs_dir() -> PathBuf {
    beagle_data_dir().join("logs").join("beagle-monorepo")
}
