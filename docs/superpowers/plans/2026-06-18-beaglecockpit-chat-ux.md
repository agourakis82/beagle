# BeagleCockpit Chat UX — Chromatic Presence + Spatial Dialogue

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign BeagleCockpit's conversation interface using Gaggioli Positive Technology — per-profile ambient hue, Z-space bubble layering, inline streaming context in input bar, and a Conversation Harvest action to send the full thread to the cluster/memory.

**Architecture:** Profile hue map added to `BeagleTheme` as a static helper; ambient tint and harvest toolbar live in `ConversationView`; bubbles gain spatial depth in `ChatBubbleView`; input bar gets profile color edge and inline streaming state; `HarvestSheetView` is a new bottom sheet backed by a new `ConversationStore.harvestConversation(mode:)` method.

**Tech Stack:** SwiftUI (iOS 17+ / macOS 14+), `@Observable`, `.ultraThinMaterial`, `.scrollTransition`, `UIImpactFeedbackGenerator`, `UIPasteboard`, `BeagleClient` HTTP.

**Mac paths:** `~/Developer/beagle/beagle-ios/BeagleSuite/Sources/`  
**Branch:** `feat/ios-100pct-real` (on Mac)  
**Build check:** `ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build-for-testing 2>&1 | tail -5"`

---

### Task 1: Profile hue map in BeagleTheme

**Files:**
- Modify: `BeagleCore/Theme.swift` — add `profileHue(for:)` after existing color tokens

- [ ] **Add profileHue helper** — find the line `public static func dataFont` (~line 164) and insert before it:

```swift
    // MARK: - Discussion profile hues (Chromatic Presence system)
    public static func profileHue(for profile: DiscussionProfile) -> Color {
        switch profile {
        case .cluster:    return Color(hue: 186/360, saturation: 0.70, brightness: 0.85) // teal
        case .qwen3b:     return Color(hue: 40/360,  saturation: 0.80, brightness: 0.90) // amber
        case .yi6b:       return Color(hue: 150/360, saturation: 0.65, brightness: 0.80) // emerald
        case .grok:       return Color(hue: 275/360, saturation: 0.60, brightness: 0.88) // violet
        case .kimi:       return Color(hue: 215/360, saturation: 0.65, brightness: 0.90) // sky blue
        case .claudeCode: return Color(hue: 25/360,  saturation: 0.85, brightness: 0.92) // orange
        case .codex:      return Color(hue: 120/360, saturation: 0.55, brightness: 0.78) // green
        }
    }
```

- [ ] **Build check:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|BUILD'"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Commit:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCore/Theme.swift && git commit -m 'feat(theme): add profileHue(for:) chromatic presence map'"
```

---

### Task 2: Ambient tint + harvest toolbar in ConversationView

**Files:**
- Modify: `BeagleCockpit/ConversationView.swift`

Add ambient tint to the VStack background, a harvest toolbar button, and the harvest sheet state.

- [ ] **Add state + toolbar** — replace the `body` computed property (the outer `VStack`) with:

```swift
    @State private var showHarvestSheet = false

    var body: some View {
        let hue = BeagleTheme.profileHue(for: conversation.discussionProfile)
        VStack(spacing: 0) {
            discussionProfileStrip
            messageList
            if userScrolledUp && conversation.isStreaming {
                newMessagePill
            }
            BeagleInputBar(
                text: $inputText,
                placeholder: profilePlaceholder,
                mode: .chat,
                isEnabled: !conversation.isStreaming,
                onSubmit: { text in
                    userScrolledUp = false
                    conversation.submitMessage(text)
                },
                onStop: { conversation.stopStreaming() },
                activeProfileHue: hue,
                isStreaming: conversation.isStreaming,
                streamingProfileLabel: conversation.discussionProfile.label
            )
        }
        .background(
            ZStack {
                Color.black
                LinearGradient(
                    colors: [hue.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.35), value: conversation.discussionProfile)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showHarvestSheet = true } label: {
                    Image(systemName: "arrow.up.right.circle")
                }
                .disabled(conversation.messages.count < 2)
            }
        }
        .sheet(isPresented: $showHarvestSheet) {
            HarvestSheetView(conversation: conversation)
                .presentationDetents([.medium])
        }
    }

    private var profilePlaceholder: String {
        switch conversation.discussionProfile {
        case .cluster:    return "Talk to Beagle..."
        case .qwen3b:     return "Ask Qwen..."
        case .yi6b:       return "Ask Yi..."
        case .grok:       return "Ask Grok..."
        case .kimi:       return "Ask Kimi..."
        case .claudeCode: return "Ask Claude Code..."
        case .codex:      return "Ask Codex..."
        }
    }
