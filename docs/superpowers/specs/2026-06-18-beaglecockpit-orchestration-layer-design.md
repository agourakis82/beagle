# BeagleCockpit Orchestration Layer — A+B+C Design

**Date:** 2026-06-18  
**Branch target:** `feat/ios-100pct-real` → next  
**Status:** Design approved, pending implementation plan  
**Gaggioli dimensions:** Engagement/Actualization (A), Emotional Quality (B), SDT Autonomy (C)

---

## Evidence Foundation

These are the **only** claims used as design justification — all others from the 2026 UX report are treated as forward bets or overreach.

| Claim | Source | Confidence |
|-------|--------|-----------|
| Hybrid > chat-only surfaces | Multi-source convergence (no single authoritative study) | High directional |
| Controllability is binding constraint | EMNLP peer-reviewed survey, 60/1781 papers | Strong (peer-reviewed) |
| Structured plan review lifts success 17%→60% | AgentStepper, arXiv replicable | Strong (specific metric) |
| v_bal (Error Verifiability) doesn't scale with model | arXiv, replicable methodology | Strong |

**Not used:** Nielsen triple-layer taxonomy, N=16 active participation study, A2UI as standard.

**Research opportunity Beagle is positioned to fill:** "verification efficiency as dominant metric" is a hypothesis, not a fact. Beagle can measure `time-to-correct` empirically on real users and report to the field.

---

## Design Overview

Three surfaces rendered inside the existing `ConversationView` flow:

```
A: AgentPlanCard     — structured plan before agent acts, with tool depth sliders
B: VerificationStrip — post-response evidence panel with temporal memory
C: Autonomy Dial     — per-profile graded control (Ask → Plan → Auto)
```

These are NOT a three-layer architecture taxonomy. They are three composable UI components that appear in a single conversation thread when the context warrants them.

---

## A: AgentPlanCard

### Purpose

When Beagle is about to take multi-step action (tool calls, cluster jobs, exocortex writes), surface the plan as an editable card before execution. Grounded in AgentStepper finding: structured review before execution is the highest-ROI intervention.

### Layout

```
╔══════════════════════════════════════════════════════════╗
║  Plan · Web Research + Memory                  [Edit]   ║
║  ─────────────────────────────────────────────────────  ║
║  Step 1  Search — deep web research                     ║
║          Depth: ●────────────────── (5/5)               ║
║                 Surface ←──────────→ Exhaustive         ║
║                                                         ║
║  Step 2  Synthesize — cross-source analysis             ║
║          Depth: ●──────── (3/5)                         ║
║                 Draft ←──────────→ Peer-quality         ║
║                                                         ║
║  Step 3  Save to memory — knowledge artifact            ║
║          Depth: ●──── (2/5)                             ║
║                 Tag only ←──────────→ Full context      ║
║                                                         ║
║                          [Adjust] [Run]                 ║
╚══════════════════════════════════════════════════════════╝
```

### Tool Depth Sliders

Each tool in the plan has a continuous depth control — not binary (on/off), not tier-based (shallow/deep/exhaustive), but a single slider the user can read as effort/cost/quality investment.

**Slider values map to concrete backend parameters:**

| Tool | Slider 1 | Slider 5 |
|------|---------|---------|
| Web research | 3 sources, surface synthesis | 20+ sources, contradiction check, gap analysis |
| Deep analysis | Single-pass summary | Multi-pass with Triad adversarial review |
| Memory save | Tag + title only | Full transcript + semantic context + graph links |
| Cluster job | cpu-ops, fast | GPU + full validation, slower |

Sliders are stored per-tool-type in `UserDefaults` and persist across sessions — the user's "usual depth for web research" is remembered.

### Autonomy Interaction

- When `C` dial is at **Ask**: plan card always appears, user must tap Run
- When `C` dial is at **Plan**: plan card appears, auto-runs after 5s countdown (cancelable)
- When `C` dial is at **Auto**: plan executes silently, plan card accessible via "View plan" disclosure

### Technical Surface

Backend sends plan as structured JSON before execution begins:

