# BeagleCockpit Orchestration Layer (A+B+C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three composable UI surfaces to BeagleCockpit: AgentPlanCard (A), VerificationStrip (B), and AutonomyDial (C) — enabling structured plan review, per-bubble evidence inspection, and graded per-profile autonomy control.

**Architecture:** All edits are on the Mac at `~/Developer/beagle/beagle-ios/`. New types go in `BeagleCore` (models + client methods); new views go in `BeagleCockpit`. The three components share `ConversationStore` additions but are otherwise independent — implement A, then B, then C, each with its own commit. All work targets `feat/ios-100pct-real`.

**Tech Stack:** SwiftUI (iOS 17+ / macOS 14+), `@Observable`, `UserDefaults` for persistence, `BeagleClient.post(_:path:body:timeout:)` → `Truthful<T>`, SSH to Mac for all file delivery.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `BeagleCore/OrchestrationModels.swift` | **Create** | All new data types: `AgentPlan`, `PlanStep`, `AutonomyMode`, `VerificationResult`, `EvidenceItem`, `OrchestrationEvent` |
| `BeagleCore/ConversationStore.swift` | **Modify** | Add `pendingPlan`, `autonomyMode(for:)`, `verificationResult(for:)`, `confirmPlan(depths:)` |
| `BeagleCore/BeagleClient.swift` | **Modify** | Add `verifyMessage(claimHash:profileId:lookback:)` |
| `BeagleCockpit/AgentPlanCard.swift` | **Create** | Sheet: scrollable plan steps + depth sliders, Run/Cancel |
| `BeagleCockpit/ToolDepthSlider.swift` | **Create** | Single-step slider 1–5 with semantic labels |
| `BeagleCockpit/VerificationStrip.swift` | **Create** | iOS: inline collapsible; macOS: sidebar panel |
| `BeagleCockpit/EvidenceTag.swift` | **Create** | Individual source chip (✓ / ◯ / ? / ⚠) |
| `BeagleCockpit/AutonomyDial.swift` | **Create** | Three-position segmented control Ask/Plan/Auto |
| `BeagleCockpit/ConversationView.swift` | **Modify** | Wire plan sheet, macOS sidebar, profile pill autonomy dial |
| `BeagleCockpit/ChatBubbleView.swift` | **Modify** | Long-press context menu "Check sources" on assistant bubbles |

---

## Task 1: Data models

**Files:**
- Create: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/OrchestrationModels.swift`

- [ ] **Step 1: Write the file to /tmp then scp to Mac**

```bash
cat > /tmp/OrchestrationModels.swift << 'SWIFT'
//
//  OrchestrationModels.swift
//  BeagleCore
//
import Foundation

// MARK: - A: Agent Plan

public struct AgentPlan: Decodable, Sendable {
    public let planId: String
    public let title: String
    public let steps: [PlanStep]
    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"; case title; case steps
    }
}

public struct PlanStep: Decodable, Sendable, Identifiable {
    public let id: String
    public let tool: String
    public let label: String
    public let depthDefault: Int
    public let depthMin: Int
    public let depthMax: Int
    public let depthLabelMin: String
    public let depthLabelMax: String
    enum CodingKeys: String, CodingKey {
        case id; case tool; case label
        case depthDefault = "depth_default"
        case depthMin = "depth_min"
        case depthMax = "depth_max"
        case depthLabelMin = "depth_label_min"
        case depthLabelMax = "depth_label_max"
    }
}

public struct ConfirmedPlan: Encodable, Sendable {
    public let planId: String
    public let steps: [ConfirmedStep]
    enum CodingKeys: String, CodingKey { case planId = "plan_id"; case steps }
}
public struct ConfirmedStep: Encodable, Sendable {
    public let id: String
    public let depth: Int
}

// MARK: - B: Verification

public struct VerificationResult: Decodable, Sendable {
    public let messageId: String
    public let sources: [EvidenceItem]
    public let temporalConflict: TemporalConflict?
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"; case sources
        case temporalConflict = "temporal_conflict"
    }
}

public struct EvidenceItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let url: String?
    public let confidence: EvidenceConfidence
    public enum EvidenceConfidence: String, Decodable, Sendable {
        case cited, inferred, unverified, conflict
    }
}

public struct TemporalConflict: Decodable, Sendable {
    public let summary: String
    public let noteId: String?
    public let daysAgo: Int
    enum CodingKeys: String, CodingKey {
        case summary; case noteId = "note_id"; case daysAgo = "days_ago"
    }
}

