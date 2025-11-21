//! Teste de fumaça para pipeline v0.1
//!
//! Valida que o pipeline básico funciona:
//! - Gera draft.md
//! - Gera draft.pdf (placeholder)
//! - Gera run_report.json
//! - Estrutura JSON correta

use beagle_core::BeagleContext;
use beagle_config::load as load_config;
use beagle_monorepo::pipeline::run_beagle_pipeline;
use serde_json::Value;
use std::fs;
use tempfile::tempdir;
use uuid::Uuid;

#[tokio::test]
async fn test_pipeline_smoke() -> anyhow::Result<()> {
    let mut cfg = load_config();
    cfg.safe_mode = true; // Força SAFE_MODE para teste
    
    // Usa diretório temporário
    let temp_dir = tempdir()?;
    cfg.storage.data_dir = temp_dir.path().to_string_lossy().to_string();

    let mut ctx = BeagleContext::new(cfg).await?;
    let question = "Teste de fumaça: explique machine learning em 2 parágrafos";
    let run_id = Uuid::new_v4().to_string();

    let paths = run_beagle_pipeline(&mut ctx, question, &run_id, None, None).await?;

    // Verifica que arquivos foram criados
    assert!(paths.draft_md.exists(), "draft.md deve existir");
    assert!(paths.draft_pdf.exists(), "draft.pdf deve existir");
    assert!(paths.run_report.exists(), "run_report.json deve existir");

    // Verifica conteúdo do draft.md
    let draft_content = fs::read_to_string(&paths.draft_md)?;
    assert!(!draft_content.is_empty(), "draft.md não deve estar vazio");
    assert!(draft_content.len() > 100, "draft.md deve ter conteúdo substancial");

    // Verifica estrutura do run_report.json
    let report_content = fs::read_to_string(&paths.run_report)?;
    let report: Value = serde_json::from_str(&report_content)?;
    
    assert!(report.get("run_id").is_some(), "run_report deve ter run_id");
    assert!(report.get("timestamp").is_some(), "run_report deve ter timestamp");
    assert!(report.get("question").is_some(), "run_report deve ter question");
    assert!(report.get("profile").is_some(), "run_report deve ter profile");
    assert_eq!(report["safe_mode"], true, "run_report deve ter safe_mode=true");

    println!("✅ Teste de fumaça passou!");
    println!("   Draft MD: {}", paths.draft_md.display());
    println!("   Draft PDF: {}", paths.draft_pdf.display());
    println!("   Run Report: {}", paths.run_report.display());

    Ok(())
}

