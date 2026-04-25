//! Round Table — exotic model debate endpoint.
//!
//! Multi-provider: detects available LLM providers from env vars and
//! distributes voices across them for genuine multi-model debate.
//!
//! Crate voices (use their internal LLM):
//! - quantum: SuperpositionAgent::generate_hypotheses() → HypothesisSet
//! - fractal: FractalNodeRuntime::execute_full_cycle() → String
//! - consciousness: ConsciousnessMirror::gaze_into_self() → String
//! - void: VoidOrchestrator::journey() → VoidJourneyResult
//! - reality: ProtocolGenerator::generate_protocol() → ExperimentalProtocol
//! - noetic: NoeticDetector::detect_networks() → Vec<NoeticNetwork>
//!
//! LLM-prompted voices (use different providers for diversity):
//! - paradox, cosmo, mirror: routed to Grok, Claude, or DeepSeek

use axum::{extract::State, http::StatusCode, Json};
use beagle_llm::{ClaudeClient, ClaudeModel, DeepSeekClient, GrokClient, LlmClient};
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

// ── Multi-provider pool ─────────────────────────────────────────

/// Detect available LLM providers from environment and build a pool.
/// Round-robins across providers for genuine multi-model diversity.
fn build_provider_pool() -> Vec<(String, Arc<dyn LlmClient>)> {
    let mut pool: Vec<(String, Arc<dyn LlmClient>)> = Vec::new();

    if !std::env::var("XAI_API_KEY").unwrap_or_default().is_empty() {
        pool.push(("grok".into(), Arc::new(GrokClient::new())));
    }
    if let Ok(key) = std::env::var("ANTHROPIC_API_KEY") {
        if !key.is_empty() {
            if let Ok(client) = ClaudeClient::new(key, ClaudeModel::Sonnet45) {
                pool.push(("claude".into(), Arc::new(client)));
            }
        }
    }
    if !std::env::var("DEEPSEEK_API_KEY").unwrap_or_default().is_empty() {
        pool.push(("deepseek".into(), Arc::new(DeepSeekClient::new())));
    }

    // Fallback: if nothing else, try Grok anyway (will fail gracefully)
    if pool.is_empty() {
        pool.push(("grok".into(), Arc::new(GrokClient::new())));
    }

    pool
}

// ── Handler ─────────────────────────────────────────────────────