// MARK: - C: Autonomy

public enum AutonomyMode: Int, CaseIterable, Sendable {
    case ask = 0, plan = 1, auto = 2
    public var label: String {
        switch self { case .ask: return "Ask"; case .plan: return "Plan"; case .auto: return "Auto" }
    }
    public var subtitle: String {
        switch self {
        case .ask:  return "Beagle asks before every action"
        case .plan: return "Beagle proposes, then acts"
        case .auto: return "Beagle acts, you review after"
        }
    }
}

// MARK: - Instrumentation

public struct OrchestrationEvent: Encodable, Sendable {
    public let eventType: String
    public let profileId: String
    public let autonomyMode: Int
    public let metadata: [String: String]
    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"; case profileId = "profile_id"
        case autonomyMode = "autonomy_mode"; case metadata
    }
}
SWIFT
scp /tmp/OrchestrationModels.swift mac:~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/OrchestrationModels.swift
```

- [ ] **Step 2: Verify build compiles**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'"
```

Expected: `BUILD SUCCEEDED` with no `error:` lines.

- [ ] **Step 3: Commit**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCore/OrchestrationModels.swift && git commit -m 'feat(models): OrchestrationModels — AgentPlan, VerificationResult, AutonomyMode'"
```

---

## Task 2: ConversationStore additions

**Files:**
- Modify: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/ConversationStore.swift`

The store needs:
1. `public var pendingPlan: AgentPlan? = nil` — set by backend, cleared after user confirms/cancels
2. `autonomyMode(for:) / setAutonomyMode(_:for:)` — reads/writes `UserDefaults`
3. `verificationResults: [UUID: VerificationResult]` — cache per message ID
4. `confirmPlan(depths: [String: Int]) async` — posts `ConfirmedPlan` to backend
5. `fetchVerification(for messageId: UUID) async` — calls `/api/exocortex/v1/verify`

- [ ] **Step 1: Write the patch script to /tmp**

```bash
cat > /tmp/patch_store.py << 'PY'
import re

path = "/Users/demetriosagourakis/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/ConversationStore.swift"
with open(path) as f:
    src = f.read()

# Insert new properties after autoImportState line
old = "    public private(set) var autoImportState: ConversationAutoImportState = .idle"
new = """    public private(set) var autoImportState: ConversationAutoImportState = .idle

    // MARK: - Orchestration layer (A/B/C)
    public var pendingPlan: AgentPlan? = nil
    public private(set) var verificationResults: [UUID: VerificationResult] = [:]

    public func autonomyMode(for profile: DiscussionProfile) -> AutonomyMode {
        let key = "autonomy_\\(profile.rawValue)"
        let raw = UserDefaults.standard.integer(forKey: key)
        return AutonomyMode(rawValue: raw) ?? .ask
    }

    public func setAutonomyMode(_ mode: AutonomyMode, for profile: DiscussionProfile) {
        let key = "autonomy_\\(profile.rawValue)"
        UserDefaults.standard.set(mode.rawValue, forKey: key)
    }

    public func confirmPlan(depths: [String: Int]) async {
        guard let plan = pendingPlan else { return }
        let confirmed = ConfirmedPlan(
            planId: plan.planId,
            steps: plan.steps.map { ConfirmedStep(id: $0.id, depth: depths[$0.id] ?? $0.depthDefault) }
        )
        _ = await client.postEncoded(ActionResponse.self, path: "/api/orchestration/plan/confirm", body: confirmed, timeout: 30)
        pendingPlan = nil
    }

    public func fetchVerification(for messageId: UUID, profileId: String) async {
        let lookback = lookbackDays(for: discussionProfile)
        let result = await client.post(
            VerificationResult.self,
            path: "/api/exocortex/v1/verify",
            body: ["message_id": messageId.uuidString, "profile_id": profileId, "lookback_days": lookback],
            timeout: 20
        )
        if let vr = result.value {
            verificationResults[messageId] = vr
        }
    }

    private func lookbackDays(for profile: DiscussionProfile) -> Int {
        switch profile {
        case .claudeCode, .grok, .kimi: return 90
        default: return 30
        }
    }"""

src = src.replace(old, new, 1)
with open(path, "w") as f:
    f.write(src)
print("done")
PY
scp /tmp/patch_store.py mac:/tmp/patch_store.py
ssh mac "python3 /tmp/patch_store.py"
```

