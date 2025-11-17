//! Manuscript management and state machine

mod state_machine;

pub use state_machine::ManuscriptState;

use crate::{Result, ManuscriptStatus, SectionType};
use sqlx::{PgPool, Row};
use uuid::Uuid;
use chrono::{DateTime, Utc};

pub struct ManuscriptManager {
    pool: PgPool,
}

impl ManuscriptManager {
    pub async fn new(postgres_uri: &str) -> Result<Self> {
        let pool = PgPool::connect(postgres_uri).await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        // Setup schema
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS manuscripts (
                id UUID PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                state TEXT NOT NULL DEFAULT 'draft'
            )
            "#
        ).execute(&pool).await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS sections (
                id UUID PRIMARY KEY,
                manuscript_id UUID NOT NULL REFERENCES manuscripts(id),
                section_type TEXT NOT NULL,
                content TEXT,
                word_count INTEGER DEFAULT 0,
                completion REAL DEFAULT 0.0,
                has_new_draft BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            "#
        ).execute(&pool).await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        Ok(Self { pool })
    }

    pub async fn get_status(&self, paper_id: &str) -> Result<ManuscriptStatus> {
        let manuscript_id = Uuid::parse_str(paper_id)
            .map_err(|e| crate::HermesError::ManuscriptError(format!("Invalid paper_id: {}", e)))?;

        let manuscript_row = sqlx::query(
            "SELECT id, title, updated_at FROM manuscripts WHERE id = $1"
        )
        .bind(manuscript_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?
        .ok_or_else(|| crate::HermesError::ManuscriptError("Manuscript not found".to_string()))?;

        let manuscript = ManuscriptRow {
            id: manuscript_row.get::<Uuid, _>("id"),
            title: manuscript_row.get::<String, _>("title"),
            updated_at: manuscript_row.get::<DateTime<Utc>, _>("updated_at"),
        };

        let section_rows = sqlx::query(
            "SELECT section_type, completion, word_count, has_new_draft FROM sections WHERE manuscript_id = $1"
        )
        .bind(manuscript_id)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        let sections: Vec<SectionRow> = section_rows
            .into_iter()
            .map(|row| SectionRow {
                section_type: row.get::<String, _>("section_type"),
                completion: row.get::<f32, _>("completion"),
                word_count: row.get::<i32, _>("word_count"),
                has_new_draft: row.get::<bool, _>("has_new_draft"),
            })
            .collect();

        let section_statuses: Vec<crate::SectionStatus> = sections
            .into_iter()
            .map(|s| crate::SectionStatus {
                section_type: parse_section_type(&s.section_type),
                completion: s.completion as f64,
                word_count: s.word_count as usize,
                has_new_draft: s.has_new_draft,
            })
            .collect();

        let overall_completion = if section_statuses.is_empty() {
            0.0
        } else {
            section_statuses.iter().map(|s| s.completion).sum::<f64>() / section_statuses.len() as f64
        };

        Ok(ManuscriptStatus {
            paper_id: manuscript.id.to_string(),
            title: manuscript.title,
            sections: section_statuses,
            overall_completion,
            last_updated: manuscript.updated_at,
        })
    }
}

struct ManuscriptRow {
    id: Uuid,
    title: String,
    updated_at: DateTime<Utc>,
}

struct SectionRow {
    section_type: String,
    completion: f32,
    word_count: i32,
    has_new_draft: bool,
}

fn parse_section_type(s: &str) -> SectionType {
    match s.to_lowercase().as_str() {
        "abstract" => SectionType::Abstract,
        "introduction" => SectionType::Introduction,
        "methods" => SectionType::Methods,
        "results" => SectionType::Results,
        "discussion" => SectionType::Discussion,
        "conclusion" => SectionType::Conclusion,
        _ => SectionType::Introduction,
    }
}

