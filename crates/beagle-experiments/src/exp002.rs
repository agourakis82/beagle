//! Beagle Expedition 002 – HRV-aware vs blind
//!
//! Hypothesis H2: With canonical observer state available, `hrv_aware`
//! runs will behave differently from `hrv_blind` runs under the same
//! question/workload envelope.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Official identifier for Expedition 002.
pub const EXPEDITION_002_ID: &str = "beagle_exp_002_hrv_aware_vs_blind";

/// Default run count for the live baseline.
pub const EXPEDITION_002_DEFAULT_N: usize = 4;

/// Default question template for Expedition 002.
pub const EXPEDITION_002_DEFAULT_QUESTION_TEMPLATE: &str =
    "Expedition 002 run {i}: assess how physiological context should influence bounded scientific synthesis tone and prioritization.";

/// Frozen human-eval protocol for Expedition 002.
pub const EXPEDITION_002_HUMAN_EVAL_PROTOCOL: &str =
    "b17.5-expedition-002-human-eval-v1";

/// Frozen config for Expedition 002.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002Config {
    pub experiment_id: String,
    pub n_total: usize,
    pub question_template: String,
}

impl Default for Expedition002Config {
    fn default() -> Self {
        Self {
            experiment_id: EXPEDITION_002_ID.to_string(),
            n_total: EXPEDITION_002_DEFAULT_N,
            question_template: EXPEDITION_002_DEFAULT_QUESTION_TEMPLATE.to_string(),
        }
    }
}

impl Expedition002Config {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_custom(
        experiment_id: Option<String>,
        n_total: Option<usize>,
        question_template: Option<String>,
    ) -> Self {
        Self {
            experiment_id: experiment_id.unwrap_or_else(|| EXPEDITION_002_ID.to_string()),
            n_total: n_total.unwrap_or(EXPEDITION_002_DEFAULT_N),
            question_template: question_template
                .unwrap_or_else(|| EXPEDITION_002_DEFAULT_QUESTION_TEMPLATE.to_string()),
        }
    }

    pub fn n_per_condition(&self) -> (usize, usize) {
        let n_hrv_aware = self.n_total.div_ceil(2);
        let n_hrv_blind = self.n_total / 2;
        (n_hrv_aware, n_hrv_blind)
    }
}

/// Canonical flags for condition `hrv_aware`.
pub fn hrv_aware_condition_flags() -> (bool, bool, bool, bool) {
    (
        false, // triad_enabled
        true,  // hrv_aware
        false, // serendipity_enabled
        false, // space_aware
    )
}

/// Canonical flags for condition `hrv_blind`.
pub fn hrv_blind_condition_flags() -> (bool, bool, bool, bool) {
    (
        false, // triad_enabled
        false, // hrv_aware
        false, // serendipity_enabled
        false, // space_aware
    )
}

/// Builds a balanced, deterministic condition sequence.
pub fn generate_condition_sequence(n_total: usize) -> Vec<String> {
    let (mut aware_remaining, mut blind_remaining) = (
        n_total.div_ceil(2),
        n_total / 2,
    );
    let mut sequence = Vec::with_capacity(n_total);
    let mut next_aware = aware_remaining >= blind_remaining;

    while aware_remaining > 0 || blind_remaining > 0 {
        if next_aware && aware_remaining > 0 {
            sequence.push("hrv_aware".to_string());
            aware_remaining -= 1;
        } else if !next_aware && blind_remaining > 0 {
            sequence.push("hrv_blind".to_string());
            blind_remaining -= 1;
        } else if aware_remaining > 0 {
            sequence.push("hrv_aware".to_string());
            aware_remaining -= 1;
        } else if blind_remaining > 0 {
            sequence.push("hrv_blind".to_string());
            blind_remaining -= 1;
        }

        if aware_remaining == 0 {
            next_aware = false;
        } else if blind_remaining == 0 {
            next_aware = true;
        } else {
            next_aware = !next_aware;
        }
    }

    sequence
}

