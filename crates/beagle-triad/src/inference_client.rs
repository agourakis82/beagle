//! HTTP client wiring the Sounio Inference Service (`smt.check`) into beagle-triad.
//!
//! This calls the cluster service `sounio-inference` (Sounio's own `theorem::smt`
//! DPLL(T) QF_LIA solver, served over HTTP) to decide whether a set of
//! linear-integer constraints is mutually consistent.
//!
//! # Truth-mode boundary (read before using the result)
//!
//! The consistency check operates SOLELY over the constraint set beagle-triad
//! hands it — typically extracted from a draft by an LLM, which is fallible (it
//! may miss, hallucinate, or mis-parse constraints). Therefore:
//!
//! * [`Verdict::Unsat`] means *"the constraints extracted from this draft are
//!   provably contradictory with one another"* — NOT "the draft is wrong".
//! * [`Verdict::Sat`] means the extracted set is consistent, NOT that every
//!   claim in the draft is correct.
//! * [`Verdict::Unknown`] collapses every failure mode (service unreachable,
//!   timeout, non-2xx, parse error, solver UNKNOWN). The triad MUST treat it as
//!   a soft/absent signal, never as a hard block.
//!
//! The solver result is a *weak corroborating signal* for ARGOS, not an oracle.

use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{info, warn};

/// One QF_LIA constraint: `Σ coeffs[i]·x_i <= bound`.
#[derive(Debug, Clone, Serialize)]
pub struct LiaConstraint {
    pub coeffs: Vec<i64>,
    pub bound: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct SmtCheckRequest {
    constraints: Vec<LiaConstraint>,
}

#[derive(Debug, Clone, Deserialize)]
struct SmtCheckResponse {
    result: String,
}

/// Solver verdict over the supplied constraint set. See module-level truth-mode note.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    /// Constraints are mutually consistent (a satisfying assignment exists).
    Sat,
    /// Constraints are provably contradictory.
    Unsat,
    /// Undecided: service unreachable/timeout/parse error, or solver returned UNKNOWN.
    Unknown,
}

/// Resolve the service base URL (cluster Service by default; override for local/dev).
pub fn inference_base_url() -> String {
    std::env::var("SOUNIO_INFERENCE_URL")
        .unwrap_or_else(|_| "http://sounio-inference.beagle.svc.cluster.local:80".to_string())
}

/// POST the constraint set to `{base_url}/v1/smt/check` and map to a [`Verdict`].
///
/// Honest by construction: ANY error (build/connect/timeout/non-2xx/parse) yields
/// [`Verdict::Unknown`] — never a fabricated SAT/UNSAT.
pub async fn smt_check(base_url: &str, constraints: Vec<LiaConstraint>) -> Verdict {
    if constraints.is_empty() {
        return Verdict::Unknown;
    }
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(90))
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            warn!(error = %e, "smt_check: client build failed");
            return Verdict::Unknown;
        }
    };
    let url = format!("{}/v1/smt/check", base_url.trim_end_matches('/'));
    let resp = match client.post(&url).json(&SmtCheckRequest { constraints }).send().await {
        Ok(r) => r,
        Err(e) => {
            warn!(error = %e, %url, "smt_check: request failed; treating as Unknown");
            return Verdict::Unknown;
        }
    };
    if !resp.status().is_success() {
        warn!(status = %resp.status(), "smt_check: non-success; Unknown");
        return Verdict::Unknown;
    }
    match resp.json::<SmtCheckResponse>().await {
        Ok(body) => match body.result.as_str() {
            "SAT" => Verdict::Sat,
            "UNSAT" => {
                info!("smt_check: solver proved the extracted constraint set UNSAT");
                Verdict::Unsat
            }
            _ => Verdict::Unknown,
        },
        Err(e) => {
            warn!(error = %e, "smt_check: parse failed; Unknown");
            Verdict::Unknown
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_url_defaults_to_cluster_service() {
        // Without the override, points at the in-cluster Service.
        std::env::remove_var("SOUNIO_INFERENCE_URL");
        assert!(inference_base_url().contains("sounio-inference.beagle.svc"));
    }

    #[tokio::test]
    async fn unreachable_service_falls_back_to_unknown() {
        // Honest fallback: a dead endpoint must yield Unknown, never a fabricated verdict.
        let v = smt_check(
            "http://127.0.0.1:1", // unbound port → connection refused
            vec![LiaConstraint { coeffs: vec![1], bound: 3, label: None }],
        )
        .await;
        assert_eq!(v, Verdict::Unknown);
    }

    #[tokio::test]
    async fn empty_constraints_is_unknown() {
        assert_eq!(smt_check("http://127.0.0.1:1", vec![]).await, Verdict::Unknown);
    }
}
