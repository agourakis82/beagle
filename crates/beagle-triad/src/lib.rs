//! beagle-triad - Honest AI Triad
//!
//! Sistema adversarial de revisão:
//! - ATHENA: agente "literatura" (pontos fortes/fracos, sugestões)
//! - HERMES: revisor (reescreve mantendo estilo/autoria)
//! - ARGOS: crítico (falhas lógicas, claims sem suporte)
//! - Juiz final: arbitra versões finais

use beagle_core::BeagleContext;
use beagle_llm::{stats::LlmCallsStats as LlmCallsStatsLLM, ProviderTier, RequestMeta};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use tracing::{info, warn};

/// HTTP client for the Sounio Inference Service (`smt.check`) — lets the triad
/// ask Sounio's own DPLL(T) solver whether an extracted constraint set is
/// consistent. See the module docs for the truth-mode boundary.
pub mod inference_client;

/// Fingerprints the serialized input artifact that was handed to a Sounio verb.
/// Input is the raw string rendered just before the HTTP call (the constraint /
/// DSep / GUM / theorem JSON). Returns hex SHA-256.
fn artifact_sha256(artifact_json: &str) -> String {
    let mut h = Sha256::new();
    h.update(artifact_json.as_bytes());
    format!("{:x}", h.finalize())
}

/// Immutable record of ONE solver call that actually executed in this run.
///
/// The record is created INSIDE each traced `*_claim_check` function, at the exact
/// point the HTTP response is received — not from the markdown text ARGOS sees.
/// This makes it structurally impossible to have a [`VerdictRecord`] for a call
/// that never happened.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerdictRecord {
    /// Sounio verb: one of `smt.check`, `causal.dsep`, `gum.propagate`, `theorem.prove`.
    pub verb: &'static str,
    /// SHA-256 hex of the JSON artifact handed to the solver (fingerprints the input).
    /// Empty when the call never reached the solver (gate-off / extraction-empty).
    pub input_sha256: String,
    /// The solver verdict string as returned, or an abstain marker: `UNSAT`, `SAT`,
    /// `UNKNOWN`, `PROVED`, `INVALID`, `d-separated`, `d-connected`, `gum-understated`,
    /// `gum-ok`, `gate-off`, `extraction-empty`, `validation-rejected`, `transport-error`.
    pub result: String,
    /// Copied from the enclosing `run_argos` call for cross-referencing.
    pub run_id: String,
}

/// Per-run registry of [`VerdictRecord`]s, one per enabled solver gate.
///
/// Always populated before the ARGOS LLM call is issued, so the post-hoc
/// validator ([`VerdictRegistry::redact_unattested`]) has the ground truth when
/// it scans ARGOS's output. The registry is local to a single `run_argos` call
/// and never persisted, so stale records from a previous run can never validate
/// current output.
#[derive(Debug, Default)]
pub struct VerdictRegistry {
    records: Vec<VerdictRecord>,
}

impl VerdictRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Append a record. Called once per solver gate, regardless of verdict.
    pub fn push(&mut self, r: VerdictRecord) {
        self.records.push(r);
    }

    /// Number of records currently held.
    pub fn len(&self) -> usize {
        self.records.len()
    }

    /// True when no records have been pushed.
    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    /// Returns the record for `verb` if exactly one exists (linear scan; only four
    /// verbs, so O(4) is fine). Ambiguous (multiple) matches return `None`.
    pub fn lookup(&self, verb: &str) -> Option<&VerdictRecord> {
        let mut hits = self.records.iter().filter(|r| r.verb == verb);
        let first = hits.next()?;
        if hits.next().is_some() {
            return None; // ambiguous — shouldn't happen (one record per verb)
        }
        Some(first)
    }

    /// Post-hoc validator: scans `argos_text` for solver-attribution patterns
    /// (verb name + verdict keyword on the SAME line) and REDACTS any attribution
    /// that has no matching attested [`VerdictRecord`].
    ///
    /// A line is flagged when it names a solver verb AND a verdict keyword. The
    /// attribution is allowed through only when a [`VerdictRecord`] for that verb
    /// exists AND its `result` is not an abstain/gate marker (`gate-off`,
    /// `extraction-empty`, `validation-rejected`, `transport-error`). Otherwise the
    /// line is replaced with a `[REDACTED ...]` marker. A machine-checked integrity
    /// note is appended at the bottom.
    ///
    /// Granularity is line-level (conservative; avoids false positives across
    /// multi-sentence prose). The ARGOS verification blocks always put verb+verdict
    /// on the same line, so attested attributions pass unchanged.
    ///
    /// Returns the validated (possibly redacted) text plus a short summary line.
    pub fn redact_unattested(&self, argos_text: &str) -> (String, String) {
        const VERBS: &[&str] = &["smt.check", "causal.dsep", "gum.propagate", "theorem.prove"];
        const VERDICT_WORDS: &[&str] = &[
            "unsat",
            "sat",
            "proved",
            "unknown",
            "invalid",
            "d-separ",
            "d-conect",
            "d-connect",
        ];

        let mut redactions: Vec<String> = Vec::new();
        let mut out_lines: Vec<String> = Vec::new();

        for line in argos_text.lines() {
            let lower = line.to_ascii_lowercase();
            let mut flagged_verb: Option<&str> = None;

            // Flag iff the line names a verb AND a verdict word.
            'outer: for verb in VERBS {
                if lower.contains(verb) {
                    for vw in VERDICT_WORDS {
                        if lower.contains(vw) {
                            flagged_verb = Some(verb);
                            break 'outer;
                        }
                    }
                }
            }

            match flagged_verb {
                None => out_lines.push(line.to_string()),
                Some(verb) => {
                    let attested = self
                        .lookup(verb)
                        .map(|r| {
                            !matches!(
                                r.result.as_str(),
                                "gate-off"
                                    | "extraction-empty"
                                    | "validation-rejected"
                                    | "transport-error"
                            )
                        })
                        .unwrap_or(false);

                    if attested {
                        out_lines.push(line.to_string());
                    } else {
                        let marker = format!(
                            "[REDACTED: solver attribution unattested — no executed VerdictRecord for `{verb}`]"
                        );
                        redactions.push(format!("`{verb}` — no VerdictRecord"));
                        out_lines.push(marker);
                        warn!(
                            verb = verb,
                            "redact_unattested: ARGOS cited a solver verdict with no matching VerdictRecord — line redacted"
                        );
                    }
                }
            }
        }

        let integrity_note = if redactions.is_empty() {
            format!(
                "\n\n---\n**[Integrity check PASSED]** All solver verdict attribution(s) in this \
                 ARGOS output match a VerdictRecord from this run ({} record(s)). No confabulated \
                 citations detected.",
                self.records.len()
            )
        } else {
            format!(
                "\n\n---\n**[Integrity check FAILED — {} attribution(s) REDACTED]** The following \
                 verb(s) were cited without an attested VerdictRecord: {}. Redacted lines were \
                 replaced with [REDACTED] markers above.",
                redactions.len(),
                redactions.join("; ")
            )
        };

        let summary = if redactions.is_empty() {
            format!("integrity=PASS records={}", self.records.len())
        } else {
            format!(
                "integrity=FAIL redacted={} verbs={}",
                redactions.len(),
                redactions.join(",")
            )
        };

        (
            format!("{}{}", out_lines.join("\n"), integrity_note),
            summary,
        )
    }
}

/// O contexto simbólico (PCS) só é injetado nos prompts quando explicitamente habilitado
/// (`BEAGLE_SYMBOLIC_CONTEXT_ENABLE=1`), e fica OFF por padrão.
///
/// Quando habilitado, `generate_symbolic_summary` chama o **solver real em Sounio** — o
/// verbo `pcs.reason` do Sounio Inference Service (ODE de sintomas integrada por RK4 em
/// Sounio puro; portado do antigo `reason_symbolically` em Julia). Se o serviço estiver
/// indisponível (inalcançável, timeout, erro), faz fallback para um resumo HEURÍSTICO de
/// palavra-chave. O bloco SEMPRE se auto-rotula com o status real (VERIFICADO POR SOLVER vs
/// HEURÍSTICO). Disciplina truth_mode: o prompt crítico nunca recebe sinal heurístico
/// disfarçado de simbólico verificado por solver.
fn symbolic_context_enabled() -> bool {
    std::env::var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(false)
}

/// Sinais sintomáticos em [0,1] extraídos do draft por proxy de palavra-chave.
/// São a ENTRADA (aproximada) do solver — quem é verificado por solver é o RACIOCÍNIO
/// (a evolução temporal da ODE), não estes sinais de entrada.
fn extract_symptom_signals(text: &str) -> std::collections::BTreeMap<String, f64> {
    let t = text.to_lowercase();
    let terms: [(&str, &[&str]); 4] = [
        (
            "depression",
            &[
                "depress",
                "anhedon",
                "humor deprimido",
                "desânimo",
                "melancol",
            ],
        ),
        (
            "anxiety",
            &["ansied", "anxiety", "pânico", "panic", "preocupaç", "worry"],
        ),
        (
            "stress",
            &[
                "estresse", "stress", "cortisol", "burnout", "alostá", "allosta",
            ],
        ),
        (
            "sleep",
            &[
                "insôn",
                "insomn",
                "privação de sono",
                "sleep deprivation",
                "vigília",
            ],
        ),
    ];
    let mut out = std::collections::BTreeMap::new();
    for (sym, kws) in terms.iter() {
        let hits = kws.iter().filter(|kw| t.contains(**kw)).count();
        // `sleep` é qualidade do sono: default alto (0.7), e CAI quando insônia é citada.
        let v = if *sym == "sleep" {
            (0.7 - 0.15 * hits as f64).max(0.1)
        } else if hits == 0 {
            0.5 // neutro
        } else {
            (0.5 + 0.15 * hits as f64).min(1.0)
        };
        out.insert((*sym).to_string(), v);
    }
    out
}

/// Chama o verbo `pcs.reason` do Sounio Inference Service (ODE de sintomas, RK4 em Sounio puro).
/// HTTP POST com timeout de 90s; qualquer falha vira `Err` (o chamador faz fallback heurístico).
/// `SOUNIO_INFERENCE_URL` aponta o serviço (default: Service in-cluster). Resposta:
/// `{ final_state: {depression,anxiety,stress,sleep}, severity_score }`.
async fn pcs_reason_sounio(
    symptoms: &std::collections::BTreeMap<String, f64>,
) -> anyhow::Result<serde_json::Value> {
    let base = std::env::var("SOUNIO_INFERENCE_URL")
        .unwrap_or_else(|_| "http://sounio-inference.beagle.svc.cluster.local:80".to_string());
    let url = format!("{}/v1/pcs/reason", base.trim_end_matches('/'));
    let body = serde_json::json!({
        "symptoms": {
            "depression": symptoms.get("depression").copied().unwrap_or(0.5),
            "anxiety": symptoms.get("anxiety").copied().unwrap_or(0.5),
            "stress": symptoms.get("stress").copied().unwrap_or(0.5),
            "sleep": symptoms.get("sleep").copied().unwrap_or(0.7),
        }
    });
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(90))
        .build()?;
    let resp = client.post(&url).json(&body).send().await?;
    if !resp.status().is_success() {
        anyhow::bail!("pcs.reason HTTP {}", resp.status());
    }
    Ok(resp.json::<serde_json::Value>().await?)
}

/// Gera resumo simbólico do draft via PCS (Symbolic Computational Psychiatry).
///
/// Quando o gate está ligado, chama o verbo `pcs.reason` do Sounio Inference Service (ODE de
/// sintomas, RK4 em Sounio puro); em qualquer falha (ou gate OFF) faz fallback para heurística
/// de palavra-chave. O bloco retornado se auto-rotula com o status real (VERIFICADO POR SOLVER
/// vs HEURÍSTICO).
pub async fn generate_symbolic_summary(
    draft: &str,
    _ctx: &BeagleContext,
) -> anyhow::Result<String> {
    info!("Gerando resumo simbólico do draft");

    let concepts = extract_key_concepts(draft);
    let logical_structure = analyze_logical_structure(draft);

    // Caminho REAL: solver simbólico em SOUNIO (verbo pcs.reason), via HTTP — gated.
    if symbolic_context_enabled() {
        let symptoms = extract_symptom_signals(draft);
        match pcs_reason_sounio(&symptoms).await {
            Ok(res) => {
                let fs = res.get("final_state");
                let g = |k: &str| fs.and_then(|o| o.get(k)).and_then(|v| v.as_f64());
                let fmt_state = |k: &str| {
                    g(k).map(|v| format!("{}={:.3}", k, v))
                        .unwrap_or_else(|| format!("{}=?", k))
                };
                let signals_in: Vec<String> = symptoms
                    .iter()
                    .map(|(k, v)| format!("{}={:.2}", k, v))
                    .collect();
                let severity = res
                    .get("severity_score")
                    .and_then(|v| v.as_f64())
                    .map(|s| format!("{:.3}", s))
                    .unwrap_or_else(|| "?".into());
                info!(severity = %severity, "PCS solver Sounio OK");
                return Ok(format!(
                    "## Resumo Simbólico — VERIFICADO POR SOLVER (PCS/Sounio)\n\n\
                    > Raciocínio resolvido pelo verbo `pcs.reason` do Sounio Inference Service \
                    (ODE de sintomas integrada por RK4 em Sounio puro; portado do antigo Julia). \
                    Os sinais de ENTRADA são proxy de palavra-chave (aproximados); a EVOLUÇÃO \
                    temporal e a severidade abaixo são verificadas por solver.\n\n\
                    **Sinais de entrada (proxy)**: {}\n\n\
                    **Estado simbólico final (t=10)**: {}, {}, {}, {}\n\n\
                    **Severity score (solver)**: {}\n\n\
                    **Conceitos-chave (heurístico)**: {}",
                    signals_in.join(", "),
                    fmt_state("depression"),
                    fmt_state("anxiety"),
                    fmt_state("stress"),
                    fmt_state("sleep"),
                    severity,
                    concepts.join(", "),
                ));
            }
            Err(e) => {
                warn!(error = %e, "PCS solver Sounio indisponível; fallback heurístico");
            }
        }
    }

    // Fallback HEURÍSTICO (auto-rotulado).
    let summary = format!(
        "## Resumo Simbólico — HEURÍSTICO (NÃO verificado por solver)\n\n\
        > ⚠️ Gerado por heurísticas de palavra-chave, NÃO pelo PCS/Sounio (indisponível neste ambiente). \
        Trate como dica fraca/aproximada — não como sinal simbólico verificado por solver.\n\n\
        **Conceitos-chave**: {}\n\n\
        **Estrutura lógica**: {}",
        concepts.join(", "),
        logical_structure
    );

    Ok(summary)
}

fn extract_key_concepts(text: &str) -> Vec<String> {
    // Heurística simples: palavras em maiúsculas, termos técnicos comuns
    let keywords = [
        "entropia",
        "curvatura",
        "scaffold",
        "biomaterial",
        "PBPK",
        "KEC",
        "psiquiatria",
        "computacional",
        "neurociência",
        "filosofia",
        "consciência",
        "geometria",
        "não-comutativa",
        "fractal",
        "holográfico",
    ];

    let mut found = Vec::new();
    let text_lower = text.to_lowercase();

    for keyword in &keywords {
        if text_lower.contains(keyword) {
            found.push(keyword.to_string());
        }
    }

    found
}

fn analyze_logical_structure(text: &str) -> String {
    // Heurística simples: conta seções, referências, equações
    let sections = text.matches("##").count();
    let references = text.matches("@").count() + text.matches("\\cite").count();
    let equations = text.matches("$$").count() / 2; // pares

    format!(
        "{} seções principais, {} referências, {} equações",
        sections, references, equations
    )
}

/// Input para a Triad
#[derive(Debug, Clone)]
pub struct TriadInput {
    pub run_id: String,
    pub draft_path: PathBuf,
    pub context_summary: Option<String>, // pode ser JSON com top-k chunks, etc.
}

