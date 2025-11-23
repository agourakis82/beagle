//! Testes do pipeline com MockLlmClient

use beagle_core::BeagleContext;
use beagle_monorepo::run_beagle_pipeline;
use tempfile::TempDir;
use uuid::Uuid;

#[tokio::test]
async fn test_pipeline_with_mock() -> anyhow::Result<()> {
    // Setup: cria BeagleContext com mocks
    let mut ctx = BeagleContext::new_with_mock()?;
    
    // Cria diretório temporário para artefatos
    let temp_dir = TempDir::new()?;
    let temp_path = temp_dir.path().to_path_buf();
    
    // Override data_dir no config para usar temp
    ctx.cfg.storage.data_dir = temp_path.to_string_lossy().to_string();
    
    // Garante que diretórios existem
    std::fs::create_dir_all(&temp_path.join("papers").join("drafts"))?;
    std::fs::create_dir_all(&temp_path.join("logs").join("beagle-pipeline"))?;
    std::fs::create_dir_all(&temp_path.join("feedback"))?;
    
    // Executa pipeline
    let run_id = Uuid::new_v4().to_string();
    let question = "Qual o papel da entropia curva em scaffolds biológicos?";
    
    let paths = run_beagle_pipeline(&mut ctx, question, &run_id, None, None, None).await?;
    
    // Verifica que artefatos foram criados
    assert!(paths.draft_md.exists(), "draft_md deve existir");
    assert!(paths.draft_pdf.exists(), "draft_pdf deve existir");
    assert!(paths.run_report.exists(), "run_report deve existir");
    
    // Verifica conteúdo básico
    let draft_content = std::fs::read_to_string(&paths.draft_md)?;
    assert!(!draft_content.is_empty(), "draft_md não deve estar vazio");
    
    let report_content = std::fs::read_to_string(&paths.run_report)?;
    assert!(report_content.contains(&run_id), "run_report deve conter run_id");
    
    Ok(())
}