/// Source material used to build a blinded human-eval packet.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002HumanEvalSource {
    pub run_id: String,
    pub condition: String,
    pub question: String,
    pub draft_md_path: PathBuf,
    pub draft_pdf_path: Option<PathBuf>,
    pub draft_markdown: String,
}

/// One blinded item presented to the evaluator.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002HumanEvalItem {
    pub blinded_item_id: String,
    pub prompt: String,
    pub draft_markdown: String,
}

/// Canonical blinded packet for Expedition 002 human evaluation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002HumanEvalPacket {
    pub experiment_id: String,
    pub packet_id: String,
    pub protocol_version: String,
    pub blinded: bool,
    pub instructions: Vec<String>,
    pub items: Vec<Expedition002HumanEvalItem>,
}

/// Audit key that resolves blinded ids back to canonical runs/conditions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002HumanEvalKeyEntry {
    pub blinded_item_id: String,
    pub run_id: String,
    pub condition: String,
    pub draft_md_path: PathBuf,
    pub draft_pdf_path: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002HumanEvalKey {
    pub experiment_id: String,
    pub packet_id: String,
    pub protocol_version: String,
    pub entries: Vec<Expedition002HumanEvalKeyEntry>,
}

/// One evaluator judgment for a blinded item.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002HumanRating {
    pub blinded_item_id: String,
    pub accepted: Option<bool>,
    pub rating_global_0_10: Option<u8>,
    pub clarity_0_10: Option<u8>,
    pub adequacy_of_tone_0_10: Option<u8>,
    pub usefulness_0_10: Option<u8>,
    pub safety_or_emotional_fit_0_10: Option<u8>,
    pub notes: Option<String>,
}

/// Batch of ratings persisted against a blinded packet.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition002HumanRatingBatch {
    pub experiment_id: String,
    pub packet_id: String,
    pub protocol_version: String,
    pub evaluator_id: String,
    pub ratings: Vec<Expedition002HumanRating>,
}

/// Builds a deterministic blinded packet plus its audit key.
pub fn build_human_eval_packet(
    experiment_id: &str,
    packet_id: &str,
    mut sources: Vec<Expedition002HumanEvalSource>,
) -> (Expedition002HumanEvalPacket, Expedition002HumanEvalKey) {
    // UUIDs are already opaque; lexical sort keeps the packet deterministic
    // without revealing the underlying condition to the evaluator.
    sources.sort_by(|a, b| a.run_id.cmp(&b.run_id));

    let mut items = Vec::with_capacity(sources.len());
    let mut entries = Vec::with_capacity(sources.len());

    for (idx, source) in sources.into_iter().enumerate() {
        let blinded_item_id = format!("item-{:03}", idx + 1);
        items.push(Expedition002HumanEvalItem {
            blinded_item_id: blinded_item_id.clone(),
            prompt: source.question.clone(),
            draft_markdown: source.draft_markdown,
        });
        entries.push(Expedition002HumanEvalKeyEntry {
            blinded_item_id,
            run_id: source.run_id,
            condition: source.condition,
            draft_md_path: source.draft_md_path,
            draft_pdf_path: source.draft_pdf_path,
        });
    }

    (
        Expedition002HumanEvalPacket {
            experiment_id: experiment_id.to_string(),
            packet_id: packet_id.to_string(),
            protocol_version: EXPEDITION_002_HUMAN_EVAL_PROTOCOL.to_string(),
            blinded: true,
            instructions: vec![
                "Rate each draft without inferring or revealing the hidden condition.".to_string(),
                "Use the same rubric for all items: global quality, clarity, tone adequacy, usefulness, and safety/emotional fit.".to_string(),
                "Keep notes short and audit-friendly.".to_string(),
            ],
            items,
        },
        Expedition002HumanEvalKey {
            experiment_id: experiment_id.to_string(),
            packet_id: packet_id.to_string(),
            protocol_version: EXPEDITION_002_HUMAN_EVAL_PROTOCOL.to_string(),
            entries,
        },
    )
}