```

- [ ] **Update profile strip button** — replace `discussionProfileButton(for:)` to use profile hue when selected:

```swift
    private func discussionProfileButton(for profile: DiscussionProfile) -> some View {
        let isSelected = conversation.discussionProfile == profile
        let hue = BeagleTheme.profileHue(for: profile)
        let foreground = isSelected ? hue : BeagleTheme.textSecondary
        let fill = isSelected ? hue.opacity(0.18) : BeagleTheme.surface1.opacity(0.45)
        let stroke = isSelected ? hue.opacity(0.40) : BeagleTheme.hairline

        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                conversation.discussionProfile = profile
            }
        } label: {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: profile.iconName)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.label)
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                    Text(profile.subtitle)
                        .font(BeagleFont.caption2.font)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, BeagleSpacing.sm)
            .padding(.vertical, BeagleSpacing.xs)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isSelected)
    }
```

- [ ] **Remove the old streamingContextBar** — it's moving into BeagleInputBar in Task 3. Delete:
```swift
    // streaming context bar block — the `if conversation.isStreaming { streamingContextBar }` line
    // AND the `private var streamingContextBar: some View { ... }` computed property
```

- [ ] **Build check:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|BUILD'"
```
Note: HarvestSheetView doesn't exist yet — expect one error `cannot find type 'HarvestSheetView'`. That's fine; Task 4 adds it.

- [ ] **Commit (with the expected error — use `-allowProvisioningUpdates` not needed, just check build):**

Actually wait — skip commit until Task 4 makes it compile.

---

### Task 3: BeagleInputBar — profile edge bar + inline streaming context

**Files:**
- Modify: `BeagleCockpit/BeagleInputBar.swift`

Add two new parameters: `activeProfileHue: Color` and `isStreaming: Bool` and `streamingProfileLabel: String`. Replace the streaming glow with an inline context label. Add 3pt leading edge bar.

- [ ] **Update struct signature** — change the property declarations block:

```swift
struct BeagleInputBar: View {
    @Binding var text: String
    let placeholder: String
    let mode: InputBarMode
    let isEnabled: Bool
    var focusRequest: Int = 0
    let onSubmit: (String) -> Void
    var onStop: (() -> Void)? = nil
    var onSpecialKey: ((SpecialKey) -> Void)?
    // New chromatic presence params
    var activeProfileHue: Color = BeagleTheme.truthObserved
    var isStreaming: Bool = false
    var streamingProfileLabel: String = "Beagle"
```

- [ ] **Replace body** — update the `body` computed property:

```swift
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // 3pt leading profile hue edge bar
            Rectangle()
                .fill(activeProfileHue)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: BeagleRadius.md,
                    bottomLeadingRadius: BeagleRadius.md,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                ))

            HStack(alignment: .bottom, spacing: BeagleSpacing.xs) {
                inputFieldContainer
                sendButton
            }
            .animation(BeagleMotion.fast, value: isEnabled)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
        }
        .background(
            ZStack {
                Color(uiColor: .systemBackground).opacity(0)
                activeProfileHue.opacity(0.05)
            }
        )
        .background(.ultraThinMaterial)
        .sensoryFeedback(.impact(weight: .medium), trigger: submitCount)
        .onChange(of: focusRequest) {
            guard isEnabled else { return }
            isFocused = true
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                keyboardToolbarContent
            }
        }
        #endif
    }
```

