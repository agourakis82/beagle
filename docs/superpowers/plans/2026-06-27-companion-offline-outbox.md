# Companion Offline Outbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The companion never goes mute when Wi-Fi/5G drops (replies via the on-device MLX model), and nothing said offline is lost — each offline turn is queued in a durable local outbox and synced to the memory spine when connectivity returns.

**Architecture:** Online personal turns already ingest server-side (the cockpit calls `ingestPersonalTurn` during the chat). So the outbox only carries **offline** turns. iOS gains a `NetworkMonitor` (NWPathMonitor) → routing prefers cloud when online, on-device when offline (and falls back to local if a cloud send dies mid-flight). Offline turns are enqueued to a SwiftData `PendingIngest` outbox; a flush worker drains it to a new cockpit endpoint `POST /api/mobile/v1/ingest` (which reuses `ingestPersonalTurn`) on reconnect/foreground. beagle-core's `content_hash` dedup makes flush retries harmless.

**Tech Stack:** Swift / SwiftData / `Network.NWPathMonitor` / XCTest (`BeagleCoreTests`); Node ESM + `node:test` (cockpit endpoint). Reuses `memory-ingest.mjs`'s `ingestPersonalTurn`.

**Out of scope:** sessions UI, diary, timeline, search (separate plans).

---

## File Structure

- **Modify:** `apps/project-cockpit/server/mobile-routes.mjs` — add `POST /api/mobile/v1/ingest` → `ingestPersonalTurn`.
- **Create:** `apps/project-cockpit/server/memory-ingest-endpoint.test.mjs` — endpoint unit test (handler-level).
- **Modify:** `beagle-ios/.../BeagleCore/Persistence.swift` — add `@Model PendingIngest`; register in the schema.
- **Create:** `beagle-ios/.../BeagleCore/OutboxStore.swift` — enqueue/pending/delete over a `ModelContext`.
- **Create:** `beagle-ios/.../BeagleCore/NetworkMonitor.swift` — `@Observable` `isOnline` from NWPathMonitor.
- **Modify:** `beagle-ios/.../BeagleCore/BeagleClient.swift` — `ingestTurn(...)` POST helper.
- **Modify:** `beagle-ios/.../BeagleCore/ConversationStore.swift` — network-aware routing + enqueue offline + flush worker.
- **Create:** `beagle-ios/Tests/BeagleCoreTests/OutboxStoreTests.swift` — outbox queue logic (in-memory container).

---

### Task 1: Cockpit ingest endpoint (reuses `ingestPersonalTurn`)

**Files:**
- Modify: `apps/project-cockpit/server/mobile-routes.mjs`
- Create: `apps/project-cockpit/server/memory-ingest-endpoint.test.mjs`

- [ ] **Step 1: Write the failing test** — a pure handler we can unit-test without Express:

Create `apps/project-cockpit/server/memory-ingest-endpoint.test.mjs`:

```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { handleIngestRequest } from "./memory-ingest.mjs";

test("handleIngestRequest calls ingestPersonalTurn with the body fields", async () => {
  let got = null;
  const fakeIngest = async (turn, deps) => { got = { turn, deps }; };
  const body = {
    session_id: "s9", userText: "guarda X", assistantText: "ok",
    clientTime: "2026-06-27T10:00:00Z", timezone: "UTC",
  };
  const res = await handleIngestRequest(body, { ingestFn: fakeIngest, tokenFn: async () => ({ token: "t" }) });
  assert.equal(res.status, 202);
  assert.equal(got.turn.sessionId, "s9");
  assert.equal(got.turn.userText, "guarda X");
  assert.equal(got.turn.assistantText, "ok");
  assert.equal(typeof got.deps.tokenFn, "function");
});

test("handleIngestRequest 400 when both sides empty", async () => {
  const res = await handleIngestRequest({ userText: "", assistantText: "" },
    { ingestFn: async () => {}, tokenFn: async () => ({ token: "t" }) });
  assert.equal(res.status, 400);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/project-cockpit && node --test server/memory-ingest-endpoint.test.mjs`
Expected: FAIL — `handleIngestRequest is not a function`.

- [ ] **Step 3: Implement `handleIngestRequest` in `memory-ingest.mjs`**

Append to `apps/project-cockpit/server/memory-ingest.mjs`:

```javascript
/**
 * Handler core for POST /api/mobile/v1/ingest — flushes one queued offline turn into the spine.
 * Returns {status, body}. ingestPersonalTurn is fire-and-forget; we ack 202 immediately.
 */
export async function handleIngestRequest(body = {}, { ingestFn = ingestPersonalTurn, tokenFn } = {}) {
  const userText = clean(body.userText || body.user_text);
  const assistantText = clean(body.assistantText || body.assistant_text);
  if (!userText || !assistantText) return { status: 400, body: { error: "userText and assistantText required" } };
  // detached — the outbox already has it durably; we just kick the ingest.
  ingestFn({
    sessionId: clean(body.session_id || body.sessionId),
    userText, assistantText,
    clientTime: clean(body.clientTime || body.client_time),
    timezone: clean(body.timezone),
  }, { tokenFn }).catch(() => {});
  return { status: 202, body: { status: "accepted" } };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd apps/project-cockpit && node --test server/memory-ingest-endpoint.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire the Express route in `mobile-routes.mjs`**

Add `handleIngestRequest` to the existing `import { ingestPersonalTurn } from "./memory-ingest.mjs";` line:
```javascript
import { ingestPersonalTurn, handleIngestRequest } from "./memory-ingest.mjs";
```
Then register the route alongside the other mobile routes (find where `/api/mobile/v1/chat` is registered with `router.post`/`app.post` and add next to it):
```javascript
  router.post("/api/mobile/v1/ingest", async (req, res) => {
    const out = await handleIngestRequest(req.body || {}, { tokenFn: fetchOperatorToken });
    res.status(out.status).json(out.body);
  });