pub async fn round_table(
    State(_state): State<AppState>,
    Json(req): Json<RoundTableRequest>,
) -> Result<Json<RoundTableResponse>, (StatusCode, String)> {
    let start = Instant::now();

    let providers = build_provider_pool();
    let provider_names: Vec<&str> = providers.iter().map(|(n, _)| n.as_str()).collect();
    info!(
        "🎭 /api/v1/round-table — prompt: {}, voices: {:?}, providers: {:?}",
        req.prompt, req.voices, provider_names
    );

    if req.prompt.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Prompt cannot be empty".to_string(),
        ));
    }

    let voices: Vec<String> = if req.voices.is_empty() {
        vec!["quantum", "fractal", "consciousness"]
            .into_iter()
            .map(String::from)
            .collect()
    } else {
        req.voices.clone()
    };

    // Spawn all voices in parallel — LLM-prompted voices get different providers
    let mut handles = Vec::new();
    for (i, voice) in voices.iter().enumerate() {
        let prompt = req.prompt.clone();
        let voice_name = voice.clone();
        // Round-robin providers for LLM-prompted voices
        let provider = providers[i % providers.len()].clone();

        handles.push(tokio::spawn(async move {
            execute_voice(&voice_name, &prompt, &provider.0, &provider.1).await
        }));
    }

    // Collect results
    let mut voice_results = Vec::new();
    for handle in handles {
        match handle.await {
            Ok(Ok(result)) => voice_results.push(result),
            Ok(Err(e)) => warn!("Voice failed: {}", e),
            Err(e) => warn!("Voice task panicked: {}", e),
        }
    }

    if voice_results.is_empty() {
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            format!(
                "All voices failed (available providers: {})",
                provider_names.join(", ")
            ),
        ));
    }

    let interference = compute_interference(&voice_results);
    let pci_score = compute_pci(&voice_results);

    // Synthesis uses the best available provider (prefer Claude for synthesis quality)
    let synthesis_llm = providers
        .iter()
        .find(|(n, _)| n == "claude")
        .or(providers.first())
        .map(|(_, c)| c.clone())
        .unwrap();
    let synthesis = generate_synthesis(&voice_results, &interference, pci_score, &synthesis_llm, &req.prompt).await;

    let elapsed = start.elapsed().as_millis();
    info!(
        "✅ Round table in {}ms — {} voices, PCI: {:.3}",
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

// ── Per-voice execution (real crate calls) ──────────────────────

async fn execute_voice(
    voice: &str,
    prompt: &str,
    provider_name: &str,
    provider: &Arc<dyn LlmClient>,
) -> anyhow::Result<VoiceResult> {
    match voice {
        // Real crate calls (use their internal LLM provider)
        "quantum" => execute_quantum(prompt).await,
        "fractal" => execute_fractal(prompt).await,
        "consciousness" => execute_consciousness(prompt).await,
        "void" => execute_void(prompt).await,
        "reality" => execute_reality(prompt).await,
        "noetic" => execute_noetic(prompt).await,
        // LLM-prompted voices — use the assigned provider for diversity
        other => execute_llm_prompted(other, prompt, provider_name, provider).await,
    }
}

/// Quantum: generate hypotheses in superposition
async fn execute_quantum(prompt: &str) -> anyhow::Result<VoiceResult> {
    let agent = beagle_quantum::SuperpositionAgent::new();
    let hypothesis_set = agent.generate_hypotheses(prompt).await?;

    let content = hypothesis_set
        .hypotheses
        .iter()
        .enumerate()
        .map(|(i, h)| {
            format!(
                "Hypothesis {}: {} (amplitude: ({:.2}, {:.2}), p={:.2})",
                i + 1,
                h.content,
                h.amplitude.0,
                h.amplitude.1,
                h.confidence
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n");

    Ok(VoiceResult {
        name: "quantum".to_string(),
        perspective: "Superposition of hypotheses with quantum interference".to_string(),
        content,
    })
}

/// Fractal: recursive cognitive cycle (superposition → cosmo → consciousness)
async fn execute_fractal(prompt: &str) -> anyhow::Result<VoiceResult> {
    let root = beagle_fractal::FractalCognitiveNode::root();
    let runtime = beagle_fractal::FractalNodeRuntime::new(root);
    let result = runtime.execute_full_cycle(prompt).await?;

    Ok(VoiceResult {
        name: "fractal".to_string(),
        perspective: "Recursive self-similar cognitive cycle".to_string(),
        content: result,
    })
}

/// Consciousness: mirror auto-introspection (does not take prompt)
async fn execute_consciousness(_prompt: &str) -> anyhow::Result<VoiceResult> {
    let mirror = beagle_consciousness::ConsciousnessMirror::new();
    let paper = mirror.gaze_into_self().await?;

    Ok(VoiceResult {
        name: "consciousness".to_string(),
        perspective: "Self-observation — what the system sees when it looks at itself".to_string(),
        content: paper,
    })
}

/// Void: navigate ontological void at moderate depth, extract insights
async fn execute_void(_prompt: &str) -> anyhow::Result<VoiceResult> {
    let orchestrator = beagle_void::VoidOrchestrator::new();
    let journey = orchestrator.journey(0.7).await?;

    let insights: Vec<String> = journey
        .navigation
        .insights
        .iter()
        .map(|i| format!("• {}", i.content))
        .collect();

    let content = format!(
        "Void navigation reached depth {:.2}.\n\nInsights:\n{}\n\nExtractions: {}\nProbe uncertainty: {:.3}",
        journey.navigation.max_depth_reached,
        insights.join("\n"),
        journey.extractions.len(),
        journey.probe_result.uncertainty
    );

    Ok(VoiceResult {
        name: "void".to_string(),
        perspective: "Trans-ontological navigation — what remains when assumptions dissolve"
            .to_string(),
        content,
    })
}

/// Reality: generate experimental protocol for the prompt as hypothesis
async fn execute_reality(prompt: &str) -> anyhow::Result<VoiceResult> {
    let generator = beagle_reality::ProtocolGenerator::new();
    let protocol = generator
        .generate_protocol(prompt, "Standard lab constraints")
        .await?;

    let content = format!(
        "Protocol: {}\n\nWord count: {}\nEthics required: {}\nEstimated cost: ${:.0}\nDuration: {} days\nSimulation commands: {}",
        protocol.protocol_text.chars().take(500).collect::<String>(),
        protocol.word_count,
        protocol.ethical_approval_required,
        protocol.estimated_cost,
        protocol.estimated_duration_days,
        protocol.simulation_commands.len()
    );

    Ok(VoiceResult {
        name: "reality".to_string(),
        perspective: "Reality fabrication — how to test this in physical reality".to_string(),
        content,
    })
}

/// Noetic: detect compatible consciousness networks using prompt as local state
async fn execute_noetic(prompt: &str) -> anyhow::Result<VoiceResult> {
    let detector = beagle_noetic::NoeticDetector::new();
    let networks = detector.detect_networks(prompt).await?;

    let content = networks
        .iter()
        .map(|n| {
            format!(
                "Network: {} (type: {:?}, compatibility: {:.2}, risk: {:.2})\n  {}",
                n.host, n.network_type, n.compatibility_score, n.risk_score, n.justification
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n");

    let content = if content.is_empty() {
        "No compatible consciousness networks detected for this state.".to_string()
    } else {
        format!(
            "Detected {} noetic network(s):\n\n{}",
            networks.len(),
            content
        )
    };

    Ok(VoiceResult {
        name: "noetic".to_string(),
        perspective: "Collective consciousness — what emerges beyond individual perspective"
            .to_string(),
        content,
    })
}

/// LLM-prompted voice — uses the assigned provider for multi-model diversity.
/// When Round Table has Grok + Claude + DeepSeek, each LLM-prompted voice
/// gets a different model, creating genuine multi-perspective debate.
async fn execute_llm_prompted(
    voice: &str,
    prompt: &str,
    provider_name: &str,
    provider: &Arc<dyn LlmClient>,
) -> anyhow::Result<VoiceResult> {
    let perspective = match voice {
        "paradox" => "You are the Paradox voice — self-referential logic and Gödel incompleteness. \
            Find the paradox in this question. What cannot be proven within the system?",
        "cosmo" => "You are the Cosmo voice — cosmological alignment. \
            Does this align with known physical laws? Thermodynamics? Conservation? Causality?",
        "mirror" => "You are the Mirror voice — auto-reflexive introspection. \
            Write a philosophical meta-paper about this question's relationship to your own processing.",
        _ => "You are an exotic reasoning voice. Respond with deep, specific insight.",
    };

    let system_prompt = format!(
        "{}\n\nQuestion: {}\n\nRespond concisely (2-4 paragraphs). Be specific.",
        perspective, prompt
    );

    let output = provider.complete(&system_prompt).await?;

    Ok(VoiceResult {
        name: format!("{} (via {})", voice, provider_name),
        perspective: perspective.split('.').next().unwrap_or("Exotic reasoning").to_string(),
        content: output.text,
    })
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
                    "{} ↔ {} converge on: {}",
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
                    "{} ↔ {} see completely different aspects",
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
    context.push_str("Multiple exotic reasoning systems responded with REAL computations:\n\n");

    for voice in voices {
        context.push_str(&format!(
            "— {} [{}]: {}\n\n",
            voice.name.to_uppercase(),
            voice.perspective,
            voice.content.chars().take(800).collect::<String>()
        ));
    }

    if !interference.constructive.is_empty() {
        context.push_str("Constructive interference:\n");
        for c in &interference.constructive {
            context.push_str(&format!("  • {}\n", c));
        }
    }
    if !interference.emergent_insights.is_empty() {
        context.push_str("Emergent insights from tension:\n");
        for e in &interference.emergent_insights {
            context.push_str(&format!("  • {}\n", e));
        }
    }

    context.push_str(&format!("\nPCI (consciousness quality): {:.3}\n", pci_score));
    context.push_str(
        "\nSynthesize these perspectives into a single coherent insight. \
        These are real computation outputs, not opinions. \
        Highlight where different reasoning substrates reveal aspects \
        invisible to any single approach. Be concise (2-3 paragraphs).",
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