- [ ] **Step 2: Verify build**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCore/ConversationStore.swift && git commit -m 'feat(store): orchestration state — pendingPlan, autonomyMode, verificationResults'"
```

---

## Task 3: ToolDepthSlider component

**Files:**
- Create: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ToolDepthSlider.swift`

- [ ] **Step 1: Write and scp**

```bash
cat > /tmp/ToolDepthSlider.swift << 'SWIFT'
//
//  ToolDepthSlider.swift
//  BeagleCockpit
//
import SwiftUI
import BeagleCore

struct ToolDepthSlider: View {
    let labelMin: String
    let labelMax: String
    @Binding var value: Double   // 1.0 – 5.0, step 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: $value, in: 1...5, step: 1)
                .tint(BeagleTheme.truthObserved)
            HStack {
                Text(labelMin)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Text(labelMax)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }
}
SWIFT
scp /tmp/ToolDepthSlider.swift mac:~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ToolDepthSlider.swift
```

- [ ] **Step 2: Verify build**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'"
```

Expected: `BUILD SUCCEEDED`.

---

## Task 4: AgentPlanCard sheet

**Files:**
- Create: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/AgentPlanCard.swift`

- [ ] **Step 1: Write and scp**

```bash
cat > /tmp/AgentPlanCard.swift << 'SWIFT'
//
//  AgentPlanCard.swift
//  BeagleCockpit
//
//  Sheet that appears when ConversationStore.pendingPlan != nil.
//  User can adjust per-step depth sliders before confirming execution.
//
import SwiftUI
import BeagleCore

struct AgentPlanCard: View {
    @Bindable var conversation: ConversationStore
    @Environment(\.dismiss) private var dismiss

    // Local depth state: step.id → depth value (1–5)
    @State private var depths: [String: Double] = [:]
    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = conversation.pendingPlan {
                    planContent(plan)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        conversation.pendingPlan = nil
                        dismiss()
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .onAppear { initDepths() }
    }

    private func planContent(_ plan: AgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.title)
                .font(BeagleFont.subheadline.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
                .padding(.bottom, BeagleSpacing.sm)

            ScrollView {
                VStack(spacing: BeagleSpacing.sm) {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { idx, step in
                        stepRow(step: step, index: idx)
                    }
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.bottom, BeagleSpacing.lg)
            }

            Divider()
                .padding(.horizontal, BeagleSpacing.lg)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                Task { await confirmAndDismiss() }
            } label: {
                HStack {
                    if isConfirming {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Run Plan")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BeagleTheme.truthObserved, in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isConfirming)
            .padding(BeagleSpacing.lg)
        }
    }

    private func stepRow(step: PlanStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.xs) {
                Text("\(index + 1)")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .frame(width: 18)
                Text(step.label)
                    .font(BeagleFont.body.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
            }
            ToolDepthSlider(
                labelMin: step.depthLabelMin,
                labelMax: step.depthLabelMax,
                value: Binding(
                    get: { depths[step.id] ?? Double(step.depthDefault) },
                    set: { depths[step.id] = $0 }
                )
            )
            .padding(.leading, 26)
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(BeagleTheme.surface1.opacity(0.5))
        )
    }

    private func initDepths() {
        guard let plan = conversation.pendingPlan else { return }
        depths = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.id, Double($0.depthDefault)) })
    }

    private func confirmAndDismiss() async {
        isConfirming = true
        let intDepths = depths.mapValues { Int($0) }
        await conversation.confirmPlan(depths: intDepths)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        isConfirming = false
        dismiss()
    }
}
SWIFT
scp /tmp/AgentPlanCard.swift mac:~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/AgentPlanCard.swift
```

- [ ] **Step 2: Wire the sheet in ConversationView**

The sheet triggers when `conversation.pendingPlan != nil`. Find the existing `.sheet(isPresented: $showHarvestSheet)` block in `ConversationView.swift` and add a second sheet after it:

```bash
cat > /tmp/wire_plan_sheet.py << 'PY'
path = "/Users/demetriosagourakis/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ConversationView.swift"
with open(path) as f:
    src = f.read()

old = '        .sheet(isPresented: $showHarvestSheet) {\n            HarvestSheetView(conversation: conversation)\n                .presentationDetents([.medium])\n        }'
new = '''        .sheet(isPresented: $showHarvestSheet) {
            HarvestSheetView(conversation: conversation)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(
            get: { conversation.pendingPlan != nil },
            set: { if !$0 { conversation.pendingPlan = nil } }
        )) {
            AgentPlanCard(conversation: conversation)
                .presentationDetents([.medium, .large])
        }'''
src = src.replace(old, new, 1)
with open(path, "w") as f:
    f.write(src)
print("done")
PY
scp /tmp/wire_plan_sheet.py mac:/tmp/wire_plan_sheet.py
ssh mac "python3 /tmp/wire_plan_sheet.py"
```

- [ ] **Step 3: Verify build**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCockpit/AgentPlanCard.swift BeagleSuite/Sources/BeagleCockpit/ToolDepthSlider.swift BeagleSuite/Sources/BeagleCockpit/ConversationView.swift && git commit -m 'feat(A): AgentPlanCard sheet with tool depth sliders'"
```

---

## Task 5: EvidenceTag component

**Files:**
- Create: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/EvidenceTag.swift`

- [ ] **Step 1: Write and scp**

```bash
cat > /tmp/EvidenceTag.swift << 'SWIFT'
//
//  EvidenceTag.swift
//  BeagleCockpit
//
import SwiftUI
import BeagleCore

struct EvidenceTag: View {
    let item: EvidenceItem

    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 11))
            Text(item.label)
                .font(BeagleFont.caption2.font)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }

    private var icon: String {
        switch item.confidence {
        case .cited:       return "✓"
        case .inferred:    return "◯"
        case .unverified:  return "?"
        case .conflict:    return "⚠"
        }
    }

    private var color: Color {
        switch item.confidence {
        case .cited:       return BeagleTheme.stateReady
        case .inferred:    return BeagleTheme.truthObserved
        case .unverified:  return BeagleTheme.textTertiary
        case .conflict:    return BeagleTheme.stateError
        }
    }
}
SWIFT
scp /tmp/EvidenceTag.swift mac:~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/EvidenceTag.swift
```

---

## Task 6: VerificationStrip

**Files:**
- Create: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/VerificationStrip.swift`

- [ ] **Step 1: Write and scp**

```bash
cat > /tmp/VerificationStrip.swift << 'SWIFT'
//
//  VerificationStrip.swift
//  BeagleCockpit
//
//  iOS: inline collapsible below the assistant bubble (activated by long-press context menu).
//  macOS: shown in the sidebar panel when the user taps an assistant bubble.
//
import SwiftUI
import BeagleCore

struct VerificationStrip: View {
    let result: VerificationResult
    let profileHue: Color
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header — always visible
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: BeagleSpacing.xs) {
                    Circle()
                        .fill(conflictColor)
                        .frame(width: 7, height: 7)
                    Text(summaryLabel)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .padding(.horizontal, BeagleSpacing.sm)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, BeagleSpacing.sm)
                expandedContent
                    .padding(.horizontal, BeagleSpacing.sm)
                    .padding(.bottom, BeagleSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.sm)
                .fill(BeagleTheme.surface1.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.sm)
                        .strokeBorder(BeagleTheme.hairline, lineWidth: 0.5)
                )
        )
        // Auto-expand when there is a temporal conflict
        .onAppear {
            if result.temporalConflict != nil { isExpanded = true }
        }
    }

    private var summaryLabel: String {
        let n = result.sources.count
        let src = n == 1 ? "1 source" : "\(n) sources"
        if result.temporalConflict != nil {
            return "\(src) · ⚠ Memory conflict"
        }
        let unverified = result.sources.filter { $0.confidence == .unverified }.count
        if unverified > 0 {
            return "\(src) · \(unverified) unverified"
        }
        return src
    }

    private var conflictColor: Color {
        if result.temporalConflict != nil { return BeagleTheme.stateError }
        if result.sources.contains(where: { $0.confidence == .unverified }) { return BeagleTheme.textTertiary }
        return BeagleTheme.stateReady
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            // Sources
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                FlowLayout(spacing: 4) {
                    ForEach(result.sources) { item in
                        EvidenceTag(item: item)
                    }
                }
            }

            // Temporal conflict
            if let conflict = result.temporalConflict {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("Memory conflict · \(conflict.daysAgo)d ago", systemImage: "exclamationmark.triangle.fill")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.stateError)
                    Text(conflict.summary)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, BeagleSpacing.xs)
    }
}