```
(Use the same `router`/`app` object and auth middleware the `/chat` route uses — check the file; mirror it exactly.)

- [ ] **Step 6: Verify + commit**

Run: `cd apps/project-cockpit && node --check server/mobile-routes.mjs && node --test server/*.test.mjs`
Expected: clean; all PASS.
```bash
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/mobile-routes.mjs apps/project-cockpit/server/memory-ingest-endpoint.test.mjs
git commit -m "feat(companion): /api/mobile/v1/ingest endpoint for offline outbox flush"
```

---

### Task 2: `PendingIngest` SwiftData model

**Files:**
- Modify: `beagle-ios/BeagleSuite/Sources/BeagleCore/Persistence.swift` (the `@Model` block + `makeContainer()` schema at ~line 165)

- [ ] **Step 1: Add the model**

In `Persistence.swift`, after the existing `PersistedMessage` model, add:

```swift
/// A personal-space turn captured offline, awaiting sync to the memory spine.
@Model
public final class PendingIngest {
    @Attribute(.unique) public var id: UUID
    public var sessionId: String
    public var userText: String
    public var assistantText: String
    public var clientTime: String
    public var timezone: String
    public var createdAt: Date

    public init(id: UUID = UUID(), sessionId: String, userText: String, assistantText: String,
                clientTime: String, timezone: String, createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.userText = userText
        self.assistantText = assistantText
        self.clientTime = clientTime
        self.timezone = timezone
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Register in the schema**

In `makeContainer()` (~line 165), add `PendingIngest.self` to the `Schema([...])` array:
```swift
let schema = Schema([
    PersistedMessage.self,
    PendingIngest.self,
    // ...existing entries...
])
```

- [ ] **Step 3: Commit**

```bash
git add beagle-ios/BeagleSuite/Sources/BeagleCore/Persistence.swift
git commit -m "feat(companion): PendingIngest SwiftData model for the offline outbox"
```

---

### Task 3: `OutboxStore` (enqueue / pending / delete)

**Files:**
- Create: `beagle-ios/BeagleSuite/Sources/BeagleCore/OutboxStore.swift`
- Create: `beagle-ios/BeagleSuite/Tests/BeagleCoreTests/OutboxStoreTests.swift`

- [ ] **Step 1: Write the failing test (in-memory SwiftData container)**

Create `beagle-ios/BeagleSuite/Tests/BeagleCoreTests/OutboxStoreTests.swift`:

```swift
import XCTest
import SwiftData
@testable import BeagleCore

final class OutboxStoreTests: XCTestCase {
    private func memoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PendingIngest.self, configurations: config)
        return ModelContext(container)
    }

    func testEnqueueThenPendingReturnsIt() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "guarda X", assistantText: "ok", clientTime: "", timezone: "UTC")
        let pending = store.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.userText, "guarda X")
    }

    func testDeleteRemovesFromPending() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "a", assistantText: "b", clientTime: "", timezone: "")
        let item = store.pending().first!
        store.delete(item)
        XCTAssertEqual(store.pending().count, 0)
    }

    func testEnqueueSkipsEmptySides() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "", assistantText: "b", clientTime: "", timezone: "")
        XCTAssertEqual(store.pending().count, 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run on the Mac: `xcodebuild test -project BeagleSuite.xcodeproj -scheme BeagleCockpit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BeagleCoreTests/OutboxStoreTests`
Expected: FAIL — `cannot find 'OutboxStore' in scope`.

- [ ] **Step 3: Implement**

Create `beagle-ios/BeagleSuite/Sources/BeagleCore/OutboxStore.swift`:

```swift
import Foundation
import SwiftData

/// Durable queue of offline personal turns awaiting sync to the memory spine.
@MainActor
public final class OutboxStore {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func enqueue(sessionId: String, userText: String, assistantText: String, clientTime: String, timezone: String) {
        let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !a.isEmpty else { return }
        context.insert(PendingIngest(sessionId: sessionId, userText: u, assistantText: a,
                                     clientTime: clientTime, timezone: timezone))
        try? context.save()
    }

    public func pending() -> [PendingIngest] {
        let descriptor = FetchDescriptor<PendingIngest>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func delete(_ item: PendingIngest) {
        context.delete(item)
        try? context.save()
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run the same `xcodebuild test` command. Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add beagle-ios/BeagleSuite/Sources/BeagleCore/OutboxStore.swift beagle-ios/BeagleSuite/Tests/BeagleCoreTests/OutboxStoreTests.swift
git commit -m "feat(companion): OutboxStore — durable offline ingest queue"
```

---

### Task 4: `NetworkMonitor` (online/offline signal)

**Files:**
- Create: `beagle-ios/BeagleSuite/Sources/BeagleCore/NetworkMonitor.swift`

- [ ] **Step 1: Implement (NWPathMonitor → @Observable isOnline)**

Create `beagle-ios/BeagleSuite/Sources/BeagleCore/NetworkMonitor.swift`:

```swift
import Foundation
import Network
import Observation

/// Observable connectivity signal. `isOnline` flips with the real network path.
@Observable
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()
    public private(set) var isOnline: Bool = true
    /// Set when connectivity transitions offline→online, so the app can trigger an outbox flush.
    public var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.sounio.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            Task { @MainActor in
                let was = self.isOnline
                self.isOnline = online
                if online && !was { self.onReconnect?() }
            }
        }
        monitor.start(queue: queue)
    }
}
```

- [ ] **Step 2: Verify it compiles (build the target)**

Run on the Mac: `xcodebuild build -project BeagleSuite.xcodeproj -scheme BeagleCockpit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add beagle-ios/BeagleSuite/Sources/BeagleCore/NetworkMonitor.swift
git commit -m "feat(companion): NetworkMonitor — observable online/offline signal"
```

---

### Task 5: `BeagleClient.ingestTurn` (POST the flush)

**Files:**
- Modify: `beagle-ios/BeagleSuite/Sources/BeagleCore/BeagleClient.swift`

- [ ] **Step 1: Add the method** (mirror the existing `post<T>` request building at ~line 137 — same `baseURLs`, headers, encoder):

```swift
public struct IngestTurnRequest: Encodable, Sendable {
    public let session_id: String
    public let userText: String
    public let assistantText: String
    public let clientTime: String
    public let timezone: String
}

/// Flush one queued offline turn to the cockpit. Returns true on 2xx (so the caller can
/// delete it from the outbox). Best-effort: false on any failure, never throws.
public func ingestTurn(_ body: IngestTurnRequest) async -> Bool {
    for base in baseURLs {
        guard let url = URL(string: "/api/mobile/v1/ingest", relativeTo: base) else { continue }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request)   // mirror what post<T> uses for consumer/token headers
        request.httpBody = try? encoder.encode(body)
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) { return true }
        } catch { continue }
    }
    return false
}
```
Note: `applyAuthHeaders` is illustrative — use the exact header-application the existing `post<T>`/`chat` methods use in this file (consumer id + bearer token); copy that snippet inline if there is no shared helper.

- [ ] **Step 2: Verify it compiles**

Run on the Mac: `xcodebuild build -project BeagleSuite.xcodeproj -scheme BeagleCockpit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add beagle-ios/BeagleSuite/Sources/BeagleCore/BeagleClient.swift
git commit -m "feat(companion): BeagleClient.ingestTurn — flush a turn to the cockpit"
```

---

### Task 6: Network-aware routing + enqueue + flush worker

**Files:**
- Modify: `beagle-ios/BeagleSuite/Sources/BeagleCore/ConversationStore.swift`

- [ ] **Step 1: Network-aware routing.** In the companion send path (~line 164, the `if llm.isReady` branch), make the personal companion prefer cloud when online and fall back to local when offline:

```swift
        // Companion: cloud (rich, grounded, server-side memory ingest) when online;
        // on-device MLX when offline — and enqueue the offline turn for later sync.
        if NetworkMonitor.shared.isOnline {
            await sendMessageCloud(text)
        } else if llm.isReady {
            await sendMessageLocal(text)
            enqueueOffline(userText: text)   // offline → spine misses it; outbox carries it
        } else {
            await sendMessageCloud(text)     // last resort (will surface a connection error)
        }
```

- [ ] **Step 2: `enqueueOffline` helper.** Add to `ConversationStore` (uses `modelContext`; the assistant reply is the last assistant message's content):

```swift
    private func enqueueOffline(userText: String) {
        guard let ctx = modelContext else { return }
        let assistant = messages.last(where: { $0.role == .assistant })?.content ?? ""
        OutboxStore(context: ctx).enqueue(
            sessionId: persistenceConversationId,
            userText: userText,
            assistantText: assistant,
            clientTime: ISO8601DateFormatter().string(from: Date()),
            timezone: TimeZone.current.identifier
        )
    }
```

- [ ] **Step 3: Flush worker.** Add a method that drains the outbox, and wire it to `NetworkMonitor.onReconnect` (set it once, e.g. in `init` or a `start()` the app calls):

```swift
    public func flushOutbox() async {
        guard let ctx = modelContext else { return }
        let store = OutboxStore(context: ctx)
        for item in store.pending() {
            let ok = await client.ingestTurn(.init(
                session_id: item.sessionId, userText: item.userText, assistantText: item.assistantText,
                clientTime: item.clientTime, timezone: item.timezone))
            if ok { store.delete(item) }   // idempotent server-side, so a failed retry is safe
        }
    }
```
And in `init` (after `self.client = client`), wire the reconnect trigger:
```swift
        NetworkMonitor.shared.onReconnect = { [weak self] in
            Task { await self?.flushOutbox() }
        }
```

- [ ] **Step 4: Build + the suite**

Run on the Mac: `xcodebuild test -project BeagleSuite.xcodeproj -scheme BeagleCockpit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BeagleCoreTests/OutboxStoreTests`
Expected: BUILD SUCCEEDED + 3 tests PASS (the routing change must not break the build).

- [ ] **Step 5: Commit**

```bash
git add beagle-ios/BeagleSuite/Sources/BeagleCore/ConversationStore.swift
git commit -m "feat(companion): network-aware routing + offline enqueue + outbox flush on reconnect"
```

---

## Self-Review

**Spec coverage:** network-aware routing online→cloud/offline→local (Task 6) ✓ · graceful behavior when offline (Task 6) ✓ · durability via SwiftData (Tasks 2-3, already true for messages) ✓ · ingestion outbox enqueue (Tasks 3,6) + flush on reconnect (Tasks 5,6) ✓ · idempotent flush via server `content_hash` (Task 1 reuse) ✓ · distill defers to sync — the flush hits `ingestPersonalTurn` which runs the sovereign distill server-side (Task 1) ✓ · sovereignty: on-device is most-sovereign; flush goes to the in-cluster cockpit, distill on the Spark (Tasks 1,6) ✓.

**Placeholder scan:** the two `applyAuthHeaders`/`router` notes explicitly say "mirror the existing pattern in this file" — they are pointers to established code, not invented APIs, per the existing-codebase rule; all other steps carry complete code. No TBD/TODO.

**Type consistency:** `PendingIngest` fields (`sessionId/userText/assistantText/clientTime/timezone/createdAt`) match across Tasks 2,3,6; `IngestTurnRequest` (`session_id/userText/assistantText/clientTime/timezone`) matches the cockpit endpoint body keys (Task 1 reads `userText||user_text`, `session_id||sessionId`) and the flush call (Task 6). `OutboxStore.enqueue/pending/delete` names consistent across Tasks 3,6.
