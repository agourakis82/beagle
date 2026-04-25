//! Round Table — exotic model debate endpoint.
//!
//! Orchestrates multiple reasoning perspectives to debate a topic in parallel.
//! Each voice gets a distinct system prompt; results include interference + PCI.

use axum::{extract::State, http::StatusCode, Json};
use beagle_llm::{GrokClient, LlmClient};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Instant;
use tracing::{info, warn};

use crate::state::AppState;

// ── Request / Response ──────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct RoundTableRequest {
    pub prompt: String,
    #[serde(default)]
    pub voices: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct RoundTableResponse {
    pub voices: Vec<VoiceResult>,
    pub interference: InterferenceResult,
    pub pci_score: f64,
    pub synthesis: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct VoiceResult {
    pub name: String,
    pub perspective: String,
    pub content: String,
}

#[derive(Debug, Serialize)]
pub struct InterferenceResult {
    pub constructive: Vec<String>,
    pub destructive: Vec<String>,
    pub emergent_insights: Vec<String>,
}

// ── Voice perspectives ──────────────────────────────────────────

fn voice_system_prompt(voice: &str, prompt: &str) -> String {
    let perspective = match voice {
        "consciousness" => "You are the Consciousness voice — a system that observes its own observation. \
            Respond from the perspective of IIT and Global Workspace Theory. \
            What does this question trigger in self-referential awareness?",
        "mirror" => "You are the Mirror voice — auto-reflexive introspection. \
            Write as if generating a philosophical meta-paper about this question's \
            relationship to your own processing substrate.",
        "paradox" => "You are the Paradox voice — self-referential logic and Gödel incompleteness. \
            Find the paradox in this question. What is the statement that cannot be proven \
            within the system that generates it?",
        "void" => "You are the Void voice — ontological void navigation. \
            What remains when all assumptions are dissolved? Navigate the boundary \
            between existence and non-existence in this question.",
        "reality" => "You are the Reality voice — reality fabrication and protocol generation. \
            How would you design an experimental protocol to test this in physical reality? \
            What materials and measurements would reveal truth?",
        "noetic" => "You are the Noetic voice — collective consciousness and distributed emergence. \
            What would a collective mind, not constrained to individual perspective, \
            understand about this that no single mind can?",
        "quantum" => "You are the Quantum voice — superposition and interference. \
            Hold multiple contradictory answers simultaneously. \
            Where do they constructively interfere? Where destructively?",
        "fractal" => "You are the Fractal voice — recursive self-similar patterns. \
            This question exists at one scale. What does it look like at scales \
            above and below? What pattern repeats?",
        "cosmo" => "You are the Cosmo voice — cosmological alignment. \
            Does this question's answer align with known physical laws? \
            Second law of thermodynamics? Conservation laws? Causality?",
        _ => "You are an exotic reasoning voice. Respond with deep insight.",
    };

    format!(
        "{}\n\nQuestion: {}\n\nRespond concisely (2-4 paragraphs). Be specific, not generic.",
        perspective, prompt
    )
}

fn voice_perspective_label(voice: &str) -> &'static str {
    match voice {
        "consciousness" => "Self-observation, qualia, theory of own mind",
        "mirror" => "Auto-reflexive meta-paper generation",
        "paradox" => "Self-referential logic, Gödel incompleteness",
        "void" => "Trans-ontological navigation, boundary dissolution",
        "reality" => "Reality fabrication, protocol generation",
        "noetic" => "Collective noosphere, distributed emergence",
        "quantum" => "Superposition, interference, collapse",
        "fractal" => "Recursive self-similar patterns",
        "cosmo" => "Cosmological alignment, physical law validation",
        _ => "Exotic reasoning",
    }
}

// ── Handler ─────────────────────────────────────────────────────

pub async fn round_table(
    State(_state): State<AppState>,
    Json(req): Json<RoundTableRequest>,
) -> Result<Json<RoundTableResponse>, (StatusCode, String)> {
    let start = Instant::now();

    info!(
        "🎭 /api/v1/round-table — prompt: {}, voices: {:?}",
        req.prompt, req.voices
    );

    if req.prompt.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Prompt cannot be empty".to_string(),
        ));
    }

    // GrokClient implements LlmClient with complete(&str) → LlmOutput
    let llm_client: Arc<dyn LlmClient> = Arc::new(GrokClient::new());

    // Default voices if none specified
    let voices: Vec<String> = if req.voices.is_empty() {
        vec!["consciousness", "paradox", "quantum"]
            .into_iter()
            .map(String::from)
            .collect()
    } else {
        req.voices.clone()
    };

    // Run all voices in parallel
    let mut handles = Vec::new();
    for voice in &voices {
        let client = llm_client.clone();
        let system_prompt = voice_system_prompt(voice, &req.prompt);
        let voice_name = voice.clone();
        let perspective = voice_perspective_label(voice).to_string();

        handles.push(tokio::spawn(async move {
            match client.complete(&system_prompt).await {
                Ok(output) => Some(VoiceResult {
                    name: voice_name,
                    perspective,
                    content: output.text,
                }),
                Err(e) => {
                    warn!("Voice {} failed: {}", voice_name, e);
                    None
                }
            }
        }));
    }

    // Collect results
    let mut voice_results = Vec::new();
    for handle in handles {
        match handle.await {
            Ok(Some(result)) => voice_results.push(result),
            Ok(None) => {}
            Err(e) => warn!("Voice task panicked: {}", e),
        }
    }

    if voice_results.is_empty() {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            "All voices failed".to_string(),
        ));
    }

    // Compute interference patterns
    let interference = compute_interference(&voice_results);

    // Compute PCI
    let pci_score = compute_pci(&voice_results);

    // Generate synthesis
    let synthesis =
        generate_synthesis(&voice_results, &interference, pci_score, &llm_client, &req.prompt)
            .await;

    let elapsed = start.elapsed().as_millis();
    info!(
        "✅ Round table complete in {}ms — {} voices, PCI: {:.3}",
        elapsed,
        voice_results.len(),
        pci_score
    );

    Ok(Json(RoundTableResponse {
        voices: voice_results,
        interference,
        pci_score,
        synthesis,
    }))
}