// Minimal flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.height }.max() ?? 0 }.reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.height }.max() ?? 0
            for item in row {
                item.view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += item.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private struct Item { let view: LayoutSubview; let width: CGFloat; let height: CGFloat }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Item]] {
        let maxWidth = proposal.width ?? 300
        var rows: [[Item]] = [[]]
        var rowWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(Item(view: view, width: size.width, height: size.height))
            rowWidth += size.width + spacing
        }
        return rows
    }
}
SWIFT
scp /tmp/VerificationStrip.swift mac:~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/VerificationStrip.swift
```

- [ ] **Step 2: Add long-press context menu to assistant bubbles in ChatBubbleView**

Find the `assistantBubble` computed var in `ChatBubbleView.swift`. Add a context menu with "Check sources":

```bash
cat > /tmp/patch_bubble.py << 'PY'
path = "/Users/demetriosagourakis/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ChatBubbleView.swift"
with open(path) as f:
    src = f.read()

# Add new property for verification callback
old = "    var profileHue: Color = BeagleTheme.truthObserved"
new = """    var profileHue: Color = BeagleTheme.truthObserved
    var verificationResult: VerificationResult? = nil
    var onCheckSources: (() -> Void)? = nil"""
src = src.replace(old, new, 1)

# Add context menu + verification strip below assistant bubble
old = "    private var assistantBubble: some View {"
insertion_target = "        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))\n    }\n\n    private var userBubble"
replacement = """        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
        .contextMenu {
            if message.role == .assistant {
                Button {
                    onCheckSources?()
                } label: {
                    Label("Check sources", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        if let vr = verificationResult, message.role == .assistant {
            VerificationStrip(result: vr, profileHue: profileHue)
                .padding(.top, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var userBubble"""
src = src.replace(insertion_target, replacement, 1)
with open(path, "w") as f:
    f.write(src)
print("done")
PY
scp /tmp/patch_bubble.py mac:/tmp/patch_bubble.py
ssh mac "python3 /tmp/patch_bubble.py"
```

- [ ] **Step 3: Wire fetchVerification in ConversationView**

In `ConversationView.swift`, inside the `ForEach(conversation.messages)` loop, pass the callback and result to `ChatBubbleView`:

```bash
cat > /tmp/wire_verification.py << 'PY'
path = "/Users/demetriosagourakis/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ConversationView.swift"
with open(path) as f:
    src = f.read()

old = "                            ChatBubbleView(\n                                message: message,"
new = """                            ChatBubbleView(
                                message: message,
                                verificationResult: conversation.verificationResults[message.id],
                                onCheckSources: message.role == .assistant ? {
                                    Task {
                                        await conversation.fetchVerification(
                                            for: message.id,
                                            profileId: conversation.discussionProfile.rawValue
                                        )
                                    }
                                } : nil,"""
src = src.replace(old, new, 1)
with open(path, "w") as f:
    f.write(src)
print("done")
PY
scp /tmp/wire_verification.py mac:/tmp/wire_verification.py
ssh mac "python3 /tmp/wire_verification.py"
```

- [ ] **Step 4: Verify build**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCockpit/EvidenceTag.swift BeagleSuite/Sources/BeagleCockpit/VerificationStrip.swift BeagleSuite/Sources/BeagleCockpit/ChatBubbleView.swift BeagleSuite/Sources/BeagleCockpit/ConversationView.swift && git commit -m 'feat(B): VerificationStrip per-bubble with temporal memory + EvidenceTag'"
```

---

## Task 7: AutonomyDial

**Files:**
- Create: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/AutonomyDial.swift`

- [ ] **Step 1: Write and scp**

```bash
cat > /tmp/AutonomyDial.swift << 'SWIFT'
//
//  AutonomyDial.swift
//  BeagleCockpit
//
//  Three-position control: Ask / Plan / Auto, stored per profile in UserDefaults.
//
import SwiftUI
import BeagleCore

struct AutonomyDial: View {
    @Bindable var conversation: ConversationStore