/// Opinião de um agente da Triad
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriadOpinion {
    pub agent: String, // "ATHENA" | "HERMES" | "ARGOS"
    pub summary: String,
    pub suggestions_md: String, // markdown
    pub score: f32,             // 0.0–1.0
    pub provider_tier: String,  // "grok-3" | "grok-4-heavy" | etc.
}

/// Resultado da etapa EVOLVE (#21B).
///
/// Produz um draft refinado a partir das opiniões ATHENA/HERMES/ARGOS e do draft,
/// framado AUMENTATIVAMENTE (toda claim forte marcada como "requires
/// human/wet-lab validation" em vez de afirmada como fato) e CITATION-GROUNDED
/// (claims carregam referências ao contexto/fontes de suporte).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolvedDraft {
    /// Draft evoluído/refinado em Markdown.
    pub evolved_draft_md: String,
    /// Claims extraídas/evoluídas, cada uma framada aumentativamente e com citação.
    pub claims: Vec<EvolvedClaim>,
    /// Provider tier usado para a etapa EVOLVE.
    pub provider_tier: String,
}

/// Uma claim evoluída, framada aumentativamente e ancorada em citações (#21B).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolvedClaim {
    /// Texto da claim.
    pub claim: String,
    /// Sempre `true` por construção: a claim NÃO é afirmada como fato, mas
    /// como hipótese que requer validação humana / em laboratório (wet-lab).
    pub requires_human_validation: bool,
    /// Citações/fontes que suportam a claim (carregadas do contexto/fontes).
    pub citations: Vec<String>,
}

/// Per-verb accounting of formal verification attempts in a single run.
/// Counts are from the perspective of `run_argos`: each verb either ran
/// (gate enabled) or was skipped (gate disabled / gates are OFF by default).
/// `finding_emitted` is 1 if the verb produced an incoherence finding.
///
/// SOTA note: formal verifiability of scientific prose is partial (VeriCoT-class
/// benchmarks); a finding has precision >> raw accuracy but recall is low. This
/// struct makes that honest and machine-readable.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct VerbStats {
    /// 0 or 1 — each verb runs at most once per ARGOS.
    pub ran: u8,
    /// 1 when the gate was disabled (verb skipped).
    pub abstained: u8,
    /// 1 when the verb emitted an incoherence finding (UNSAT/d-sep/understated/non-sequitur).
    pub finding_emitted: u8,
}

/// Machine-readable summary of formal verification attempts emitted by `run_argos`.
/// Attached to [`TriadReport`] so callers can display or log it without parsing prose.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct VerificationSummary {
    pub smt: VerbStats,
    pub causal: VerbStats,
    pub gum: VerbStats,
    pub theorem: VerbStats,
    /// ISO-8601 timestamp when `run_argos` completed (UTC).
    pub completed_at: String,
    /// Fraction of ran verbs that emitted a finding (None when all abstained).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub finding_rate: Option<f32>,
}

impl VerificationSummary {
    /// Compact one-liner appended to formal-verification section headers, e.g.
    /// `[verification: 2/4 ran, 1 finding(s), rate 50%]` or
    /// `[verification: all abstained — gates disabled or no verifiable claims]`.
    pub fn machine_note(&self) -> String {
        let total_ran = (self.smt.ran + self.causal.ran + self.gum.ran + self.theorem.ran) as usize;
        let total_findings = (self.smt.finding_emitted
            + self.causal.finding_emitted
            + self.gum.finding_emitted
            + self.theorem.finding_emitted) as usize;
        if total_ran == 0 {
            return "[verification: all abstained — gates disabled or no verifiable claims]"
                .to_string();
        }
        let rate_pct = (total_findings as f32 / total_ran as f32 * 100.0).round() as u32;
        format!(
            "[verification: {}/{} ran, {} finding(s), rate {}%]",
            total_ran, 4, total_findings, rate_pct
        )
    }
}

/// Relatório final da Triad
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriadReport {
    pub run_id: String,
    pub original_draft: String,
    pub final_draft: String,
    pub opinions: Vec<TriadOpinion>,
    pub created_at: DateTime<Utc>,
    pub llm_stats: LlmCallsStatsLLM,
    /// Saída opcional da etapa EVOLVE (#21B). `None` quando a tournament
    /// EVOLVE não foi executada (preserva compat com consumidores existentes).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub evolved: Option<EvolvedDraft>,
    /// Contabilidade de verificação formal vinda de ARGOS (`run_argos`). `None`
    /// quando o estágio ARGOS foi carregado de checkpoint (resume) ou no caminho
    /// legado. Sempre `Some` para execuções frescas de ARGOS.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verification_summary: Option<VerificationSummary>,
}

/// Estatísticas de chamadas LLM
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct LlmCallsStats {
    pub grok3_calls: usize,
    pub grok3_tokens_est: usize,
    pub heavy_calls: usize,
    pub heavy_tokens_est: usize,
}

// ============================================================================
// #21C — Checkpoint / Resume (file-based)
// ============================================================================

/// Resolve o diretório de checkpoint `{data_dir}/triad/<run_id>`.
///
/// Espelha o padrão de `triad_review.rs`: usa `ctx.cfg.storage.data_dir`,
/// com fallback para a env `BEAGLE_DATA_DIR` e, por último, um diretório temp.
/// Best-effort: nunca falha a run.
pub fn checkpoint_dir(ctx: &BeagleContext, run_id: &str) -> PathBuf {
    let base = {
        let configured = ctx.cfg.storage.data_dir.trim();
        if !configured.is_empty() {
            PathBuf::from(configured)
        } else if let Ok(env_dir) = std::env::var("BEAGLE_DATA_DIR") {
            PathBuf::from(env_dir)
        } else {
            std::env::temp_dir().join("beagle-data")
        }
    };
    base.join("triad").join(run_id)
}

/// Caminho do arquivo de checkpoint de um estágio: `<dir>/<stage>.json`.
fn stage_path(dir: &std::path::Path, stage: &str) -> PathBuf {
    dir.join(format!("{stage}.json"))
}

/// Persiste a saída de um estágio como JSON (best-effort, #21C).
///
/// Falhas de escrita são logadas via `warn!` e NÃO interrompem a run.
fn save_stage<T: Serialize>(dir: &std::path::Path, stage: &str, value: &T) {
    if let Err(e) = std::fs::create_dir_all(dir) {
        warn!(
            "checkpoint: falha ao criar dir {} para stage '{}': {}",
            dir.display(),
            stage,
            e
        );
        return;
    }
    let path = stage_path(dir, stage);
    match serde_json::to_string_pretty(value) {
        Ok(json) => {
            if let Err(e) = std::fs::write(&path, json) {
                warn!(
                    "checkpoint: falha ao escrever {} (stage '{}'): {}",
                    path.display(),
                    stage,
                    e
                );
            } else {
                info!("checkpoint: stage '{}' salvo em {}", stage, path.display());
            }
        }
        Err(e) => warn!("checkpoint: falha ao serializar stage '{}': {}", stage, e),
    }
}

/// Carrega a saída de um estágio se já existir um checkpoint (resume, #21C).
///
/// Retorna `None` se o arquivo não existe ou não desserializa (re-computa).
fn load_stage<T: for<'de> Deserialize<'de>>(dir: &std::path::Path, stage: &str) -> Option<T> {
    let path = stage_path(dir, stage);
    if !path.exists() {
        return None;
    }
    match std::fs::read_to_string(&path) {
        Ok(s) => match serde_json::from_str::<T>(&s) {
            Ok(v) => {
                info!(
                    "checkpoint: resume — stage '{}' carregado de {}",
                    stage,
                    path.display()
                );
                Some(v)
            }
            Err(e) => {
                warn!(
                    "checkpoint: stage '{}' existe mas não desserializa ({}); re-computando",
                    stage, e
                );
                None
            }
        },
        Err(e) => {
            warn!(
                "checkpoint: falha ao ler {} (stage '{}'): {}; re-computando",
                path.display(),
                stage,
                e
            );
            None
        }
    }
}

/// Executa a Triad completa (compat: ATHENA → HERMES → ARGOS → Juiz).
///
/// Mantém a assinatura/comportamento públicos existentes. Internamente delega
/// para [`run_triad_tournament`] com a etapa EVOLVE desabilitada, de modo que
/// consumidores atuais não veem mudança alguma (o campo `evolved` será `None`).
pub async fn run_triad(input: &TriadInput, ctx: &BeagleContext) -> anyhow::Result<TriadReport> {
    // Legacy entrypoint: no EVOLVE and no checkpoint side-effects — behavior is
    // identical to before (no files written, never auto-resumes).
    run_triad_tournament(input, ctx, false, false).await
}

/// #21B — Tournament generate-debate-EVOLVE com checkpoint/resume (#21C).
///
/// Roda ATHENA → HERMES → ARGOS → Juiz e, se `enable_evolve == true`, uma etapa
/// EVOLVE adicional após a crítica de ARGOS. Cada estágio é persistido em
/// `{data_dir}/triad/<run_id>/<stage>.json` conforme progride; ao iniciar, se o
/// arquivo de um estágio já existir para esse `run_id`, ele é CARREGADO e o
/// recálculo é pulado (resume). Checkpoint é best-effort; resume só é tentado
/// quando há `run_id`.
pub async fn run_triad_tournament(
    input: &TriadInput,
    ctx: &BeagleContext,
    enable_evolve: bool,
    checkpoint: bool,
) -> anyhow::Result<TriadReport> {
    info!(
        "🔍 Iniciando Triad para run_id: {} (evolve={}, checkpoint={})",
        input.run_id, enable_evolve, checkpoint
    );

    let ckpt_dir = checkpoint_dir(ctx, &input.run_id);

    // 1) Ler draft
    let original_draft = std::fs::read_to_string(&input.draft_path)?;
    info!("📄 Draft lido: {} chars", original_draft.len());

    // #21C: checkpoint/resume is OPT-IN. The legacy run_triad passes checkpoint=false,
    // so it writes NO files and never auto-resumes (behavior unchanged). When on,
    // resume reuses stages ONLY if the draft+evolve fingerprint matches the stored one
    // — editing the draft and re-running the same run_id recomputes instead of loading
    // stale opinions describing the old draft.
    let draft_fingerprint = {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        original_draft.hash(&mut h);
        enable_evolve.hash(&mut h);
        format!("{:016x}", h.finish())
    };
    let resume = checkpoint
        && !input.run_id.trim().is_empty()
        && load_stage::<String>(&ckpt_dir, "meta").as_deref() == Some(draft_fingerprint.as_str());
    if checkpoint {
        save_stage(&ckpt_dir, "meta", &draft_fingerprint);
    }

    // 2) ATHENA (agente literatura) — resume se já houver checkpoint
    let athena: TriadOpinion = match resume
        .then(|| load_stage::<TriadOpinion>(&ckpt_dir, "athena"))
        .flatten()
    {
        Some(op) => {
            info!("⏭️  ATHENA: resume de checkpoint (Score: {:.2})", op.score);
            op
        }
        None => {
            info!("🔬 Executando ATHENA...");
            let (op, tier) =
                run_athena(&original_draft, &input.context_summary, ctx, &input.run_id).await?;
            info!(
                "✅ ATHENA concluído - Score: {:.2} | Provider: {}",
                op.score,
                tier.as_str()
            );
            if checkpoint {
                save_stage(&ckpt_dir, "athena", &op);
            }
            op
        }
    };

    // 3) HERMES (revisor)
    let hermes: TriadOpinion = match resume
        .then(|| load_stage::<TriadOpinion>(&ckpt_dir, "hermes"))
        .flatten()
    {
        Some(op) => {
            info!("⏭️  HERMES: resume de checkpoint (Score: {:.2})", op.score);
            op
        }
        None => {
            info!("✍️  Executando HERMES...");
            let (op, tier) = run_hermes(&original_draft, &athena, ctx, &input.run_id).await?;
            info!(
                "✅ HERMES concluído - Score: {:.2} | Provider: {}",
                op.score,
                tier.as_str()
            );
            if checkpoint {
                save_stage(&ckpt_dir, "hermes", &op);
            }
            op
        }
    };

    // 4) ARGOS (crítico)
    // P4: VerificationSummary é Some apenas para execuções frescas de ARGOS; resume
    // de checkpoint deixa None (compat retroativa preservada no relatório).
    let mut argos_vsummary: Option<VerificationSummary> = None;
    let argos: TriadOpinion = match resume
        .then(|| load_stage::<TriadOpinion>(&ckpt_dir, "argos"))
        .flatten()
    {
        Some(op) => {
            info!("⏭️  ARGOS: resume de checkpoint (Score: {:.2})", op.score);
            op
        }
        None => {
            info!("⚔️  Executando ARGOS...");
            let (op, tier, vsummary) =
                run_argos(&original_draft, &hermes, &athena, ctx, &input.run_id).await?;
            info!(
                "✅ ARGOS concluído - Score: {:.2} | Provider: {} | {}",
                op.score,
                tier.as_str(),
                vsummary.machine_note()
            );
            if checkpoint {
                save_stage(&ckpt_dir, "argos", &op);
                save_stage(&ckpt_dir, "argos_verification", &vsummary);
            }
            argos_vsummary = Some(vsummary);
            op
        }
    };

    // 4b) EVOLVE (#21B) — refina o draft após a crítica de ARGOS.
    let evolved: Option<EvolvedDraft> = if enable_evolve {
        match resume
            .then(|| load_stage::<EvolvedDraft>(&ckpt_dir, "evolve"))
            .flatten()
        {
            Some(ev) => {
                info!(
                    "⏭️  EVOLVE: resume de checkpoint ({} claims)",
                    ev.claims.len()
                );
                Some(ev)
            }
            None => {
                info!("🧬 Executando EVOLVE...");
                let ev = run_evolve(
                    &original_draft,
                    &athena,
                    &hermes,
                    &argos,
                    &input.context_summary,
                    ctx,
                    &input.run_id,
                )
                .await?;
                info!(
                    "✅ EVOLVE concluído - {} claims | Provider: {}",
                    ev.claims.len(),
                    ev.provider_tier
                );
                if checkpoint {
                    save_stage(&ckpt_dir, "evolve", &ev);
                }
                Some(ev)
            }
        }
    } else {
        None
    };

    // 5) Juiz final (arbitra versões)
    info!("⚖️  Executando Juiz Final...");
    let (final_draft, tier) = arbitrate_final(
        &original_draft,
        &hermes,
        &athena,
        &argos,
        ctx,
        &input.run_id,
    )
    .await?;
    info!(
        "✅ Juiz Final concluído - Draft final: {} chars | Provider: {}",
        final_draft.len(),
        tier.as_str()
    );

    // Obtém stats finais do contexto
    let llm_stats = ctx.llm_stats.get(&input.run_id).unwrap_or_default();
    let llm_stats_converted = LlmCallsStatsLLM {
        grok3_calls: llm_stats.grok3_calls,
        grok3_tokens_in: llm_stats.grok3_tokens_in,
        grok3_tokens_out: llm_stats.grok3_tokens_out,
        grok4_calls: llm_stats.grok4_calls,
        grok4_tokens_in: llm_stats.grok4_tokens_in,
        grok4_tokens_out: llm_stats.grok4_tokens_out,
        deepseek_calls: llm_stats.deepseek_calls,
        deepseek_tokens_in: llm_stats.deepseek_tokens_in,
        deepseek_tokens_out: llm_stats.deepseek_tokens_out,
        local_calls: llm_stats.local_calls,
        local_tokens_in: llm_stats.local_tokens_in,
        local_tokens_out: llm_stats.local_tokens_out,
    };

    let report = TriadReport {
        run_id: input.run_id.clone(),
        original_draft,
        final_draft,
        opinions: vec![athena, hermes, argos],
        created_at: Utc::now(),
        llm_stats: llm_stats_converted,
        evolved,
        verification_summary: argos_vsummary,
    };

    // Persiste o relatório final (best-effort, #21C).
    save_stage(&ckpt_dir, "report", &report);

    Ok(report)
}