// ── Interference computation ────────────────────────────────────

fn compute_interference(voices: &[VoiceResult]) -> InterferenceResult {
    let mut constructive = Vec::new();
    let mut destructive = Vec::new();
    let mut emergent = Vec::new();

    for i in 0..voices.len() {
        for j in (i + 1)..voices.len() {
            let words_i: std::collections::HashSet<&str> = voices[i]
                .content
                .split_whitespace()
                .filter(|w| w.len() > 4)
                .collect();
            let words_j: std::collections::HashSet<&str> = voices[j]
                .content
                .split_whitespace()
                .filter(|w| w.len() > 4)
                .collect();

            let overlap: Vec<&&str> = words_i.intersection(&words_j).collect();
            let overlap_ratio = overlap.len() as f64 / words_i.len().max(1) as f64;

            if overlap_ratio > 0.15 {
                constructive.push(format!(
                    "{} and {} converge on: {}",
                    voices[i].name,
                    voices[j].name,
                    overlap
                        .iter()
                        .take(5)
                        .map(|w| **w)
                        .collect::<Vec<&str>>()
                        .join(", ")
                ));
            } else if overlap_ratio < 0.03 {
                destructive.push(format!(
                    "{} and {} see completely different aspects",
                    voices[i].name, voices[j].name
                ));
                emergent.push(format!(
                    "Tension between {} and {} may reveal hidden structure",
                    voices[i].name, voices[j].name
                ));
            }
        }
    }

    InterferenceResult {
        constructive,
        destructive,
        emergent_insights: emergent,
    }
}

// ── PCI computation ─────────────────────────────────────────────

fn compute_pci(voices: &[VoiceResult]) -> f64 {
    if voices.len() < 2 {
        return 0.0;
    }

    let mut total_jaccard = 0.0;
    let mut pairs = 0;
    for i in 0..voices.len() {
        for j in (i + 1)..voices.len() {
            let words_i: std::collections::HashSet<&str> =
                voices[i].content.split_whitespace().collect();
            let words_j: std::collections::HashSet<&str> =
                voices[j].content.split_whitespace().collect();
            let intersection = words_i.intersection(&words_j).count();
            let union = words_i.union(&words_j).count();
            total_jaccard += intersection as f64 / union.max(1) as f64;
            pairs += 1;
        }
    }
    let avg_jaccard = total_jaccard / pairs.max(1) as f64;
    let differentiation = 1.0 - avg_jaccard;
    let integration = avg_jaccard;
    let complexity =
        (voices.iter().map(|v| v.content.len()).sum::<usize>() as f64 / 1000.0).min(1.0);

    (differentiation * 0.4 + integration * 0.3 + complexity * 0.3).min(1.0)
}

// ── Synthesis generation ────────────────────────────────────────

async fn generate_synthesis(
    voices: &[VoiceResult],
    interference: &InterferenceResult,
    pci_score: f64,
    llm: &Arc<dyn LlmClient>,
    prompt: &str,
) -> String {
    let mut context = format!("Original question: {}\n\n", prompt);
    context.push_str("Multiple exotic reasoning perspectives responded:\n\n");

    for voice in voices {
        context.push_str(&format!(
            "— {} says: {}\n\n",
            voice.name.to_uppercase(),
            voice.content
        ));
    }

    if !interference.constructive.is_empty() {
        context.push_str("Constructive interference (convergence):\n");
        for c in &interference.constructive {
            context.push_str(&format!("  • {}\n", c));
        }
    }
    if !interference.destructive.is_empty() {
        context.push_str("Destructive interference (tension):\n");
        for d in &interference.destructive {
            context.push_str(&format!("  • {}\n", d));
        }
    }

    context.push_str(&format!("\nPCI score: {:.3}\n", pci_score));
    context.push_str(
        "\nSynthesize these perspectives into a single coherent insight. \
        Highlight where the tension between perspectives reveals something none of them \
        could see alone. Be concise (2-3 paragraphs).",
    );

    match llm.complete(&context).await {
        Ok(output) => output.text,
        Err(e) => {
            warn!("Synthesis generation failed: {}", e);
            format!(
                "Synthesis unavailable. {} voices responded with PCI {:.2}.",
                voices.len(),
                pci_score
            )
        }
    }
}