```json
{
  "plan_id": "plan_abc123",
  "steps": [
    {
      "id": "step_1",
      "tool": "web_research",
      "label": "Search — deep web research",
      "depth_default": 3,
      "depth_min": 1,
      "depth_max": 5,
      "depth_label_min": "Surface",
      "depth_label_max": "Exhaustive"
    }
  ]
}
```

Client sends back confirmed plan with user-adjusted depths before execution.

### Files

| File | Change |
|------|--------|
| `AgentPlanCard.swift` | **New** — plan card component |
| `ToolDepthSlider.swift` | **New** — continuous depth control |
| `ConversationStore.swift` | Add `pendingPlan: AgentPlan?`, `confirmPlan(depths:)` |
| `ConversationView.swift` | Show plan card above input bar when `pendingPlan != nil` |

---

## B: VerificationStrip

### Purpose

After assistant response, surface the evidence quality inline — not as a warning, not as a red flag, but as epistemic context that helps the user judge quickly. Grounded in: v_bal evidence, Gravity7 post-action audit pattern, and the **temporal memory advantage** Beagle has that no other system can replicate.

### Layout (collapsed, default)

```
───────────────────────────────────────────────
  ◉  3 sources  ·  ⚠ 1 unverified  ·  ↺ Memory  ▿
───────────────────────────────────────────────
```

### Layout (expanded)

```
╔══════════════════════════════════════════════╗
║  Sources (3)                                 ║
║  ✓ PubMed 2024 — cited directly             ║
║  ✓ arXiv 2023 — corroborating               ║
║  ? Wikipedia — low confidence               ║
║                                              ║
║  Memory context                              ║
║  ⚠ Contradicts your note from 2 weeks ago   ║
║    "X treatment is contraindicated in Y"     ║
║    [View note]  [Flag as conflict]           ║
║                                              ║
║  Escalation                                  ║
║  [Request Triad review]  [Add to study]      ║
╚══════════════════════════════════════════════╝
```

### Temporal Memory — Beagle's Unique Advantage

The exocortex stores timestamped knowledge artifacts. The verification strip can query:

```
/api/exocortex/v1/verify?claim={claim_hash}&lookback=30d
```

Response includes any conflicting notes from the user's own memory within the lookback window. This surfaces contradictions the user themselves recorded — the most trusted form of verification.

**Example signals:**
- "Contradicts what you noted 14 days ago in [Clinical session — Darwin thread]"
- "Consistent with your stored protocol from 3 months ago"
- "You flagged this as uncertain in a Grok thread last week"

No other consumer AI can do this because no other consumer AI has a user-owned persistent exocortex.

### Evidence Quality Taxonomy

Simple, not borrowed from Nielsen:

| Signal | Meaning |
|--------|---------|
| ✓ Cited | Direct source with URL/DOI |
| ◯ Inferred | Synthesized from sources, not directly cited |
| ? Unverified | Model knowledge, no source |
| ⚠ Conflict | Contradicts a stored memory or another source |

### Escalation

Two escalation paths:

1. **Triad review** — sends the response for adversarial debate by ATHENA/HERMES/ARGOS; result arrives as a follow-up message
2. **Add to study** — sends claim + sources to a persistent study session in the exocortex for later synthesis

### Files

| File | Change |
|------|--------|
| `VerificationStrip.swift` | **New** — collapsible strip with temporal memory |
| `EvidenceTag.swift` | **New** — individual source/evidence chip |
| `ConversationStore.swift` | Add `verificationContext: VerificationResult?` per message |
| `ChatBubbleView.swift` | Attach verification strip below assistant bubbles |
| `BeagleClient.swift` | Add `verify(claimHash:, lookback:)` method |

---

## C: Autonomy Dial

### Purpose

Per-profile graded control that lets the user set how much Beagle acts vs. asks. Grounded in the strongest finding from the evidence base: controllability is a binding constraint on AI adoption (EMNLP, peer-reviewed). The dial is not about trust — it's about cognitive load preference in context.

### Three Positions

| Position | Name | Behavior |
|----------|------|---------|
| 1 | Ask | Beagle asks before every tool call. Plan card always appears. Verification strip always expanded. |
| 2 | Plan | Beagle proposes plan, auto-runs after countdown. Verification strip collapsed by default. |
| 3 | Auto | Beagle acts immediately. Plan accessible via disclosure. Verification strip collapsed. Triad review auto-triggered for high-stakes responses. |