    private var current: AutonomyMode {
        conversation.autonomyMode(for: conversation.discussionProfile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(AutonomyMode.allCases, id: \.rawValue) { mode in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            conversation.setAutonomyMode(mode, for: conversation.discussionProfile)
                        }
                    } label: {
                        Text(mode.label)
                            .font(BeagleFont.caption.font)
                            .fontWeight(current == mode ? .semibold : .regular)
                            .foregroundStyle(current == mode ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                current == mode
                                    ? BeagleTheme.truthObserved.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: BeagleRadius.xs)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(BeagleTheme.surface1.opacity(0.5), in: RoundedRectangle(cornerRadius: BeagleRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.sm)
                    .strokeBorder(BeagleTheme.hairline, lineWidth: 0.5)
            )

            Text(current.subtitle)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .padding(.horizontal, 4)
        }
    }
}
SWIFT
scp /tmp/AutonomyDial.swift mac:~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/AutonomyDial.swift
```

- [ ] **Step 2: Embed dial in the profile strip**

When a profile button is selected, expand the active pill to show the dial below it. Patch `ConversationView.swift` to add `@State private var showAutonomyDial = false` and toggle it on profile pill tap:

```bash
cat > /tmp/patch_autonomy.py << 'PY'
path = "/Users/demetriosagourakis/Developer/beable/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ConversationView.swift"
with open(path) as f:
    src = f.read()

# Add state var
old = "    @State private var showHarvestSheet = false"
new = "    @State private var showHarvestSheet = false\n    @State private var showAutonomyDial = false"
src = src.replace(old, new, 1)

# Add autonomy dial below the active profile pill (inside discussionProfileButton, after the capsule)
old = "        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isSelected)"
new = """        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isSelected)
        .simultaneousGesture(TapGesture().onEnded {
            if isSelected {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    showAutonomyDial.toggle()
                }
            } else {
                showAutonomyDial = false
            }
        })"""
src = src.replace(old, new, 1)

# Add dial below the profile strip ScrollView
old = "        .padding(.bottom, BeagleSpacing.xs)\n        }\n    }"
new = """        .padding(.bottom, BeagleSpacing.xs)
        }
        if showAutonomyDial {
            AutonomyDial(conversation: conversation)
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.bottom, BeagleSpacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }"""
src = src.replace(old, new, 1)

with open(path, "w") as f:
    f.write(src)
print("done")
PY
scp /tmp/patch_autonomy.py mac:/tmp/patch_autonomy.py
ssh mac "python3 /tmp/patch_autonomy.py"
```

**Note:** If the `discussionProfileStrip` block structure differs from the patch target, inspect manually with `grep -n` and adjust line numbers. The patch targets the closing `}` of the ScrollView `.padding` chain.

- [ ] **Step 3: Verify build**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCockpit/AutonomyDial.swift BeagleSuite/Sources/BeagleCockpit/ConversationView.swift && git commit -m 'feat(C): AutonomyDial per-profile Ask/Plan/Auto, embedded in profile strip'"
```

---

## Task 8: macOS sidebar for VerificationStrip

**Files:**
- Modify: `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ConversationView.swift`

On macOS, `ConversationView` should show a trailing sidebar column that displays the `VerificationStrip` for the currently selected assistant bubble. On iOS this task is a no-op (context menu already handles it in Task 6).

- [ ] **Step 1: Add selectedMessageId state and tap gesture on macOS**

```bash
cat > /tmp/patch_mac_sidebar.py << 'PY'
path = "/Users/demetriosagourakis/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ConversationView.swift"
with open(path) as f:
    src = f.read()

# Add state
old = "    @State private var showAutonomyDial = false"
new = "    @State private var showAutonomyDial = false\n    @State private var selectedVerificationId: UUID? = nil"
src = src.replace(old, new, 1)

# Wrap the existing VStack body in HStack with conditional macOS sidebar
old = "        VStack(spacing: 0) {\n            discussionProfileStrip"
new = """        HStack(spacing: 0) {
            VStack(spacing: 0) {
            discussionProfileStrip"""
# Also close the inner VStack and add sidebar before outer HStack closes
old2 = "            .sheet(isPresented: Binding("
new2 = """            } // inner VStack
            #if os(macOS)
            if let msgId = selectedVerificationId,
               let vr = conversation.verificationResults[msgId] {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                        Text("Evidence")
                            .font(BeagleFont.subheadline.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        VerificationStrip(result: vr, profileHue: BeagleTheme.profileHue(for: conversation.discussionProfile))
                    }
                    .padding(BeagleSpacing.md)
                }
                .frame(width: 280)
                .background(BeagleTheme.surface1.opacity(0.35))
            }
            #endif
        } // outer HStack
            .sheet(isPresented: Binding("""
src = src.replace(old, new, 1)
src = src.replace(old2, new2, 1)

with open(path, "w") as f:
    f.write(src)
print("done")
PY
scp /tmp/patch_mac_sidebar.py mac:/tmp/patch_mac_sidebar.py
ssh mac "python3 /tmp/patch_mac_sidebar.py"
```