/// Produces a fillable rating template with null values.
pub fn blank_human_rating_template(
    experiment_id: &str,
    packet_id: &str,
    evaluator_id: &str,
    blinded_item_ids: &[String],
) -> Expedition002HumanRatingBatch {
    Expedition002HumanRatingBatch {
        experiment_id: experiment_id.to_string(),
        packet_id: packet_id.to_string(),
        protocol_version: EXPEDITION_002_HUMAN_EVAL_PROTOCOL.to_string(),
        evaluator_id: evaluator_id.to_string(),
        ratings: blinded_item_ids
            .iter()
            .map(|blinded_item_id| Expedition002HumanRating {
                blinded_item_id: blinded_item_id.clone(),
                accepted: None,
                rating_global_0_10: None,
                clarity_0_10: None,
                adequacy_of_tone_0_10: None,
                usefulness_0_10: None,
                safety_or_emotional_fit_0_10: None,
                notes: None,
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        blank_human_rating_template, build_human_eval_packet, generate_condition_sequence,
        Expedition002Config, Expedition002HumanEvalSource, EXPEDITION_002_HUMAN_EVAL_PROTOCOL,
        EXPEDITION_002_ID,
    };
    use std::path::PathBuf;

    #[test]
    fn expedition_002_defaults_are_canonical() {
        let config = Expedition002Config::default();
        assert_eq!(config.experiment_id, EXPEDITION_002_ID);
        assert_eq!(config.n_total, 4);
        assert!(config.question_template.contains("{i}"));
    }

    #[test]
    fn sequence_is_balanced_and_deterministic() {
        let sequence = generate_condition_sequence(4);
        assert_eq!(sequence, vec!["hrv_aware", "hrv_blind", "hrv_aware", "hrv_blind"]);
    }

    #[test]
    fn odd_sequence_stays_bounded() {
        let sequence = generate_condition_sequence(5);
        let aware = sequence.iter().filter(|c| c.as_str() == "hrv_aware").count();
        let blind = sequence.iter().filter(|c| c.as_str() == "hrv_blind").count();
        assert_eq!(aware, 3);
        assert_eq!(blind, 2);
        assert_eq!(sequence.len(), 5);
    }

    #[test]
    fn human_eval_packet_is_blinded_and_deterministic() {
        let (packet, key) = build_human_eval_packet(
            EXPEDITION_002_ID,
            "packet-001",
            vec![
                Expedition002HumanEvalSource {
                    run_id: "b-run".to_string(),
                    condition: "hrv_blind".to_string(),
                    question: "Q2".to_string(),
                    draft_md_path: PathBuf::from("/tmp/b.md"),
                    draft_pdf_path: None,
                    draft_markdown: "blind draft".to_string(),
                },
                Expedition002HumanEvalSource {
                    run_id: "a-run".to_string(),
                    condition: "hrv_aware".to_string(),
                    question: "Q1".to_string(),
                    draft_md_path: PathBuf::from("/tmp/a.md"),
                    draft_pdf_path: None,
                    draft_markdown: "aware draft".to_string(),
                },
            ],
        );

        assert_eq!(packet.protocol_version, EXPEDITION_002_HUMAN_EVAL_PROTOCOL);
        assert!(packet.blinded);
        assert_eq!(packet.items.len(), 2);
        assert_eq!(packet.items[0].blinded_item_id, "item-001");
        assert_eq!(packet.items[0].prompt, "Q1");
        assert_eq!(key.entries[0].run_id, "a-run");
        assert_eq!(key.entries[0].condition, "hrv_aware");
    }

    #[test]
    fn human_eval_template_is_fillable() {
        let template = blank_human_rating_template(
            EXPEDITION_002_ID,
            "packet-001",
            "pending-human",
            &["item-001".to_string(), "item-002".to_string()],
        );
        assert_eq!(template.protocol_version, EXPEDITION_002_HUMAN_EVAL_PROTOCOL);
        assert_eq!(template.ratings.len(), 2);
        assert!(template.ratings.iter().all(|rating| rating.accepted.is_none()));
    }
}