/// #21B — EVOLVE: refina draft + claims a partir das opiniões da Triad.
///
/// O output é (a) framado AUMENTATIVAMENTE — toda claim forte marcada como
/// `requires_human_validation` em vez de afirmada como fato — e (b)
/// CITATION-GROUNDED — claims carregam citações do contexto/fontes de suporte.
///
/// O LLM produz o draft evoluído em Markdown; as claims são extraídas
/// programaticamente e marcadas, garantindo a invariante aumentativa mesmo que
/// o modelo escorregue. Citações são carregadas do `context_summary` (quando
/// disponível) e de citações detectadas no próprio draft (`@key`, `\cite{...}`).
#[allow(clippy::too_many_arguments)]
pub async fn run_evolve(
    original_draft: &str,
    athena: &TriadOpinion,
    hermes: &TriadOpinion,
    argos: &TriadOpinion,
    context_summary: &Option<String>,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<EvolvedDraft> {
    let mut prompt = String::from(
        "Você é EVOLVE, o agente de refinamento aumentativo do sistema BEAGLE (HONEST AI TRIAD).\n\n\
        Você recebeu o DRAFT original e três opiniões (ATHENA, HERMES, ARGOS).\n\
        Sua tarefa é produzir um DRAFT EVOLUÍDO em Markdown que:\n\
        1. AUMENTATIVO: NÃO afirme claims fortes como fato. Toda afirmação forte deve ser\n\
           framada como hipótese/proposta que REQUER validação humana ou em laboratório\n\
           (wet-lab). Use linguagem como 'propomos que', 'hipótese a ser testada',\n\
           'requer validação experimental'.\n\
        2. CITATION-GROUNDED: cada claim forte deve referenciar a(s) fonte(s)/contexto de\n\
           suporte. Preserve e carregue citações do contexto (não invente referências).\n\
        3. Incorpore o melhor de ATHENA/HERMES e corrija os problemas apontados por ARGOS.\n\n\
        Responda APENAS com o draft evoluído em Markdown.\n\n",
    );

    if let Some(ctx_sum) = context_summary {
        prompt.push_str("=== CONTEXTO / FONTES ===\n");
        prompt.push_str(ctx_sum);
        prompt.push_str("\n\n");
    }
    prompt.push_str("=== FEEDBACK_ATHENA ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== DRAFT_HERMES ===\n");
    prompt.push_str(&hermes.suggestions_md);
    prompt.push_str("\n\n=== FEEDBACK_ARGOS ===\n");
    prompt.push_str(&argos.suggestions_md);
    prompt.push_str("\n\n=== DRAFT_ORIGINAL ===\n");
    prompt.push_str(original_draft);

    // EVOLVE é refinamento final crítico: alta qualidade + raciocínio PhD.
    let meta = RequestMeta::new(
        false,                      // requires_math
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,                       // high_bias_risk (decide framing de claims)
        true,                       // requires_phd_level_reasoning
        true,                       // critical_section
    );

    let (evolved_md, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

    // Pool de citações conhecidas (draft + contexto) usado como fallback de
    // grounding quando uma claim não traz citação inline própria.
    let mut draft_level_citations = extract_citations(original_draft);
    draft_level_citations.extend(extract_citations(&evolved_md));
    if let Some(ctx_sum) = context_summary {
        draft_level_citations.extend(extract_citations(ctx_sum));
    }
    dedup_in_place(&mut draft_level_citations);

    // Extrai claims do draft evoluído. Grounding é PER-CLAIM: as citações vêm do
    // texto da própria claim (extract_citations(&claim)); só caem para o pool
    // draft-level quando a claim não cita nada inline. requires_human_validation
    // é true por DESIGN (framing aumentativo: nenhuma claim do tournament é
    // afirmada como fato — todas requerem validação humana/wet-lab).
    let claims = extract_claims(&evolved_md)
        .into_iter()
        .map(|claim| {
            let mut per_claim = extract_citations(&claim);
            if per_claim.is_empty() {
                per_claim = draft_level_citations.clone();
            }
            EvolvedClaim {
                claim,
                requires_human_validation: true,
                citations: per_claim,
            }
        })
        .collect();

    Ok(EvolvedDraft {
        evolved_draft_md: evolved_md,
        claims,
        provider_tier: tier.as_str().to_string(),
    })
}

/// Extrai citações de um texto: padrões `@chave`, `\cite{...}` e `[N]`.
fn extract_citations(text: &str) -> Vec<String> {
    let mut out = Vec::new();

    if let Ok(re) = regex::Regex::new(r"\\cite\{([^}]+)\}") {
        for caps in re.captures_iter(text) {
            if let Some(m) = caps.get(1) {
                for key in m.as_str().split(',') {
                    let k = key.trim();
                    if !k.is_empty() {
                        out.push(format!("\\cite{{{k}}}"));
                    }
                }
            }
        }
    }
    if let Ok(re) = regex::Regex::new(r"@([A-Za-z][A-Za-z0-9_:-]+)") {
        for caps in re.captures_iter(text) {
            if let Some(m) = caps.get(1) {
                out.push(format!("@{}", m.as_str()));
            }
        }
    }
    if let Ok(re) = regex::Regex::new(r"\[(\d{1,3})\]") {
        for caps in re.captures_iter(text) {
            if let Some(m) = caps.get(1) {
                out.push(format!("[{}]", m.as_str()));
            }
        }
    }

    dedup_in_place(&mut out);
    out
}

/// Divide texto em sentenças sem fragmentar decimais (0.05) nem abreviações
/// comuns (et al., e.g., i.e., Fig., vs.). Quebra só em `.`/`!`/`?` seguido de
/// espaço/fim, e não quando o `.` está entre dígitos.
fn split_sentences(text: &str) -> Vec<String> {
    const ABBREVS: &[&str] = &[
        "et al", "e.g", "i.e", "fig", "eq", "vs", "cf", "dr", "al", "no", "ref",
    ];
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut start = 0usize;
    for i in 0..chars.len() {
        let c = chars[i];
        if c != '.' && c != '!' && c != '?' {
            continue;
        }
        let next = chars.get(i + 1).copied();
        let prev = if i > 0 {
            chars.get(i - 1).copied()
        } else {
            None
        };
        // Decimal: dígito.dígito (ex.: 0.05) — não é fim de sentença.
        if c == '.'
            && prev.is_some_and(|p| p.is_ascii_digit())
            && next.is_some_and(|n| n.is_ascii_digit())
        {
            continue;
        }
        // Fim de sentença só quando seguido de espaço ou fim de string.
        if next.is_none_or(|n| n.is_whitespace()) {
            let frag: String = chars[start..=i].iter().collect();
            let last_word = frag
                .trim()
                .rsplit(char::is_whitespace)
                .next()
                .unwrap_or("")
                .trim_end_matches('.')
                .to_ascii_lowercase();
            if ABBREVS.iter().any(|a| *a == last_word) {
                continue; // abreviação — não quebra
            }
            out.push(frag);
            start = i + 1;
        }
    }
    if start < chars.len() {
        out.push(chars[start..].iter().collect());
    }
    out
}

/// Extrai claims candidatas de um Markdown: frases não-triviais, sem cabeçalhos.
fn extract_claims(md: &str) -> Vec<String> {
    let mut claims = Vec::new();
    for line in md.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') || t.starts_with("```") || t.starts_with('|') {
            continue;
        }
        // Quebra a linha em sentenças (respeitando decimais/abreviações).
        for raw in split_sentences(t) {
            let s = raw
                .trim_start_matches(['-', '*', '>', ' '])
                .trim()
                .trim_end_matches(['.', '!', '?'])
                .trim()
                .to_string();
            // Heurística: claim = sentença com substância (mais de 5 palavras).
            if s.split_whitespace().count() > 5 {
                claims.push(s);
            }
        }
    }
    dedup_in_place(&mut claims);
    claims
}

/// Remove duplicatas preservando ordem.
fn dedup_in_place(v: &mut Vec<String>) {
    let mut seen = std::collections::HashSet::new();
    v.retain(|x| seen.insert(x.clone()));
}

/// Helper para chamada LLM com tracking de stats na Triad
async fn call_llm_with_stats_triad(
    ctx: &BeagleContext,
    run_id: &str,
    prompt: &str,
    meta: RequestMeta,
) -> anyhow::Result<(String, ProviderTier)> {
    // Obtém stats atuais do run
    let current_stats = ctx.llm_stats.get_or_create(run_id);

    // Escolhe client com limites
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);

    // Os AGENTES do Triad (ATHENA/HERMES/ARGOS/Juiz/evolve) rodam num modelo de reasoning
    // ROBUSTO (glm-5.1 por padrão, override via BEAGLE_TRIAD_AGENT_MODEL) — explicitamente, NÃO
    // pelo fleet default, para que o resto da plataforma (draft-gen, utilidades) possa usar um
    // modelo de chat rápido sem arrastar tudo para o caminho lento de reasoning.
    // max_tokens AMPLO: modelos de reasoning gastam tokens em `reasoning_content` ANTES do
    // `content`; com max_tokens baixo (2048) o content sai vazio/truncado (Juiz=0 chars).
    let req = beagle_llm::LlmRequest {
        model: std::env::var("BEAGLE_TRIAD_AGENT_MODEL").unwrap_or_else(|_| "glm-5.1".to_string()),
        messages: vec![beagle_llm::ChatMessage::user(prompt)],
        temperature: Some(0.7),
        max_tokens: Some(8000),
    };
    let text = client.chat(req).await?;
    let output = beagle_llm::LlmOutput::from_text(text, prompt);

    // Atualiza stats
    ctx.llm_stats.update(run_id, |stats| {
        match tier {
            ProviderTier::Grok3 => {
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
            ProviderTier::Grok4Heavy => {
                stats.grok4_calls += 1;
                stats.grok4_tokens_in += output.tokens_in_est as u32;
                stats.grok4_tokens_out += output.tokens_out_est as u32;
            }
            _ => {
                // Outros tiers contam como Grok3 por enquanto
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
        }
    });

    Ok((output.text, tier))
}

/// Chamada de EXTRAÇÃO de claims para o solver: força um modelo de CHAT determinístico
/// (deepseek-chat por padrão, override via `BEAGLE_TRIAD_EXTRACTION_MODEL`) com temperatura 0.
/// Diferente dos agentes (que rodam num modelo de reasoning robusto como glm-5.1), a extração
/// precisa de JSON estruturado CONFIÁVEL e barato — reasoning é lento e arrisca truncar o JSON
/// pequeno, e modelos de chat não-reasoning não super-dividem variáveis tão facilmente. O
/// `LocalFleetClient` honra `req.model` quando nomeia um modelo real, então isto é independente
/// do fleet default usado pelos agentes.
async fn call_llm_extraction(
    ctx: &BeagleContext,
    run_id: &str,
    prompt: &str,
    meta: RequestMeta,
) -> anyhow::Result<(String, ProviderTier)> {
    let current_stats = ctx.llm_stats.get_or_create(run_id);
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);
    let req = beagle_llm::LlmRequest {
        model: std::env::var("BEAGLE_TRIAD_EXTRACTION_MODEL")
            .unwrap_or_else(|_| "deepseek-chat".to_string()),
        messages: vec![beagle_llm::ChatMessage::user(prompt)],
        temperature: Some(0.0),
        max_tokens: Some(2048),
    };
    let text = client.chat(req).await?;
    let output = beagle_llm::LlmOutput::from_text(text, prompt);
    ctx.llm_stats.update(run_id, |stats| {
        stats.grok3_calls += 1;
        stats.grok3_tokens_in += output.tokens_in_est as u32;
        stats.grok3_tokens_out += output.tokens_out_est as u32;
    });
    Ok((output.text, tier))
}