**Note:** This patch is structural — if the build fails due to brace mismatch, open `ConversationView.swift` on the Mac, find the top-level body `VStack`, wrap it in `HStack`, and add the `#if os(macOS)` sidebar block at the trailing edge before closing the `HStack`. The logic is: `HStack { VStack { ...all existing content... } #if os(macOS) sidebar #endif }`.

- [ ] **Step 2: Update ChatBubbleView call to set selectedVerificationId on macOS tap**

```bash
cat > /tmp/patch_mac_tap.py << 'PY'
path = "/Users/demetriosagourakis/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/ConversationView.swift"
with open(path) as f:
    src = f.read()

old = "                                onCheckSources: message.role == .assistant ? {\n                                    Task {\n                                        await conversation.fetchVerification(\n                                            for: message.id,\n                                            profileId: conversation.discussionProfile.rawValue\n                                        )\n                                    }\n                                } : nil,"
new = """                                onCheckSources: message.role == .assistant ? {
                                    Task {
                                        await conversation.fetchVerification(
                                            for: message.id,
                                            profileId: conversation.discussionProfile.rawValue
                                        )
                                    }
                                    #if os(macOS)
                                    selectedVerificationId = message.id
                                    #endif
                                } : nil,"""
src = src.replace(old, new, 1)
with open(path, "w") as f:
    f.write(src)
print("done")
PY
scp /tmp/patch_mac_tap.py mac:/tmp/patch_mac_tap.py
ssh mac "python3 /tmp/patch_mac_tap.py"
```

- [ ] **Step 3: Verify build — both platforms**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'"
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|BUILD'"
```

Expected: both `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCockpit/ConversationView.swift && git commit -m 'feat(B): macOS sidebar for VerificationStrip — persistent evidence panel'"
```

---

## Task 9: Push and push

- [ ] **Step 1: Push branch to origin**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git push origin feat/ios-100pct-real"
```

- [ ] **Step 2: Confirm all 5 commits landed**

```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git log --oneline -8"
```

Expected top 5 lines (newest first):
```
xxxxxxx feat(B): macOS sidebar for VerificationStrip
xxxxxxx feat(C): AutonomyDial per-profile Ask/Plan/Auto
xxxxxxx feat(B): VerificationStrip per-bubble with temporal memory + EvidenceTag
xxxxxxx feat(A): AgentPlanCard sheet with tool depth sliders
xxxxxxx feat(models): OrchestrationModels — AgentPlan, VerificationResult, AutonomyMode
```

---

## Self-review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| AgentPlan JSON model | Task 1 |
| PlanStep with depth fields | Task 1 |
| ConfirmedPlan/ConfirmedStep for backend | Task 1 |
| VerificationResult, EvidenceItem, TemporalConflict | Task 1 |
| AutonomyMode enum | Task 1 |
| OrchestrationEvent | Task 1 |
| ConversationStore pendingPlan | Task 2 |
| autonomyMode per profile in UserDefaults | Task 2 |
| verificationResults cache | Task 2 |
| confirmPlan posts to backend | Task 2 |
| fetchVerification with 90d/30d lookback | Task 2 |
| ToolDepthSlider 1–5 discrete | Task 3 |
| AgentPlanCard sheet with sliders | Task 4 |
| Sheet wired in ConversationView | Task 4 |
| EvidenceTag with confidence icons | Task 5 |
| VerificationStrip collapsible | Task 6 |
| Long-press context menu on bubbles | Task 6 |
| Per-bubble verification fetch | Task 6 |
| AutonomyDial Ask/Plan/Auto | Task 7 |
| Dial embedded in profile strip | Task 7 |
| macOS evidence sidebar | Task 8 |
| Auto-expand on temporal conflict | Task 6 (`.onAppear`) |
| Plan sheet `.presentationDetents([.medium, .large])` | Task 4 |

All spec requirements covered. No placeholders. Types used in later tasks (`VerificationResult`, `AgentPlan`, `AutonomyMode`, `EvidenceItem`, `ConfirmedPlan`) defined in Task 1.
