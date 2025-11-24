//! Binário CLI para revisão Triad
//!
//! Uso:
//!   cargo run --bin triad-review --package beagle-triad -- <run_id>

use beagle_config::load as load_config;
use beagle_core::BeagleContext;
use beagle_feedback::{append_event, create_triad_event};
use beagle_triad::{run_triad, TriadInput};
use std::path::PathBuf;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let run_id = std::env::args()
        .nth(1)
        .ok_or_else(|| anyhow::anyhow!("Use: triad_review <run_id>"))?;

    info!("🔍 Iniciando Triad review para run_id: {}", run_id);

    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    // Localizar draft e log pela convenção do pipeline v0.1
    let drafts_dir = data_dir.join("papers").join("drafts");
    let logs_dir = data_dir.join("logs").join("beagle-pipeline");

    let draft_path = find_draft(&drafts_dir, &run_id)?;
    let context_summary = find_context_summary(&logs_dir, &run_id).ok();

    let input = TriadInput {
        run_id: run_id.clone(),
        draft_path,
        context_summary,
    };

    let ctx = BeagleContext::new(cfg).await?;
    let report = run_triad(&input, &ctx).await?;

    // Salvar artefatos
    let triad_dir = data_dir.join("triad").join(&run_id);
    std::fs::create_dir_all(&triad_dir)?;
    let report_json = triad_dir.join("triad_report.json");
    let final_md = triad_dir.join("draft_reviewed.md");

    std::fs::write(&report_json, serde_json::to_string_pretty(&report)?)?;
    std::fs::write(&final_md, &report.final_draft)?;

    // Log feedback event para Continuous Learning
    let llm_stats = Some((
        report.llm_stats.grok3_calls as u32,
        report.llm_stats.grok4_calls as u32,
        (report.llm_stats.grok3_tokens_in + report.llm_stats.grok3_tokens_out) as u32,
        (report.llm_stats.grok4_tokens_in + report.llm_stats.grok4_tokens_out) as u32,
    ));

    // Tenta recuperar question do run_report original (simplificado)
    // Por enquanto, None - pode ser melhorado para ler do run_report.json
    let question = None;

    let event = create_triad_event(
        run_id.clone(),
        question,
        final_md.clone(),
        report_json.clone(),
        llm_stats,
    );

    if let Err(e) = append_event(&data_dir, &event) {
        eprintln!("⚠️  Falha ao logar feedback event: {}", e);
    } else {
        info!("📊 Feedback event da Triad logado para Continuous Learning");
    }

    println!("\n=== BEAGLE TRIAD REVIEW CONCLUÍDO ===");
    println!("Run ID: {}", run_id);
    println!("Relatório: {}", report_json.display());
    println!("Draft final: {}", final_md.display());
    println!("\nOpiniões:");
    for opinion in &report.opinions {
        println!(
            "  {}: Score {:.2} - {} | Provider: {}",
            opinion.agent, opinion.score, opinion.summary, opinion.provider_tier
        );
    }
    println!("\nLLM Stats:");
    println!(
        "  Grok 3: {} calls, {} tokens (in: {}, out: {})",
        report.llm_stats.grok3_calls,
        report.llm_stats.grok3_tokens_in + report.llm_stats.grok3_tokens_out,
        report.llm_stats.grok3_tokens_in,
        report.llm_stats.grok3_tokens_out
    );
    println!(
        "  Grok 4 Heavy: {} calls, {} tokens (in: {}, out: {})",
        report.llm_stats.grok4_calls,
        report.llm_stats.grok4_tokens_in + report.llm_stats.grok4_tokens_out,
        report.llm_stats.grok4_tokens_in,
        report.llm_stats.grok4_tokens_out
    );

    Ok(())
}

fn find_draft(drafts_dir: &PathBuf, run_id: &str) -> anyhow::Result<PathBuf> {
    for entry in std::fs::read_dir(drafts_dir)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            if name.contains(run_id) && name.ends_with(".md") {
                return Ok(path);
            }
        }
    }
    Err(anyhow::anyhow!(
        "Draft .md para run_id={} não encontrado",
        run_id
    ))
}

fn find_context_summary(logs_dir: &PathBuf, run_id: &str) -> anyhow::Result<String> {
    for entry in std::fs::read_dir(logs_dir)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            if name.contains(run_id) && name.ends_with(".json") {
                let s = std::fs::read_to_string(&path)?;
                // Por enquanto devolve o JSON inteiro como "summary"
                // Em produção, parsear e extrair context_summary específico
                return Ok(s);
            }
        }
    }
    Err(anyhow::anyhow!(
        "Log JSON para run_id={} não encontrado",
        run_id
    ))
}
