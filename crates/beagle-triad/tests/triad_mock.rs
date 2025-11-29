//! Testes da Triad com MockLlmClient

use beagle_config::load as load_config;
use beagle_core::BeagleContext;
use beagle_triad::{run_triad, TriadInput};
use tempfile::TempDir;

#[tokio::test]
async fn test_triad_generates_report() -> anyhow::Result<()> {
    let temp_dir = TempDir::new()?;
    let data_dir = temp_dir.path().to_path_buf();

    // Cria draft de teste
    let draft_dir = data_dir.join("papers").join("drafts");
    std::fs::create_dir_all(&draft_dir)?;
    let draft_path = draft_dir.join("test_draft.md");
    std::fs::write(
        &draft_path,
        "# Test Draft\n\nThis is a test draft for Triad review.",
    )?;

    let mut cfg = load_config();
    cfg.storage.data_dir = data_dir.to_string_lossy().to_string();

    let ctx = BeagleContext::new_with_mocks(cfg);

    let input = TriadInput {
        run_id: "test-triad-001".to_string(),
        draft_path: draft_path.clone(),
        context_summary: Some("Test context summary".to_string()),
    };

    let report = run_triad(&input, &ctx).await?;

    // Verifica que o report foi gerado
    assert_eq!(report.run_id, "test-triad-001");
    assert!(!report.original_draft.is_empty());
    assert!(!report.final_draft.is_empty());
    assert_eq!(
        report.opinions.len(),
        3,
        "Deve ter 3 opiniões (ATHENA, HERMES, ARGOS)"
    );

    // Verifica que cada agente tem uma opinião
    let agent_names: Vec<String> = report.opinions.iter().map(|o| o.agent.clone()).collect();
    assert!(agent_names.contains(&"ATHENA".to_string()));
    assert!(agent_names.contains(&"HERMES".to_string()));
    assert!(agent_names.contains(&"ARGOS".to_string()));

    Ok(())
}
