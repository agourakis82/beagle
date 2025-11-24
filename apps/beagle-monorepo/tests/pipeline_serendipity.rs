//! Testes de integração Serendipity no pipeline

use beagle_core::BeagleContext;
use beagle_monorepo::run_beagle_pipeline;
use tempfile::TempDir;
use uuid::Uuid;

#[tokio::test]
#[ignore] // Requer BEAGLE_SERENDIPITY_ENABLE=true e profile=lab
async fn test_pipeline_with_serendipity() -> anyhow::Result<()> {
    std::env::set_var("BEAGLE_SERENDIPITY_ENABLE", "true");

    let mut ctx = BeagleContext::new_with_mock()?;
    ctx.cfg.profile = "lab".to_string();

    let temp_dir = TempDir::new()?;
    ctx.cfg.storage.data_dir = temp_dir.path().to_string_lossy().to_string();

    std::fs::create_dir_all(&temp_dir.path().join("papers").join("drafts"))?;
    std::fs::create_dir_all(&temp_dir.path().join("logs").join("beagle-pipeline"))?;

    let run_id = Uuid::new_v4().to_string();
    let paths = run_beagle_pipeline(
        &mut ctx,
        "Como a entropia curva afeta scaffolds biológicos?",
        &run_id,
        None,
        None,
        None,
    )
    .await?;

    // Verifica que serendipity_score está no report
    let report_content = std::fs::read_to_string(&paths.run_report)?;
    assert!(
        report_content.contains("serendipity_score"),
        "Report deve conter serendipity_score"
    );

    Ok(())
}
