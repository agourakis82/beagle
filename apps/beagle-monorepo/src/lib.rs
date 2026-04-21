//! beagle-monorepo - Biblioteca compartilhada

pub mod auth;
pub mod cognitive_events;
pub mod http;
pub mod http_cognitive;
pub mod http_darwin_hpc;
pub mod http_deep_think;
pub mod http_exocortex;
pub mod http_external_jobs;
pub mod http_feedback;
pub mod http_fractal;
pub mod phi_iit;
pub mod http_memory;
pub mod jobs;
pub mod pipeline;
pub mod pipeline_checkpoint;
pub mod pipeline_void;
// config removido - usar beagle_config diretamente

pub use http::{build_router, AppState};
pub use jobs::{
    FractalTreeRegistry, FractalTreeSummary, JobRegistry, PhiMeasurementRegistry,
    PhiMeasurementSummary, RunState, RunStatus, ScienceJobKind, ScienceJobRegistry,
    ScienceJobState, ScienceJobStatus, VoidJourneyRegistry, VoidJourneySummary,
    truth_mode_for_age,
};
pub use pipeline::{run_beagle_pipeline, ExperimentFlags, PipelinePaths};
pub use pipeline_checkpoint::{PipelineCheckpointer, PipelinePhase, PipelineState};

// init_tracing removido - usar tracing_subscriber diretamente ou função local
