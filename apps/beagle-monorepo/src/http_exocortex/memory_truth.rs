//! exocortex memory-truthset domain — extracted from the god-file (plan #16).
//! HTTP handlers for memory truthsets, their cases, and review flows.
//! Shared helpers (e.g. `internal_error`), DTOs, consts, and the repository
//! are reachable via `use super::*` since they are pub(crate).

use super::*;

pub(crate) async fn memory_truthset_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateMemoryTruthSetRequest>,
) -> Result<Json<MemoryTruthSet>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let truthset = repo.create_memory_truthset(req).map_err(internal_error)?;
    Ok(Json(truthset))
}

pub(crate) async fn memory_truthset_get_handler(
    State(_state): State<AppState>,
    Path(truthset_id): Path<String>,
) -> Result<Json<MemoryTruthSetResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .memory_truthset_response(&truthset_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(response))
}

pub(crate) async fn memory_truthset_case_create_handler(
    State(_state): State<AppState>,
    Path(truthset_id): Path<String>,
    Json(req): Json<CreateMemoryTruthCaseRequest>,
) -> Result<Json<MemoryTruthCase>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let case = repo
        .create_memory_truth_case(&truthset_id, req)
        .map_err(internal_error)?;
    Ok(Json(case))
}

pub(crate) async fn memory_truthset_review_handler(
    State(_state): State<AppState>,
    Path(truthset_id): Path<String>,
    Json(req): Json<ReviewMemoryTruthSetRequest>,
) -> Result<Json<MemoryTruthSetResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .review_memory_truthset(&truthset_id, req)
        .map_err(internal_error)?;
    Ok(Json(response))
}
