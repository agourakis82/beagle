use std::path::PathBuf;

use beagle_db::{MigrationError, Migrator};
use clap::{Parser, Subcommand};
use sqlx::PgPool;
use tracing::info;
use tracing_subscriber::{fmt, EnvFilter};

#[derive(Parser, Debug)]
#[command(
    name = "beagle-migrate",
    version,
    about = "Orquestra migrações do schema PostgreSQL para o projeto Beagle."
)]
struct Cli {
    /// URL de conexão com o PostgreSQL. Pode ser informada via env DATABASE_URL.
    #[arg(long, env = "DATABASE_URL")]
    database_url: String,

    /// Caminho para diretório de migrações (default: migrations/ do crate).
    #[arg(long)]
    migrations_dir: Option<PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Aplica todas as migrações pendentes.
    Up,

    /// Reverte migrações aplicadas (default: 1 passo).
    Down {
        #[arg(long, default_value_t = 1)]
        steps: u32,
    },

    /// Exibe status das migrações.
    Status,
}

#[tokio::main]
async fn main() -> Result<(), MigrationError> {
    init_tracing();
    let cli = Cli::parse();
    let pool = connect_pool(&cli.database_url).await?;
    let migrator = match cli.migrations_dir {
        Some(dir) => Migrator::with_directory(pool.clone(), dir),
        None => Migrator::new(pool.clone()),
    };

    match cli.command {
        Command::Up => {
            info!("Aplicando migrações pendentes...");
            migrator.run_migrations().await?;
        }
        Command::Down { steps } => {
            info!("Executando rollback ({} passo[s])", steps);
            for _ in 0..steps {
                if migrator.rollback_last().await?.is_none() {
                    break;
                }
            }
        }
        Command::Status => {
            let status = migrator.status().await?;
            for entry in status {
                println!("{}", entry);
            }
        }
    }

    Ok(())
}

async fn connect_pool(database_url: &str) -> Result<PgPool, MigrationError> {
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(database_url)
        .await?;
    Ok(pool)
}

fn init_tracing() {
    let default_filter = "info";
    let env_filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(default_filter));
    fmt()
        .with_env_filter(env_filter)
        .with_target(false)
        .compact()
        .init();
}
