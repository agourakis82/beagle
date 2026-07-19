# iOS Synthesis Screen Implementation Plan

> **Execution note:** This runs on the Mac (`Sounio-Language-MacBook`, M5 Max) over `ssh mac`, repo `~/dev/beagle/beagle-ios`, branch `integration/ios-physiome-merge`. It is DRIVEN BY THE CONTROLLER (me) via ssh — not subagent-driven — because the Mac build/install loop is ssh-bound. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A deliberate `SynthesisView` sheet, opened from the ChatScreen drawer footer, that streams the `/api/mobile/v1/synthesize` 5-block markdown — never touching the intimate chat.

**Architecture:** New standalone files (`SynthesisSSEParser`, `SynthesisClient`, `SynthesisView`) + a `.synthesize` case in the existing `ChatSheet` enum + a "Sintetizar" entry in `ConversationDrawer`'s footer. The client reuses `BeagleClient`'s base URLs + `cockpitMobileToken`; the view renders markdown with a small local block renderer (the chat's renderer is fileprivate — not extracted, to keep the chat file untouched).

**Tech Stack:** Swift 6.4, SwiftUI, `URLSession.bytes(for:)` SSE, xcodegen (project.yml → pbxproj), `xcodebuild` + `devicectl`.

## Global Constraints (THE HARD WALL — every task inherits, from the spec)

- **Separate surface:** synthesis is its own view, presented as a sheet. NEVER inline in the conversation, never a chat message.
- **Deliberate, never automatic:** opens only on an explicit "Sintetizar" tap. Nothing auto-triggers it.
- **Result never enters the chat:** the streamed synthesis lives ONLY in the sheet's local `@State`. It is NEVER appended to `ConversationStore`/the message list and NEVER persisted (no SwiftData write, no capture). Dismiss = discard.
- **Do NOT modify the chat renderer, ConversationStore, MessageBubble, or any chat behavior.** Additive only, except the two integration points (the `ChatSheet` enum + the `ConversationDrawer` footer) which gain ONE new case / ONE new entry.
- Server contract: `POST {base}/api/mobile/v1/synthesize`, header `x-cockpit-token: <BeagleClient.cockpitMobileToken>`, body `{"topic": <string?>}` (omit/empty topic → recent mode). Response is SSE `text/event-stream`: `data: {"token":"…"}` deltas, terminated by `data: {"done":true, ...}` (may carry `insufficient:true` / `error`).
- Copy is PT-BR, his register.

---

### Task 0: xcodegen prerequisite (unblocks adding new files)

The pbxproj uses NO file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup` count = 0), so new `.swift` files are only picked up when the pbxproj is regenerated from `project.yml` (a directory glob) via xcodegen. xcodegen isn't installed and there's no Homebrew. Build it from source with the installed Swift.

- [ ] **Step 1: build + install xcodegen from source (no brew)**

```bash
ssh mac 'set -e
  cd ~/dev
  [ -d XcodeGen ] || git clone --depth 1 https://github.com/yonaskolb/XcodeGen.git
  cd XcodeGen
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  swift build -c release 2>&1 | tail -3
  mkdir -p ~/bin && cp -f .build/release/xcodegen ~/bin/xcodegen
  ~/bin/xcodegen --version'
```
Expected: prints an xcodegen version. (`~/bin/xcodegen` is now the tool; use its full path in later steps since `~/bin` may not be on the non-login PATH.)

- [ ] **Step 2: confirm regenerating the project is a no-op on the clean tree**

```bash
ssh mac 'cd ~/dev/beagle/beagle-ios && ~/bin/xcodegen generate 2>&1 | tail -2 && git status --short BeagleSuite.xcodeproj | head'
```
Expected: xcodegen reports success; the committed pbxproj is regenerated (a diff here is fine — the point is xcodegen runs). Do NOT commit the regenerated pbxproj yet.

---

### Task 1: `SynthesisSSEParser` (pure — the one unit-tested piece)

There is no iOS test target in `project.yml`; test this pure parser with a standalone `swift` script (Swift is installed).

**Files:**
- Create: `beagle-ios/BeagleSuite/Sources/BeagleCockpit/Synthesis/SynthesisSSEParser.swift`
- Test (standalone, not in the app target): `/tmp/synthparse_test.swift` on the Mac

**Interfaces:**
- Produces: `enum SSEChunk { case token(String); case done(insufficient: Bool, error: String?) }` and `struct SynthesisSSEParser { static func parse(line: String) -> SSEChunk? }` — one SSE `data:` line → a chunk (nil for non-data/`[DONE]`/blank lines).

- [ ] **Step 1: write the failing standalone test** (`/tmp/synthparse_test.swift`) — paste the SAME parse implementation body under test plus asserts, since a standalone script can't import the app module:

```swift
import Foundation
enum SSEChunk: Equatable { case token(String); case done(insufficient: Bool, error: String?) }
struct SynthesisSSEParser {
  static func parse(line: String) -> SSEChunk? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("data:") else { return nil }
    let json = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
    guard !json.isEmpty, json != "[DONE]", let d = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
    if obj["done"] as? Bool == true {
      return .done(insufficient: obj["insufficient"] as? Bool ?? false, error: obj["error"] as? String)
    }
    if let tok = obj["token"] as? String { return .token(tok) }
    return nil
  }
}
// asserts
func eq(_ a: SSEChunk?, _ b: SSEChunk?, _ m: String) { assert(a == b, m); print("ok: \(m)") }
eq(SynthesisSSEParser.parse(line: "data: {\"token\":\"## Elevator\"}"), .token("## Elevator"), "token parsed")
eq(SynthesisSSEParser.parse(line: "data: {\"done\":true,\"insufficient\":true}"), .done(insufficient: true, error: nil), "done+insufficient")
eq(SynthesisSSEParser.parse(line: "data: {\"done\":true}"), .done(insufficient: false, error: nil), "done plain")
eq(SynthesisSSEParser.parse(line: ": comment"), nil, "non-data → nil")
eq(SynthesisSSEParser.parse(line: "data: [DONE]"), nil, "[DONE] → nil")
eq(SynthesisSSEParser.parse(line: ""), nil, "blank → nil")
print("ALL PASS")
```

- [ ] **Step 2: run it — RED first (before the app file exists it still runs standalone; this proves the logic, then you copy it into the app file)**

```bash
ssh mac 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift /tmp/synthparse_test.swift'
```
Expected: `ALL PASS` (the test embeds the impl; this validates the parse logic before it goes in the app).

- [ ] **Step 3: create the app file** with the SAME `SSEChunk` + `SynthesisSSEParser` (public), plus a file header comment noting it is standalone (no chat imports).

- [ ] **Step 4: regenerate + compile-check the app target**

```bash
ssh mac 'cd ~/dev/beagle/beagle-ios && ~/bin/xcodegen generate >/dev/null && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleCockpit -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bc build 2>&1 | tail -3'
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: commit** (on the Mac)