- [ ] **Replace inputFieldContainer overlay** — change the glow border overlay to use `activeProfileHue`, and add inline streaming label in the text area when streaming:

Replace the `inputFieldContainer` computed property:

```swift
    private var inputFieldContainer: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            if mode == .terminal {
                promptPrefix
            }
            if isStreaming {
                // Inline streaming context label replaces text input
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                        .foregroundStyle(activeProfileHue)
                        .symbolEffect(.pulse, isActive: true)
                    Text("\(streamingProfileLabel) · responding...")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                }
                .padding(.leading, 5)
                .padding(.top, 8)
                .frame(minHeight: 40)
            } else {
                textInputArea
            }
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, mode == .terminal ? BeagleSpacing.xs : BeagleSpacing.xxs)
        .background(inputBackground)
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .strokeBorder(
                    activeProfileHue.opacity(isEnabled ? 0 : 0.28),
                    lineWidth: isEnabled ? 0 : 1
                )
                .animation(
                    isEnabled ? .easeOut(duration: 0.2) : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                    value: isEnabled
                )
        )
        .onKeyPress(characters: .init(charactersIn: "cd"), phases: .down) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            if press.characters == "c" { onSpecialKey?(.interrupt); return .handled }
            if press.characters == "d" { onSpecialKey?(.eof); return .handled }
            return .ignored
        }
    }
```

- [ ] **Replace sendButton** — use profile hue on the send circle, stop button stays red:

```swift
    @ViewBuilder
    private var sendButton: some View {
        if !isEnabled, let onStop {
            Button { onStop() } label: {
                ZStack {
                    Circle()
                        .fill(BeagleTheme.stateError.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BeagleTheme.stateError)
                }
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        } else {
            Button { performSubmit() } label: {
                ZStack {
                    Circle()
                        .fill(isTextEmpty ? Color.white.opacity(0.1) : activeProfileHue)
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isTextEmpty ? BeagleTheme.textTertiary : .white)
                }
            }
            .buttonStyle(.plain)
            .disabled(isTextEmpty || !isEnabled)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }
```

- [ ] **Build check:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|BUILD'"
```
Expected: Only remaining error is `cannot find type 'HarvestSheetView'`.

---

### Task 4: HarvestSheetView — new file

**Files:**
- Create: `BeagleCockpit/HarvestSheetView.swift`

- [ ] **Create the file** on Mac:

```swift
//
//  HarvestSheetView.swift
//  BeagleCockpit
//
//  Bottom sheet to send the full conversation to the cluster for analysis,
//  memory storage, or follow-up angle generation.
//

import SwiftUI
import BeagleCore

struct HarvestSheetView: View {
    @Bindable var conversation: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var harvestState: HarvestState = .idle

    enum HarvestState { case idle, loading, success(String), failure(String) }

