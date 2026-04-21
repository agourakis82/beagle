use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct CompiledContextSourceSliceSummary {
    pub source_kind: String,
    pub budgeted_items: usize,
    pub selected_count: usize,
    pub support_ids: Vec<String>,
}