```bash
ssh mac 'cd ~/dev/beagle && git add beagle-ios/BeagleSuite/Sources/BeagleCockpit/Synthesis/SynthesisSSEParser.swift beagle-ios/BeagleSuite.xcodeproj && git commit -m "ios(synthesis): SSE chunk parser"'
```

---

### Task 2: `SynthesisClient` (streaming)

**Files:**
- Create: `beagle-ios/BeagleSuite/Sources/BeagleCockpit/Synthesis/SynthesisClient.swift`

**Interfaces:**
- Consumes: `SynthesisSSEParser` (Task 1); `BeagleClient.cockpitMobileToken` + the base URL from `BeagleCore/CockpitClient.swift` (read that file for the exact base-URL accessor — it holds `baseURLs: [URL]`; use the first/primary the same way `fetchMobile` does).
- Produces: `struct SynthesisClient { func stream(topic: String) -> AsyncThrowingStream<SSEChunk, Error> }` — POSTs `/api/mobile/v1/synthesize` and yields chunks.

- [ ] **Step 1: implement** — `URLRequest` to `<base>/api/mobile/v1/synthesize`, method POST, `x-cockpit-token: BeagleClient.cockpitMobileToken`, `content-type: application/json`, body `["topic": topic]` (JSON; omit key if topic is empty). Consume `URLSession.shared.bytes(for:)`; `for try await line in bytes.lines { if let chunk = SynthesisSSEParser.parse(line: line) { continuation.yield(chunk); if case .done = chunk { break } } }`; finish the stream. Mirror the base-URL + token usage from `CockpitClient.swift` exactly (read it first). No persistence, no chat imports.

