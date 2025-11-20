//! Manuscript management and state machine

mod state_machine;

pub use state_machine::{ManuscriptEvent, ManuscriptState};

use crate::{ManuscriptStatus, Result, SectionType};
use chrono::{DateTime, Utc};
use serde_json::json;
use sqlx::{PgPool, Postgres, Row, Transaction};
use state_machine::ManuscriptStateMachine;
use uuid::Uuid;

pub struct ManuscriptManager {
    pool: PgPool,
}

impl ManuscriptManager {
    pub async fn new(postgres_uri: &str) -> Result<Self> {
        let pool = PgPool::connect(postgres_uri)
            .await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        // Setup schema
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS manuscripts (
                id UUID PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                state TEXT NOT NULL DEFAULT 'ideation',
                last_transition TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                completed_sections TEXT[] NOT NULL DEFAULT '{}'::text[]
            )
            "#,
        )
        .execute(&pool)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        sqlx::query(
            r#"
            ALTER TABLE manuscripts
                ADD COLUMN IF NOT EXISTS last_transition TIMESTAMPTZ NOT NULL DEFAULT NOW()
            "#,
        )
        .execute(&pool)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        sqlx::query(
            r#"
            ALTER TABLE manuscripts
                ADD COLUMN IF NOT EXISTS completed_sections TEXT[] NOT NULL DEFAULT '{}'::text[]
            "#,
        )
        .execute(&pool)
        .await
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
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                UNIQUE (manuscript_id, section_type)
            )
            "#,
        )
        .execute(&pool)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS manuscript_state_events (
                id UUID PRIMARY KEY,
                manuscript_id UUID NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
                event TEXT NOT NULL,
                from_state TEXT NOT NULL,
                to_state TEXT NOT NULL,
                metadata JSONB,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            "#,
        )
        .execute(&pool)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        Ok(Self { pool })
    }

    /// Ensure a manuscript exists and all sections are initialized.
    pub async fn initialize_manuscript(&self, manuscript_id: Uuid, title: &str) -> Result<()> {
        let mut tx = self
            .pool
            .begin()
            .await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        sqlx::query(
            r#"
            INSERT INTO manuscripts (id, title)
            VALUES ($1, $2)
            ON CONFLICT (id) DO UPDATE
                SET title = EXCLUDED.title,
                    updated_at = NOW()
            "#,
        )
        .bind(manuscript_id)
        .bind(title)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        for section in SectionType::all() {
            sqlx::query(
                r#"
                INSERT INTO sections (id, manuscript_id, section_type)
                VALUES ($1, $2, $3)
                ON CONFLICT (manuscript_id, section_type) DO NOTHING
                "#,
            )
            .bind(Uuid::new_v4())
            .bind(manuscript_id)
            .bind(section.as_str())
            .execute(&mut *tx)
            .await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;
        }

        tx.commit()
            .await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        Ok(())
    }

    /// Apply a ManuscriptEvent and persist state transitions.
    pub async fn update_state(
        &self,
        manuscript_id: Uuid,
        event: ManuscriptEvent,
    ) -> Result<ManuscriptState> {
        let mut tx = self
            .pool
            .begin()
            .await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        let mut machine = self.load_state_machine(manuscript_id, &mut tx).await?;
        let from_state = machine.state();

        machine.apply(event);

        self.persist_state_machine(manuscript_id, &machine, &mut tx, event, from_state)
            .await?;

        tx.commit()
            .await
            .map_err(|e| crate::HermesError::DatabaseError(e))?;

        Ok(machine.state())
    }

    pub async fn get_status(&self, paper_id: &str) -> Result<ManuscriptStatus> {
        let manuscript_id = Uuid::parse_str(paper_id)
            .map_err(|e| crate::HermesError::ManuscriptError(format!("Invalid paper_id: {}", e)))?;

        let manuscript_row = sqlx::query(
            "SELECT id, title, updated_at, state, last_transition, completed_sections FROM manuscripts WHERE id = $1",
        )
                .bind(manuscript_id)
                .fetch_optional(&self.pool)
                .await
                .map_err(|e| crate::HermesError::DatabaseError(e))?
                .ok_or_else(|| {
                    crate::HermesError::ManuscriptError("Manuscript not found".to_string())
                })?;

        let manuscript = ManuscriptRow {
            id: manuscript_row.get::<Uuid, _>("id"),
            title: manuscript_row.get::<String, _>("title"),
            updated_at: manuscript_row.get::<DateTime<Utc>, _>("updated_at"),
            state: ManuscriptState::from_str(&manuscript_row.get::<String, _>("state")),
            last_transition: manuscript_row.get::<DateTime<Utc>, _>("last_transition"),
            completed_sections: manuscript_row
                .get::<Vec<String>, _>("completed_sections")
                .len(),
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
            .filter_map(|s| {
                SectionType::from_str(&s.section_type).map(|section_type| crate::SectionStatus {
                    section_type,
                    completion: s.completion as f64,
                    word_count: s.word_count as usize,
                    has_new_draft: s.has_new_draft,
                })
            })
            .collect();

        let overall_completion = if section_statuses.is_empty() {
            0.0
        } else {
            section_statuses.iter().map(|s| s.completion).sum::<f64>()
                / section_statuses.len() as f64
        };

        Ok(ManuscriptStatus {
            paper_id: manuscript.id.to_string(),
            title: manuscript.title,
            state: Some(manuscript.state.as_str().to_string()),
            state_last_transition: Some(manuscript.last_transition),
            sections: section_statuses,
            overall_completion,
            last_updated: manuscript.updated_at,
            completed_sections: Some(manuscript.completed_sections),
        })
    }

    async fn load_state_machine(
        &self,
        manuscript_id: Uuid,
        tx: &mut Transaction<'_, Postgres>,
    ) -> Result<ManuscriptStateMachine> {
        let row = sqlx::query(
            r#"
            SELECT state, last_transition, completed_sections
            FROM manuscripts
            WHERE id = $1
            FOR UPDATE
            "#,
        )
        .bind(manuscript_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?
        .ok_or_else(|| crate::HermesError::ManuscriptError("Manuscript not found".to_string()))?;

        let state = ManuscriptState::from_str(&row.get::<String, _>("state"));
        let last_transition = row.get::<DateTime<Utc>, _>("last_transition");
        let completed_sections_raw = row.get::<Vec<String>, _>("completed_sections");

        let completed_sections: std::collections::HashSet<SectionType> = completed_sections_raw
            .into_iter()
            .filter_map(|s| SectionType::from_str(&s))
            .collect();

        Ok(ManuscriptStateMachine::from_parts(
            state,
            completed_sections,
            last_transition,
        ))
    }

    async fn persist_state_machine(
        &self,
        manuscript_id: Uuid,
        machine: &ManuscriptStateMachine,
        tx: &mut Transaction<'_, Postgres>,
        event: ManuscriptEvent,
        from_state: ManuscriptState,
    ) -> Result<()> {
        let completed_sections: Vec<String> = machine
            .completed_section_list()
            .into_iter()
            .map(|section| section.as_str().to_string())
            .collect();

        sqlx::query(
            r#"
            UPDATE manuscripts
            SET state = $2,
                last_transition = $3,
                completed_sections = $4,
                updated_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(manuscript_id)
        .bind(machine.state().as_str())
        .bind(machine.last_transition())
        .bind(&completed_sections)
        .execute(&mut **tx)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        let metadata =
            serde_json::to_value(event).unwrap_or_else(|_| json!({ "event": event.as_str() }));

        sqlx::query(
            r#"
            INSERT INTO manuscript_state_events (
                id,
                manuscript_id,
                event,
                from_state,
                to_state,
                metadata
            ) VALUES ($1, $2, $3, $4, $5, $6)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(manuscript_id)
        .bind(event.as_str())
        .bind(from_state.as_str())
        .bind(machine.state().as_str())
        .bind(metadata)
        .execute(&mut **tx)
        .await
        .map_err(|e| crate::HermesError::DatabaseError(e))?;

        Ok(())
    }
}

struct ManuscriptRow {
    id: Uuid,
    title: String,
    updated_at: DateTime<Utc>,
    state: ManuscriptState,
    last_transition: DateTime<Utc>,
    completed_sections: usize,
}

struct SectionRow {
    section_type: String,
    completion: f32,
    word_count: i32,
    has_new_draft: bool,
}
