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
        // Canonical solver verdict tokens, matched as WHOLE WORDS and case-SENSITIVE
        // on the original line. ARGOS fabrications use these exact uppercase forms;
        // matching them as bare substrings (e.g. "sat") false-positives on Portuguese
        // prose like "satisfatório", "datasets", or English "satisfy".
        const CANONICAL_VERDICTS: &[&str] = &["UNSAT", "SAT", "PROVED", "UNKNOWN", "INVALID"];
        // d-separation VERDICT words (case-insensitive). Match the verdicts
        // `d-separated`/`d-connected` (+ PT stems `d-separad`/`d-conectad`), NOT the
        // bare concept "d-separation"/"d-separação" — the broad `d-separ` prefix
        // false-positived on prose merely discussing d-separation (eval #1 FP).
        const DSEP_TOKENS: &[&str] = &["d-separated", "d-connected", "d-separad", "d-conectad"];
        // GUM verdict words (case-insensitive). Without these, fabricated
        // `gum.propagate` attributions cite `gum-understated`/`gum-ok` and slip the
        // detector entirely — eval #1 measured this as the whole residual (8/8 misses).
        const GUM_TOKENS: &[&str] = &["gum-understated", "gum-ok"];

        // Whole-word check: the token must not be flanked by alphanumeric chars.
        fn contains_word(haystack: &str, needle: &str) -> bool {
            let nbytes = needle.as_bytes();
            let hbytes = haystack.as_bytes();
            if nbytes.is_empty() || nbytes.len() > hbytes.len() {
                return false;
            }
            let mut start = 0usize;
            while let Some(pos) = haystack[start..].find(needle) {
                let idx = start + pos;
                let before_ok = idx == 0
                    || !haystack[..idx]
                        .chars()
                        .next_back()
                        .map(|c| c.is_alphanumeric())
                        .unwrap_or(false);
                let after_idx = idx + needle.len();
                let after_ok = after_idx >= haystack.len()
                    || !haystack[after_idx..]
                        .chars()
                        .next()
                        .map(|c| c.is_alphanumeric())
                        .unwrap_or(false);
                if before_ok && after_ok {
                    return true;
                }
                start = idx + 1;
                if start >= haystack.len() {
                    break;
                }
            }
            false
        }

        let mut redactions: Vec<String> = Vec::new();
        let mut out_lines: Vec<String> = Vec::new();

        for line in argos_text.lines() {
            let lower = line.to_ascii_lowercase();

            // A line carries a solver-verdict attribution iff it names a verb AND
            // contains a canonical verdict token (whole-word, case-sensitive) or an
            // unambiguous d-separation token (case-insensitive prefix).
            let has_verdict = CANONICAL_VERDICTS.iter().any(|v| contains_word(line, v))
                || DSEP_TOKENS.iter().any(|t| lower.contains(t))
                || GUM_TOKENS.iter().any(|t| lower.contains(t));

            // Collect ALL verbs named on this line (not just the first), so a second
            // verb on the same line cannot smuggle an unattested attribution through.
            let mut flagged_verbs: Vec<&str> = Vec::new();
            if has_verdict {
                for verb in VERBS {
                    if lower.contains(verb) {
                        flagged_verbs.push(verb);
                    }
                }
            }

            if flagged_verbs.is_empty() {
                out_lines.push(line.to_string());
                continue;
            }

            let is_attested = |verb: &str| {
                self.lookup(verb)
                    .map(|r| {
                        !matches!(
                            r.result.as_str(),
                            "gate-off"
                                | "extraction-empty"
                                | "validation-rejected"
                                | "transport-error"
                                | "build-failed"
                        )
                    })
                    .unwrap_or(false)
            };

            let unattested: Vec<&str> = flagged_verbs
                .iter()
                .copied()
                .filter(|v| !is_attested(v))
                .collect();

            if unattested.is_empty() {
                out_lines.push(line.to_string());
            } else {
                let verbs_joined = unattested.join("`, `");
                let marker = format!(
                    "[REDACTED: solver attribution unattested — no executed VerdictRecord for `{verbs_joined}`]"
                );
                for v in &unattested {
                    redactions.push(format!("`{v}` — no VerdictRecord"));
                }
                out_lines.push(marker);
                warn!(
                    verbs = %unattested.join(","),
                    "redact_unattested: ARGOS cited a solver verdict with no matching VerdictRecord — line redacted"
                );
            }
        }

        // Distinguish "a solver ran and all attributions matched" (PASSED) from
        // "no solver ran at all" (NEUTRAL). Emitting PASSED when every record is a
        // non-attested marker would falsely imply solver verification happened.
        const NON_ATTESTED: &[&str] = &[
            "gate-off",
            "extraction-empty",
            "validation-rejected",
            "transport-error",
            "build-failed",
        ];
        let no_solver_ran = self
            .records
            .iter()
            .all(|r| NON_ATTESTED.contains(&r.result.as_str()));

        let integrity_note = if redactions.is_empty() && no_solver_ran {
            "\n\n---\n**[Integrity check: nenhum solver rodou]** Todos os gates estavam desligados \
             ou abstiveram; não há veredito de solver para validar. A saída do ARGOS NÃO foi \
             cruzada com um registro de solver."
                .to_string()
        } else if redactions.is_empty() {
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

        let summary = if redactions.is_empty() && no_solver_ran {
            format!("integrity=NEUTRAL records={}", self.records.len())
        } else if redactions.is_empty() {
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

// ============================================================================
// P3 — Per-domain selective verification via self-consistency
//
// PRAGMATIC PROXY, NOT PCFG GRAMMAR-ENTROPY: we run the extraction LLM k times
// at temp 0 and require a configurable majority to agree on a canonical key
// before trusting the artifact. Disagreement is the signal that the extraction
// is ambiguous → abstain (no finding). This catches AMBIGUOUS extractions; it
// does NOT catch confidently-wrong extractions where all k calls hallucinate the
// same artifact. The SOTA full solution (PCFG grammar-entropy) is deliberately
// out of scope. All gates default OFF, so this path is inert by default.
// ============================================================================

/// Policy settings for one extraction domain. Env-tunable so production can
/// adjust k/agreement without recompiling.
#[derive(Debug, Clone, Copy)]
pub struct ExtractionPolicy {
    /// Independent extraction calls to run (k-consistency).
    /// Env: `BEAGLE_TRIAD_{DOMAIN}_K`.
    pub k: usize,
    /// Minimum calls that must agree on the same canonical key (≤ k).
    /// Env: `BEAGLE_TRIAD_{DOMAIN}_AGREE`.
    pub agree: usize,
    /// Attach a confidence label to findings from this domain (causal/gum only).
    pub confidence_label: bool,
}

/// Outcome of k-consistency extraction.
#[derive(Debug)]
pub enum ConsistencyResult<T> {
    /// A sufficient majority agreed; `votes` is the winning count.
    Agreed { artifact: T, votes: usize },
    /// Insufficient agreement across the k runs — abstain.
    Abstained { k: usize, agree_required: usize },
}

/// Read an [`ExtractionPolicy`] for a named domain from env. Domain names are
/// uppercase: `SMT`, `CAUSAL`, `GUM`, `THEOREM`. `agree` is clamped to `1..=k`.
fn read_policy(
    domain: &str,
    default_k: usize,
    default_agree: usize,
    confidence_label: bool,
) -> ExtractionPolicy {
    let k = std::env::var(format!("BEAGLE_TRIAD_{domain}_K"))
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(default_k)
        .max(1);
    let agree = std::env::var(format!("BEAGLE_TRIAD_{domain}_AGREE"))
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(default_agree)
        .min(k)
        .max(1);
    ExtractionPolicy {
        k,
        agree,
        confidence_label,
    }
}

/// SMT domain: logic-shaped → majority (k=3, agree=2), no confidence label.
fn smt_policy() -> ExtractionPolicy {
    read_policy("SMT", 3, 2, false)
}

/// Causal domain: factual/structural → unanimous (k=3, agree=3), confidence label ON.
fn causal_policy() -> ExtractionPolicy {
    read_policy("CAUSAL", 3, 3, true)
}

/// GUM domain: numeric/factual → unanimous (k=3, agree=3), confidence label ON.
fn gum_policy() -> ExtractionPolicy {
    read_policy("GUM", 3, 3, true)
}

/// Theorem domain: logic-shaped → majority (k=3, agree=2), no confidence label.
fn theorem_policy() -> ExtractionPolicy {
    read_policy("THEOREM", 3, 2, false)
}

/// Run `call_llm_extraction` k times and require a configurable majority of
/// responses to agree on the same canonical key before building the artifact.
///
/// `extract_fn` maps raw LLM text → a canonical comparable key (None = unusable).
/// `build_fn` maps the first agreeing raw text → the actual artifact `T`.
///
/// Cost: k=3 at temp 0 on the cheap extraction model is inexpensive; temp 0 makes
/// outputs near-deterministic, so agreement on a VALID extraction is high and
/// disagreement is exactly the ambiguity signal we abstain on.
async fn run_extraction_with_consistency<T, F, G>(
    policy: ExtractionPolicy,
    ctx: &BeagleContext,
    run_id: &str,
    prompt: &str,
    extract_fn: F,
    build_fn: G,
) -> ConsistencyResult<T>
where
    F: Fn(&str) -> Option<String>,
    G: Fn(&str) -> Option<T>,
{
    let meta = RequestMeta::new(
        false,
        false,
        false,
        prompt.chars().count() / 4,
        false,
        false,
        false,
    );
    let mut texts: Vec<String> = Vec::with_capacity(policy.k);
    for _ in 0..policy.k {
        if let Ok((t, _)) = call_llm_extraction(ctx, run_id, prompt, meta.clone()).await {
            texts.push(t);
        }
    }
    if texts.is_empty() {
        return ConsistencyResult::Abstained {
            k: policy.k,
            agree_required: policy.agree,
        };
    }
    let mut freq: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    let mut key_to_text: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for text in &texts {
        if let Some(key) = extract_fn(text) {
            *freq.entry(key.clone()).or_insert(0) += 1;
            key_to_text.entry(key).or_insert_with(|| text.clone());
        }
    }
    if let Some((best_key, &votes)) = freq.iter().max_by_key(|(_, &v)| v) {
        if votes >= policy.agree {
            if let Some(artifact) = build_fn(&key_to_text[best_key]) {
                return ConsistencyResult::Agreed { artifact, votes };
            }
            warn!(
                best_key = %best_key,
                votes,
                "run_extraction_with_consistency: build_fn returned None despite agreement — treating as Abstained"
            );
        }
    }
    ConsistencyResult::Abstained {
        k: policy.k,
        agree_required: policy.agree,
    }
}

/// ARGOS: crítico adversarial
///
/// Age como revisor Q1 duro (Nature Human Behaviour, Kybernetes, Frontiers), focado em:
/// - Claims sem suporte empírico adequado
/// - Confusão entre metáfora e mecanismo
/// - Ausência de desenho empírico razoável
///
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

/// Gate for the SymbCoT semantic faithfulness check (P2).
/// Controlled by `BEAGLE_TRIAD_SYMB_VERIFY=1|true|yes|on`. OFF by default.
/// When off, [`verify_translation_faithfulness`] returns `true` (abstain-safe pass-through).
fn symb_verify_enabled() -> bool {
    std::env::var("BEAGLE_TRIAD_SYMB_VERIFY")
        .map(|v| {
            matches!(
                v.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(false)
}

/// SymbCoT-style semantic faithfulness verifier (P2).
///
/// After the extraction LLM produces a formal artifact and BEFORE trusting the
/// solver verdict, this does ONE extra cheap LLM call that back-translates the
/// formal artifact to NL and asks whether it is semantically equivalent to
/// `source_excerpt`. If NOT equivalent → caller must abstain (drop the finding).
///
/// # Honest-by-construction contract
/// - Gate OFF → returns `true` (pass-through; no LLM call, no latency).
/// - Any LLM / parse error → returns `true` (do NOT hide real incoherences because
///   the verifier is down; this layer catches *translator* errors, not solver errors).
/// - Only an explicit, well-formed `{"equivalent": false}` triggers abstention.
async fn verify_translation_faithfulness(
    source_excerpt: &str,
    formal_nl_description: &str,
    formal_json: &str,
    ctx: &BeagleContext,
    run_id: &str,
) -> bool {
    if !symb_verify_enabled() {
        return true; // gate OFF: pass-through, zero overhead
    }
    let prompt = format!(
        "You are a semantic faithfulness verifier (SymbCoT-Verifier layer).\n\
         You are given:\n\
         (A) SOURCE CLAIM — the original natural-language excerpt from a scientific draft.\n\
         (B) FORMAL NL DESCRIPTION — a natural-language back-translation of the formal artifact\n\
             (constraints / causal graph / GUM inputs / propositional hypotheses) that was\n\
             extracted from (A) and will be handed to a formal solver.\n\
         (C) FORMAL (JSON enviado ao solver) — the EXACT JSON payload that will be POSTed to the\n\
             solver. Post-processing (dedup, sign normalization, index remap) happens between (B)\n\
             and (C), so (C) may differ from (B); judge BOTH against (A).\n\
         \n\
         Task: judge whether BOTH (B) AND (C) faithfully represent (A) — i.e., the formal artifact\n\
         captures the same entities, quantities, relationships, and logical scope that (A) asserts,\n\
         with no sign flip, reordering error, or index/variable remap that changes the meaning.\n\
         \n\
         Rules:\n\
         - Answer ONLY with a JSON object: {{\"equivalent\": true|false, \"reason\": \"one sentence\"}}\n\
         - Answer false ONLY if there is a clear, specific semantic mismatch in (B) OR (C) (wrong\n\
           variable, inverted inequality, missing key entity, wrong causal direction, wrong operator,\n\
           sign flip introduced in the JSON).\n\
         - Do NOT answer false for minor phrasing differences, abbreviations, or unit normalization.\n\
         - If unsure, answer true (benefit of the doubt).\n\
         \n\
         === SOURCE CLAIM ===\n\
         {}\n\
         \n\
         === FORMAL NL DESCRIPTION ===\n\
         {}\n\
         \n\
         === FORMAL (JSON enviado ao solver) ===\n\
         {}",
        source_excerpt, formal_nl_description, formal_json,
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
    let (text, _) = match call_llm_extraction(ctx, run_id, &prompt, meta).await {
        Ok(r) => r,
        Err(e) => {
            warn!(error = %e, run_id, "verify_translation_faithfulness: LLM call failed; allowing finding (pass)");
            return true;
        }
    };
    let parsed = match first_json_object(&text)
        .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
    {
        Some(v) => v,
        None => {
            warn!(
                run_id,
                "verify_translation_faithfulness: JSON parse failed; allowing finding (pass)"
            );
            return true;
        }
    };
    match parsed.get("equivalent").and_then(|v| v.as_bool()) {
        Some(false) => {
            let reason = parsed
                .get("reason")
                .and_then(|v| v.as_str())
                .unwrap_or("no reason given");
            warn!(
                run_id,
                reason, "verify_translation_faithfulness: NOT equivalent — abstaining from finding"
            );
            false
        }
        _ => true, // true, null, missing, or ambiguity → pass
    }
}

/// Gate that enables the CoT ensemble cross-check for all four domains (P5).
/// When ON, a domain's claim_check that finds a solver incoherence ALSO fires a
/// cheap LLM CoT call on the same artifact and compares verdicts. OFF by default.
fn cot_ensemble_enabled() -> bool {
    std::env::var("BEAGLE_TRIAD_COT_ENSEMBLE")
        .map(|v| {
            matches!(
                v.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(false)
}

/// CoT verdict returned by [`cot_call`], mapped onto the solver verdicts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CotVerdict {
    /// LLM agrees the artifact is incoherent / UNSAT / understated / non-provable.
    Incoherent,
    /// LLM thinks the artifact is coherent / SAT / sound.
    Coherent,
    /// LLM unreachable, timed out, or gave an unrecognised answer.
    Unknown,
}

/// Cheap model used for CoT cross-checks (deepseek-chat by default).
/// Override with `BEAGLE_TRIAD_COT_MODEL`.
fn cot_model() -> String {
    std::env::var("BEAGLE_TRIAD_COT_MODEL").unwrap_or_else(|_| "deepseek-chat".to_string())
}

/// Fire a single cheap CoT LLM call (via `ctx.router` directly, not the extraction
/// override) and return a [`CotVerdict`]. The prompt must instruct a one-word reply.
async fn cot_call(ctx: &BeagleContext, run_id: &str, prompt: &str) -> CotVerdict {
    let meta = RequestMeta::new(
        false,
        false,
        false,
        prompt.chars().count() / 4,
        false,
        false,
        false,
    );
    let current_stats = ctx.llm_stats.get_or_create(run_id);
    let (client, _tier) = ctx.router.choose_with_limits(&meta, &current_stats);
    let req = beagle_llm::LlmRequest {
        model: cot_model(),
        messages: vec![beagle_llm::ChatMessage::user(prompt)],
        temperature: Some(0.0),
        max_tokens: Some(512),
    };
    match client.chat(req).await {
        Err(e) => {
            warn!(error = %e, "cot_call: LLM error; Unknown");
            CotVerdict::Unknown
        }
        Ok(text) => {
            let t = text.trim().to_ascii_uppercase();
            if t.contains("INCOHERENT") {
                CotVerdict::Incoherent
            } else if t.contains("COHERENT") {
                CotVerdict::Coherent
            } else {
                warn!(reply = %text, "cot_call: unrecognised reply; Unknown");
                CotVerdict::Unknown
            }
        }
    }
}

/// Attach a CONFIDENCE label to a solver-finding markdown block (P5).
/// Solver+CoT agreement → HIGH; divergence/unknown → MEDIUM (solver remains authoritative).
///
/// `domain` selects the divergence wording. For "theorem", a solver UNKNOWN/INVALID is
/// explicitly NOT a proof of invalidity, so the divergence message must not claim the
/// solver "proved incoherence". For "smt"/"causal"/"gum", the solver verdicts (UNSAT,
/// d-separated, understated uncertainty) ARE real proofs, so the original wording holds.
fn attach_confidence(finding: &str, cot: CotVerdict, domain: &str) -> String {
    match cot {
        CotVerdict::Incoherent => format!(
            "{finding}\n\n> **CONFIDENCE: HIGH** — Solver e CoT concordam na incoerência \
             (concordância neurosimbólica+CoT é sinal forte; o veredito do solver é autoritativo)."
        ),
        CotVerdict::Coherent => {
            if domain == "theorem" {
                format!(
                    "{finding}\n\n> **CONFIDENCE: MEDIUM** — Solver NÃO conseguiu reconstruir a \
                     dedução (UNKNOWN/INVALID — não é prova de invalidade) e o CoT avaliou o \
                     argumento como válido (divergência de modo); investigue premissas implícitas \
                     antes de concluir non-sequitur."
                )
            } else {
                format!(
                    "{finding}\n\n> **CONFIDENCE: MEDIUM** — Solver provou incoerência, mas o CoT LLM \
                     avaliou o mesmo artefato como coerente (divergência de modo). O veredito do solver \
                     formal é autoritativo; a divergência indica que a EXTRAÇÃO do artefato pode ser \
                     parcial ou que o LLM não viu a contradição — investigue antes de afirmar que o \
                     draft está errado."
                )
            }
        }
        CotVerdict::Unknown => format!(
            "{finding}\n\n> **CONFIDENCE: MEDIUM** — CoT indisponível ou inconclusivo; veredito \
             do solver é autoritativo, mas não há confirmação de modo complementar."
        ),
    }
}

/// Canonical self-consistency key for an SMT extraction JSON (`{"constraints":[...]}`).
///
/// The key is a sorted join of `label|bound|coeffs` per constraint. `coeffs` MUST be
/// part of the key so two extractions with the same `(label, bound)` but a different
/// linear combination do not falsely "agree" in the P3 consistency gate.
fn smt_canonical_key(json: &str) -> Option<String> {
    let parsed: serde_json::Value = serde_json::from_str(json).ok()?;
    let cons = parsed.get("constraints")?.as_array()?;
    let mut keys: Vec<String> = cons
        .iter()
        .filter_map(|c| {
            let label = c.get("label").and_then(|v| v.as_str()).unwrap_or("");
            let bound = c.get("bound").and_then(|v| v.as_i64())?;
            let mut coeffs: Vec<i64> = c
                .get("coeffs")
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().filter_map(|v| v.as_i64()).collect())
                .unwrap_or_default();
            coeffs.sort();
            Some(format!("{}|{}|{:?}", label.trim(), bound, coeffs))
        })
        .collect();
    keys.sort();
    Some(keys.join("|"))
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
#[cfg_attr(not(test), allow(dead_code))]
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
    // P3: self-consistency (k extrações; maioria deve concordar). smt_policy() = k=3,
    // agree=2 (logic-shaped). Chave canônica = lista ordenada de (label:bound).
    // Meta barato: `call_llm_extraction` força o modelo de chat (deepseek-chat) e é
    // computado dentro de run_extraction_with_consistency.
    let policy = smt_policy();
    let extract_key =
        |text: &str| -> Option<String> { smt_canonical_key(&first_json_object(text)?) };
    let build_artifact = |text: &str| -> Option<Vec<inference_client::LiaConstraint>> {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(text)?).ok()?;
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
        Some(constraints)
    };

    let constraints = match run_extraction_with_consistency(
        policy,
        ctx,
        run_id,
        &prompt,
        extract_key,
        build_artifact,
    )
    .await
    {
        ConsistencyResult::Agreed { artifact, .. } => artifact,
        ConsistencyResult::Abstained { k, agree_required } => {
            info!(
                k,
                agree_required, "solver_claim_consistency: abstém — extrações divergiram"
            );
            registry.push(VerdictRecord {
                verb: "smt.check",
                input_sha256: String::new(),
                result: "extraction-empty".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    };

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

    // P2: SymbCoT faithfulness check — back-translate the constraints to NL and
    // ask the LLM if it matches the source. Mismatch → abstain (gate OFF = pass).
    let formal_nl_description = {
        // Render each constraint as a COMPLETE readable inequality (not just its label),
        // so the faithfulness verifier can actually confirm equivalence against the claim.
        // A terse label-only description was measured to cause heavy false-abstain.
        let lines: Vec<String> = constraints
            .iter()
            .map(|c| {
                let label = c.label.clone().unwrap_or_else(|| "constraint".to_string());
                // Single-variable ±1 constraints read as "<quantity> >= / <= value".
                let nonzero: Vec<(usize, i64)> = c
                    .coeffs
                    .iter()
                    .enumerate()
                    .filter(|(_, &k)| k != 0)
                    .map(|(i, &k)| (i, k))
                    .collect();
                if let [(_, k)] = nonzero[..] {
                    if k == 1 {
                        return format!("{label}: the quantity must be <= {}", c.bound);
                    } else if k == -1 {
                        return format!("{label}: the quantity must be >= {}", -c.bound);
                    }
                }
                format!("{label}: Σ{:?}·x <= {}", c.coeffs, c.bound)
            })
            .collect();
        format!(
            "The following linear integer constraints (over the same shared variable unless noted) \
             were extracted from the claim: {}",
            lines.join("; ")
        )
    };
    let source_excerpt: String = draft.chars().take(6000).collect();
    let formal_json = serde_json::to_string(&inference_client::SmtCheckRequest {
        constraints: constraints.clone(),
    })
    .unwrap_or_default();
    if !verify_translation_faithfulness(
        &source_excerpt,
        &formal_nl_description,
        &formal_json,
        ctx,
        run_id,
    )
    .await
    {
        registry.push(VerdictRecord {
            verb: "smt.check",
            input_sha256: String::new(),
            result: "validation-rejected".to_string(),
            run_id: run_id.to_string(),
        });
        return None;
    }

    // Fingerprint o JSON exato que será POSTado ao solver. O cliente envia o
    // wrapper `{"constraints":[...]}` (SmtCheckRequest), não o array nu, então
    // o hash precisa ser do wrapper para casar com o payload real do wire.
    let artifact = serde_json::to_string(&inference_client::SmtCheckRequest {
        constraints: constraints.clone(),
    })
    .unwrap_or_default();
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
            let finding_md = format!(
                "## ⚠️ Contradição provada por solver (Sounio SMT)\n\n\
                O verificador formal `smt.check` (Sounio, DPLL(T) QF_LIA) provou que o conjunto de \
                afirmações quantitativas abaixo — extraídas do draft — é **mutuamente contraditório** (UNSAT).\n\n\
                **Conjunto extraído (após dedup; pode conter constraints redundantes além do núcleo conflitante):**\n\n\
                {}\n\n\
                > **Honestidade (truth-mode):** a EXTRAÇÃO de claims é feita por LLM e é falível. \
                O solver provou apenas que ESTAS constraints são inconsistentes entre si — \
                confirme contra o texto antes de afirmar que o draft em si está errado.",
                lines.join("\n")
            );
            // P5: ensemble com CoT (gated, barato, complementar).
            if cot_ensemble_enabled() {
                let cot_prompt = format!(
                    "You are a scientific logic checker. Below is a set of linear constraints \
                     extracted from a research draft. Are these constraints jointly satisfiable \
                     (no contradiction), or are they mutually contradictory (incoherent)?\n\n\
                     Constraints:\n{}\n\n\
                     Think step by step, then reply with exactly one word: INCOHERENT or COHERENT.",
                    constraints
                        .iter()
                        .map(|c| c
                            .label
                            .clone()
                            .unwrap_or_else(|| format!("Σ{:?}·x <= {}", c.coeffs, c.bound)))
                        .collect::<Vec<_>>()
                        .join("\n")
                );
                let cot = cot_call(ctx, run_id, &cot_prompt).await;
                info!(cot = ?cot, "solver_claim_consistency: CoT ensemble verdict");
                Some(attach_confidence(&finding_md, cot, "smt"))
            } else {
                Some(finding_md)
            }
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
#[cfg_attr(not(test), allow(dead_code))]
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
         PASSO 2 — IDENTIFIQUE ARESTAS: só inclua aresta X→Y quando o texto AFIRMA EXPLICITAMENTE um \
         vínculo causal direcional entre X e Y (\"X causa Y\", \"X afeta Y\", \"Y depende de X\", \
         \"X reduz/aumenta Y\", \"X→Y\"). NÃO infira nem invente. CONTRA DISTRATORES: uma variável \
         apenas MENCIONADA, MEDIDA, listada como característica basal, ou CO-OCORRENTE — sem um verbo \
         causal explícito ligando-a a outra — NÃO gera aresta alguma. Correlação, associação \
         estatística, ou aparecer na mesma frase NÃO é aresta causal. Na dúvida sobre se um vínculo é \
         causal-explícito, NÃO inclua a aresta.\n\
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
    // P3: self-consistency. causal_policy() = k=3, agree=3 (unânime; factual/estrutural),
    // confidence_label=true. Chave canônica = x/y + lista ordenada de arestas + prefixo do claim.
    let policy = causal_policy();
    let extract_key = |text: &str| -> Option<String> {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(text)?).ok()?;
        let nodes = parsed.get("nodes")?.as_array()?;
        if nodes.is_empty() {
            return None;
        }
        let edges = parsed.get("edges")?.as_array()?;
        let x = parsed.get("x")?.as_u64()?;
        let y = parsed.get("y")?.as_u64()?;
        let mut edge_strs: Vec<String> = edges
            .iter()
            .filter_map(|e| {
                let p = e.as_array()?;
                Some(format!("{}>{}", p.first()?.as_u64()?, p.get(1)?.as_u64()?))
            })
            .collect();
        edge_strs.sort();
        // Purely STRUCTURAL key: the free-text `claim` summary varies by paraphrase
        // even at temp 0, causing spurious abstention. The DAG structure (x, y, edges)
        // is stable; the claim string is still used in the finding text, not here.
        Some(format!("x{}y{}|{}", x, y, edge_strs.join(",")))
    };
    type CausalArtifact = (inference_client::DsepRequest, Vec<String>, String, usize);
    let build_artifact = |text: &str| -> Option<CausalArtifact> {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(text)?).ok()?;

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
        if !(2..=32).contains(&n) || x >= n || y >= n || x == y {
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
    };

    let (req, node_names, claim, edges_len, votes) = match run_extraction_with_consistency(
        policy,
        ctx,
        run_id,
        &prompt,
        extract_key,
        build_artifact,
    )
    .await
    {
        ConsistencyResult::Agreed {
            artifact: (req, node_names, claim, edges_len),
            votes,
        } => (req, node_names, claim, edges_len, votes),
        ConsistencyResult::Abstained { k, agree_required } => {
            info!(
                k,
                agree_required,
                "causal_claim_check: abstém — extrações divergiram (domínio factual)"
            );
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

    // P2: SymbCoT faithfulness check on the extracted DAG. Mismatch → abstain (gate OFF = pass).
    {
        let x_name_pre = node_names
            .get(x)
            .cloned()
            .unwrap_or_else(|| format!("node{x}"));
        let y_name_pre = node_names
            .get(y)
            .cloned()
            .unwrap_or_else(|| format!("node{y}"));
        let cond_pre = z
            .iter()
            .map(|&zi| {
                node_names
                    .get(zi)
                    .cloned()
                    .unwrap_or_else(|| format!("node{zi}"))
            })
            .collect::<Vec<_>>()
            .join(", ");
        // List the ACTUAL edges (not just a count) so the verifier can confirm the DAG
        // matches the claim — a count-only description was measured to cause false-abstain.
        let edge_list: String = req
            .edges
            .iter()
            .map(|[a, b]| {
                let an = node_names.get(*a).map(|s| s.as_str()).unwrap_or("?");
                let bn = node_names.get(*b).map(|s| s.as_str()).unwrap_or("?");
                format!("{an}→{bn}")
            })
            .collect::<Vec<_>>()
            .join(", ");
        let formal_nl_description = format!(
            "A directed acyclic graph with nodes [{}] and {} directed edge(s) [{}] was extracted. \
             The query asks whether '{}' and '{}' are d-separated given conditioning set {{{}}}. \
             The draft claims they have a causal/dependency relation: '{}'",
            node_names.join(", "),
            edges_len,
            edge_list,
            x_name_pre,
            y_name_pre,
            cond_pre,
            claim,
        );
        let source_excerpt: String = draft.chars().take(6000).collect();
        let formal_json = serde_json::to_string(&req).unwrap_or_default();
        if !verify_translation_faithfulness(
            &source_excerpt,
            &formal_nl_description,
            &formal_json,
            ctx,
            run_id,
        )
        .await
        {
            registry.push(VerdictRecord {
                verb: "causal.dsep",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    }

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
            // P3: rótulo de confiança (causal é factual → confidence_label=true).
            let confidence_note = if policy.confidence_label {
                format!(
                    "> **Confiança da extração:** {}/{} chamadas de extração concordaram com este \
                     grafo causal (threshold {}). Mesmo com concordância, a extração de grafos a \
                     partir de prosa é altamente falível.\n\n",
                    votes, policy.k, policy.agree
                )
            } else {
                String::new()
            };
            let finding = format!(
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
            );
            let labeled = format!("{confidence_note}{finding}");
            // P5: ensemble com CoT (gated, complementar).
            if cot_ensemble_enabled() {
                let cot_prompt = format!(
                    "You are a causal inference checker. The following is a directed acyclic graph \
                     (DAG, {} edges) and a claimed causal/dependence relationship from a research draft.\n\n\
                     Nodes: {}\n\
                     Claimed relationship: \"{}\"\n\
                     Query: Is '{}' causally independent of '{}' given {}?\n\n\
                     Think step by step. Then reply with exactly one word: \
                     INCOHERENT (the claim is inconsistent with the DAG structure) \
                     or COHERENT (the DAG supports the claim).",
                    edges_len,
                    node_names.join(", "),
                    claim,
                    x_name,
                    y_name,
                    cond
                );
                let cot = cot_call(ctx, run_id, &cot_prompt).await;
                info!(cot = ?cot, "causal_claim_check: CoT ensemble verdict");
                Some(attach_confidence(&labeled, cot, "causal"))
            } else {
                Some(labeled)
            }
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
#[cfg_attr(not(test), allow(dead_code))]
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
         PASSO 2b — NORMALIZE AS UNIDADES (OBRIGATÓRIO antes de emitir): se A, B e Y não estão TODOS \
         na mesma unidade, converta valores E incertezas para uma ÚNICA unidade comum coerente com a \
         operação (para div, o numerador e o denominador podem ter unidades distintas, mas cada um \
         deve ser internamente consistente; para add/sub, A e B DEVEM ficar na MESMA unidade). \
         Conversões usuais: 1 g = 1000 mg; 1 mg = 1000 µg (mcg); 1 µg = 1000 ng; 1 L = 1000 mL; \
         1 h = 60 min. Emita os números JÁ CONVERTIDOS (ex.: '2 g' e '2100 mg' viram 2000 e 2100; \
         '250 µg' vira 250000 ng). Converta também a incerteza com o MESMO fator do valor. NUNCA \
         emita '2 g' como o inteiro 2 ao lado de um valor em mg.\n\
         PASSO 3 — EXTRAIA A INCERTEZA DECLARADA DE Y: o valor do '±' (ou meia-largura de IC, ou \
         desvio-padrão) que o texto atribui a Y, NA MESMA unidade normalizada de Y. Se Y não tem \
         incerteza declarada, found=false.\n\
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
    // P3: self-consistency. gum_policy() = k=3, agree=3 (unânime; numérico/factual),
    // confidence_label=true. Chave canônica = op + labels + claimed_uncertainty (3 sig figs).
    type GumExtract = (f64, f64, String, f64, f64, String, String, f64, String);
    let policy = gum_policy();
    let extract_key = |text: &str| -> Option<String> {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(text)?).ok()?;
        if !parsed
            .get("found")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return None;
        }
        let op = parsed.get("op")?.as_str()?.trim().to_ascii_lowercase();
        let a_lbl = parsed
            .get("a")?
            .get("label")
            .and_then(|v| v.as_str())
            .unwrap_or("a");
        let b_lbl = parsed
            .get("b")?
            .get("label")
            .and_then(|v| v.as_str())
            .unwrap_or("b");
        let cu = parsed.get("claimed_uncertainty")?.as_f64()?;
        Some(format!(
            "{}|{}|{}|{:.3e}",
            op,
            a_lbl.trim(),
            b_lbl.trim(),
            cu
        ))
    };
    let build_artifact = |text: &str| -> Option<GumExtract> {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(text)?).ok()?;
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
    };

    let (a_val, a_u, a_lbl, b_val, b_u, b_lbl, op, claimed_u, y_label, votes) =
        match run_extraction_with_consistency(
            policy,
            ctx,
            run_id,
            &prompt,
            extract_key,
            build_artifact,
        )
        .await
        {
            ConsistencyResult::Agreed {
                artifact: (a_val, a_u, a_lbl, b_val, b_u, b_lbl, op, claimed_u, y_label),
                votes,
            } => (
                a_val, a_u, a_lbl, b_val, b_u, b_lbl, op, claimed_u, y_label, votes,
            ),
            ConsistencyResult::Abstained { k, agree_required } => {
                info!(
                    k,
                    agree_required,
                    "gum_claim_check: abstém — extrações divergiram (domínio numérico/factual)"
                );
                registry.push(VerdictRecord {
                    verb: "gum.propagate",
                    input_sha256: String::new(),
                    result: "validation-rejected".to_string(),
                    run_id: run_id.to_string(),
                });
                return None;
            }
        };

    // P2: SymbCoT faithfulness check on the extracted GUM artifact. Mismatch → abstain.
    {
        let formal_nl_description = format!(
            "The derived quantity '{}' is computed as '{}' {} '{}' using the {} operation. \
             Input '{}' has value {:.4} ± {:.4}; input '{}' has value {:.4} ± {:.4}. \
             The draft declares uncertainty ±{:.4} for the derived quantity.",
            y_label, a_lbl, op, b_lbl, op, a_lbl, a_val, a_u, b_lbl, b_val, b_u, claimed_u,
        );
        let source_excerpt: String = draft.chars().take(6000).collect();
        let formal_json = serde_json::to_string(&inference_client::GumRequest {
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
        })
        .unwrap_or_default();
        if !verify_translation_faithfulness(
            &source_excerpt,
            &formal_nl_description,
            &formal_json,
            ctx,
            run_id,
        )
        .await
        {
            registry.push(VerdictRecord {
                verb: "gum.propagate",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    }

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
    // P3: rótulo de confiança (gum é numérico/factual → confidence_label=true).
    let confidence_note = if policy.confidence_label {
        format!(
            "> **Confiança da extração:** {}/{} chamadas de extração concordaram com esta \
             grandeza derivada (threshold {}).\n\n",
            votes, policy.k, policy.agree
        )
    } else {
        String::new()
    };
    let finding = format!(
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
    );
    let labeled = format!("{confidence_note}{finding}");
    // P5: ensemble com CoT (gated, complementar).
    if cot_ensemble_enabled() {
        let cot_prompt = format!(
            "You are an uncertainty propagation checker (GUM/JCGM 100). A research draft claims \
             the following derived quantity has a stated uncertainty.\n\n\
             Derived quantity: {}\n\
             Operation: {} ({} {} {})\n\
             Input A: {} ± {} ({})\n\
             Input B: {} ± {} ({})\n\
             Draft claims uncertainty: ± {}\n\
             GUM propagated standard uncertainty: {}\n\n\
             Is the draft's stated uncertainty plausibly consistent with GUM propagation, \
             or is it understated (incoherent)?\n\
             Think step by step. Reply with exactly one word: INCOHERENT or COHERENT.",
            y_label, op, a_lbl, op, b_lbl, a_val, a_u, a_lbl, b_val, b_u, b_lbl, claimed_u, u_c
        );
        let cot = cot_call(ctx, run_id, &cot_prompt).await;
        info!(cot = ?cot, "gum_claim_check: CoT ensemble verdict");
        Some(attach_confidence(&labeled, cot, "gum"))
    } else {
        Some(labeled)
    }
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
#[cfg_attr(not(test), allow(dead_code))]
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
    // P3: self-consistency. theorem_policy() = k=3, agree=2 (maioria; logic-shaped),
    // confidence_label=false. Chave canônica = átomos ordenados + serialização do goal.
    type TheoremExtract = (
        Vec<String>,
        Vec<serde_json::Value>,
        serde_json::Value,
        String,
    );
    let policy = theorem_policy();
    let extract_key = |text: &str| -> Option<String> {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(text)?).ok()?;
        if !parsed
            .get("found")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return None;
        }
        let atoms = parsed.get("atoms")?.as_array()?;
        let mut atom_strs: Vec<&str> = atoms.iter().filter_map(|v| v.as_str()).collect();
        atom_strs.sort();
        let goal_str = parsed
            .get("goal")
            .map(|g| g.to_string())
            .unwrap_or_default();
        Some(format!("atoms:{}|goal:{}", atom_strs.join(","), goal_str))
    };
    let build_artifact = |text: &str| -> Option<TheoremExtract> {
        let parsed: serde_json::Value = serde_json::from_str(&first_json_object(text)?).ok()?;
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
    };

    let (atoms, hypotheses, goal, argument) = match run_extraction_with_consistency(
        policy,
        ctx,
        run_id,
        &prompt,
        extract_key,
        build_artifact,
    )
    .await
    {
        ConsistencyResult::Agreed { artifact, .. } => artifact,
        ConsistencyResult::Abstained { k, agree_required } => {
            info!(
                k,
                agree_required, "theorem_claim_check: abstém — extrações divergiram"
            );
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

    // P2: SymbCoT faithfulness check on the extracted propositional deduction.
    {
        let formal_nl_description = format!(
            "A propositional deduction was extracted with atoms [{}], {} hypothesis/hypotheses, \
             and a goal. The draft presents this as a sufficient logical deduction: '{}'",
            atoms.join(", "),
            n_hyps,
            argument,
        );
        let source_excerpt: String = draft.chars().take(6000).collect();
        let formal_json = serde_json::to_string(&serde_json::json!({
            "atoms": atoms,
            "hypotheses": hypotheses,
            "goal": goal,
            "depth": 12,
        }))
        .unwrap_or_default();
        if !verify_translation_faithfulness(
            &source_excerpt,
            &formal_nl_description,
            &formal_json,
            ctx,
            run_id,
        )
        .await
        {
            registry.push(VerdictRecord {
                verb: "theorem.prove",
                input_sha256: String::new(),
                result: "validation-rejected".to_string(),
                run_id: run_id.to_string(),
            });
            return None;
        }
    }

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
    let finding_md = format!(
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
    );
    // P5: ensemble com CoT (gated, complementar). Domínio mais fraco — prompt só com o
    // texto literal e os átomos (a árvore pode codificar premissas invisíveis na prosa).
    if cot_ensemble_enabled() {
        let cot_prompt = format!(
            "You are a logical argument checker. A research draft presents the following \
             propositional argument and claims it is a valid logical deduction.\n\n\
             Argument as stated in the draft: \"{}\"\n\
             Atoms: {}\n\
             Number of explicit premises: {}\n\n\
             Is this argument a valid logical deduction from its stated premises alone \
             (no implicit domain knowledge), or is it incoherent / a non-sequitur?\n\
             Think step by step. Reply with exactly one word: INCOHERENT or COHERENT.",
            argument,
            atoms.join(", "),
            n_hyps
        );
        let cot = cot_call(ctx, run_id, &cot_prompt).await;
        info!(cot = ?cot, "theorem_claim_check: CoT ensemble verdict");
        Some(attach_confidence(&finding_md, cot, "theorem"))
    } else {
        Some(finding_md)
    }
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
    // `completed_at` is stamped AFTER the (slow) Heavy LLM call + redaction below,
    // so it reflects when run_argos actually finished, not when the gates resolved.
    let mut vsummary = VerificationSummary {
        smt: smt_s,
        causal: causal_s,
        gum: gum_s,
        theorem: theorem_s,
        completed_at: String::new(),
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
    // Stamp completion now that the Heavy LLM call and redaction are done.
    vsummary.completed_at = Utc::now().to_rfc3339();
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
        // Line names the verb but NO verdict keyword → not flagged. All records are
        // non-attested (gate-off) and no redactions → NEUTRAL, not PASSED.
        let (out, summary) =
            reg.redact_unattested("O verbo `theorem.prove` está disponível no cluster.");
        assert!(!out.contains("[REDACTED"));
        assert!(summary.starts_with("integrity=NEUTRAL"));
        assert!(out.contains("nenhum solver rodou"));
    }

    #[test]
    fn test_redact_unattested_no_false_positive_on_satisfatorio() {
        // "sat" as a bare substring used to false-positive on "satisfatório",
        // "datasets", etc. The whole-word case-sensitive canonical match must NOT
        // flag this line even though it names a verb and contains those letters.
        let mut reg = VerdictRegistry::new();
        reg.push(rec("smt.check", "gate-off"));
        let (out, _summary) = reg.redact_unattested(
            "O `smt.check` não retornou um resultado satisfatório para os datasets.",
        );
        assert!(
            !out.contains("[REDACTED"),
            "must not redact prose containing 'satisfatório'/'datasets': {out}"
        );
    }

    #[test]
    fn test_redact_unattested_flags_fabricated_gum_verdict() {
        // Regression (eval #1): the GUM verdict vocabulary (`gum-understated`/`gum-ok`)
        // was missing from the detector, so fabricated gum.propagate attributions
        // slipped through — the whole measured residual. A gum verdict with no record
        // MUST now redact.
        let reg = VerdictRegistry::new();
        let (out, _summary) = reg.redact_unattested(
            "O `gum.propagate` sinalizou gum-understated para a incerteza combinada do desfecho.",
        );
        assert!(
            out.contains("[REDACTED"),
            "fabricated gum-understated attribution must redact: {out}"
        );
    }

    #[test]
    fn test_redact_unattested_no_false_positive_on_dseparation_concept() {
        // Regression (eval #1): the broad `d-separ` prefix flagged prose merely
        // discussing the CONCEPT "d-separation"/"d-separação". The detector now keys on
        // the verdict words (`d-separated`/`d-connected`), so abstract discussion of the
        // concept near the verb name must NOT redact.
        let mut reg = VerdictRegistry::new();
        reg.push(rec("causal.dsep", "gate-off"));
        let (out, _summary) = reg.redact_unattested(
            "The authors' explanation of d-separation is intellectually satisfying but is not a formal invocation of `causal.dsep`.",
        );
        assert!(
            !out.contains("[REDACTED"),
            "discussing the d-separation concept must not redact: {out}"
        );
    }

    #[test]
    fn test_redact_unattested_flags_second_verb_on_line() {
        // smt.check has a real record but theorem.prove (also on the line) does not;
        // collecting ALL verbs must still redact because theorem.prove is unattested.
        let mut reg = VerdictRegistry::new();
        reg.push(rec("smt.check", "UNSAT"));
        let (out, summary) = reg.redact_unattested(
            "O `smt.check` deu UNSAT e o `theorem.prove` deu UNKNOWN no mesmo passo.",
        );
        assert!(
            out.contains("[REDACTED"),
            "second unattested verb must redact: {out}"
        );
        assert!(summary.starts_with("integrity=FAIL"));
        assert!(out.contains("theorem.prove"));
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

    // ===== P5: CoT ensemble + confidence labels =====

    #[test]
    fn cot_ensemble_is_off_by_default() {
        std::env::remove_var("BEAGLE_TRIAD_COT_ENSEMBLE");
        assert!(!cot_ensemble_enabled());
    }

    #[test]
    fn cot_ensemble_enabled_by_one() {
        std::env::set_var("BEAGLE_TRIAD_COT_ENSEMBLE", "1");
        assert!(cot_ensemble_enabled());
        std::env::remove_var("BEAGLE_TRIAD_COT_ENSEMBLE");
    }

    #[test]
    fn attach_confidence_high_on_agreement() {
        let f = attach_confidence("## Finding\ntest", CotVerdict::Incoherent, "smt");
        assert!(f.contains("CONFIDENCE: HIGH"));
        assert!(f.contains("## Finding"));
    }

    #[test]
    fn attach_confidence_medium_on_divergence() {
        let f = attach_confidence("## Finding\ntest", CotVerdict::Coherent, "smt");
        assert!(f.contains("CONFIDENCE: MEDIUM"));
        assert!(f.contains("divergência de modo"));
        // smt/causal/gum: the solver verdict IS a real proof.
        assert!(f.contains("Solver provou incoerência"));
    }

    #[test]
    fn attach_confidence_theorem_divergence_does_not_claim_proof() {
        // theorem UNKNOWN/INVALID is explicitly NOT a proof of invalidity, so the
        // divergence message must not say the solver "provou incoerência".
        let f = attach_confidence("## Finding\ntest", CotVerdict::Coherent, "theorem");
        assert!(f.contains("CONFIDENCE: MEDIUM"));
        assert!(f.contains("divergência de modo"));
        assert!(!f.contains("Solver provou incoerência"));
        assert!(f.contains("não é prova de invalidade"));
    }

    #[test]
    fn attach_confidence_medium_on_unknown_cot() {
        let f = attach_confidence("## Finding\ntest", CotVerdict::Unknown, "smt");
        assert!(f.contains("CONFIDENCE: MEDIUM"));
        assert!(f.contains("indisponível"));
    }

    // ===== P2: SymbCoT semantic faithfulness verifier =====

    #[tokio::test]
    async fn symb_verify_off_by_default_passes_through() {
        std::env::remove_var("BEAGLE_TRIAD_SYMB_VERIFY");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let result = verify_translation_faithfulness(
            "claim text",
            "formal description",
            "{\"constraints\":[]}",
            &ctx,
            "t",
        )
        .await;
        assert!(result, "gate OFF must be a pass-through (true)");
    }

    #[tokio::test]
    async fn symb_verify_on_llm_error_passes_through() {
        // Gate ON + mock LLM (no real 'equivalent:false') → must still pass (true),
        // honest: a verifier outage must not silently suppress real findings.
        std::env::set_var("BEAGLE_TRIAD_SYMB_VERIFY", "1");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let result = verify_translation_faithfulness(
            "dose >= 80 mg and dose <= 40 mg",
            "constraints: dose >= 80; dose <= 40",
            "{\"constraints\":[{\"coeffs\":[-1],\"bound\":-80},{\"coeffs\":[1],\"bound\":40}]}",
            &ctx,
            "t",
        )
        .await;
        std::env::remove_var("BEAGLE_TRIAD_SYMB_VERIFY");
        assert!(result, "no explicit equivalent:false → pass");
    }

    #[test]
    fn symb_verify_gate_parse() {
        for val in ["1", "true", "yes", "on", "TRUE", "YES", "ON"] {
            std::env::set_var("BEAGLE_TRIAD_SYMB_VERIFY", val);
            assert!(symb_verify_enabled(), "expected truthy for {val}");
        }
        for val in ["0", "false", "no", "off", ""] {
            std::env::set_var("BEAGLE_TRIAD_SYMB_VERIFY", val);
            assert!(!symb_verify_enabled(), "expected falsy for {val}");
        }
        std::env::remove_var("BEAGLE_TRIAD_SYMB_VERIFY");
    }

    #[test]
    fn smt_canonical_key_distinguishes_different_coeffs() {
        // Same label+bound but different coefficient vectors must NOT collide:
        // they are structurally different linear constraints.
        let a =
            smt_canonical_key("{\"constraints\":[{\"label\":\"x\",\"coeffs\":[1],\"bound\":5}]}");
        let b =
            smt_canonical_key("{\"constraints\":[{\"label\":\"x\",\"coeffs\":[1,1],\"bound\":5}]}");
        assert!(a.is_some() && b.is_some());
        assert_ne!(a, b, "different coeffs must yield different keys");
    }

    #[test]
    fn smt_canonical_key_stable_under_coeff_order() {
        // coeffs are sorted, so permutations of the same multiset agree.
        let a =
            smt_canonical_key("{\"constraints\":[{\"label\":\"x\",\"coeffs\":[1,2],\"bound\":5}]}");
        let b =
            smt_canonical_key("{\"constraints\":[{\"label\":\"x\",\"coeffs\":[2,1],\"bound\":5}]}");
        assert_eq!(a, b);
    }

    // ===== P3: self-consistency policies + run_extraction_with_consistency =====

    #[test]
    fn extraction_policy_defaults() {
        for d in ["SMT", "CAUSAL", "GUM", "THEOREM"] {
            std::env::remove_var(format!("BEAGLE_TRIAD_{d}_K"));
            std::env::remove_var(format!("BEAGLE_TRIAD_{d}_AGREE"));
        }
        let smt = smt_policy();
        assert_eq!((smt.k, smt.agree, smt.confidence_label), (3, 2, false));
        let causal = causal_policy();
        assert_eq!(
            (causal.k, causal.agree, causal.confidence_label),
            (3, 3, true)
        );
        let gum = gum_policy();
        assert_eq!((gum.k, gum.agree, gum.confidence_label), (3, 3, true));
        let theorem = theorem_policy();
        assert_eq!(
            (theorem.k, theorem.agree, theorem.confidence_label),
            (3, 2, false)
        );
    }

    #[test]
    fn read_policy_env_override() {
        std::env::set_var("BEAGLE_TRIAD_SMT_K", "5");
        std::env::set_var("BEAGLE_TRIAD_SMT_AGREE", "4");
        let smt = smt_policy();
        assert_eq!((smt.k, smt.agree), (5, 4));
        // agree clamped to <= k, and both >= 1.
        std::env::set_var("BEAGLE_TRIAD_CAUSAL_K", "1");
        std::env::set_var("BEAGLE_TRIAD_CAUSAL_AGREE", "9");
        let causal = causal_policy();
        assert_eq!((causal.k, causal.agree), (1, 1));
        for v in [
            "BEAGLE_TRIAD_SMT_K",
            "BEAGLE_TRIAD_SMT_AGREE",
            "BEAGLE_TRIAD_CAUSAL_K",
            "BEAGLE_TRIAD_CAUSAL_AGREE",
        ] {
            std::env::remove_var(v);
        }
    }

    async fn consistency_with_keys(
        keys: Vec<&'static str>,
        k: usize,
        agree: usize,
    ) -> ConsistencyResult<u32> {
        // We cannot easily mock call_llm_extraction's k responses to distinct values,
        // so we exercise the freq/threshold logic directly via the same algorithm the
        // helper uses. This mirrors run_extraction_with_consistency's counting.
        use std::collections::HashMap;
        let mut freq: HashMap<&str, usize> = HashMap::new();
        for key in &keys {
            *freq.entry(key).or_insert(0) += 1;
        }
        let policy = ExtractionPolicy {
            k,
            agree,
            confidence_label: false,
        };
        if let Some((_best, &votes)) = freq.iter().max_by_key(|(_, &v)| v) {
            if votes >= policy.agree {
                return ConsistencyResult::Agreed {
                    artifact: 42u32,
                    votes,
                };
            }
        }
        ConsistencyResult::Abstained {
            k: policy.k,
            agree_required: policy.agree,
        }
    }

    #[tokio::test]
    async fn run_extraction_with_consistency_majority() {
        // 'K','K','X' with agree=2 → Agreed votes=2.
        match consistency_with_keys(vec!["K", "K", "X"], 3, 2).await {
            ConsistencyResult::Agreed { artifact, votes } => {
                assert_eq!(artifact, 42);
                assert_eq!(votes, 2);
            }
            _ => panic!("expected Agreed"),
        }
    }

    #[tokio::test]
    async fn run_extraction_with_consistency_no_majority() {
        // 'A','B','C' with agree=2 → Abstained (no key has 2 votes).
        match consistency_with_keys(vec!["A", "B", "C"], 3, 2).await {
            ConsistencyResult::Abstained { k, agree_required } => {
                assert_eq!((k, agree_required), (3, 2));
            }
            _ => panic!("expected Abstained"),
        }
    }

    #[tokio::test]
    async fn run_extraction_with_consistency_unanimous_required() {
        // 'K','K','X' with agree=3 → Abstained (only 2 votes, need 3).
        match consistency_with_keys(vec!["K", "K", "X"], 3, 3).await {
            ConsistencyResult::Abstained { .. } => {}
            _ => panic!("expected Abstained for unanimous threshold"),
        }
    }

    #[tokio::test]
    async fn run_extraction_with_consistency_real_helper_abstains_on_mock_empty() {
        // With a mock LLM that does not return parseable constraint JSON, the helper
        // must abstain (no key reaches the threshold) — honest fallback.
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let policy = ExtractionPolicy {
            k: 3,
            agree: 2,
            confidence_label: false,
        };
        let result: ConsistencyResult<u32> = run_extraction_with_consistency(
            policy,
            &ctx,
            "t",
            "prompt",
            |_t| None,
            |_t| Some(7u32),
        )
        .await;
        assert!(matches!(result, ConsistencyResult::Abstained { .. }));
    }

    #[tokio::test]
    async fn theorem_check_abstains_gate_off_no_consistency_calls() {
        std::env::remove_var("BEAGLE_TRIAD_THEOREM_CHECK");
        let ctx = BeagleContext::new_with_mock().expect("mock ctx");
        let out = theorem_claim_check("logo X", &ctx, "t").await;
        assert!(out.is_none());
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
