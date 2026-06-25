# Beagle Companion — Design System Spec (iOS 27)

> Ground-up redesign direction for the BeagleCockpit iOS app as a **warm personal
> companion**. Derived from the 2026-06-24 deep-research (95 agents, 8 high-confidence
> cited findings). Persona chosen by the user: **companheiro pessoal** — intimate,
> biographical, warm; not an institutional dashboard. Focus chosen: **the design system
> foundation** (tokens → components → motion), then screens, starting with **chat**.

## 0. North star

The app is someone who **knows you** — your body (HealthKit/Physiome: HRV, sleep, ECG,
local pressure) and your life (the sovereign exocortex memory). It talks like a friend
who remembers, not a clinic. Every design decision serves **warmth with honesty** and
**craft**, on the newest Apple SDK.

## 1. Intelligence architecture (what the UI is wired to)

**Hybrid, sovereign-first** (finding 1, high):
- **On-device Foundation Models** (`SystemLanguageModel.default` / `LanguageModelSession`)
  for privacy-sensitive *narrow* tasks over the biography — summarize, tag, extract,
  classify — that **never leave the device**.
- **Self-hosted frontier model** (the cluster) for deep life-history reasoning. The
  on-device ~3B model is too weak / hallucination-prone to own that alone.
- The UI must make the **active tier visible but quiet** (a small "on-device" vs "cluster"
  affordance), and degrade gracefully (on-device fallback when offline).

**iOS 27 Foundation Models** (finding 2, high — *beta-risky, gate behind the on-device tier*):
- **Multimodal image prompts** + on-device **Vision tools** (OCR/barcode) the model can
  call directly → attach a photo / read a lab result on-device.
- **Dynamic Profiles** — swap model/tools/instructions mid-session → this is the
  **register/persona actuator** (researcher↔friend) made *native*, no session restart.

## 2. The Liquid Glass law (finding 3 & 4, high)

**Glass is chrome, never content.**
- Apply `glassEffect` ONLY to the **floating navigation layer**: the **input bar**, tab
  bar, nav/toolbars, floating buttons.
- **Never** on chat bubbles or content cards — they stay **flat/opaque**.
- Glass cannot sample glass → wrap adjacent glass elements in a `GlassEffectContainer`.
- API: `glassEffect(.regular | .clear | .identity, in: shape)` + `.tint(_)` + `.interactive()`.
  Use `.identity` to conditionally disable. `.regular` is the adaptive default; `.tint`
  with a faint surface/truth color for dark-first.
- iOS 27 auto-refines the material (better content diffusion/legibility, darkened edges,
  brighter specular) for already-adopting apps, and adds a **user transparency slider** —
  so don't hardcode opacity; treat glass as adaptive and let the system tune it.

## 3. Design tokens

Build on the existing `BeagleCore/Theme.swift` (truth-modes, surfaces, spacing, radius,
type ramp). **Add a warmth layer** — the current palette is cool/clinical (teal/sky/slate);
a companion needs warmth in the *content* layer while keeping the cool **truth-modes as
epistemic accents** (the exocortex distinguishes observed vs remembered vs declared).

