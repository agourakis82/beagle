//! Binário CLI para pipeline BEAGLE v0.1
//!
//! Uso:
//!   cargo run --bin pipeline --package beagle-monorepo -- "Pergunta científica..."

use beagle_monorepo::pipeline::run_beagle_pipeline;
use beagle_core::BeagleContext;
use beagle_config::load as load_config;
use uuid::Uuid;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let question = std::env::args()
        .nth(1)
        .ok_or_else(|| anyhow::anyhow!("Forneça a pergunta/tópico como argumento"))?;

    let run_id = Uuid::new_v4().to_string();
    info!("Run ID: {}", run_id);

    let cfg = load_config();
    let mut ctx = BeagleContext::new(cfg).await?;

    let paths = run_beagle_pipeline(&mut ctx, &question, &run_id, None, None).await?;

    println!("\n=== BEAGLE PIPELINE v0.1 CONCLUÍDO ===");
    println!("Run ID:     {}", run_id);
    println!("Draft MD:   {}", paths.draft_md.display());
    println!("Draft PDF:  {}", paths.draft_pdf.display());
    println!("RunReport:  {}", paths.run_report.display());
    println!("\n✅ Pipeline executado com sucesso!");

    Ok(())
}

