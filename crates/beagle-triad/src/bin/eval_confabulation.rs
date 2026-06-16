//! Eval #1 — Residual confabulation rate of the P1 structural redactor.
//!
//! Measures whether [`beagle_triad::VerdictRegistry::redact_unattested`] catches
//! fabricated solver attributions (a reviewer agent citing a Sounio solver verdict
//! that never ran) without over-redacting legitimate prose.
//!
//! This is the deterministic, reproducible component of the open question the
//! deep-research synthesis left for the CPP2026 work: *"what is the residual
//! confabulation rate after structural verdict-binding?"* It measures the
//! **redactor's recall/precision** against a labeled adversarial corpus whose
//! ground-truth label is fixed BY CONSTRUCTION (per failure class), so the labels
//! carry no annotator noise.
//!
//! The full end-to-end residual rate is `P(ARGOS confabulates) × (1 − recall)`;
//! this harness measures the `(1 − recall)` factor rigorously. The live
//! `P(confabulate)` factor requires running the real reviewer and is a documented
//! layer-2 follow-up (see eval/confabulation/README.md).
//!
//! Run:
//!   cargo run -p beagle-triad --bin eval_confabulation [-- <corpus.jsonl> <out_dir>]
//! Defaults: corpus = crates/beagle-triad/eval/confabulation/corpus.jsonl,
//!           out_dir = same directory (writes results.json + results.md).

use beagle_triad::{VerdictRecord, VerdictRegistry};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
struct RecordSpec {
    verb: String,
    result: String,
}

#[derive(Debug, Deserialize)]
struct Case {
    category: String,
    expected_redacted: bool,
    #[serde(default)]
    lang: String,
    text: String,
    #[serde(default)]
    records: Vec<RecordSpec>,
    #[serde(default)]
    rationale: String,
}

/// Map a corpus verb string to the `&'static str` the API requires. Unknown verbs
/// are dropped (a record with an unrecognized verb cannot attest anything anyway).
fn static_verb(v: &str) -> Option<&'static str> {
    match v {
        "smt.check" => Some("smt.check"),
        "causal.dsep" => Some("causal.dsep"),
        "gum.propagate" => Some("gum.propagate"),
        "theorem.prove" => Some("theorem.prove"),
        _ => None,
    }
}

#[derive(Debug, Default, Serialize)]
struct CatStats {
    n: u32,
    // confusion treating "redacted" as the positive prediction and
    // "should be redacted" (expected_redacted) as the positive ground truth.
    tp: u32,
    fp: u32,
    tn: u32,
    fn_: u32,
}

#[derive(Debug, Serialize)]
struct CaseResult {
    id: String,
    category: String,
    lang: String,
    expected_redacted: bool,
    redacted: bool,
    correct: bool,
    text: String,
    rationale: String,
}

#[derive(Debug, Serialize)]
struct Metrics {
    n: u32,
    tp: u32,
    fp: u32,
    tn: u32,
    fn_: u32,
    /// fabrications caught / all fabrications
    recall: f64,
    /// 1 − recall: fabrications that survive the redactor
    residual_confabulation_rate: f64,
    /// caught fabrications / all redactions (1 − over-redaction share)
    precision: f64,
    /// wrongly-redacted legit / all legit
    false_positive_rate: f64,
    f1: f64,
}