### Color (dark-first, semantic)
- **Surfaces** (existing `surface0…3`): deep indigo-blacks for the canvas + the living mesh.
- **Content warmth (new):** `companionInk` (warm off-white text), `companionSurface`
  (a faintly warm raised surface for the assistant's voice), `userSurface` (cool, the
  user's bubble). Warmth differentiates *the companion's voice* from chrome and from you.
- **Truth-modes (existing) = accents only:** `truthObserved` (teal, live), `truthRemembered`
  (sky, recalled memory), `truthDeclared` (slate, policy), `truthStale`. Used on memory
  chips, recall provenance, status — NOT as bubble fills.
- Semantic tokens, not raw colors: `surface/content/chrome/accent/onSurface`.

### Type
- Use the existing `BeagleFont` semantic ramp (display/title/headline/body/caption) — never
  raw sizes. Full **Dynamic Type**. Body is the chat workhorse; keep line length comfortable.

### Spacing & radius
- Existing `BeagleSpacing` (xxs…jumbo) and `BeagleRadius` (sm…pill). Bubbles: `lg` radius,
  asymmetric tail corner. Input bar: `pill`/`xl`. Generous vertical rhythm in chat.

## 4. Components (chat-first)

| Component | Spec |
|---|---|
| **MessageBubble** | Flat, opaque, directional (Messages-style). User = trailing, cool `userSurface`. Companion = leading, warm `companionSurface`, no avatar chrome (presence is in the voice). Selectable text. Tail via asymmetric corner radius. |
| **StreamingBubble** | The companion bubble while `isStreaming`: a soft pulsing presence dot, text grows by **coalesced snapshot diffs** (finding 5), never per-token jank. |
| **ChatComposer** | The **only glass element** in chat — a floating pill input bar (`glassEffect(.regular)`), multiline grow, attach (photo → multimodal), mic (voice), send. Tier indicator (on-device/cluster) as a quiet leading chip. |
| **MemoryChip / Provenance** | When the companion grounds on biography/physiome, a small **truth-mode-colored** chip ("lembro que…", recalled) — surfacing memory builds warmth (finding 7), but show provenance to avoid creepiness. |
| **MemoryArtifact (later)** | Named, revisitable keepsakes — "Nossa Memória" / "Nosso Plano" (finding 6). Conversation → returnable artifact, not flat scrollback. |

## 5. Motion principles
- Calm, purposeful, no gratuitous decoration. Bubbles **rise + fade** in (subtle, spring).
- Streaming presence = a gentle breathing dot, not a spinner.
- Honor `accessibilityReduceMotion` (the living-mesh bg already does).
- The mesh background drifts slowly (existing) — content sits flat above it.

## 6. Companion UX laws (the soul)
1. **Zero-friction** — no forms, no setup walls. You just talk (finding 6).
2. **Memory as keepsake** — named, revisitable artifacts, not dead history (finding 6).
3. **Proactive biographical surfacing** — recall a prior thread, follow up — strongest
   warmth signal (finding 7) — *with provenance* to avoid mis-remembering/creepiness.
4. **🔴 Warm but HONEST — the #1 evidence-backed pitfall is SYCOPHANCY** (finding 8, high):
   companions tuned to flatter for engagement **measurably harm wellbeing**. Emotional
   mirroring does **not** substitute for substantive content. This is the user's own
   stated intent (warm "conselho de amigo", never over-cautious grey, never flattering).
   The persona/system-prompt and any RLHF must optimize honesty-with-care, not agreeableness.

## 7. Build order
1. Tokens: extend Theme.swift with the **warmth content layer** (`companionInk/Surface`,
   `userSurface`). ← this spec's companion code.
2. **Chat skeleton** (this deliverable): `ChatScreen` + `MessageBubble` + `ChatComposer`
   on `ConversationStore` (existing @Observable streaming), glass input only, flat warm
   bubbles, coalesced streaming, memory provenance affordance.
3. Then: memory artifacts, voice, multimodal attach, tier switching (Dynamic Profiles).

## Sources (high-confidence, adversarially verified)
- Apple WWDC26 Apple-Intelligence guide + session 241 (Foundation Models: multimodal,
  Vision tools, Dynamic Profiles).
- WWDC25 sessions 323/310 + Apple HIG "Adopting Liquid Glass"; conorluddy/LiquidGlassReference;
  swiftwithmajid (glassEffect API, glass-on-navigation-only, GlassEffectContainer).
- MacRumors/Tom's Guide 2026-06 (iOS 27 Liquid Glass refinements + transparency slider).
- Dimillian/FoundationChat, mattt/chat-ui-swift (on-device streaming, snapshot coalescing).
- natashatherobot, Apple ML research (on-device model limits → hybrid).
- Chatura / digitalhumancorp 2026, Frontiers in Psychology 2026 (warmth patterns, memory surfacing).
- Taylor & Francis 2026 (sycophancy harms wellbeing; mirroring ≠ substance).
