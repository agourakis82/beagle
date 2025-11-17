use serde::{Deserialize, Serialize};
use tauri::command;
use tracing::info;

#[derive(Debug, Serialize, Deserialize)]
pub struct Manuscript {
    pub id: String,
    pub title: String,
    pub state: String,
    pub completion: f64,
    pub last_updated: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ManuscriptStatus {
    pub paper_id: String,
    pub title: String,
    pub sections: Vec<SectionStatus>,
    pub overall_completion: f64,
    pub last_updated: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SectionStatus {
    pub section_type: String,
    pub completion: f64,
    pub word_count: usize,
    pub has_new_draft: bool,
}

#[command]
pub async fn list_manuscripts() -> Result<Vec<Manuscript>, String> {
    info!("Listing manuscripts");
    
    // TODO: Connect to HERMES API
    // For now, return mock data
    Ok(vec![
        Manuscript {
            id: "1".to_string(),
            title: "KEC Entropy and Collagen Degradation".to_string(),
            state: "Drafting".to_string(),
            completion: 0.65,
            last_updated: "2025-11-17T10:00:00Z".to_string(),
        },
    ])
}

#[command]
pub async fn get_manuscript(paper_id: String) -> Result<ManuscriptStatus, String> {
    info!("Getting manuscript: {}", paper_id);
    
    // TODO: Connect to HERMES API
    Ok(ManuscriptStatus {
        paper_id: paper_id.clone(),
        title: "KEC Entropy and Collagen Degradation".to_string(),
        sections: vec![
            SectionStatus {
                section_type: "Introduction".to_string(),
                completion: 0.9,
                word_count: 450,
                has_new_draft: true,
            },
            SectionStatus {
                section_type: "Methods".to_string(),
                completion: 0.7,
                word_count: 320,
                has_new_draft: false,
            },
        ],
        overall_completion: 0.65,
        last_updated: "2025-11-17T10:00:00Z".to_string(),
    })
}

#[command]
pub async fn get_manuscript_status(paper_id: String) -> Result<ManuscriptStatus, String> {
    get_manuscript(paper_id).await
}

#[command]
pub async fn upload_voice_note(file_path: String) -> Result<String, String> {
    info!("Uploading voice note: {}", file_path);
    
    // TODO: Send to HERMES API /api/thoughts/voice
    Ok("Voice note processed successfully".to_string())
}

#[command]
pub async fn capture_text_insight(text: String) -> Result<String, String> {
    info!("Capturing text insight: {} chars", text.len());
    
    // TODO: Send to HERMES API /api/thoughts/text
    Ok("Insight captured successfully".to_string())
}

#[command]
pub async fn trigger_synthesis(paper_id: String) -> Result<String, String> {
    info!("Triggering synthesis for paper: {}", paper_id);
    
    // TODO: Send to HERMES API /api/synthesis/trigger
    Ok("Synthesis triggered".to_string())
}

