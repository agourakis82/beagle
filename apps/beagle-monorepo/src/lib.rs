//! beagle-monorepo - Biblioteca compartilhada

pub mod auth;
pub mod http;
pub mod http_memory;
pub mod jobs;
pub mod pipeline;
pub mod pipeline_void;
// config removido - usar beagle_config diretamente

pub use http::{build_router, AppState};
pub use jobs::{
    JobRegistry, RunState, RunStatus, ScienceJobKind, ScienceJobRegistry, ScienceJobState,
    ScienceJobStatus,
};
pub use pipeline::{run_beagle_pipeline, ExperimentFlags, PipelinePaths};

// init_tracing removido - usar tracing_subscriber diretamente ou função local