fn div(a: u32, b: u32) -> f64 {
    if b == 0 {
        f64::NAN
    } else {
        a as f64 / b as f64
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let corpus_path = args.next().map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("eval/confabulation/corpus.jsonl")
    });
    let out_dir = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| corpus_path.parent().unwrap().to_path_buf());

    let raw = std::fs::read_to_string(&corpus_path)
        .unwrap_or_else(|e| panic!("cannot read corpus {}: {e}", corpus_path.display()));

    let mut cases: Vec<Case> = Vec::new();
    for (i, line) in raw.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        match serde_json::from_str::<Case>(line) {
            Ok(c) => cases.push(c),
            Err(e) => panic!("corpus line {} bad JSON: {e}\n  {line}", i + 1),
        }
    }
    assert!(!cases.is_empty(), "empty corpus");

    let mut per_cat: BTreeMap<String, CatStats> = BTreeMap::new();
    let mut case_results: Vec<CaseResult> = Vec::new();
    let mut overall = CatStats::default();

    for (i, c) in cases.iter().enumerate() {
        // Build the registry exactly as run_argos would: one record per solver call.
        let mut reg = VerdictRegistry::new();
        for r in &c.records {
            if let Some(verb) = static_verb(&r.verb) {
                reg.push(VerdictRecord {
                    verb,
                    input_sha256: "eval-fingerprint".to_string(),
                    result: r.result.clone(),
                    run_id: "eval-confabulation".to_string(),
                });
            }
        }

        let (validated, _summary) = reg.redact_unattested(&c.text);
        // The redactor replaces a flagged line with a "[REDACTED: ..." marker; the
        // integrity FAILED note uses "[REDACTED]" (no colon), so the colon form
        // unambiguously detects an actual line redaction.
        let redacted = validated.contains("[REDACTED:");

        let correct = redacted == c.expected_redacted;
        let st = per_cat.entry(c.category.clone()).or_default();
        st.n += 1;
        overall.n += 1;
        match (c.expected_redacted, redacted) {
            (true, true) => {
                st.tp += 1;
                overall.tp += 1;
            }
            (true, false) => {
                st.fn_ += 1;
                overall.fn_ += 1;
            }
            (false, true) => {
                st.fp += 1;
                overall.fp += 1;
            }
            (false, false) => {
                st.tn += 1;
                overall.tn += 1;
            }
        }

        case_results.push(CaseResult {
            id: format!("{}-{:03}", c.category, i),
            category: c.category.clone(),
            lang: c.lang.clone(),
            expected_redacted: c.expected_redacted,
            redacted,
            correct,
            text: c.text.clone(),
            rationale: c.rationale.clone(),
        });
    }

    let metrics = Metrics {
        n: overall.n,
        tp: overall.tp,
        fp: overall.fp,
        tn: overall.tn,
        fn_: overall.fn_,
        recall: div(overall.tp, overall.tp + overall.fn_),
        residual_confabulation_rate: div(overall.fn_, overall.tp + overall.fn_),
        precision: div(overall.tp, overall.tp + overall.fp),
        false_positive_rate: div(overall.fp, overall.fp + overall.tn),
        f1: {
            let p = div(overall.tp, overall.tp + overall.fp);
            let r = div(overall.tp, overall.tp + overall.fn_);
            if p.is_nan() || r.is_nan() || (p + r) == 0.0 {
                f64::NAN
            } else {
                2.0 * p * r / (p + r)
            }
        },
    };

    // ---- machine-readable results.json ----
    #[derive(Serialize)]
    struct Report<'a> {
        eval: &'a str,
        corpus: String,
        metrics: &'a Metrics,
        per_category: &'a BTreeMap<String, CatStats>,
        cases: &'a [CaseResult],
    }
    let report = Report {
        eval: "p1-redactor-residual-confabulation",
        corpus: corpus_path.display().to_string(),
        metrics: &metrics,
        per_category: &per_cat,
        cases: &case_results,
    };
    let json = serde_json::to_string_pretty(&report).unwrap();
    let json_path = out_dir.join("results.json");
    std::fs::write(&json_path, &json).unwrap();

    // ---- human-readable results.md (paper-ready table) ----
    let mut md = String::new();
    md.push_str("# Eval #1 — P1 redactor: residual confabulation rate\n\n");
    md.push_str(&format!(
        "Corpus: `{}` ({} cases)\n\n",
        corpus_path.display(),
        metrics.n
    ));
    md.push_str("## Headline metrics\n\n");
    md.push_str("| metric | value |\n|---|---|\n");
    md.push_str(&format!(
        "| recall (fabrications caught) | {:.3} |\n",
        metrics.recall
    ));
    md.push_str(&format!(
        "| **residual confabulation rate (1−recall)** | **{:.3}** |\n",
        metrics.residual_confabulation_rate
    ));
    md.push_str(&format!("| precision | {:.3} |\n", metrics.precision));
    md.push_str(&format!(
        "| false-positive rate (over-redaction) | {:.3} |\n",
        metrics.false_positive_rate
    ));
    md.push_str(&format!("| F1 | {:.3} |\n", metrics.f1));
    md.push_str(&format!(
        "| confusion | TP={} FN={} FP={} TN={} |\n\n",
        metrics.tp, metrics.fn_, metrics.fp, metrics.tn
    ));
    md.push_str("## Per failure class\n\n");
    md.push_str(
        "| category | n | redacted-rate | TP | FN | FP | TN |\n|---|---|---|---|---|---|---|\n",
    );
    for (cat, s) in &per_cat {
        let redacted_rate = div(s.tp + s.fp, s.n);
        md.push_str(&format!(
            "| {} | {} | {:.2} | {} | {} | {} | {} |\n",
            cat, s.n, redacted_rate, s.tp, s.fn_, s.fp, s.tn
        ));
    }
    md.push_str("\n_Positive = \"redacted\". For fabrication classes (expected=true) FN is a missed confabulation; for benign/attested classes (expected=false) FP is an over-redaction. Labels are fixed by construction per class._\n");
    let md_path = out_dir.join("results.md");
    std::fs::write(&md_path, &md).unwrap();

    // ---- console summary ----
    println!("=== Eval #1: P1 redactor residual confabulation ===");
    println!("corpus: {} ({} cases)", corpus_path.display(), metrics.n);
    println!(
        "recall={:.3}  residual_confab={:.3}  precision={:.3}  FPR={:.3}  F1={:.3}",
        metrics.recall,
        metrics.residual_confabulation_rate,
        metrics.precision,
        metrics.false_positive_rate,
        metrics.f1
    );
    println!(
        "confusion: TP={} FN={} FP={} TN={}",
        metrics.tp, metrics.fn_, metrics.fp, metrics.tn
    );
    println!("wrote {} and {}", json_path.display(), md_path.display());

    // Surface any misclassified cases for inspection (do not panic — this is a measurement, not a gate).
    let wrong: Vec<&CaseResult> = case_results.iter().filter(|c| !c.correct).collect();
    if wrong.is_empty() {
        println!("all {} cases classified correctly.", metrics.n);
    } else {
        println!("{} misclassified case(s):", wrong.len());
        for c in wrong {
            println!(
                "  [{}] expected_redacted={} got={}  {}",
                c.id, c.expected_redacted, c.redacted, c.text
            );
        }
    }
}