- [ ] **Step 2: compile-check**

```bash
ssh mac 'cd ~/dev/beagle/beagle-ios && ~/bin/xcodegen generate >/dev/null && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleCockpit -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bc build 2>&1 | tail -3'
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: commit** — `ios(synthesis): streaming client for /api/mobile/v1/synthesize`

---

### Task 3: `SynthesisView` (the screen)

**Files:**
- Create: `beagle-ios/BeagleSuite/Sources/BeagleCockpit/Synthesis/SynthesisView.swift`

**Interfaces:**
- Consumes: `SynthesisClient` (Task 2).
- Produces: `struct SynthesisView: View` (no external inputs; self-contained sheet content).

- [ ] **Step 1: implement** the view:
  - `@State topic = ""`, `@State markdown = ""`, `@State phase: Phase = .idle` (`enum Phase { case idle, streaming, done, insufficient, error(String) }`), `@State task: Task<Void, Never>?`.
  - Layout: title "Síntese" + dismiss; a `TextField("sobre o quê? (vazio = últimos dias)", text: $topic)`; a "Sintetizar" button (disabled while `.streaming`, label "sintetizando…" then); a scrolling result area rendering `markdown`.
  - Rendering: a SMALL LOCAL renderer (do NOT import the chat's fileprivate one, do NOT touch chat files) — split `markdown` on lines; render `## X` lines as a bold/title `Text`, `- x` as a bullet row, blank lines as spacing, other lines as body `Text`. (The 5 blocks are only `##` headings + paragraphs + bullets.)
  - Action: on tap, `phase = .streaming; markdown = ""`; `task = Task { for try await chunk in SynthesisClient().stream(topic: topic) { switch chunk { case .token(let t): markdown += t; case .done(let insuf, let err): phase = err != nil ? .error(err!) : (insuf ? .insufficient : .done) } } }` wrapped in do/catch → `.error`.
  - "nova síntese" resets to `.idle`. A copy button (`UIPasteboard`) on `.done`.
  - THE WALL: this view writes `markdown` only to its own `@State`. It has NO reference to `ConversationStore`, no SwiftData `modelContext` write, no capture call.

- [ ] **Step 2: compile-check** (same xcodebuild command as Task 2 Step 2). Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: commit** — `ios(synthesis): SynthesisView screen (streamed 5-block markdown, local render)`

---

### Task 4: wire it in — `.synthesize` sheet case + drawer "Sintetizar" entry

**Files:**
- Modify: `beagle-ios/BeagleSuite/Sources/BeagleCockpit/Companion/ChatScreen.swift` (the `ChatSheet` enum ~line 477; the `.sheet(item:)` switch ~line 147; the `ConversationDrawer` view ~line 492 footer)

**Interfaces:**
- Consumes: `SynthesisView` (Task 3).

- [ ] **Step 1: add the enum case** to `ChatSheet` (after `.goDeep`):
```swift
    case synthesize
```
and in its `id` switch: `case .synthesize: return "synthesize"`.

- [ ] **Step 2: present it** in the `.sheet(item: $activeSheet)` switch (~line 147), a new arm:
```swift
            case .synthesize:
                SynthesisView()
```

- [ ] **Step 3: add the "Sintetizar" footer entry** in `ConversationDrawer` (~line 492), mirroring the EXISTING Data/Capture/Dream footer entries (read them first for the exact row style + how they signal the parent — the drawer signals via a closure/binding the parent passes; add a matching `onSynthesize` closure that the parent wires to `activeSheet = .synthesize`, then dismisses the drawer). Match the existing footer row visual exactly (icon + label), label "Sintetizar", a fitting SF Symbol (e.g. `sparkles` or `wand.and.stars`).

