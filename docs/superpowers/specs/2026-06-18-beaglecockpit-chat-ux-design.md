# BeagleCockpit Chat UX — Chromatic Presence + Spatial Dialogue

**Date:** 2026-06-18  
**Branch target:** `feat/ios-100pct-real`  
**Framework:** Gaggioli Positive Technology (Emotional Quality · Engagement/Actualization · Connectedness) + SDT autonomy  
**Hedonic register:** Flow-state, pleasure-of-use, multi-sensory reward

---

## 1. Design Pillars

| Pillar | Gaggioli Dimension | Implementation lever |
|--------|-------------------|----------------------|
| Chromatic Presence | Emotional Quality | Per-profile hue saturates entire ambient space |
| Spatial Dialogue | Engagement | Z-space layering — user inset, assistant elevated |
| Profile Sovereignty | SDT Autonomy | Switching is haptic, immediate, satisfying |
| Brilliant Colleague | Connectedness | AI has personality, memory of YOU, relationship |
| Cognitive Mirror | Actualization | AI reflects your growth; GoDeep surfaces depth |
| Conversation Harvest | Actualization | Crystallize conversation → cluster memory |

---

## 2. Color & Spatial Architecture

### Profile Hues (base values — final calibration via designer eye)

| Profile | Role | Hue | Usage |
|---------|------|-----|-------|
| Beagle | Platform agent | Teal `#00B4D8` | Default; calm, capable |
| Deep Thought | Research/reasoning | Violet `#9B5DE5` | Deep analysis mode |
| Darwin | Medical/clinical | Emerald `#2DC653` | Healthcare context |
| Cognitive | Memory/recall | Amber `#F5A623` | Exocortex access |
| *(others)* | — | Derived from palette | Distinct, non-conflicting |

### Ambient Tint System

```swift
// ConversationView background
.background(
    ZStack {
        Color.black  // base
        LinearGradient(
            colors: [profileHue.opacity(0.08), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
)
```

- Tint opacity: **0.06–0.10** (OLED-safe, dark-only)
- Cross-fade duration: **0.35s** on profile switch
- No tint on message list area — only on background layer behind scroll

### Z-Space Layers

```
Z = 3  │  Assistant bubbles (elevated, drop shadow)
Z = 2  │  Profile strip + input bar (sticky layer)
Z = 1  │  Scroll content (messages flow)
Z = 0  │  Ambient tinted background
Z = -1 │  Blur layer (iOS: .ultraThinMaterial base)
```

---

## 3. Profile Strip

**Component:** `ProfileStrip` (horizontal scroll, anchored below nav bar)

### Active Profile Anchor Pill

```
╔══════════════════════════════════════════════╗
║  [●] Deep Thought  ▸ Research & reasoning    ║  ← active pill (full width)
╚══════════════════════════════════════════════╝
  [Bgl]  [Dar]  [Cog]   ← inactive chips (32pt circle)
```

- Active pill: `RoundedRectangle(cornerRadius: 20)` filled with `profileHue.opacity(0.18)`, border `profileHue.opacity(0.4)` 1pt
- Inactive chips: `Circle()` 32pt, `.ultraThinMaterial`, profile icon SF Symbol
- Routing hint: subtitle line `"Research & reasoning"` in `.caption` `.secondary`

### Switching Choreography

1. Tap inactive chip → `.medium` haptic
2. Chip expands to pill (spring: `response: 0.38, dampingFraction: 0.72`)
3. Previous pill collapses to chip
4. Background hue cross-fades (0.35s)
5. Input bar placeholder text fades to new profile's text (0.2s delay)

---

## 4. Message Bubbles

### User Bubbles — "Inset / Pressed"

```swift
.background(Color.white.opacity(0.07))
.overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
.shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
// Inner shadow effect via overlay gradient
.overlay(
    LinearGradient(colors: [.black.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
        .clipShape(RoundedRectangle(cornerRadius: 18))
)
```

Alignment: trailing (right), max width 80%

### Assistant Bubbles — "Elevated + Accent Bar"

```swift
.background(.ultraThinMaterial)
.overlay(
    HStack(spacing: 0) {
        Rectangle().fill(profileHue).frame(width: 3)
        Spacer()
    }
    .clipShape(RoundedRectangle(cornerRadius: 18))
)
.shadow(color: profileHue.opacity(0.20), radius: 12, x: 0, y: 4)
```

Alignment: leading (left), max width 88%

### Typography

- User text: `.body`, weight `.regular`, `lineSpacing(3)`
- Assistant text: `.body`, weight `.regular`, `lineSpacing(4)` (slightly airier for reading long responses)
- Timestamps / metadata: `.caption2`, `.tertiary`

### Recency Fade (`.scrollTransition`)

```swift
.scrollTransition(.animated) { content, phase in
    content
        .opacity(phase.isIdentity ? 1.0 : 0.55)
        .scaleEffect(phase.isIdentity ? 1.0 : 0.97)
}
```

Applied to messages older than the 4 most recent — creates sense of depth/recency.

### GoDeep Capsule

Appears 0.6s after streaming completes, slides in from leading edge:

```swift
Button(action: { /* trigger deep analysis */ }) {
    Label("Go Deeper", systemImage: "arrow.triangle.branch")
        .font(.caption.weight(.medium))
        .foregroundStyle(profileHue)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(profileHue.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(profileHue.opacity(0.3), lineWidth: 0.5))
}
.transition(.move(edge: .leading).combined(with: .opacity))
```

