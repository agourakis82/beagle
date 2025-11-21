//! beagle-monorepo - Biblioteca compartilhada

pub mod pipeline;
pub mod jobs;
pub mod http;
// config removido - usar beagle_config diretamente

pub use pipeline::{run_beagle_pipeline, PipelinePaths};
pub use jobs::{JobRegistry, RunState, RunStatus, ScienceJobRegistry, ScienceJobState, ScienceJobKind, ScienceJobStatus};
pub use http::{build_router, AppState};

// init_tracing removido - usar tracing_subscriber diretamente ou função local