- [ ] **Step 4: regenerate + build for device (signed)** — full device build so the wiring is real:
```bash
ssh mac 'cd ~/dev/beagle/beagle-ios && ~/bin/xcodegen generate >/dev/null
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  security unlock-keychain -p <LOGIN_PW> ~/Library/Keychains/login.keychain-db 2>/dev/null || true
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <LOGIN_PW> ~/Library/Keychains/login.keychain-db 2>/dev/null || true
  xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleCockpit -configuration Debug -destination "id=<DEVICE_UDID>" -derivedDataPath /tmp/bcdev -allowProvisioningUpdates build 2>&1 | tail -4'
```
Expected: `BUILD SUCCEEDED`. (`<LOGIN_PW>` and `<DEVICE_UDID>` from the user at run time — the login password on the NEW Mac must be confirmed; the old `1982` may not apply.)

- [ ] **Step 5: commit** — `ios(synthesis): open SynthesisView from the drawer footer (separate surface)`

---

### Task 5: install on device + live-verify + WALL-CHECK

- [ ] **Step 1: install**
```bash
ssh mac 'xcrun devicectl device install app --device <DEVICE_UDID> /tmp/bcdev/Build/Products/Debug-iphoneos/BeagleCockpit.app 2>&1 | tail -3'
```

- [ ] **Step 2: live-verify (user, on the phone)** — open the app → open the drawer (☰) → tap **Sintetizar** → enter "redes semânticas em depressão" → confirm the 5-block markdown STREAMS in, grounded in his words. Enter a nonsense topic → confirm the honest "Ainda não tenho o bastante…" message. Leave a topic empty → confirm a recent-days synthesis.

- [ ] **Step 3: WALL-CHECK (user, on the phone)** — after viewing a synthesis, dismiss the sheet and return to the chat → confirm the synthesis text does NOT appear as a chat message and is NOT in the history. Confirm synthesis never appeared unless he tapped Sintetizar.

- [ ] **Step 4: push the branch**
```bash
ssh mac 'cd ~/dev/beagle && git push origin integration/ios-physiome-merge 2>&1 | tail -2'
```

---

## Self-Review

**Spec coverage:** placement (drawer footer → `.synthesize` sheet) → Task 4; SynthesisView + states → Task 3; SSE client + reuse base URL/token → Task 2; SSE parsing unit test → Task 1; markdown render → Task 3 (local renderer, deviating from spec's "reuse chat renderer" because that renderer is `fileprivate` in MessageBubble and extracting it would touch chat code — a wall risk; a small local renderer for `##`/paragraph/bullet is safer and YAGNI-appropriate; FLAGGED for user awareness); wall (result never enters chat/persists) → Task 3 Step 1 + Task 5 Step 3; error/insufficient → Task 3; build+device live-verify → Tasks 4-5; xcodegen prerequisite (machine reality) → Task 0. No gaps.

**Placeholder scan:** `<LOGIN_PW>`, `<DEVICE_UDID>` are runtime secrets the user supplies (not logic placeholders). The drawer-entry wiring (Task 4 Step 3) references reading the existing footer rows for the exact closure mechanism rather than inventing it — this is "follow the established pattern in THIS file", concrete by reference, because the drawer's parent-signal convention must match its siblings exactly.

**Type consistency:** `SSEChunk` (Task 1) is consumed by `SynthesisClient.stream` (Task 2) and switched in `SynthesisView` (Task 3). `SynthesisView()` (Task 3) is presented in Task 4. `BeagleClient.cockpitMobileToken` matches the confirmed symbol in CockpitClient.swift.

**Deviation flagged:** local markdown renderer instead of reusing the chat's fileprivate one (wall-safety over DRY). Confirm this is acceptable, or Task 3 becomes an extraction task (behavior-preserving move of `MarkdownBlock` to a shared file, verifying the chat still builds + renders identically).
