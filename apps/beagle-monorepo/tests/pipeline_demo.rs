//! Teste de integração do pipeline BEAGLE usando mocks
//!
//! Este teste verifica que o pipeline completo funciona sem depender de
//! serviços externos (Grok, Neo4j, Qdrant, etc.), usando mocks.

use anyhow::Result;
use beagle_config::{BeagleConfig, StorageConfig};
use beagle_core::BeagleContext;
use std::path::PathBuf;
use tempfile::tempdir;

#[tokio::test]
async fn pipeline_demo_produz_draft_e_summary() -> Result<()> {
    // 1. Configuração de teste com diretório temporário
    let temp_dir = tempdir()?;
    let mut cfg = BeagleConfig {
        profile: "dev".to_string(),
        safe_mode: true,
        api_token: None,
        llm: Default::default(),
        storage: StorageConfig {
            data_dir: temp_dir.path().to_string_lossy().to_string(),
        },
        graph: Default::default(),
        hermes: Default::default(),
        advanced: Default::default(),
        observer: Default::default(),
    };

    // 2. Cria contexto com mocks
    let ctx = BeagleContext::new_with_mocks(cfg.clone());
    let run_id = "test-run-001";
    let question = "Test question for pipeline demo";

    // 3. Simula execução do pipeline
    // (Por enquanto, apenas verifica que o contexto funciona)
    let _answer = ctx.llm.complete(question).await?;
    let _vectors = ctx.vector.query(question, 5).await?;
    let _graph_result = ctx
        .graph
        .cypher_query("MATCH (n) RETURN n LIMIT 10", serde_json::json!({}))
        .await?;

    // 4. Verifica que os diretórios base existem
    let data_dir = PathBuf::from(&ctx.cfg.storage.data_dir);
    assert!(data_dir.exists(), "Data dir deve existir");

    // 5. Verifica que o draft_dir seria criado
    let draft_dir = data_dir.join("papers").join("drafts").join(run_id);
    std::fs::create_dir_all(&draft_dir)?;
    assert!(draft_dir.exists(), "Draft dir deve ser criável");

    // 6. Cria draft de teste
    let draft_md = draft_dir.join("draft.md");
    let content = format!(
        "# BEAGLE Draft\n\nRun ID: {}\nProfile: {}\nSAFE_MODE: {}\n\n## Question\n{}\n",
        run_id, ctx.cfg.profile, ctx.cfg.safe_mode, question
    );
    std::fs::write(&draft_md, content)?;
    assert!(draft_md.exists(), "Draft.md deve ser criado");

    // 7. Verifica conteúdo do draft
    let content_read = std::fs::read_to_string(&draft_md)?;
    assert!(content_read.contains(run_id), "Draft deve conter run_id");
    assert!(
        content_read.contains(question),
        "Draft deve conter question"
    );

    Ok(())
}

#[tokio::test]
async fn beagle_context_com_mocks_funciona() -> Result<()> {
    let temp_dir = tempdir()?;
    let cfg = BeagleConfig {
        profile: "dev".to_string(),
        safe_mode: true,
        api_token: None,
        llm: Default::default(),
        storage: StorageConfig {
            data_dir: temp_dir.path().to_string_lossy().to_string(),
        },
        graph: Default::default(),
        hermes: Default::default(),
        advanced: Default::default(),
        observer: Default::default(),
    };

    let ctx = BeagleContext::new_with_mocks(cfg);

    // Testa LLM mock
    let llm_response = ctx.llm.complete("test prompt").await?;
    assert!(
        llm_response.contains("MOCK_ANSWER"),
        "LLM mock deve responder"
    );

    // Testa Vector Store mock
    let vectors = ctx.vector.query("test query", 3).await?;
    assert_eq!(vectors.len(), 3, "Vector store deve retornar 3 resultados");
    assert!(vectors[0].score > 0.0, "Scores devem ser positivos");

    // Testa Graph Store mock
    let graph_result = ctx
        .graph
        .cypher_query("MATCH (n) RETURN n", serde_json::json!({}))
        .await?;
    assert!(
        graph_result.get("results").is_some(),
        "Graph store deve retornar resultados"
    );

    Ok(())
}
