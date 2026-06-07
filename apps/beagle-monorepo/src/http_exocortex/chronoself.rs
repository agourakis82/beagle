//! `chronoself` exocortex HTTP handlers (split from the former god-file).
//!
//! Pure code movement: handlers call `super::ExocortexRepository` methods and shared
//! DTOs/helpers re-exported from the parent module. Behavior and route paths unchanged.

use super::*;

pub(crate) async fn chronoself_current_handler(
    State(_state): State<AppState>,
) -> Result<Json<SelfVersion>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let current = repo.current_self().map_err(internal_error)?;
    Ok(Json(current))
}

pub(crate) async fn chronoself_commits_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<CommitListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let commits = repo
        .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(CommitListResponse { commits }))
}

pub(crate) async fn chronoself_create_commit_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateCommitRequest>,
) -> Result<Json<ChronoselfCommit>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let commit = repo.create_commit(req).map_err(internal_error)?;
    Ok(Json(commit))
}