### Layout

```
╔══════════════════════════════════════════════╗
║  ○ Ask  ───  ● Plan  ───  ○ Auto             ║
║  "Propose then act"                           ║
╚══════════════════════════════════════════════╝
```

- Rendered in the **profile pill** expanded state (tapping active profile pill reveals dial)
- Per-profile: `.cluster` might default to Auto (trusted platform operations), `.claudeCode` to Ask (code review should be deliberate)
- Setting persists in `UserDefaults` keyed by `profile.rawValue`
- Changing position gives `.medium` haptic

### Autonomy × Verification Interaction

The dial also gates verification strip behavior:

| Dial | Plan card | Verification | Escalation |
|------|-----------|-------------|-----------|
| Ask | Always visible | Always expanded | Prompted |
| Plan | Visible + countdown | Collapsed, tap to expand | Available |
| Auto | Disclosure only | Collapsed | Auto for high-stakes |

"High-stakes" is determined by backend response metadata: `risk_level: high` triggers auto-Triad regardless of dial position.

### Files

| File | Change |
|------|--------|
| `AutonomyDial.swift` | **New** — three-position segmented control |
| `ProfilePill.swift` | **New** or modify `discussionProfileButton` — expand to show dial |
| `ConversationStore.swift` | Add `autonomyMode: AutonomyMode` per profile |

---

## Interaction Choreography

### Plan Card arrival

1. Backend sends plan JSON before tool execution begins
2. Plan card slides up from below input bar (spring: `response: 0.42, dampingFraction: 0.75`)
3. `.rigid` haptic on arrival
4. If dial = Plan: 5s countdown ring on Run button, tap to cancel
5. User adjusts sliders → sliders animate with `.interactiveSpring`
6. Tap Run → `.medium` haptic, card collapses, execution begins

### Verification strip

1. Assistant response completes streaming
2. 0.8s delay (allow user to read ending)
3. Strip slides in from bottom of bubble (`.move(edge: .bottom).combined(with: .opacity)`)
4. If temporal memory conflict found: strip auto-expands with `⚠` signal, `.warning` notification haptic
5. No conflict: strip stays collapsed

### Autonomy dial change

1. Tap active profile pill → expands to show dial (spring animation)
2. Tap new position → `.medium` haptic + position animates
3. Pill collapses after 1.5s or on next tap outside

---

## Research Instrumentation

Beagle is positioned to answer what the field cannot. Instrument these events:

| Event | Metric |
|-------|--------|
| User edits plan before running | Plan edit rate by tool type |
| User expands verification strip | Verification engagement rate |
| Time from response to user action | `time-to-correct` proxy |
| User escalates to Triad | Escalation rate by profile |
| Temporal conflict ⚠ shown | Memory conflict frequency |

These emit to the feedback system (`crates/beagle-feedback/`) as `OrchestrationEvent` type. Aggregate weekly into a `time_to_correct` metric. This becomes the empirical answer to what the UX literature only hypothesizes.

---

## Non-Goals

- No A2UI compatibility or protocol compliance
- No light mode
- No Nielsen triple-layer architecture imposed as code structure
- No changes to backend routing or LLM selection logic (dial is UI-only)
- No gamification or progress bars
- No onboarding tour or tooltips

---

## Open Questions (decide before implementation)

1. **Plan card location:** Above input bar (always visible) vs. as a full-screen sheet? Recommendation: above input bar, 280pt max height with scroll if needed.

2. **Slider step count:** Continuous float (0.0–1.0) vs. discrete integers (1–5)? Recommendation: discrete 1–5, maps cleanly to backend parameters.

3. **Verification strip on iOS vs macOS:** On macOS, strip can be persistent sidebar. On iOS, must be collapsible. Recommendation: same collapsible component on both platforms; macOS gets `.frame(maxWidth: 320)` sidebar option later.

4. **Temporal lookback window:** 7d, 30d, or user-configurable? Recommendation: 30d default, configurable in profile settings.