---

## 5. Input Bar

**Component:** `BeagleInputBar` (already exists — extend)

### Layout

```
┌─────────────────────────────────────────────────────┐
│▌│ [ultraThinMaterial + profileHue 6% tint]           │
│▌│  {placeholder}                          [● send]  │
└─────────────────────────────────────────────────────┘
 ▌ = 3pt leading edge bar, profileHue solid
```

### States

**Idle:**
- Placeholder: profile-specific text (e.g., `"Ask Deep Thought..."`, `"Talk to Beagle..."`)
- Send button: circle filled `profileHue`, white chevron icon
- No glow

**Streaming:**
```
┌─────────────────────────────────────────────────────┐
│▌│ 🧠 Deep Thought · responding...         [■ stop]  │
└─────────────────────────────────────────────────────┘
```
- Edge glow: `strokeBorder(profileHue.opacity(0.28))` repeating animation (opacity 0.28→0.12→0.28, 1.8s)
- Streaming context label replaces placeholder text area
- Stop button: `Circle()` red fill, `stop.fill` icon, `.transition(.scale(0.7).combined(.opacity))`

### Profile-Specific Placeholders

```swift
var profilePlaceholder: String {
    switch activeProfile.id {
    case "deep-thought":  return "Ask Deep Thought..."
    case "darwin":        return "Ask Darwin..."
    case "cognitive":     return "What do you remember about..."
    default:              return "Talk to Beagle..."
    }
}
```

---

## 6. Conversation Harvest — "Send to Cluster"

**Purpose:** Surface the full conversation to the exocortex for synthesis, memory storage, or deep analysis. Backend endpoints already exist (`/api/memory`, cognitive deep-think).

### Entry Point

Toolbar button (top-right of ConversationView), shown after first exchange:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { showHarvestSheet = true }) {
            Image(systemName: "arrow.up.right.circle")
                .symbolEffect(.pulse, isActive: conversation.messages.count > 1)
        }
        .disabled(conversation.messages.count < 2)
    }
}
```

### Harvest Bottom Sheet

```
┌─────────────────────────────────────────────────────┐
│  ╔═══════════════════════════════════════════════╗  │
│  ║  Send this conversation to Beagle             ║  │
│  ║  {N} exchanges · {profile} thread             ║  │
│  ╚═══════════════════════════════════════════════╝  │
│                                                     │
│  ┌─────────────────────────────┐                   │
│  │ 🧠  Deep Analysis           │                   │
│  │ Extract insights + patterns │                   │
│  └─────────────────────────────┘                   │
│                                                     │
│  ┌─────────────────────────────┐                   │
│  │ 💾  Save to Memory          │                   │
│  │ Store as knowledge artifact │                   │
│  └─────────────────────────────┘                   │
│                                                     │
│  ┌─────────────────────────────┐                   │
│  │ ⬦  Go Deeper on thread     │                   │
│  │ Generate follow-up angles   │                   │
│  └─────────────────────────────┘                   │
│                                                     │
│  [Cancel]                                           │
└─────────────────────────────────────────────────────┘
```

### Backend Routing

| Action | Endpoint | Payload |
|--------|----------|---------|
| Deep Analysis | `POST /api/cognitive/deep-think` | Full message array, profile context |
| Save to Memory | `POST /api/memory` (Bearer token) | Formatted transcript as knowledge artifact |
| Go Deeper | `POST /api/cognitive/deep-think` | Messages + `mode: "follow-up-angles"` |

### Haptic Choreography

1. Tap toolbar → `.light` impact
2. Sheet arrives → `.rigid` impact
3. Select action → `.medium` impact
4. Success → `.success` notification haptic + checkmark overlay on toolbar button (1.5s, then fades)

---

## 7. Full Choreography Reference

| Event | Animation | Haptic |
|-------|-----------|--------|
| Profile switch | Spring expand pill + hue cross-fade 0.35s | `.medium` |
| Message arrive (assistant) | Slide from leading + shadow pop | none |
| Message arrive (user) | Slide from trailing | none |
| Streaming start | Input bar edge glow + context label | none |
| Streaming end | Glow fade + GoDeep pill slides in (0.6s delay) | none |
| Stop tap | Button swap + glow cut | `.light` |
| Harvest open | Sheet slide up | `.rigid` |
| Harvest action | Action select | `.medium` |
| Harvest success | Checkmark overlay + fade | `.success` notification |

---

## 8. Files to Create / Modify

| File | Change |
|------|--------|
| `ConversationView.swift` | Ambient tint, profile strip integration, harvest toolbar button |
| `ProfileStrip.swift` | **New** — active pill + inactive chips, spring choreography |
| `ChatBubbleView.swift` | User inset style, assistant elevated + accent bar, GoDeep pill, recency fade |
| `BeagleInputBar.swift` | Leading edge bar, profile-colored send circle, streaming context inline, profile placeholders |
| `ConversationStore.swift` | `harvestConversation(mode:)` async method calling backend |
| `HarvestSheetView.swift` | **New** — bottom sheet with 3 actions |
| `BeagleTheme.swift` | Profile hue map, `profileHue(for:)` helper |

---

## 9. Non-Goals

- No light mode — dark/OLED only
- No animated background particles or motion beyond what is specified
- No changes to macOS layout structure (sidebar stays as-is)
- No new profile types in this pass