/// ATHENA: leitura crítica + literatura
///
/// Prompts customizados para o contexto científico interdisciplinar do BEAGLE:
/// - Psiquiatria computacional, entropia/curvatura, PBPK, biomateriais, neurociência
/// - Filosofia da mente, geometria não-comutativa, consciência celular
/// ATHENA: Research accuracy specialist with high-quality requirements
///
/// Routed at requires_high_quality + requires_phd_level_reasoning. No published
/// latency/accuracy numbers are claimed here — measure them via the eval harness
/// (see docs/MODERNIZATION_PLAN_2026.md) rather than asserting unbacked figures.
#[tracing::instrument(skip(draft, context_summary, ctx), fields(run_id = %run_id, agent = "ATHENA"))]
pub async fn run_athena(
    draft: &str,
    context_summary: &Option<String>,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let start = std::time::Instant::now();

    // ATHENA requires highest accuracy for research validation
    let meta = RequestMeta {
        requires_high_quality: true,
        requires_phd_level_reasoning: true,
        high_bias_risk: false, // ATHENA is accuracy-focused, not bias-prone
        critical_section: false,
        requires_math: draft.contains("equation") || draft.contains("theorem"),
        offline_required: false,
        requires_vision: false,
        approximate_tokens: draft.len() / 4, // rough estimate
        ..Default::default()
    };

    info!("ATHENA: Evaluating draft with high-quality reasoning (PhD-level)");

    let mut prompt = String::from(
        "You are ATHENA, the scientific rigor specialist of the BEAGLE Triad system.\n\n\
        CONTEXT: Interdisciplinary research spanning:\n\
        • Computational psychiatry & neuroscience (cf. Friston, 2010; Montague et al., 2012)\n\
        • Non-commutative geometry & curved entropy (cf. Connes, 1994; Tsallis, 1988)\n\
        • PBPK modeling & kinetic energy considerations (cf. Rowland & Tozer, 2011)\n\
        • Biomaterials & biological scaffolds (cf. Langer & Vacanti, 1993)\n\
        • Cellular consciousness & philosophy of mind (cf. Koch, 2019; Tononi, 2008)\n\
        • Chemical engineering in biological systems (cf. Bailey & Ollis, 1986)\n\n\
        TASK: Analyze the draft below with Q1 journal standards. Identify:\n\
        1. Conceptual strengths (especially interdisciplinary connections)\n\
        2. Methodological weaknesses or gaps\n\
        3. Missing citations from top-tier venues (Nature, Science, Cell, PNAS)\n\n\
        OUTPUT FORMAT: Three Markdown sections:\n\
        ## Strengths\n\
        ## Weaknesses\n\
        ## Suggested References\n\n",
    );

    if let Some(ctx_sum) = context_summary {
        prompt.push_str("=== CONTEXTO (Darwin / GraphRAG) ===\n");
        prompt.push_str(ctx_sum);
        prompt.push_str("\n\n");
    }

    // Contexto simbólico (PCS) — GATED (OFF por padrão; ver symbolic_context_enabled).
    // O bloco se auto-rotula com o status real (VERIFICADO POR SOLVER vs HEURÍSTICO).
    if symbolic_context_enabled() {
        if let Ok(symbolic_summary) = generate_symbolic_summary(draft, ctx).await {
            prompt.push_str("=== CONTEXTO SIMBÓLICO (PCS) ===\n");
            prompt.push_str(&symbolic_summary);
            prompt.push_str("\n\n");
        }
    }

    prompt.push_str("=== DRAFT ===\n");
    prompt.push_str(draft);

    // Get current stats for this run
    let current_stats = ctx.llm_stats.get_or_create(run_id);

    // Choose LLM with limits - ATHENA needs high quality
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);

    // Execute LLM call with timing
    let llm_start = std::time::Instant::now();
    let output = client.complete(&prompt).await?;
    let llm_latency = llm_start.elapsed();

    // Update stats with precise tracking
    ctx.llm_stats.update(run_id, |stats| {
        match tier {
            ProviderTier::Grok3 => {
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
            ProviderTier::Grok4Heavy => {
                stats.grok4_calls += 1;
                stats.grok4_tokens_in += output.tokens_in_est as u32;
                stats.grok4_tokens_out += output.tokens_out_est as u32;
            }
            _ => {
                // Other tiers count as Grok3 for accounting
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
        }
    });

    let total_latency = start.elapsed();
    info!(
        "ATHENA completed in {:.2}s (LLM: {:.2}s) using {} with ~{} tokens",
        total_latency.as_secs_f64(),
        llm_latency.as_secs_f64(),
        tier.as_str(),
        output.total_tokens()
    );

    // Extrai score (pode pedir ao modelo explicitamente no futuro)
    let text = output.text.clone();
    let score = extract_score(&text).unwrap_or(0.8);

    Ok((
        TriadOpinion {
            agent: "ATHENA".into(),
            summary: "Leitura crítica e mapeamento de literatura sugerida".into(),
            suggestions_md: text,
            score,
            provider_tier: tier.as_str().to_string(),
        },
        tier,
    ))
}

/// HERMES: reescrita orientada
///
/// Preserva voz autoral interdisciplinar (engenharia química, medicina, psiquiatria, biomateriais, filosofia da mente).
/// Alta densidade conceitual sem simplificação infantil.
pub async fn run_hermes(
    draft: &str,
    athena: &TriadOpinion,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(TriadOpinion, ProviderTier)> {
    let mut prompt = String::from(
        "Você é HERMES, agente de síntese textual do sistema BEAGLE.\n\n\
        IMPORTANTE: Preserve a voz autoral interdisciplinar característica de um pesquisador que trabalha na intersecção de:\n\
        - Engenharia química e farmacocinética (PBPK)\n\
        - Medicina e psiquiatria computacional\n\
        - Biomateriais e scaffolds biológicos\n\
        - Neurociência e filosofia da mente\n\
        - Geometria não-comutativa e entropia curva\n\n\
        Mantenha alta densidade conceitual, clareza sem simplificação infantil, elegância técnica.\n\n\
        Você receberá:\n\
        - Um rascunho de artigo (DRAFT)\n\
        - Uma análise crítica de ATHENA com sugestões (ATHENA_FEEDBACK)\n\n\
        Sua tarefa:\n\
        1. Reescrever o texto deixando-o mais claro, coeso e lógico.\n\
        2. Incorporar as sugestões relevantes de ATHENA.\n\
        3. NÃO inventar dados ou resultados; só reorganizar e melhorar o texto.\n\
        4. Mantenha o rigor técnico e a voz autoral interdisciplinar.\n\n\
        Responda apenas com o novo texto em Markdown, sem comentários fora do texto.\n\n",
    );

    prompt.push_str("=== ATHENA_FEEDBACK ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== DRAFT ===\n");
    prompt.push_str(draft);

    let meta = RequestMeta::new(
        false,                      // requires_math
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        false,                      // high_bias_risk (HERMES não precisa de Heavy)
        false,                      // requires_phd_level_reasoning (reescrita, não análise crítica)
        false,                      // critical_section
    );

    let (text, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

    let score = extract_score(&text).unwrap_or(0.85);

    Ok((
        TriadOpinion {
            agent: "HERMES".into(),
            summary: "Reescrita coerente e estilisticamente melhorada".into(),
            suggestions_md: text.clone(), // aqui o 'suggestions_md' é o próprio rascunho reescrito
            score,
            provider_tier: tier.as_str().to_string(),
        },
        tier,
    ))
}

/// ARGOS: crítico adversarial
///
/// Age como revisor Q1 duro (Nature Human Behaviour, Kybernetes, Frontiers), focado em:
/// - Claims sem suporte empírico adequado
/// - Confusão entre metáfora e mecanismo
/// - Ausência de desenho empírico razoável
/// Gate: a verificação por solver só roda com `BEAGLE_TRIAD_SMT_CHECK` ligado (OFF por padrão).
/// Aceita as formas usuais de "ligado": `1`, `true`, `yes`, `on` (case-insensitive). Antes o
/// código fazia `v.parse::<bool>()`, que REJEITA `"1"` (só aceita `true`/`false`) — então o valor
/// documentado `BEAGLE_TRIAD_SMT_CHECK=1` deixava o gate silenciosamente DESLIGADO.
fn smt_claim_check_enabled() -> bool {
    std::env::var("BEAGLE_TRIAD_SMT_CHECK")
        .map(|v| {
            matches!(
                v.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(false)
}

/// Gate para verificação formal de d-separação causal via Sounio `causal.dsep`. Mesmo estilo
/// de parse que [`smt_claim_check_enabled`]: aceita `1`, `true`, `yes`, `on` (case-insensitive).
/// OFF por padrão.
fn dsep_claim_check_enabled() -> bool {
    std::env::var("BEAGLE_TRIAD_DSEP_CHECK")
        .map(|v| {
            matches!(
                v.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(false)
}

/// Gate para verificação formal de propagação de incerteza via Sounio `gum.propagate`.
/// Mesmo estilo de parse que [`smt_claim_check_enabled`]: aceita `1`, `true`, `yes`, `on`
/// (case-insensitive). OFF por padrão.
fn gum_claim_check_enabled() -> bool {
    std::env::var("BEAGLE_TRIAD_GUM_CHECK")
        .map(|v| {
            matches!(
                v.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(false)
}

/// Gate para verificação formal de dedução proposicional via Sounio `theorem.prove`.
/// Mesmo estilo de parse: aceita `1`, `true`, `yes`, `on` (case-insensitive). OFF por padrão.
/// É o sinal MAIS FRACO dos backstops (UNKNOWN ≠ refutação; prover proposicional e de
/// profundidade limitada), então fica desligado por padrão e só dispara em deduções
/// proposicionais EXPLÍCITAS e auto-contidas.
fn theorem_claim_check_enabled() -> bool {
    std::env::var("BEAGLE_TRIAD_THEOREM_CHECK")
        .map(|v| {
            matches!(
                v.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(false)
}

/// Extrai o primeiro objeto JSON balanceado de um texto (o LLM costuma cercar com prosa).
fn first_json_object(s: &str) -> Option<String> {
    let start = s.find('{')?;
    let mut depth = 0i32;
    for (i, ch) in s[start..].char_indices() {
        match ch {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(s[start..start + i + ch.len_utf8()].to_string());
                }
            }
            _ => {}
        }
    }
    None
}

/// Filtra e deduplica constraints antes de enviar ao solver.
///
/// Regras conservadoras (não tocam em contradições reais):
/// 1. Remove duplicatas exatas: mesmo vetor `coeffs` e mesmo `bound`.
/// 2. Remove "twins" fabricados pelo LLM: quando o `label` (lower-case) contém
///    "limite inferior" ou "limite superior" E o padrão de coeficientes dessa
///    constraint é a NEGAÇÃO EXATA do de outra constraint no conjunto. Esse é o
///    sinal de que o LLM dividiu uma única afirmação de um limite em dois
///    constraints inventados — o twin negado é o ruído; o original permanece.
fn dedup_constraints(
    mut cs: Vec<inference_client::LiaConstraint>,
) -> Vec<inference_client::LiaConstraint> {
    // Passo 1: dedup exata.
    let mut seen: std::collections::HashSet<(Vec<i64>, i64)> = std::collections::HashSet::new();
    cs.retain(|c| seen.insert((c.coeffs.clone(), c.bound)));

    // Passo 2: descarta twins fabricados.
    // Um twin é detectado quando:
    //   (a) o label contém "limite inferior" OU "limite superior" (marcador de fabricação), E
    //   (b) existe OUTRA constraint cujos coeffs são a negação exata do twin E cujo bound = -twin.bound.
    // Só descartamos o twin marcado — a constraint "original" (sem marcador ou com bound diferente)
    // permanece, preservando contradições reais.
    let originals: Vec<(Vec<i64>, i64)> = cs.iter().map(|c| (c.coeffs.clone(), c.bound)).collect();

    cs.retain(|c| {
        let lbl = c.label.as_deref().unwrap_or("").to_ascii_lowercase();
        let is_fabricated_label =
            lbl.contains("limite inferior") || lbl.contains("limite superior");
        if !is_fabricated_label {
            return true; // sem marcador → manter sempre
        }
        // Verifica se existe outra constraint com coeffs negados e bound negado.
        let neg_coeffs: Vec<i64> = c.coeffs.iter().map(|&k| -k).collect();
        let neg_bound = -c.bound;
        let has_mirror = originals
            .iter()
            .any(|(oc, ob)| *oc == neg_coeffs && *ob == neg_bound);
        // Descarta apenas se um mirror exato foi encontrado (é provável twin de fabricação).
        !has_mirror
    });

    cs
}

/// Verificação formal de consistência de claims via Sounio `smt.check`.
///
/// Fluxo: o LLM extrai afirmações quantitativas LINEARES do draft como constraints
/// inteiras QF_LIA → o verbo `smt.check` (DPLL(T) do Sounio) decide. Retorna um bloco
/// markdown de achado APENAS quando o solver prova `UNSAT` (contradição). Qualquer falha
/// (sem claims, serviço fora, parse, SAT/UNKNOWN) → `None` — honesto por construção, nunca
/// fabrica achado. Truth-mode: o solver prova que ESTAS constraints extraídas (falíveis) são
/// contraditórias, NÃO que "o draft está errado".
/// Thin wrapper preserving the historic signature for direct callers/tests.
/// Delegates to [`solver_claim_consistency_traced`] with a throwaway registry.
async fn solver_claim_consistency(
    draft: &str,
    ctx: &BeagleContext,
    run_id: &str,
) -> Option<String> {
    let mut registry = VerdictRegistry::new();
    solver_claim_consistency_traced(draft, ctx, run_id, &mut registry).await
}

/// Traced variant: identical logic to [`solver_claim_consistency`] but also emits
/// exactly one [`VerdictRecord`] on every code path (gate-off, extraction-empty,
/// SAT/UNSAT/UNKNOWN). Called by `run_argos`. The `&mut VerdictRegistry` makes the
/// record emission structurally mandatory.
async fn solver_claim_consistency_traced(
    draft: &str,
    ctx: &BeagleContext,
    run_id: &str,
    registry: &mut VerdictRegistry,
) -> Option<String> {
    if !smt_claim_check_enabled() {
        registry.push(VerdictRecord {
            verb: "smt.check",
            input_sha256: String::new(),
            result: "gate-off".to_string(),
            run_id: run_id.to_string(),
        });
        return None;
    }
    let draft_excerpt: String = draft.chars().take(6000).collect();
    let prompt = format!(
        "Extraia afirmações quantitativas LINEARES e EXPLÍCITAS do texto como constraints inteiras \
         QF_LIA. Trabalhe em DOIS PASSOS.\n\
         PASSO 1 — CANONIZE AS VARIÁVEIS: liste as grandezas físicas distintas. A IDENTIDADE de uma \
         variável é definida SÓ por (unidade de medida + entidade medida). IGNORE COMPLETAMENTE \
         palavras de papel/qualificador como: mínimo, máximo, mínima, máxima, necessária, necessário, \
         administrada, eficaz, segura, permitida, alvo, recomendada, limite. Dois números com a MESMA \
         unidade sobre a MESMA entidade são a MESMA variável, mesmo em frases/seções diferentes e mesmo \
         com qualificadores opostos. Exemplo OBRIGATÓRIO de unificação: 'a dose diária administrada de \
         Zentamab ... no mínimo 80 mg' e 'a dose diária administrada de Zentamab ... no máximo 40 mg' \
         são UMA ÚNICA variável (unidade=mg, entidade=dose diária de Zentamab) → x0; vira x0>=80 E x0<=40.\n\
         PASSO 2 — EMITA AS CONSTRAINTS na forma `soma(coef_i * x_i) <= bound` usando os índices do passo 1. \
         `a >= b` vira `(-1)*a <= -b`; `a <= b` fica `(+1)*a <= b`. Confira o SINAL: 'no mínimo 80' é x>=80 \
         → coeffs com -1 e bound -80; 'no máximo 40' é x<=40 → coeffs com +1 e bound 40.\n\
         PROIBIÇÃO ABSOLUTA — NÃO INVENTE TWINS: NÃO divida uma única afirmação de limite em dois \
         constraints. Se o texto diz apenas 'no mínimo 80 mg', emita SOMENTE a constraint x>=80 \
         (coeffs=[-1], bound=-80). NÃO crie um segundo constraint 'limite inferior' ou 'limite superior' \
         paralelo. NÃO invente um limite oposto (inferior ou superior) que não esteja LITERALMENTE no texto. \
         Cada afirmação do texto deve gerar NO MÁXIMO UMA constraint.\n\
         Responda SOMENTE com JSON, sem prosa: \
         {{\"variables\":[\"unidade|entidade\",...],\"constraints\":[{{\"label\":\"texto curto\",\"coeffs\":[inteiro por variável],\"bound\":inteiro}}]}}. \
         Se NÃO houver afirmações quantitativas lineares explícitas, responda \
         {{\"variables\":[],\"constraints\":[]}}. NÃO invente; só o que está LITERALMENTE no texto.\
         \n\n=== TEXTO ===\n{}",
        draft_excerpt
    );
    // Meta barato: `call_llm_extraction` força o modelo de chat (deepseek-chat) explicitamente,
    // então não dependemos do tier para escolher o modelo — só do override de `req.model`.
    let meta = RequestMeta::new(
        false,
        false,
        false,
        prompt.chars().count() / 4,
        false,
        false,
        false,
    );
    let (text, _tier) = call_llm_extraction(ctx, run_id, &prompt, meta).await.ok()?;

    let parsed: serde_json::Value = serde_json::from_str(&first_json_object(&text)?).ok()?;
    let cons_json = parsed.get("constraints")?.as_array()?;
    let mut constraints: Vec<inference_client::LiaConstraint> = Vec::new();
    for c in cons_json {
        let coeffs: Vec<i64> = match c.get("coeffs").and_then(|v| v.as_array()) {
            Some(arr) => arr.iter().filter_map(|v| v.as_i64()).collect(),
            None => continue,
        };
        if coeffs.is_empty() || coeffs.iter().all(|&k| k == 0) {
            continue;
        }
        let bound = match c.get("bound").and_then(|v| v.as_i64()) {
            Some(b) => b,
            None => continue,
        };
        let label = c
            .get("label")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        constraints.push(inference_client::LiaConstraint {
            coeffs,
            bound,
            label,
        });
    }
    // Dedup e filtra twins fabricados antes de enviar ao solver.
    let constraints = dedup_constraints(constraints);
    if constraints.len() < 2 {
        registry.push(VerdictRecord {
            verb: "smt.check",
            input_sha256: String::new(),
            result: "extraction-empty".to_string(),
            run_id: run_id.to_string(),
        });
        return None; // precisa de >=2 claims não-redundantes pra haver contradição
    }

    // Fingerprint o JSON exato que será POSTado ao solver.
    let artifact = serde_json::to_string(&constraints).unwrap_or_default();
    let sha = artifact_sha256(&artifact);
    let base = inference_client::inference_base_url();
    let verdict = inference_client::smt_check(&base, constraints.clone()).await;
    registry.push(VerdictRecord {
        verb: "smt.check",
        input_sha256: sha,
        result: match verdict {
            inference_client::Verdict::Sat => "SAT",
            inference_client::Verdict::Unsat => "UNSAT",
            inference_client::Verdict::Unknown => "UNKNOWN",
        }
        .to_string(),
        run_id: run_id.to_string(),
    });
    match verdict {
        inference_client::Verdict::Unsat => {
            let lines: Vec<String> = constraints
                .iter()
                .map(|c| {
                    format!(
                        "- `{}`",
                        c.label
                            .clone()
                            .unwrap_or_else(|| format!("Σ{:?}·x <= {}", c.coeffs, c.bound))
                    )
                })
                .collect();
            info!(
                n_constraints = constraints.len(),
                "solver_claim_consistency: UNSAT — contradição provada por Sounio smt.check"
            );
            Some(format!(
                "## ⚠️ Contradição provada por solver (Sounio SMT)\n\n\
                O verificador formal `smt.check` (Sounio, DPLL(T) QF_LIA) provou que o conjunto de \
                afirmações quantitativas abaixo — extraídas do draft — é **mutuamente contraditório** (UNSAT).\n\n\
                **Conjunto extraído (após dedup; pode conter constraints redundantes além do núcleo conflitante):**\n\n\
                {}\n\n\
                > **Honestidade (truth-mode):** a EXTRAÇÃO de claims é feita por LLM e é falível. \
                O solver provou apenas que ESTAS constraints são inconsistentes entre si — \
                confirme contra o texto antes de afirmar que o draft em si está errado.",
                lines.join("\n")
            ))
        }
        _ => None,
    }
}

/// Verificação formal de independência causal via Sounio `causal.dsep`.
///
/// Fluxo:
/// 1. O LLM (deepseek-chat, temperatura 0) tenta extrair do draft um DAG compacto
///    (nós + arestas dirigidas) e uma query de d-separação (x, y, conditioning set z).
/// 2. O JSON é validado ESTRITAMENTE: qualquer campo ausente, tipo errado, ou grafo com
///    >32 nós ou aresta inválida → retorna `None` imediatamente (honestidade antes de tudo).
/// 3. O verbo `causal.dsep` (Sounio, Bayes-ball de Pearl) decide.
/// 4. Retorna um bloco markdown APENAS quando o solver prova d-separação (caminho bloqueado)
///    em uma relação que o draft afirma como dependente/causal — sinal de incoerência estrutural.
///    SAT (d-connected) ou Unknown → `None`.
///
/// **Honestidade (truth-mode):** a extração de grafos causais a partir de prosa é altamente
/// falível. O grafo extraído raramente captura todas as arestas reais do draft. O achado
/// reportado refere-se APENAS ao grafo extraído — não ao sistema causal real do autor.
/// ARGOS deve tratar este sinal como fraco/indicativo, nunca como prova definitiva.
/// Thin wrapper preserving the historic signature for direct callers/tests.
async fn causal_claim_check(draft: &str, ctx: &BeagleContext, run_id: &str) -> Option<String> {
    let mut registry = VerdictRegistry::new();
    causal_claim_check_traced(draft, ctx, run_id, &mut registry).await
}

/// Traced variant of [`causal_claim_check`]: emits exactly one [`VerdictRecord`]
/// on every code path (gate-off, validation-rejected, d-separated/d-connected,
/// transport-error). Called by `run_argos`.
async fn causal_claim_check_traced(
    draft: &str,
    ctx: &BeagleContext,
    run_id: &str,
    registry: &mut VerdictRegistry,
) -> Option<String> {
    if !dsep_claim_check_enabled() {
        registry.push(VerdictRecord {
            verb: "causal.dsep",
            input_sha256: String::new(),
            result: "gate-off".to_string(),
            run_id: run_id.to_string(),
        });
        return None;
    }
    let draft_excerpt: String = draft.chars().take(6000).collect();
    let prompt = format!(
        "Extraia DO TEXTO abaixo, SE E SOMENTE SE houver afirmações causais EXPLÍCITAS e \
         INEQUÍVOCAS, um grafo dirigido acíclico (DAG) compacto e uma query de d-separação.\n\
         PASSO 1 — IDENTIFIQUE VARIÁVEIS CAUSAIS EXPLÍCITAS: liste variáveis/entidades distintas \
         mencionadas explicitamente como causas ou efeitos. Atribua índices 0,1,2,... \
         (máximo 16 variáveis). Se não houver relações causais explícitas, responda com o JSON \
         vazio abaixo.\n\
         PASSO 2 — IDENTIFIQUE ARESTAS: só inclua arestas AFIRMADAS LITERALMENTE no texto \
         (\"X causa Y\", \"X afeta Y\", \"Y depende de X\", etc.). NÃO infira nem invente.\n\
         PASSO 3 — ESCOLHA UMA QUERY: selecione dois nós x e y que o texto AFIRMA que têm \
         uma relação causal ou de dependência. O conditioning set z deve ser vazio ou \
         conter APENAS variáveis explicitamente mencionadas como confundidoras/mediadoras.\n\
         Responda SOMENTE com JSON (sem prosa):\n\
         {{\"nodes\":[\"nome0\",\"nome1\",...],\"edges\":[[from_int,to_int],...],\
         \"x\":int,\"y\":int,\"z\":[int,...],\
         \"claim\":\"texto literal da relação causal afirmada\"}}\n\
         Se NÃO houver relações causais explícitas e inequívocas, responda:\n\
         {{\"nodes\":[],\"edges\":[],\"x\":0,\"y\":0,\"z\":[],\"claim\":\"\"}}\n\
         NÃO invente; só o que está LITERALMENTE no texto.\n\n\
         === TEXTO ===\n{}",
        draft_excerpt
    );
    let meta = RequestMeta::new(
        false,
        false,
        false,
        prompt.chars().count() / 4,
        false,
        false,
        false,
    );
    let text = match call_llm_extraction(ctx, run_id, &prompt, meta).await {
        Ok((t, _tier)) => t,
        Err(_) => {
            registry.push(VerdictRecord {
                verb: "causal.dsep",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };

    // Strict validation in an inner closure so any early `?`/`None` converges to a
    // single `validation-rejected` VerdictRecord below (honest-by-construction).
    let extracted: Option<(inference_client::DsepRequest, Vec<String>, String, usize)> = (|| {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(&text)?).ok()?;

        let nodes = parsed.get("nodes")?.as_array()?;
        let edges_raw = parsed.get("edges")?.as_array()?;
        let x = parsed.get("x")?.as_u64()? as usize;
        let y = parsed.get("y")?.as_u64()? as usize;
        let claim = parsed
            .get("claim")?
            .as_str()
            .unwrap_or("")
            .trim()
            .to_string();

        // Empty extraction → nothing to check (honest: no finding).
        if nodes.is_empty() || claim.is_empty() {
            return None;
        }
        let n = nodes.len();
        // Reject oversized or trivially degenerate graphs.
        if n > 32 || n < 2 || x >= n || y >= n || x == y {
            return None;
        }

        let z_arr = parsed.get("z")?.as_array()?;
        let z: Vec<usize> = z_arr
            .iter()
            .filter_map(|v| v.as_u64().map(|u| u as usize))
            .collect();
        if z.iter().any(|&zi| zi >= n) {
            return None;
        }

        let mut edges: Vec<[usize; 2]> = Vec::new();
        for e in edges_raw {
            let pair = e.as_array()?;
            if pair.len() != 2 {
                return None;
            }
            let a = pair[0].as_u64()? as usize;
            let b = pair[1].as_u64()? as usize;
            if a >= n || b >= n {
                return None;
            }
            edges.push([a, b]);
        }
        // Need at least one edge connecting x→...→y path candidates.
        if edges.is_empty() {
            return None;
        }
        let edges_len = edges.len();

        let node_names: Vec<String> = nodes
            .iter()
            .map(|v| v.as_str().unwrap_or("?").to_string())
            .collect();

        let req = inference_client::DsepRequest {
            n,
            edges,
            x,
            y,
            z: z.clone(),
        };
        Some((req, node_names, claim, edges_len))
    })();

    let (req, node_names, claim, edges_len) = match extracted {
        Some(v) => v,
        None => {
            registry.push(VerdictRecord {
                verb: "causal.dsep",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };
    let (x, y, z) = (req.x, req.y, req.z.clone());

    let artifact = serde_json::to_string(&req).unwrap_or_default();
    let sha = artifact_sha256(&artifact);
    let base = inference_client::inference_base_url();
    let verdict = inference_client::causal_dsep(&base, req).await;
    registry.push(VerdictRecord {
        verb: "causal.dsep",
        input_sha256: sha,
        result: match verdict {
            inference_client::DsepVerdict::Separated => "d-separated",
            inference_client::DsepVerdict::Connected => "d-connected",
            inference_client::DsepVerdict::Unknown => "transport-error",
        }
        .to_string(),
        run_id: run_id.to_string(),
    });
    match verdict {
        inference_client::DsepVerdict::Separated => {
            // The draft CLAIMS dependence between x and y, but the solver proves d-separation
            // given z — structural incoherence in the extracted DAG.
            let x_name = node_names
                .get(x)
                .cloned()
                .unwrap_or_else(|| format!("node{x}"));
            let y_name = node_names
                .get(y)
                .cloned()
                .unwrap_or_else(|| format!("node{y}"));
            let z_names: Vec<String> = z
                .iter()
                .map(|&zi| {
                    node_names
                        .get(zi)
                        .cloned()
                        .unwrap_or_else(|| format!("node{zi}"))
                })
                .collect();
            let cond = if z_names.is_empty() {
                "∅ (sem condicionamento)".to_string()
            } else {
                format!("{{{}}}", z_names.join(", "))
            };
            info!(
                "causal_claim_check: d-separation proved — {} ⊥ {} | {}",
                x_name, y_name, cond
            );
            Some(format!(
                "## ⚠️ Incoerência causal detectada por solver (Sounio causal.dsep)\n\n\
                O verificador formal `causal.dsep` (Sounio, Bayes-ball de Pearl) analisou o grafo \
                causal extraído do draft e provou **d-separação** entre **{}** e **{}** dado \
                **{}** — ou seja, no DAG extraído NÃO existe caminho ativo entre estes nós, \
                mas o texto afirma uma relação de dependência/causalidade:\n\n\
                > *\"{}\"*\n\n\
                **Grafo extraído ({} arestas):** {}\n\n\
                > **Honestidade (truth-mode):** a extração de grafos causais a partir de prosa é \
                altamente falível. O solver provou d-separação apenas no grafo extraído — \
                que pode estar incompleto. Verifique se o draft omitiu arestas que justificariam \
                a relação afirmada antes de concluir que o texto está errado.",
                x_name,
                y_name,
                cond,
                claim,
                edges_len,
                node_names
                    .iter()
                    .enumerate()
                    .map(|(i, name)| format!("{i}:{name}"))
                    .collect::<Vec<_>>()
                    .join(", ")
            ))
        }
        // Connected or Unknown → no finding (honest: absence of evidence ≠ evidence of absence).
        _ => None,
    }
}

/// Verificação formal de propagação de incerteza via Sounio `gum.propagate`.
///
/// Fluxo:
/// 1. O LLM (deepseek-chat, temp 0) extrai do draft, SE E SOMENTE SE houver, uma grandeza
///    DERIVADA `Y` calculada a partir de EXATAMENTE dois insumos medidos `A` e `B` por uma
///    operação binária (`add`/`sub`/`mul`/`div`), MAIS a incerteza DECLARADA pelo draft para `Y`.
/// 2. O JSON é validado estritamente (números finitos, incertezas ≥ 0, incerteza declarada > 0,
///    operação reconhecida) — qualquer ambiguidade → `None`.
/// 3. O verbo `gum.propagate` (Sounio, GUM/JCGM 100) propaga `u(A)` e `u(B)` pela operação e
///    devolve a incerteza-padrão combinada `u_c`.
/// 4. Retorna um bloco markdown APENAS quando a incerteza DECLARADA é MATERIALMENTE MENOR que a
///    incerteza-padrão combinada propagada (subdeclaração — o erro científico sério). Tratamos
///    `±` declarado da forma MAIS GENEROSA possível (como 1σ): se mesmo assim ele é menor que
///    `u_c`, a declaração é insustentável sob os insumos extraídos. Sobre-declaração, SAT, e
///    qualquer falha → `None` (honesto: ausência de evidência ≠ evidência de ausência).
///
/// **Honestidade (truth-mode):** a extração dos números e da relação funcional é falível; a GUM
/// assume insumos NÃO-correlacionados e a operação extraída. O achado prova apenas que, SOB os
/// insumos e a operação extraídos, a incerteza declarada é estreita demais — não que o draft
/// esteja errado. Sinal fraco/indicativo para ARGOS.
/// Thin wrapper preserving the historic signature for direct callers/tests.
async fn gum_claim_check(draft: &str, ctx: &BeagleContext, run_id: &str) -> Option<String> {
    let mut registry = VerdictRegistry::new();
    gum_claim_check_traced(draft, ctx, run_id, &mut registry).await
}

/// Traced variant of [`gum_claim_check`]: emits exactly one [`VerdictRecord`] on
/// every code path (gate-off, validation-rejected, transport-error,
/// gum-understated, gum-ok). Called by `run_argos`.
async fn gum_claim_check_traced(
    draft: &str,
    ctx: &BeagleContext,
    run_id: &str,
    registry: &mut VerdictRegistry,
) -> Option<String> {
    if !gum_claim_check_enabled() {
        registry.push(VerdictRecord {
            verb: "gum.propagate",
            input_sha256: String::new(),
            result: "gate-off".to_string(),
            run_id: run_id.to_string(),
        });
        return None;
    }
    let draft_excerpt: String = draft.chars().take(6000).collect();
    let prompt = format!(
        "Extraia DO TEXTO abaixo, SE E SOMENTE SE houver uma grandeza DERIVADA calculada a partir \
         de EXATAMENTE DOIS insumos medidos por UMA operação aritmética binária, E o texto DECLARAR \
         explicitamente uma incerteza para essa grandeza derivada.\n\
         PASSO 1 — ACHE A GRANDEZA DERIVADA Y: ela é obtida de A e B por uma de: soma (add), \
         subtração (sub), multiplicação (mul) ou divisão (div). Ex.: clearance = dose / AUC (div); \
         exposição total = Cmax + Cmin (add).\n\
         PASSO 2 — EXTRAIA OS INSUMOS: para A e B pegue o VALOR e a INCERTEZA-PADRÃO (o '±', desvio-\
         padrão, ou erro-padrão) LITERALMENTE declarados no texto. Se o texto não declara a incerteza \
         de um insumo, NÃO invente — responda found=false.\n\
         PASSO 3 — EXTRAIA A INCERTEZA DECLARADA DE Y: o valor do '±' (ou meia-largura de IC, ou \
         desvio-padrão) que o texto atribui a Y. Se Y não tem incerteza declarada, found=false.\n\
         Responda SOMENTE com JSON, sem prosa:\n\
         {{\"found\":true|false,\"op\":\"add|sub|mul|div\",\
         \"a\":{{\"value\":num,\"u\":num,\"label\":\"texto curto\"}},\
         \"b\":{{\"value\":num,\"u\":num,\"label\":\"texto curto\"}},\
         \"y_label\":\"texto curto\",\"claimed_value\":num,\"claimed_uncertainty\":num}}\n\
         Se NÃO houver uma grandeza derivada de DOIS insumos COM incertezas declaradas E uma \
         incerteza declarada para a derivada, responda {{\"found\":false}}. NÃO invente; só o que \
         está LITERALMENTE no texto.\n\n=== TEXTO ===\n{}",
        draft_excerpt
    );
    let meta = RequestMeta::new(
        false,
        false,
        false,
        prompt.chars().count() / 4,
        false,
        false,
        false,
    );
    let text = match call_llm_extraction(ctx, run_id, &prompt, meta).await {
        Ok((t, _tier)) => t,
        Err(_) => {
            registry.push(VerdictRecord {
                verb: "gum.propagate",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };

    // Strict numeric validation in an inner closure so any early `None` converges to
    // a single `validation-rejected` VerdictRecord (honest-by-construction).
    type GumExtract = (f64, f64, String, f64, f64, String, String, f64, String);
    let extracted: Option<GumExtract> = (|| {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(&text)?).ok()?;
        if !parsed
            .get("found")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return None;
        }
        let op = parsed.get("op")?.as_str()?.trim().to_ascii_lowercase();
        if !matches!(op.as_str(), "add" | "sub" | "mul" | "div") {
            return None;
        }
        // Extrai um {value,u,label} validando finitude e u >= 0.
        let get_input = |key: &str| -> Option<(f64, f64, String)> {
            let o = parsed.get(key)?;
            let value = o.get("value")?.as_f64()?;
            let u = o.get("u")?.as_f64()?;
            if !value.is_finite() || !u.is_finite() || u < 0.0 {
                return None;
            }
            let label = o
                .get("label")
                .and_then(|v| v.as_str())
                .unwrap_or(key)
                .to_string();
            Some((value, u, label))
        };
        let (a_val, a_u, a_lbl) = get_input("a")?;
        let (b_val, b_u, b_lbl) = get_input("b")?;

        let claimed_u = parsed.get("claimed_uncertainty")?.as_f64()?;
        if !claimed_u.is_finite() || claimed_u <= 0.0 {
            return None; // sem incerteza declarada positiva não há o que comparar
        }
        let y_label = parsed
            .get("y_label")
            .and_then(|v| v.as_str())
            .unwrap_or("grandeza derivada")
            .to_string();

        // div por zero (ou perto) na operação ⇒ propagação degenera; abstém-se.
        if op == "div" && b_val.abs() < f64::EPSILON {
            return None;
        }
        Some((a_val, a_u, a_lbl, b_val, b_u, b_lbl, op, claimed_u, y_label))
    })();

    let (a_val, a_u, a_lbl, b_val, b_u, b_lbl, op, claimed_u, y_label) = match extracted {
        Some(v) => v,
        None => {
            registry.push(VerdictRecord {
                verb: "gum.propagate",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };

    let req = inference_client::GumRequest {
        inputs: vec![
            inference_client::GumInput {
                value: a_val,
                u: a_u,
                label: Some(a_lbl.clone()),
            },
            inference_client::GumInput {
                value: b_val,
                u: b_u,
                label: Some(b_lbl.clone()),
            },
        ],
        op: op.clone(),
    };
    let artifact = serde_json::to_string(&req).unwrap_or_default();
    let sha = artifact_sha256(&artifact);
    let base = inference_client::inference_base_url();
    let propagated = match inference_client::gum_propagate(&base, req).await {
        Some(p) => p,
        None => {
            registry.push(VerdictRecord {
                verb: "gum.propagate",
                input_sha256: sha,
                result: "transport-error".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };
    let u_c = propagated.combined_std_uncertainty;
    if !u_c.is_finite() || u_c <= 0.0 {
        registry.push(VerdictRecord {
            verb: "gum.propagate",
            input_sha256: sha,
            result: "transport-error".to_string(),
            run_id: run_id.to_string(),
        });
        return None;
    }

    // Veredito: subdeclaração (gum-understated) dispara achado; caso contrário gum-ok.
    let understated = claimed_u < u_c * 0.8;
    registry.push(VerdictRecord {
        verb: "gum.propagate",
        input_sha256: sha,
        result: if understated {
            "gum-understated"
        } else {
            "gum-ok"
        }
        .to_string(),
        run_id: run_id.to_string(),
    });

    // Subdeclaração: a incerteza declarada (lida da forma MAIS generosa, como 1σ) é
    // materialmente menor que a incerteza-padrão combinada propagada. Margem conservadora
    // de 20% para absorver ruído de extração — só dispara em subdeclaração CLARA.
    if !understated {
        return None;
    }
    let pct_tighter = ((u_c - claimed_u) / u_c * 100.0).round() as i64;

    info!(
        u_c,
        claimed_u,
        op = %op,
        "gum_claim_check: incerteza declarada subdeclarada vs propagação GUM"
    );
    Some(format!(
        "## ⚠️ Incerteza subdeclarada — propagação GUM (Sounio gum.propagate)\n\n\
        O verificador formal `gum.propagate` (Sounio, GUM/JCGM 100) propagou a incerteza dos \
        insumos declarados pelo draft através da operação `{op}` e obteve, para **{y}**:\n\n\
        - incerteza-padrão combinada **u_c = {u_c:.4}** (U₉₅ = {u95:.4}, k ≈ {k:.2}; IC95% [{lo:.4}, {hi:.4}]).\n\n\
        O draft, porém, declara uma incerteza de **±{claimed:.4}** para a mesma grandeza — \
        **{pct}% mais estreita** que a incerteza-padrão combinada propagada. Mesmo na leitura mais \
        generosa (tratando o `±` declarado como 1σ), a incerteza declarada é menor que a propagação \
        GUM permite a partir dos insumos declarados (`{a_lbl}`: {a_val}±{a_u}; `{b_lbl}`: {b_val}±{b_u}).\n\n\
        > **Honestidade (truth-mode):** a EXTRAÇÃO dos números e da relação funcional é feita por LLM \
        e é falível; a GUM aqui assume insumos NÃO-correlacionados e a operação `{op}` extraída. \
        O solver provou apenas que, SOB os insumos e a operação extraídos, a incerteza declarada é \
        menor que a propagada — confirme contra o texto (convenção do `±`, correlação dos insumos, \
        relação funcional real) antes de afirmar que o draft está errado.",
        op = op,
        y = y_label,
        u_c = u_c,
        u95 = propagated.expanded_uncertainty_95,
        k = propagated.coverage_factor_k95,
        lo = propagated.interval_95[0],
        hi = propagated.interval_95[1],
        claimed = claimed_u,
        pct = pct_tighter,
        a_lbl = a_lbl,
        a_val = a_val,
        a_u = a_u,
        b_lbl = b_lbl,
        b_val = b_val,
        b_u = b_u,
    ))
}

/// Verificação formal de dedução proposicional via Sounio `theorem.prove`.
///
/// O backstop MAIS FRACO e mais conservador dos quatro. Fluxo:
/// 1. O LLM (deepseek-chat, temp 0) extrai do draft, SE E SOMENTE SE houver uma dedução
///    proposicional EXPLÍCITA e AUTO-CONTIDA (marcadores "portanto/logo/conclui-se/segue-se"),
///    cujas premissas o texto afirma serem SUFICIENTES para a conclusão: átomos nomeados,
///    hipóteses e meta como árvores proposicionais (atom/not/and/or/implies).
/// 2. Validação local mínima (átomos 1..32, ≥1 hipótese, meta presente); as árvores são
///    repassadas e o serviço valida a estrutura (malformado → não-2xx → `None`).
/// 3. O verbo `theorem.prove` (Sounio, dedução natural, SOM por construção: só derivação real)
///    decide. PROVED → sem achado (a dedução se sustenta).
/// 4. Retorna um bloco markdown quando o prover NÃO deriva a conclusão (`UNKNOWN`/`INVALID`)
///    de uma dedução que o draft afirma ser suficiente — possível non-sequitur.
///
/// **Honestidade (truth-mode) — crítica aqui:** `UNKNOWN` **NÃO é refutação**. O prover é
/// PROPOSICIONAL e de profundidade limitada; uma dedução cientificamente válida que repouse
/// sobre premissas implícitas (conhecimento de domínio, aritmética, quantificadores) também dá
/// `UNKNOWN`. Por isso o achado é uma HIPÓTESE FRACA: "ou faltam premissas no texto, ou é um
/// non-sequitur" — nunca um veredito de invalidez.
/// Thin wrapper preserving the historic signature for direct callers/tests.
async fn theorem_claim_check(draft: &str, ctx: &BeagleContext, run_id: &str) -> Option<String> {
    let mut registry = VerdictRegistry::new();
    theorem_claim_check_traced(draft, ctx, run_id, &mut registry).await
}

/// Traced variant of [`theorem_claim_check`]: emits exactly one [`VerdictRecord`]
/// on every code path (gate-off, validation-rejected, transport-error, PROVED,
/// UNKNOWN, INVALID). Called by `run_argos`.
async fn theorem_claim_check_traced(
    draft: &str,
    ctx: &BeagleContext,
    run_id: &str,
    registry: &mut VerdictRegistry,
) -> Option<String> {
    if !theorem_claim_check_enabled() {
        registry.push(VerdictRecord {
            verb: "theorem.prove",
            input_sha256: String::new(),
            result: "gate-off".to_string(),
            run_id: run_id.to_string(),
        });
        return None;
    }
    let draft_excerpt: String = draft.chars().take(6000).collect();
    let prompt = format!(
        "Extraia DO TEXTO abaixo, SE E SOMENTE SE houver uma DEDUÇÃO LÓGICA proposicional \
         EXPLÍCITA, INEQUÍVOCA e AUTO-CONTIDA — ou seja, o texto afirma uma conclusão como \
         consequência LÓGICA de premissas declaradas (marcadores: 'portanto', 'logo', \
         'conclui-se que', 'segue-se que', 'therefore'), e as premissas declaradas são \
         apresentadas como SUFICIENTES para a conclusão.\n\
         REGRA DE OURO — SÓ EXTRAIA SE FOR PURAMENTE PROPOSICIONAL: a dedução deve ser \
         expressável SÓ com proposições atômicas (verdadeiro/falso) e os conectivos E (and), \
         OU (or), NÃO (not), SE-ENTÃO (implies). Se o argumento depende de aritmética, \
         quantificadores ('todo', 'algum'), conhecimento de domínio implícito, ou relações \
         numéricas/causais, responda found=false. NÃO force.\n\
         PASSO 1 — ÁTOMOS: liste as proposições atômicas distintas como strings curtas (máx 32).\n\
         PASSO 2 — HIPÓTESES: cada premissa declarada como uma árvore. Uma árvore é um objeto de \
         CHAVE ÚNICA: {{\"atom\":\"nome\"}}, {{\"not\":<árvore>}}, {{\"and\":[<árvore>,<árvore>]}}, \
         {{\"or\":[<árvore>,<árvore>]}}, {{\"implies\":[<árvore>,<árvore>]}}.\n\
         PASSO 3 — META: a conclusão afirmada, como uma árvore no mesmo formato.\n\
         Responda SOMENTE com JSON, sem prosa:\n\
         {{\"found\":true|false,\"atoms\":[\"...\"],\"hypotheses\":[<árvore>,...],\
         \"goal\":<árvore>,\"argument\":\"texto literal da dedução afirmada\"}}\n\
         Se NÃO houver uma dedução proposicional explícita e auto-contida, responda \
         {{\"found\":false}}. NÃO invente; só o que está LITERALMENTE no texto.\n\n\
         === TEXTO ===\n{}",
        draft_excerpt
    );
    let meta = RequestMeta::new(
        false,
        false,
        false,
        prompt.chars().count() / 4,
        false,
        false,
        false,
    );
    let text = match call_llm_extraction(ctx, run_id, &prompt, meta).await {
        Ok((t, _tier)) => t,
        Err(_) => {
            registry.push(VerdictRecord {
                verb: "theorem.prove",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };

    // Strict validation in an inner closure so any early `None` converges to a single
    // `validation-rejected` VerdictRecord (honest-by-construction).
    type TheoremExtract = (
        Vec<String>,
        Vec<serde_json::Value>,
        serde_json::Value,
        String,
    );
    let extracted: Option<TheoremExtract> = (|| {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(&text)?).ok()?;
        if !parsed
            .get("found")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return None;
        }
        let atoms: Vec<String> = parsed
            .get("atoms")?
            .as_array()?
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect();
        if atoms.is_empty() || atoms.len() > 32 {
            return None;
        }
        let hypotheses: Vec<serde_json::Value> = parsed.get("hypotheses")?.as_array()?.clone();
        if hypotheses.is_empty() {
            return None; // sem premissas não há dedução a checar
        }
        let goal = parsed.get("goal")?.clone();
        if !goal.is_object() {
            return None;
        }
        let argument = parsed
            .get("argument")?
            .as_str()
            .unwrap_or("")
            .trim()
            .to_string();
        if argument.is_empty() {
            return None;
        }
        Some((atoms, hypotheses, goal, argument))
    })();

    let (atoms, hypotheses, goal, argument) = match extracted {
        Some(v) => v,
        None => {
            registry.push(VerdictRecord {
                verb: "theorem.prove",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };

    let n_hyps = hypotheses.len();
    let req = inference_client::TheoremRequest {
        atoms: atoms.clone(),
        hypotheses,
        goal,
        depth: 12, // bem acima do default 6 — reduz UNKNOWN espúrio por busca rasa
    };
    let artifact = serde_json::to_string(&req).unwrap_or_default();
    let sha = artifact_sha256(&artifact);
    let base = inference_client::inference_base_url();
    // Some(Proved)/None → sem achado. None inclui serviço fora E estrutura malformada (422):
    // honesto — nunca confundir "serviço indisponível" com "non-sequitur".
    let verdict = match inference_client::theorem_prove(&base, req).await {
        Some(v) => v,
        None => {
            registry.push(VerdictRecord {
                verb: "theorem.prove",
                input_sha256: sha,
                result: "transport-error".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };
    registry.push(VerdictRecord {
        verb: "theorem.prove",
        input_sha256: sha,
        result: match verdict {
            inference_client::ProofVerdict::Proved => "PROVED",
            inference_client::ProofVerdict::Unknown => "UNKNOWN",
            inference_client::ProofVerdict::Invalid => "INVALID",
        }
        .to_string(),
        run_id: run_id.to_string(),
    });
    let outcome = match verdict {
        inference_client::ProofVerdict::Proved => return None,
        inference_client::ProofVerdict::Unknown => "UNKNOWN (nenhuma derivação encontrada)",
        inference_client::ProofVerdict::Invalid => "INVALID (a derivação falhou na verificação)",
    };
    info!(
        n_hyps,
        n_atoms = atoms.len(),
        result = outcome,
        "theorem_claim_check: dedução proposicional explícita NÃO reconstruída pelo prover"
    );
    Some(format!(
        "## ⚠️ Dedução não reconstruída — prova proposicional (Sounio theorem.prove)\n\n\
        O verificador formal `theorem.prove` (Sounio, dedução natural proposicional; SOM por \
        construção: só conta derivação real) **NÃO conseguiu derivar** a conclusão a partir das \
        {n} premissas EXPLÍCITAS extraídas do draft, que o texto apresenta como dedução lógica:\n\n\
        > *\"{arg}\"*\n\n\
        **Átomos extraídos:** {atoms}. **Resultado do prover:** {res}.\n\n\
        > **Honestidade (truth-mode) — leia com cuidado:** `UNKNOWN` **NÃO é uma refutação**. O \
        prover é PROPOSICIONAL e de profundidade limitada: ele não encontrou derivação, mas a \
        dedução pode repousar sobre premissas IMPLÍCITAS (conhecimento de domínio, aritmética, \
        quantificadores) não capturadas na extração, ou sobre uma relação não-proposicional. \
        Trate como hipótese FRACA — ou faltam premissas no texto, ou é um non-sequitur — e \
        verifique manualmente antes de afirmar que o argumento é inválido.",
        n = n_hyps,
        arg = argument,
        atoms = atoms.join(", "),
        res = outcome,
    ))
}

pub async fn run_argos(
    original_draft: &str,
    hermes: &TriadOpinion,
    athena: &TriadOpinion,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(TriadOpinion, ProviderTier, VerificationSummary)> {
    // P1: VerdictRegistry — populado ANTES da chamada LLM do ARGOS. Cada função traced
    // empurra exatamente um VerdictRecord, então a ground truth existe antes de ARGOS
    // escrever qualquer coisa. Local à run; nunca persistido (sem records obsoletos).
    let mut registry = VerdictRegistry::new();

    let mut prompt = String::from(
        "Você é ARGOS, agente crítico adversarial do sistema BEAGLE.\n\n\
        Você atua como revisor Q1 rigoroso (Nature Human Behaviour, Kybernetes, Frontiers in Computational Neuroscience).\n\
        Foque especialmente em:\n\
        - Claims sem suporte empírico adequado (extrapolações não suportadas)\n\
        - Confusão entre metáfora poética e mecanismo científico concreto\n\
        - Ausência de desenho empírico razoável (onde há espaço para experimentos/predictions testáveis)\n\
        - Problemas de coerência lógica e ambiguidade conceitual\n\n\
        REGRA INVIOLÁVEL — VERIFICAÇÕES FORMAIS POR SOLVER:\n\
        Você só pode citar um resultado de solver formal (Sounio `smt.check`, `causal.dsep`, \
        `gum.propagate`, `theorem.prove`, ou qualquer verificador) se ele aparecer LITERALMENTE \
        numa seção `=== VERIFICAÇÃO FORMAL ... ===` fornecida abaixo. NUNCA afirme que um solver \
        \"rodou\", \"provou\", \"retornou\" (UNSAT/SAT/UNKNOWN/PROVED/d-separação/etc.) ou foi \
        \"validado por\" se NÃO houver o bloco correspondente no input. NÃO invente, NÃO infira, \
        NÃO presuma qual seria o veredito, e NÃO nomeie um verbo de solver que não foi fornecido. \
        Se NENHUMA seção de verificação formal estiver presente, NÃO mencione solvers — faça sua \
        crítica como raciocínio próprio, explicitamente SEM atribuí-la a um verificador. \
        Atribuir a um solver um resultado que não foi fornecido é uma FALHA GRAVE de honestidade.\n\n\
        Você recebeu:\n\
        - O DRAFT original de um artigo\n\
        - Um DRAFT reescrito por HERMES\n\
        - Comentários de ATHENA\n\n\
        Sua função:\n\
        1. Liste problemas graves de coerência lógica, extrapolações não suportadas, ambiguidade.\n\
        2. Aponte onde HERMES melhorou o texto e onde piorou.\n\
        3. Sugira correções pontuais (especialmente onde o texto precisa ser mais rigoroso cientificamente).\n\n\
        Responda em Markdown com seções: ## Problemas Graves, ## Melhorias de HERMES, ## Sugestões Pontuais.\n\n",
    );

    prompt.push_str("=== ATHENA_FEEDBACK ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== DRAFT_ORIGINAL ===\n");
    prompt.push_str(original_draft);
    prompt.push_str("\n\n=== DRAFT_HERMES ===\n");
    prompt.push_str(&hermes.suggestions_md);

    // Verificação formal de consistência via Sounio smt.check (gated). UNSAT = contradição
    // PROVADA por solver — sinal forte para ARGOS, e surfaceado no relatório. Honesto:
    // None quando não há contradição provada ou o serviço está fora.
    let solver_finding =
        solver_claim_consistency_traced(original_draft, ctx, run_id, &mut registry).await;
    if let Some(ref f) = solver_finding {
        prompt.push_str("\n\n=== VERIFICAÇÃO FORMAL POR SOLVER (Sounio SMT — verificada) ===\n");
        prompt.push_str(f);
        prompt.push_str(
            "\nIncorpore este achado verificado por solver na sua crítica. É forte (prova \
             formal), mas a EXTRAÇÃO de claims que o alimentou é falível — trate a contradição \
             como provada apenas para as constraints extraídas, não como veredito sobre o autor.\n",
        );
    }

    // Segunda verificação formal: d-separação causal via Sounio causal.dsep (gated).
    // Prova d-separação no grafo causal EXTRAÍDO do draft — incoerência estrutural
    // quando o texto afirma dependência mas o DAG extraído a bloqueia.
    // Sinal FRACO (extração de grafos causais é altamente falível): None em caso de
    // dúvida, erro, grafo insuficiente, ou d-conexão (status quo).
    let causal_finding =
        causal_claim_check_traced(original_draft, ctx, run_id, &mut registry).await;
    if let Some(ref f) = causal_finding {
        prompt
            .push_str("\n\n=== VERIFICAÇÃO FORMAL CAUSAL (Sounio causal.dsep — estrutural) ===\n");
        prompt.push_str(f);
        prompt.push_str(
            "\nEste achado é baseado no grafo causal extraído do draft (pode estar incompleto). \
             Trate como hipótese a investigar: o draft pode ter omitido arestas que justificam \
             a relação afirmada. A prova de d-separação é formal apenas para o DAG extraído.\n",
        );
    }

    // Terceira verificação formal: propagação de incerteza via Sounio gum.propagate (gated).
    // Propaga a incerteza dos insumos declarados pela operação extraída e dispara só quando a
    // incerteza DECLARADA para a grandeza derivada é materialmente MENOR que a propagada
    // (subdeclaração). Sinal indicativo: a propagação é formal, mas os números/operação
    // extraídos são falíveis e a GUM assume insumos não-correlacionados. None em caso de dúvida.
    let gum_finding = gum_claim_check_traced(original_draft, ctx, run_id, &mut registry).await;
    if let Some(ref f) = gum_finding {
        prompt
            .push_str("\n\n=== VERIFICAÇÃO FORMAL DE INCERTEZA (Sounio gum.propagate — GUM) ===\n");
        prompt.push_str(f);
        prompt.push_str(
            "\nEste achado compara a incerteza DECLARADA no draft com a propagação GUM dos insumos \
             extraídos. Trate como hipótese: confirme a convenção do `±` (1σ vs IC95%), se os \
             insumos são correlacionados, e se a relação funcional extraída é a real, antes de \
             concluir que a incerteza declarada está subdeclarada.\n",
        );
    }

    // Quarta verificação formal: dedução proposicional via Sounio theorem.prove (gated).
    // O sinal MAIS FRACO: dispara só quando o prover NÃO reconstrói uma dedução proposicional
    // que o draft afirma ser suficiente. UNKNOWN ≠ refutação (prover proposicional/profundidade
    // limitada) — por isso entra como hipótese fraca, com a ressalva mais forte. None em dúvida.
    let theorem_finding =
        theorem_claim_check_traced(original_draft, ctx, run_id, &mut registry).await;
    if let Some(ref f) = theorem_finding {
        prompt.push_str(
            "\n\n=== VERIFICAÇÃO FORMAL DEDUTIVA (Sounio theorem.prove — proposicional) ===\n",
        );
        prompt.push_str(f);
        prompt.push_str(
            "\nSinal FRACO: o prover é proposicional e de profundidade limitada, então `UNKNOWN` \
             NÃO é refutação. Trate como hipótese — ou o draft omitiu premissas, ou a dedução é \
             um non-sequitur. NÃO afirme invalidez do argumento só com base neste achado; use-o \
             para PEDIR que as premissas sejam tornadas explícitas.\n",
        );
    }

    // P4: VerificationSummary a partir do estado dos gates + desfecho de cada verbo.
    // Um verbo "ran" quando seu gate estava ON (independentemente do sucesso da extração);
    // "abstained" = gate OFF; "finding_emitted" = 1 só quando houve achado de incoerência.
    let verb_stats = |gate: bool, finding: &Option<String>| -> VerbStats {
        if gate {
            VerbStats {
                ran: 1,
                abstained: 0,
                finding_emitted: finding.is_some() as u8,
            }
        } else {
            VerbStats {
                ran: 0,
                abstained: 1,
                finding_emitted: 0,
            }
        }
    };
    let smt_s = verb_stats(smt_claim_check_enabled(), &solver_finding);
    let causal_s = verb_stats(dsep_claim_check_enabled(), &causal_finding);
    let gum_s = verb_stats(gum_claim_check_enabled(), &gum_finding);
    let theorem_s = verb_stats(theorem_claim_check_enabled(), &theorem_finding);
    let total_ran = (smt_s.ran + causal_s.ran + gum_s.ran + theorem_s.ran) as usize;
    let total_findings = (smt_s.finding_emitted
        + causal_s.finding_emitted
        + gum_s.finding_emitted
        + theorem_s.finding_emitted) as usize;
    let finding_rate = (total_ran > 0).then(|| total_findings as f32 / total_ran as f32);
    let vsummary = VerificationSummary {
        smt: smt_s,
        causal: causal_s,
        gum: gum_s,
        theorem: theorem_s,
        completed_at: Utc::now().to_rfc3339(),
        finding_rate,
    };
    let machine_note = vsummary.machine_note();

    // ARGOS usa Heavy: crítica sobre claims científicos
    let meta = RequestMeta::new(
        false,                      // requires_math (ou true se for Methods de KEC/PBPK)
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,                       // high_bias_risk (crítica sobre claims científicos)
        true,                       // requires_phd_level_reasoning
        true,                       // critical_section (revisão crítica)
    );

    let (raw_text, tier) = call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await?;

    // P1: validador post-hoc de atribuição. Varre o texto do LLM por co-ocorrências
    // (verbo, veredito). Qualquer atribuição sem VerdictRecord correspondente é REDIGIDA
    // (não apenas avisada) — correção estrutural, não lembrete de prompt.
    let (validated_text, integrity_summary) = registry.redact_unattested(&raw_text);
    info!(
        run_id = %run_id,
        integrity = %integrity_summary,
        "run_argos: validação post-hoc de atribuição concluída"
    );

    let score = extract_score(&validated_text).unwrap_or(0.9);

    // P4: surfacea TODOS os quatro achados formais no topo do relatório de ARGOS
    // (corrige a omissão anterior de gum/theorem). Ordem: SMT, causal, GUM, theorem.
    // O machine_note vai como comentário HTML (invisível em renderers Markdown, mas
    // legível por máquina) no topo de suggestions_md.
    let mut formal_blocks: Vec<String> = Vec::new();
    if let Some(f) = solver_finding {
        formal_blocks.push(f);
    }
    if let Some(f) = causal_finding {
        formal_blocks.push(f);
    }
    if let Some(f) = gum_finding {
        formal_blocks.push(f);
    }
    if let Some(f) = theorem_finding {
        formal_blocks.push(f);
    }
    let note_block = format!("<!-- {} -->\n\n", machine_note);
    let suggestions_md = if formal_blocks.is_empty() {
        format!("{}{}", note_block, validated_text)
    } else {
        format!(
            "{}{}\n\n---\n\n{}",
            note_block,
            formal_blocks.join("\n\n---\n\n"),
            validated_text
        )
    };

    Ok((
        TriadOpinion {
            agent: "ARGOS".into(),
            summary: "Crítica adversarial e apontamento de falhas lógicas".into(),
            suggestions_md,
            score,
            provider_tier: tier.as_str().to_string(),
        },
        tier,
        vsummary,
    ))
}

/// Juiz final: arbitragem do draft
///
/// Combina o melhor dos três agentes (ATHENA/HERMES/ARGOS) mantendo rigor científico e estilo interdisciplinar.
/// Foca em resolver problemas críticos apontados por ARGOS enquanto preserva a voz autoral.
pub async fn arbitrate_final(
    original_draft: &str,
    hermes: &TriadOpinion,
    athena: &TriadOpinion,
    argos: &TriadOpinion,
    ctx: &BeagleContext,
    run_id: &str,
) -> anyhow::Result<(String, ProviderTier)> {
    // Contexto simbólico (PCS) — GATED (OFF por padrão). Quando ligado, tenta o solver Julia real
    // e cai para heurística se indisponível; o bloco se auto-rotula com o status real. Só injeta com
    // BEAGLE_SYMBOLIC_CONTEXT_ENABLE=1 (antes era injetado SEMPRE como sinal simbólico — falso no Juiz).
    let symbolic_block = if symbolic_context_enabled() {
        match generate_symbolic_summary(original_draft, ctx).await {
            Ok(s) => format!("**Contexto Simbólico (PCS)**:\n{}\n\n", s),
            Err(e) => {
                warn!("Falha ao gerar resumo simbólico: {}", e);
                String::new()
            }
        }
    } else {
        String::new()
    };

    let mut prompt = String::from(
        "Você é o JUIZ FINAL do sistema BEAGLE (HONEST AI TRIAD).\n\n\
        IMPORTANTE: Mantenha a voz autoral interdisciplinar (engenharia química, medicina, psiquiatria, biomateriais, filosofia da mente).\n\
        Preserve alta densidade conceitual e elegância técnica.\n\n\
        [[SYMBOLIC_BLOCK]]\
        Você recebeu:\n\
        - DRAFT_ORIGINAL: rascunho original do artigo.\n\
        - DRAFT_HERMES: versão reescrita por HERMES.\n\
        - FEEDBACK_ATHENA: análise crítica e sugestões de literatura.\n\
        - FEEDBACK_ARGOS: crítica adversarial rigorosa (nível Q1).\n\n\
        Sua tarefa:\n\
        1. Produzir uma versão FINAL do texto, em Markdown, incorporando o melhor de cada um.\n\
        2. Corrigir problemas graves apontados por ARGOS (claims sem suporte, confusão metáfora/mecanismo, etc.).\n\
        3. Incorporar sugestões relevantes de ATHENA quando apropriado.\n\
        4. Manter a voz autoral interdisciplinar e evitar inventar dados.\n\n\
        Responda **apenas** com o texto final em Markdown.\n\n",
    );
    prompt = prompt.replace("[[SYMBOLIC_BLOCK]]", &symbolic_block);

    prompt.push_str("=== FEEDBACK_ATHENA ===\n");
    prompt.push_str(&athena.suggestions_md);
    prompt.push_str("\n\n=== FEEDBACK_ARGOS ===\n");
    prompt.push_str(&argos.suggestions_md);

    // Contexto simbólico já foi adicionado no início do prompt

    prompt.push_str("\n\n=== DRAFT_ORIGINAL ===\n");
    prompt.push_str(original_draft);
    prompt.push_str("\n\n=== DRAFT_HERMES ===\n");
    prompt.push_str(&hermes.suggestions_md);

    // Juiz Final usa Heavy: decisão final sobre texto científico
    let meta = RequestMeta::new(
        false,                      // requires_math
        true,                       // requires_high_quality
        false,                      // offline_required
        prompt.chars().count() / 4, // approximate_tokens
        true,                       // high_bias_risk (decisão final sobre texto científico)
        true,                       // requires_phd_level_reasoning
        true,                       // critical_section (versão final)
    );

    call_llm_with_stats_triad(ctx, run_id, &prompt, meta).await
}

// update_stats removido - agora usa call_llm_with_stats_triad que atualiza ctx.llm_stats diretamente

/// Extrai score de resposta (simplificado)
fn extract_score(response: &str) -> Option<f32> {
    // Procura por padrões como "Score: 0.85" ou "0.85"
    let re = regex::Regex::new(r"score[:\s]+([0-9]+\.[0-9]+)").ok()?;
    let binding = response.to_lowercase();
    let caps = re.captures(binding.as_str())?;
    caps.get(1)?.as_str().parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_json_object_extracts_from_prose() {
        let s =
            "claro, aqui está: {\"constraints\":[{\"coeffs\":[1],\"bound\":3}]} — espero que ajude";
        let j = first_json_object(s).expect("deve extrair");
        let v: serde_json::Value = serde_json::from_str(&j).unwrap();
        assert!(v.get("constraints").unwrap().as_array().unwrap().len() == 1);
    }

    #[test]
    fn first_json_object_handles_nesting() {
        assert_eq!(
            first_json_object("x {\"a\":{\"b\":1}} y").as_deref(),
            Some("{\"a\":{\"b\":1}}")
        );
        assert!(first_json_object("no json here").is_none());
    }

    #[tokio::test]
    async fn solver_check_is_off_by_default() {
        // Sem BEAGLE_TRIAD_SMT_CHECK, a verificação não roda (nem chama LLM/serviço).
        std::env::remove_var("BEAGLE_TRIAD_SMT_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = solver_claim_consistency("dose >= 6 e dose <= 3", &ctx, "t").await;
        assert!(out.is_none());
    }

    // ===== P1: VerdictRegistry + post-hoc attribution validator =====

    fn rec(verb: &'static str, result: &str) -> VerdictRecord {
        VerdictRecord {
            verb,
            input_sha256: String::new(),
            result: result.to_string(),
            run_id: "t".to_string(),
        }
    }

    #[test]
    fn test_verdict_registry_push_and_lookup() {
        let mut reg = VerdictRegistry::new();
        reg.push(rec("smt.check", "UNSAT"));
        reg.push(rec("causal.dsep", "d-separated"));
        reg.push(rec("gum.propagate", "gum-understated"));
        reg.push(rec("theorem.prove", "UNKNOWN"));
        assert_eq!(reg.lookup("smt.check").unwrap().result, "UNSAT");
        assert_eq!(reg.lookup("causal.dsep").unwrap().result, "d-separated");
        assert_eq!(reg.lookup("theorem.prove").unwrap().result, "UNKNOWN");
        assert!(reg.lookup("nonexistent.verb").is_none());
    }

    #[test]
    fn test_redact_unattested_passes_when_record_exists() {
        let mut reg = VerdictRegistry::new();
        reg.push(rec("smt.check", "UNSAT"));
        let (out, summary) =
            reg.redact_unattested("O solver `smt.check` retornou UNSAT para o conjunto.");
        assert!(!out.contains("[REDACTED"));
        assert!(out.contains("smt.check"));
        assert!(summary.starts_with("integrity=PASS"));
        assert!(out.contains("Integrity check PASSED"));
    }

    #[test]
    fn test_redact_unattested_redacts_when_no_record() {
        let reg = VerdictRegistry::new();
        let (out, summary) =
            reg.redact_unattested("O `theorem.prove` retornou UNKNOWN, refutando o argumento.");
        assert!(out.contains("[REDACTED"));
        assert!(summary.starts_with("integrity=FAIL"));
        assert!(out.contains("Integrity check FAILED"));
    }

    #[test]
    fn test_redact_unattested_redacts_gate_off_record() {
        let mut reg = VerdictRegistry::new();
        reg.push(rec("theorem.prove", "gate-off"));
        let (out, summary) = reg.redact_unattested("O `theorem.prove` retornou UNKNOWN.");
        assert!(out.contains("[REDACTED"));
        assert!(summary.starts_with("integrity=FAIL"));
    }

    #[test]
    fn test_redact_unattested_passes_gate_off_without_verdict_word() {
        let mut reg = VerdictRegistry::new();
        reg.push(rec("theorem.prove", "gate-off"));
        // Line names the verb but NO verdict keyword → not flagged.
        let (out, summary) =
            reg.redact_unattested("O verbo `theorem.prove` está disponível no cluster.");
        assert!(!out.contains("[REDACTED"));
        assert!(summary.starts_with("integrity=PASS"));
    }

    #[test]
    fn test_artifact_sha256_is_deterministic() {
        let a = artifact_sha256("hello world");
        let b = artifact_sha256("hello world");
        assert_eq!(a, b);
        assert_eq!(a.len(), 64); // hex SHA-256
    }

    #[test]
    fn test_artifact_sha256_differs_on_different_input() {
        assert_ne!(artifact_sha256("{\"a\":1}"), artifact_sha256("{\"a\":2}"));
    }

    #[tokio::test]
    async fn test_solver_claim_consistency_traced_pushes_gate_off_when_disabled() {
        std::env::remove_var("BEAGLE_TRIAD_SMT_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let mut reg = VerdictRegistry::new();
        let out =
            solver_claim_consistency_traced("dose >= 6 e dose <= 3", &ctx, "t", &mut reg).await;
        assert!(out.is_none());
        assert_eq!(reg.lookup("smt.check").unwrap().result, "gate-off");
    }

    #[tokio::test]
    async fn test_theorem_claim_check_traced_pushes_gate_off_when_disabled() {
        std::env::remove_var("BEAGLE_TRIAD_THEOREM_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let mut reg = VerdictRegistry::new();
        let out = theorem_claim_check_traced("logo, portanto X", &ctx, "t", &mut reg).await;
        assert!(out.is_none());
        assert_eq!(reg.lookup("theorem.prove").unwrap().result, "gate-off");
    }

    #[test]
    fn test_integrity_note_appears_for_spurious_attribution() {
        // End-to-end of the redaction layer: an empty registry (no solver ran) and
        // ARGOS text that fabricates a theorem.prove UNKNOWN verdict → redacted.
        let reg = VerdictRegistry::new();
        let spurious = "## Problemas\nO `theorem.prove` provou UNKNOWN, logo o argumento falha.";
        let (out, _summary) = reg.redact_unattested(spurious);
        assert!(out.contains("[REDACTED"));
        assert!(out.contains("Integrity check FAILED"));
    }

    fn sample_opinion() -> TriadOpinion {
        TriadOpinion {
            agent: "ATHENA".into(),
            summary: "test summary".into(),
            suggestions_md: "## Strengths\n- good".into(),
            score: 0.83,
            provider_tier: "grok-3".into(),
        }
    }

    #[test]
    fn symptom_signals_are_bounded_and_responsive() {
        // Texto neutro → tudo no baseline (sleep alto, demais 0.5).
        let neutral = extract_symptom_signals("compilador e geometria da informação");
        assert_eq!(neutral.get("depression").copied(), Some(0.5));
        assert_eq!(neutral.get("sleep").copied(), Some(0.7));

        // Termos clínicos elevam os sinais; insônia REBAIXA o sono.
        let clinical =
            extract_symptom_signals("paciente com depressão, ansiedade, estresse e insônia");
        assert!(clinical["depression"] > 0.5);
        assert!(clinical["anxiety"] > 0.5);
        assert!(clinical["stress"] > 0.5);
        assert!(clinical["sleep"] < 0.7);
        // Sempre dentro de [0,1].
        for v in clinical.values() {
            assert!((0.0..=1.0).contains(v), "sinal fora de [0,1]: {v}");
        }
    }

    // E2E contra o serviço vivo: `SOUNIO_INFERENCE_URL=http://127.0.0.1:<pf> \
    // cargo test -p beagle-triad symbolic_summary_live -- --ignored --nocapture`
    #[tokio::test]
    #[ignore]
    async fn symbolic_summary_live_is_solver_verified() {
        std::env::set_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE", "true");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = generate_symbolic_summary("paciente com depressão, ansiedade e insônia", &ctx)
            .await
            .expect("summary");
        std::env::remove_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE");
        eprintln!("{out}");
        assert!(
            out.contains("VERIFICADO POR SOLVER (PCS/Sounio)"),
            "got: {out}"
        );
        assert!(out.contains("Severity score (solver)"));
    }

    #[tokio::test]
    async fn symbolic_summary_falls_back_honestly_without_solver() {
        // Gate LIGADO mas o Sounio Inference Service inalcançável: o resumo DEVE se
        // rotular como heurístico — nunca como verificado por solver (truth_mode).
        std::env::set_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE", "true");
        std::env::set_var("SOUNIO_INFERENCE_URL", "http://127.0.0.1:1"); // porta morta
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = generate_symbolic_summary("texto sobre entropia e PBPK", &ctx)
            .await
            .expect("summary should always succeed (fallback)");
        std::env::remove_var("BEAGLE_SYMBOLIC_CONTEXT_ENABLE");
        std::env::remove_var("SOUNIO_INFERENCE_URL");
        assert!(
            out.contains("HEURÍSTICO (NÃO verificado por solver)"),
            "fallback deve se auto-rotular heurístico, got: {out}"
        );
        assert!(!out.contains("VERIFICADO POR SOLVER"));
    }

    #[test]
    fn checkpoint_round_trip_opinion() {
        let dir = tempfile::tempdir().unwrap();
        let op = sample_opinion();

        save_stage(dir.path(), "athena", &op);

        let loaded: TriadOpinion =
            load_stage(dir.path(), "athena").expect("checkpoint should load back");
        assert_eq!(loaded.agent, op.agent);
        assert_eq!(loaded.summary, op.summary);
        assert_eq!(loaded.suggestions_md, op.suggestions_md);
        assert_eq!(loaded.score, op.score);
        assert_eq!(loaded.provider_tier, op.provider_tier);
    }

    #[test]
    fn load_stage_missing_returns_none() {
        let dir = tempfile::tempdir().unwrap();
        let loaded: Option<TriadOpinion> = load_stage(dir.path(), "argos");
        assert!(loaded.is_none(), "missing stage file must return None");
    }

    #[test]
    fn resume_skips_when_file_present() {
        // Mirrors the resume logic in run_triad_tournament: when a stage file
        // exists, load_stage returns Some and recomputation is skipped.
        let dir = tempfile::tempdir().unwrap();
        let op = sample_opinion();
        save_stage(dir.path(), "hermes", &op);

        let resume = true;
        let resumed: Option<TriadOpinion> = resume
            .then(|| load_stage::<TriadOpinion>(dir.path(), "hermes"))
            .flatten();
        assert!(
            resumed.is_some(),
            "present stage file must trigger resume (skip recompute)"
        );
        assert_eq!(resumed.unwrap().score, op.score);
    }

    #[test]
    fn evolved_draft_serde_round_trip() {
        let ev = EvolvedDraft {
            evolved_draft_md: "We propose that X requires experimental validation [1].".into(),
            claims: vec![EvolvedClaim {
                claim: "We propose that X requires experimental validation".into(),
                requires_human_validation: true,
                citations: vec!["[1]".into()],
            }],
            provider_tier: "grok-4-heavy".into(),
        };
        let json = serde_json::to_string(&ev).unwrap();
        let back: EvolvedDraft = serde_json::from_str(&json).unwrap();
        assert_eq!(back.evolved_draft_md, ev.evolved_draft_md);
        assert_eq!(back.claims.len(), 1);
        assert!(back.claims[0].requires_human_validation);
        assert_eq!(back.claims[0].citations, vec!["[1]".to_string()]);
    }

    #[test]
    fn triad_report_evolved_defaults_to_none_for_legacy_json() {
        // Existing consumers serialize TriadReport without `evolved`; ensure
        // deserialization still works (additive, non-breaking).
        let legacy = serde_json::json!({
            "run_id": "r1",
            "original_draft": "orig",
            "final_draft": "final",
            "opinions": [],
            "created_at": "2026-06-07T00:00:00Z",
            "llm_stats": {
                "grok3_calls": 0, "grok3_tokens_in": 0, "grok3_tokens_out": 0,
                "grok4_calls": 0, "grok4_tokens_in": 0, "grok4_tokens_out": 0,
                "deepseek_calls": 0, "deepseek_tokens_in": 0, "deepseek_tokens_out": 0,
                "local_calls": 0, "local_tokens_in": 0, "local_tokens_out": 0
            }
        });
        let report: TriadReport = serde_json::from_value(legacy).unwrap();
        assert!(report.evolved.is_none());
        // P4: verification_summary also defaults to None for legacy JSON.
        assert!(report.verification_summary.is_none());
    }

    // ===== P4: VerificationSummary =====

    #[tokio::test]
    async fn verification_summary_all_gates_off_all_abstained() {
        std::env::remove_var("BEAGLE_TRIAD_SMT_CHECK");
        std::env::remove_var("BEAGLE_TRIAD_DSEP_CHECK");
        std::env::remove_var("BEAGLE_TRIAD_GUM_CHECK");
        std::env::remove_var("BEAGLE_TRIAD_THEOREM_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let athena = sample_opinion();
        let hermes = sample_opinion();
        let (_op, _tier, vsummary) = run_argos("draft", &hermes, &athena, &ctx, "t")
            .await
            .expect("run_argos");
        assert_eq!(vsummary.smt.abstained, 1);
        assert_eq!(vsummary.causal.abstained, 1);
        assert_eq!(vsummary.gum.abstained, 1);
        assert_eq!(vsummary.theorem.abstained, 1);
        assert!(vsummary.finding_rate.is_none());
        assert!(vsummary.machine_note().contains("all abstained"));
    }

    #[test]
    fn machine_note_format_with_findings() {
        let v = VerificationSummary {
            smt: VerbStats {
                ran: 1,
                abstained: 0,
                finding_emitted: 1,
            },
            causal: VerbStats {
                ran: 1,
                abstained: 0,
                finding_emitted: 0,
            },
            gum: VerbStats {
                ran: 0,
                abstained: 1,
                finding_emitted: 0,
            },
            theorem: VerbStats {
                ran: 0,
                abstained: 1,
                finding_emitted: 0,
            },
            completed_at: "2026-06-15T00:00:00Z".to_string(),
            finding_rate: Some(0.5),
        };
        assert_eq!(
            v.machine_note(),
            "[verification: 2/4 ran, 1 finding(s), rate 50%]"
        );
    }

    #[test]
    fn machine_note_zero_ran() {
        let v = VerificationSummary::default();
        assert!(v.machine_note().contains("all abstained"));
    }

    #[tokio::test]
    async fn run_argos_returns_three_tuple_with_vsummary() {
        std::env::remove_var("BEAGLE_TRIAD_SMT_CHECK");
        std::env::remove_var("BEAGLE_TRIAD_DSEP_CHECK");
        std::env::remove_var("BEAGLE_TRIAD_GUM_CHECK");
        std::env::remove_var("BEAGLE_TRIAD_THEOREM_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let athena = sample_opinion();
        let hermes = sample_opinion();
        let result = run_argos("draft", &hermes, &athena, &ctx, "t").await;
        let (_op, _tier, vsummary) = result.expect("run_argos");
        assert!(vsummary.finding_rate.is_none());
        assert_eq!(vsummary.smt.ran, 0);
    }

    #[test]
    fn extract_citations_finds_patterns() {
        let text = "See @smith2020 and \\cite{jones1999,doe2001}. Also [12].";
        let cites = extract_citations(text);
        assert!(cites.contains(&"@smith2020".to_string()));
        assert!(cites.contains(&"\\cite{jones1999}".to_string()));
        assert!(cites.contains(&"\\cite{doe2001}".to_string()));
        assert!(cites.contains(&"[12]".to_string()));
    }

    #[test]
    fn extract_claims_skips_headers_and_short_lines() {
        let md = "# Title\n\nWe propose that the scaffold curvature modulates entropy flow.\nshort line\n";
        let claims = extract_claims(md);
        assert_eq!(claims.len(), 1);
        assert!(claims[0].contains("scaffold curvature modulates entropy"));
    }

    #[test]
    fn evolve_claims_are_augmentative() {
        // Every extracted claim must be flagged as requiring human/wet-lab validation.
        let md = "We propose that biomaterial scaffolds restore neural curvature dynamics.";
        let claims: Vec<EvolvedClaim> = extract_claims(md)
            .into_iter()
            .map(|claim| EvolvedClaim {
                claim,
                requires_human_validation: true,
                citations: vec![],
            })
            .collect();
        assert!(!claims.is_empty());
        assert!(claims.iter().all(|c| c.requires_human_validation));
    }

    #[test]
    fn checkpoint_dir_uses_run_id_segment() {
        // Falls back to env BEAGLE_DATA_DIR layout; verify path shape only.
        let p = stage_path(std::path::Path::new("/tmp/triad/run42"), "evolve");
        assert!(p.ends_with("evolve.json"));
    }

    #[tokio::test]
    async fn dsep_check_is_off_by_default() {
        std::env::remove_var("BEAGLE_TRIAD_DSEP_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = causal_claim_check("X causa Y diretamente", &ctx, "t").await;
        assert!(out.is_none());
    }

    #[tokio::test]
    async fn gum_check_is_off_by_default() {
        // Sem BEAGLE_TRIAD_GUM_CHECK, a verificação não roda (nem chama LLM/serviço).
        std::env::remove_var("BEAGLE_TRIAD_GUM_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = gum_claim_check("CL = dose/AUC = 5.0 ± 0.05", &ctx, "t").await;
        assert!(out.is_none());
    }

    #[tokio::test]
    async fn theorem_check_is_off_by_default() {
        // Sem BEAGLE_TRIAD_THEOREM_CHECK, a verificação não roda (nem chama LLM/serviço).
        std::env::remove_var("BEAGLE_TRIAD_THEOREM_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = theorem_claim_check("Se A então B; A; portanto C", &ctx, "t").await;
        assert!(out.is_none());
    }

    #[test]
    fn dedup_constraints_removes_exact_duplicates() {
        let make =
            |coeffs: Vec<i64>, bound: i64, label: Option<&str>| inference_client::LiaConstraint {
                coeffs,
                bound,
                label: label.map(|s| s.to_string()),
            };
        let cs = vec![
            make(vec![-1], -80, Some("dose >= 80")),
            make(vec![-1], -80, Some("dose >= 80")), // exact dup
            make(vec![1], 40, Some("dose <= 40")),
        ];
        let deduped = dedup_constraints(cs);
        assert_eq!(deduped.len(), 2);
    }

    #[test]
    fn dedup_constraints_drops_fabricated_twins() {
        let make =
            |coeffs: Vec<i64>, bound: i64, label: Option<&str>| inference_client::LiaConstraint {
                coeffs,
                bound,
                label: label.map(|s| s.to_string()),
            };
        // Real constraint: x >= 80 (coeffs=[-1], bound=-80)
        // Fabricated twin "limite inferior": coeffs=[1], bound=80 (negation of [-1],-80)
        let cs = vec![
            make(vec![-1], -80, Some("dose >= 80")),
            make(vec![1], 80, Some("limite inferior fabricado")),
            make(vec![1], 40, Some("dose <= 40")),
        ];
        let deduped = dedup_constraints(cs);
        // The twin labeled "limite inferior" should be dropped; the other two remain.
        assert_eq!(deduped.len(), 2);
        assert!(deduped.iter().all(|c| {
            c.label
                .as_deref()
                .map_or(true, |l| !l.contains("limite inferior"))
        }));
    }
}