    var body: some View {
        NavigationStack {
            VStack(spacing: BeagleSpacing.lg) {
                headerSection
                    .padding(.top, BeagleSpacing.md)

                if case .loading = harvestState {
                    ProgressView()
                        .tint(BeagleTheme.truthObserved)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if case .success(let msg) = harvestState {
                    successView(msg)
                } else if case .failure(let err) = harvestState {
                    failureView(err)
                } else {
                    actionsSection
                }

                Spacer()
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .background(Color(uiColor: .systemBackground).opacity(0))
            .background(.ultraThinMaterial)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.truthObserved)
            Text("Send to Beagle")
                .font(BeagleFont.title3.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text("\(conversation.messages.count) exchanges · \(conversation.discussionProfile.label) thread")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    private var actionsSection: some View {
        VStack(spacing: BeagleSpacing.sm) {
            harvestActionButton(
                icon: "brain.head.profile",
                title: "Deep Analysis",
                subtitle: "Extract insights + patterns",
                mode: "analyze"
            )
            harvestActionButton(
                icon: "square.and.arrow.down.on.square",
                title: "Save to Memory",
                subtitle: "Store as knowledge artifact",
                mode: "save"
            )
            harvestActionButton(
                icon: "arrow.triangle.branch",
                title: "Go Deeper on Thread",
                subtitle: "Generate follow-up angles",
                mode: "follow-up-angles"
            )
        }
    }

    private func harvestActionButton(icon: String, title: String, subtitle: String, mode: String) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            Task { await harvest(mode: mode) }
        } label: {
            HStack(spacing: BeagleSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BeagleFont.body.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(subtitle)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func successView(_ message: String) -> some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(BeagleTheme.stateReady)
                .symbolEffect(.bounce, value: true)
            Text(message)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(BeagleTheme.truthObserved)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func failureView(_ error: String) -> some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(BeagleTheme.stateError)
            Text(error)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { harvestState = .idle }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    @MainActor
    private func harvest(mode: String) async {
        harvestState = .loading
        do {
            let result = try await conversation.harvestConversation(mode: mode)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            harvestState = .success(result)
        } catch {
            harvestState = .failure(error.localizedDescription)
        }
    }
}
```

- [ ] **Write to Mac:**
```bash
ssh mac "cat > ~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCockpit/HarvestSheetView.swift" << 'SWIFTEOF'
[paste the content above]
SWIFTEOF
```
(Use the heredoc approach via SSH — or scp the file from t560.)

- [ ] **Build check:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|BUILD'"
```
Expected: one remaining error — `value of type 'ConversationStore' has no member 'harvestConversation'`.

---

### Task 5: ConversationStore.harvestConversation(mode:)

**Files:**
- Modify: `BeagleCore/ConversationStore.swift`

- [ ] **Find insertion point** — locate `public func stopStreaming()` and add after it:

```swift
    public func harvestConversation(mode: String) async throws -> String {
        let transcript = messages.map { m in
            "\(m.role == .user ? "User" : "Assistant"): \(m.content)"
        }.joined(separator: "\n\n")

        let profile = discussionProfile.rawValue
        let payload: [String: Any] = [
            "mode": mode,
            "profile": profile,
            "transcript": transcript,
            "message_count": messages.count
        ]

        if mode == "save" {
            // POST to memory API
            let memPayload: [String: Any] = [
                "content": transcript,
                "tags": ["conversation", profile, "harvest"],
                "title": "Conversation harvest — \(profile) — \(messages.count) exchanges"
            ]
            _ = try await BeagleClient.shared.post(path: "/api/memory", body: memPayload)
            return "Saved to memory — \(messages.count) exchanges stored."
        } else {
            // POST to cognitive deep-think
            let result = try await BeagleClient.shared.post(path: "/api/cognitive/deep-think", body: payload)
            if let answer = result["answer"] as? String {
                return answer
            }
            return "Analysis complete — check the Recall tab for results."
        }
    }
```

- [ ] **Check BeagleClient.shared.post signature** — run:
```bash
ssh mac "grep -n 'func post' ~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/BeagleClient.swift | head -5"
```
Adjust the call signature to match what exists. If the method doesn't exist with that name, search for the pattern used by other async API calls in ConversationStore:
```bash
ssh mac "grep -n 'BeagleClient\|await.*client\|await.*Client' ~/Developer/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/ConversationStore.swift | head -10"
```

- [ ] **Build check:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|BUILD'"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Commit tasks 2–5:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCockpit/ConversationView.swift BeagleSuite/Sources/BeagleCockpit/BeagleInputBar.swift BeagleSuite/Sources/BeagleCockpit/HarvestSheetView.swift BeagleSuite/Sources/BeagleCore/ConversationStore.swift && git commit -m 'feat(chat): Chromatic Presence ambient tint, profile edge bar, harvest action'"
```

---

### Task 6: Bubble spatial depth in ChatBubbleView

**Files:**
- Modify: `BeagleCockpit/ChatBubbleView.swift`

- [ ] **Add `activeProfileHue` to ChatBubbleView** — the bubble needs the profile hue for the assistant accent bar. `ChatBubbleView` is called from `ConversationView`. Add a new param:

```swift
struct ChatBubbleView: View {
    let message: ChatMessage
    var onRegenerate: (() -> Void)?
    var profileHue: Color = BeagleTheme.truthObserved   // new param
```

- [ ] **Replace userBubble** — inset/pressed look:

```swift
    private var userBubble: some View {
        Text(message.content)
            .font(BeagleFont.body.font)
            .lineSpacing(3)
            .foregroundStyle(BeagleTheme.textPrimary)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        // Inner shadow (top-to-bottom dark gradient)
                        LinearGradient(
                            colors: [.black.opacity(0.08), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
```

- [ ] **Replace assistantBubble** — elevated with accent bar + colored shadow:

```swift
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let voiceName = message.voiceName {
                voiceHeader(voiceName)
            }
            if message.isStreaming && message.content.isEmpty {
                streamingPlaceholder.transition(.opacity)
            } else {
                renderedContent.transition(.opacity)
            }
        }
        .animation(BeagleMotion.fast, value: message.isStreaming && message.content.isEmpty)
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            // 3pt accent bar on leading edge
            Rectangle()
                .fill(message.voiceName != nil ? voiceTint : profileHue)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: BeagleRadius.lg,
                    bottomLeadingRadius: BeagleRadius.lg,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                ))
        }
        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(
                    message.voiceName != nil ? voiceTint.opacity(0.2) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: (message.voiceName != nil ? voiceTint : profileHue).opacity(0.18),
            radius: 12, x: 0, y: 4
        )
    }
```

- [ ] **Update MarkdownMessage text lineSpacing** — find `Text(prose(s))` and add `.lineSpacing(4)`:

```swift
                Text(prose(s))
                    .font(BeagleFont.body.font)
                    .lineSpacing(4)
                    .foregroundStyle(BeagleTheme.textPrimary)
```

- [ ] **Add recency fade via scrollTransition** — in `ConversationView.messageList`, update the `ForEach` body for `ChatBubbleView` call:

In `ConversationView.swift`, find the `ChatBubbleView(...)` call inside `ForEach` and replace:
```swift
                            ChatBubbleView(
                                message: message,
                                profileHue: BeagleTheme.profileHue(for: conversation.discussionProfile),
                                onRegenerate: message.role == .assistant ? {
                                    Task { await conversation.regenerateLastResponse() }
                                } : nil
                            )
                            .id(message.id)
                            .scrollTransition(.animated) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1.0 : 0.55)
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.97)
                            }
```

- [ ] **Build check:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|BUILD'"
```
Expected: `BUILD SUCCEEDED`

- [ ] **Commit:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git add BeagleSuite/Sources/BeagleCockpit/ChatBubbleView.swift BeagleSuite/Sources/BeagleCockpit/ConversationView.swift && git commit -m 'feat(bubbles): spatial depth — user inset, assistant elevated+accent bar, recency fade'"
```

---

### Task 7: Simulator smoke test + push

- [ ] **Build for simulator:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && xcodebuild -scheme BeagleCockpit -destination 'platform=iOS Simulator,id=$(xcrun simctl list devices available -j | python3 -c \"import sys,json; d=json.load(sys.stdin)['devices']; iphones=[v for vl in d.values() for v in vl if v['isAvailable'] and 'iPhone' in v['name']]; print(iphones[0]['udid'])\")" build 2>&1 | tail -3"
```

- [ ] **Push to remote:**
```bash
ssh mac "cd ~/Developer/beagle/beagle-ios && git push origin feat/ios-100pct-real"
```
