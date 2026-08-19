# Scriptorium Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Phase 1 of Scriptorium — a native SwiftUI (macOS + iOS) editorial
writing app with a document editor, an AI assistant pane wired to the
existing gpu-chat backend, on-device clinical-base citation search, citation
insertion into the document, and basic Markdown export.

**Architecture:** A new, standalone Xcode/SwiftUI multiplatform project (not
a lane inside BeagleSuite). A thin Swift networking layer talks to
gpu-chat's existing Fastify API (conversations, SSE streaming, templates,
models) over the tailnet. A local `FileDocument`-based document model holds
the manuscript + citation registry. Clinical-base search is fully on-device
against a bundled SQLite database, using a Swift port of the exact matching
algorithm already proven in `bula_consulta.py` / the Companion app's
`BulaStore` — not a dependency on `BeagleCore` (which would pull in the
full MLX/WhisperKit on-device-LLM stack for one unrelated feature).

**Tech Stack:** Swift 6, SwiftUI (`DocumentGroup`/`FileDocument`), `URLSession`
async streaming, SQLite3 C API (no external SQLite wrapper — matches the
existing project's `sqlite3` stdlib/embedded-driver approach), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-19-scriptorium-design.md`

## Global Constraints

- New standalone Xcode project — do NOT add targets to `beagle-ios/BeagleSuite`'s
  `.xcodeproj` or touch its `project.pbxproj`.
- macOS + iOS multiplatform, single SwiftUI codebase (per spec).
- Single-operator use — no auth, no multi-user sync (per spec).
- gpu-chat's SSE wire format is fixed and MUST be matched exactly by the
  Swift client: `data: <JSON-encoded-string-token>\n\n` per token, an
  optional `event: error\ndata: <JSON-encoded-string-message>\n\n` frame on
  failure, and a final literal `data: [DONE]\n\n` (not JSON-encoded) that
  always terminates the stream. Verified against
  `apps/gpu-chat/server/src/routes/chat.ts` in this plan's authoring session.
- Documents are local-first (on-device `FileDocument`); only conversations
  persist server-side, via the existing gpu-chat API (per spec).
- Clinical-base search must work fully offline — no network call in that
  path (per spec).
- **Build/test verification requires macOS + Xcode.** This plan is authored
  from a Linux session with no Xcode access. Every task's `xcodebuild`/
  `swift test` commands must be run for real when this plan is executed
  from a session with Mac access — do not mark a task complete based on
  code review alone.

## Reference: gpu-chat API contracts (verified against the live source)

```
GET  /api/models                          -> ModelInfo[]                  ModelInfo { id: string }
POST /api/conversations                   body { title: string; model: string }
                                           -> Conversation
GET  /api/conversations                   -> Conversation[]
PATCH /api/conversations/:id              body { model: string }
                                           -> Conversation | 404 { error }
GET  /api/conversations/:id/messages      -> Message[]
POST /api/conversations/:id/messages      body { content: string; attachments?: AttachmentInput[] }
                                           -> text/event-stream:
                                              data: "<token>"\n\n              (repeated, JSON-encoded string)
                                              [event: error\ndata: "<message>"\n\n]  (optional, on failure)
                                              data: [DONE]\n\n                 (literal, always last)

Conversation  { id: number; title: string; model: string; created_at: string }
Message       { id: number; conversation_id: number; role: 'user'|'assistant'|'system';
                 content: string; model: string | null; truncated: number; created_at: string }
AttachmentInput { filename: string; content: string; mime_type: string }
```

## Reference: clinical-base matching algorithm (ported from `apps/project-cockpit/server/bula_consulta.py`)

```
STOPWORDS = ["para","dose","doses","posologia","quanto","quantas","de","do","da",
             "com","sem","em","no","na","o","a","um","uma","paciente","adulto",
             "renal","hepatico","endovenoso","oral","profilaxia","tratamento"]

normalize(text): lowercase, NFD-decompose, strip combining marks (accents),
                 keep only [a-z0-9 ], collapse whitespace, trim.

termsOf(question): normalize(question).split(" ").filter(word.length >= 4 && !STOPWORDS.contains(word))

lookup(question):
  for term in termsOf(question):
    row = SELECT id, nome_pt, generico, citacao FROM farmaco
          WHERE lower(generico) LIKE '<term>%' OR lower(nome_pt) LIKE '<term>%'
          ORDER BY length(generico) ASC LIMIT 1
    if row is null: continue
    if !normalize(row.generico).hasPrefix(term.prefix(4)): continue   // strict match guard
    sections = SELECT titulo, texto FROM secao WHERE farmaco_id = row.id ORDER BY id LIMIT 4
    if sections.isEmpty: continue
    return { nomePT: row.nome_pt, generico: row.generico, citacao: row.citacao,
             texto: sections.map { "\(titulo)\n\(texto)" }.joined(separator: "\n\n") }
  return nil
```

Schema (produced by `tools/base-clinica/build_bula2.py` + `build_pcdt.py`):
`farmaco(id, nome_pt, generico, citacao)`, `secao(farmaco_id, titulo, texto)`.

---

### Task 1: Xcode project scaffold

**Files:**
- Create: `Scriptorium/Scriptorium.xcodeproj` (via `xcodegen` or Xcode's "New
  Multiplatform App" template — either is fine; the deliverable is a
  buildable multiplatform SwiftUI app target named `Scriptorium`)
- Create: `Scriptorium/Scriptorium/ScriptoriumApp.swift`
- Create: `Scriptorium/Scriptorium/ContentView.swift`
- Create: `Scriptorium/ScriptoriumTests/ScriptoriumTests.swift`

**Interfaces:**
- Produces: a buildable `Scriptorium` app target (macOS + iOS) and a
  `ScriptoriumTests` unit test target that later tasks add test files to.

- [ ] **Step 1: Create the project**

Use Xcode's "File > New > Project > Multiplatform > App", or `xcodegen`
with a `project.yml` targeting macOS 15+ and iOS 18+ (align to whatever the
Mac's installed Xcode/SDK supports — do not block on matching BeagleSuite's
iOS 26 floor, since Scriptorium is a separate, standalone project). Product
name `Scriptorium`, org identifier matching the developer account already
used for BeagleSuite (check `beagle-ios/BeagleSuite/project.yml` or the
existing `.xcodeproj`'s bundle identifier prefix for the convention to
match).

`Scriptorium/Scriptorium/ScriptoriumApp.swift`:
```swift
import SwiftUI

@main
struct ScriptoriumApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`Scriptorium/Scriptorium/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Scriptorium")
            .padding()
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 2: Write the failing test**

`Scriptorium/ScriptoriumTests/ScriptoriumTests.swift`:
```swift
import XCTest
@testable import Scriptorium

final class ScriptoriumTests: XCTestCase {
    func testAppBoots() {
        XCTAssertTrue(true, "placeholder — proves the test target links against the app target")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' 2>&1 | tail -40`
Expected: FAIL — target/scheme not yet configured, or `@testable import
Scriptorium` unresolved, until the test target's target-membership and
scheme are set up correctly in Xcode.

- [ ] **Step 4: Fix target membership / scheme so it passes**

In Xcode: ensure `ScriptoriumTests` target depends on `Scriptorium`, and the
`Scriptorium` scheme has the test target enabled under Test in the scheme
editor.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
cd Scriptorium
git init
git add -A
git commit -m "[scriptorium] Scaffold multiplatform SwiftUI app + test target"
```

(If Scriptorium is added as a new top-level project rather than nested in
an existing repo, initialize its own git repo here; if it's placed inside
`beagle-ios/` as a sibling directory to `BeagleSuite/`, use `beagle`'s
existing git repo instead — confirm placement with the user before this
step if it wasn't already decided.)

---

### Task 2: API client — conversations, models, templates

**Files:**
- Create: `Scriptorium/Scriptorium/GPUChat/GPUChatModels.swift`
- Create: `Scriptorium/Scriptorium/GPUChat/GPUChatClient.swift`
- Test: `Scriptorium/ScriptoriumTests/GPUChatClientTests.swift`

**Interfaces:**
- Consumes: nothing (this is the networking foundation).
- Produces: `Conversation`, `ChatMessage` (note: named `ChatMessage`, not
  `Message`, to avoid colliding with SwiftUI/Foundation types), `ModelInfo`,
  `PromptTemplate` (Codable structs); `GPUChatClient` with `init(baseURL:
  URL, session: URLSession = .shared)`, `func fetchModels() async throws ->
  [ModelInfo]`, `func fetchConversations() async throws -> [Conversation]`,
  `func createConversation(title: String, model: String) async throws ->
  Conversation`, `func updateConversationModel(id: Int, model: String)
  async throws -> Conversation`, `func fetchMessages(conversationId: Int)
  async throws -> [ChatMessage]`. Later tasks (streaming, chat UI) depend
  on these exact names and signatures.

- [ ] **Step 1: Write the model types**

`Scriptorium/Scriptorium/GPUChat/GPUChatModels.swift`:
```swift
import Foundation

struct Conversation: Codable, Identifiable, Equatable {
    let id: Int
    var title: String
    var model: String
    let created_at: String
}

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: Int
    let conversation_id: Int
    let role: String  // "user" | "assistant" | "system"
    let content: String
    let model: String?
    let truncated: Int
    let created_at: String
}

struct ModelInfo: Codable, Identifiable, Equatable {
    var id: String
}

struct PromptTemplate: Codable, Identifiable, Equatable {
    let id: Int
    var name: String
    var system_prompt: String
    let created_at: String
}

enum GPUChatError: Error, LocalizedError {
    case httpStatus(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body): "gpu-chat request failed (\(code)): \(body)"
        case .decoding(let err): "gpu-chat response decode failed: \(err)"
        }
    }
}
```

- [ ] **Step 2: Write the failing test**

`Scriptorium/ScriptoriumTests/GPUChatClientTests.swift`:
```swift
import XCTest
@testable import Scriptorium

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class GPUChatClientTests: XCTestCase {
    func makeClient() -> GPUChatClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return GPUChatClient(baseURL: URL(string: "http://test.local")!, session: URLSession(configuration: config))
    }

    func testFetchModelsDecodesArray() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/models")
            let body = #"[{"id":"qwen2.5-7b"}]"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        let models = try await makeClient().fetchModels()
        XCTAssertEqual(models, [ModelInfo(id: "qwen2.5-7b")])
    }

    func testCreateConversationPostsBodyAndDecodesResult() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/conversations")
            let body = #"{"id":1,"title":"Test","model":"qwen2.5-7b","created_at":"2026-08-19"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
        let conv = try await makeClient().createConversation(title: "Test", model: "qwen2.5-7b")
        XCTAssertEqual(conv.id, 1)
        XCTAssertEqual(conv.title, "Test")
    }

    func testNon2xxThrowsHTTPStatusError() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, "upstream down".data(using: .utf8)!)
        }
        do {
            _ = try await makeClient().fetchModels()
            XCTFail("expected throw")
        } catch let error as GPUChatError {
            if case .httpStatus(let code, _) = error {
                XCTAssertEqual(code, 502)
            } else {
                XCTFail("wrong error case")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/GPUChatClientTests 2>&1 | tail -40`
Expected: FAIL — `GPUChatClient` does not exist yet.

- [ ] **Step 4: Write the implementation**

`Scriptorium/Scriptorium/GPUChat/GPUChatClient.swift`:
```swift
import Foundation

final class GPUChatClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent(path))
        try Self.checkStatus(response, data: data)
        return try Self.decode(T.self, from: data, decoder: decoder)
    }

    private func send<Body: Encodable, T: Decodable>(_ method: String, _ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
        return try Self.decode(T.self, from: data, decoder: decoder)
    }

    static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GPUChatError.httpStatus(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GPUChatError.decoding(error)
        }
    }

    func fetchModels() async throws -> [ModelInfo] {
        try await get("/api/models")
    }

    func fetchConversations() async throws -> [Conversation] {
        try await get("/api/conversations")
    }

    func createConversation(title: String, model: String) async throws -> Conversation {
        struct Body: Encodable { let title: String; let model: String }
        return try await send("POST", "/api/conversations", body: Body(title: title, model: model))
    }

    func updateConversationModel(id: Int, model: String) async throws -> Conversation {
        struct Body: Encodable { let model: String }
        return try await send("PATCH", "/api/conversations/\(id)", body: Body(model: model))
    }

    func fetchMessages(conversationId: Int) async throws -> [ChatMessage] {
        try await get("/api/conversations/\(conversationId)/messages")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/GPUChatClientTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Scriptorium/Scriptorium/GPUChat Scriptorium/ScriptoriumTests/GPUChatClientTests.swift
git commit -m "[scriptorium] Add gpu-chat API client (models, conversations, messages)"
```

---

### Task 3: Streaming client (SSE)

**Files:**
- Create: `Scriptorium/Scriptorium/GPUChat/GPUChatStreamClient.swift`
- Test: `Scriptorium/ScriptoriumTests/GPUChatStreamClientTests.swift`

**Interfaces:**
- Consumes: `GPUChatError` from Task 2.
- Produces: `enum StreamEvent { case token(String); case error(String); case done }`,
  `GPUChatStreamClient.streamMessage(baseURL: URL, conversationId: Int,
  content: String, attachments: [AttachmentInput], session: URLSession =
  .shared) -> AsyncThrowingStream<StreamEvent, Error>`. `AttachmentInput`
  struct also defined here (mirrors the server's shape from Task 2's
  reference table): `{ filename: String; content: String; mime_type: String }`.

- [ ] **Step 1: Write the failing test**

`Scriptorium/ScriptoriumTests/GPUChatStreamClientTests.swift`:
```swift
import XCTest
@testable import Scriptorium

final class GPUChatStreamClientTests: XCTestCase {
    func testParsesTokenErrorAndDoneFrames() async throws {
        // Simulates the exact wire format apps/gpu-chat/server/src/routes/chat.ts writes:
        // data: "<json-encoded token>"\n\n ... event: error\ndata: "<json message>"\n\n ... data: [DONE]\n\n
        let raw = """
        data: "Hel"

        data: "lo"

        event: error
        data: "LiteLLM chat completion failed: 500"

        data: [DONE]

        """
        let events = try parseSSE(raw)
        XCTAssertEqual(events, [
            .token("Hel"),
            .token("lo"),
            .error("LiteLLM chat completion failed: 500"),
            .done,
        ])
    }
}

// Test-only helper: feeds raw SSE text through the same line-parsing logic
// the real streamer uses, without requiring a live network stream. The
// production parser (GPUChatStreamClient.parse(line:currentEvent:)) is
// exercised directly here so this test fails if that logic regresses.
private func parseSSE(_ raw: String) throws -> [StreamEvent] {
    var events: [StreamEvent] = []
    var currentEvent = ""
    for line in raw.components(separatedBy: "\n") {
        if let parsed = GPUChatStreamClient.parse(line: line, currentEvent: &currentEvent) {
            events.append(parsed)
        }
    }
    return events
}

extension StreamEvent: Equatable {
    static func == (lhs: StreamEvent, rhs: StreamEvent) -> Bool {
        switch (lhs, rhs) {
        case (.token(let a), .token(let b)): a == b
        case (.error(let a), .error(let b)): a == b
        case (.done, .done): true
        default: false
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/GPUChatStreamClientTests 2>&1 | tail -40`
Expected: FAIL — `GPUChatStreamClient`/`StreamEvent` do not exist.

- [ ] **Step 3: Write the implementation**

`Scriptorium/Scriptorium/GPUChat/GPUChatStreamClient.swift`:
```swift
import Foundation

struct AttachmentInput: Encodable {
    let filename: String
    let content: String
    let mime_type: String
}

enum StreamEvent {
    case token(String)
    case error(String)
    case done
}

enum GPUChatStreamClient {
    /// Parses one SSE line against the wire format fixed by
    /// apps/gpu-chat/server/src/routes/chat.ts: `event: <name>` lines set
    /// currentEvent for the next `data:` line; `data: [DONE]` is checked as
    /// a literal BEFORE attempting JSON decode (it is never JSON-encoded);
    /// every other `data:` payload is a JSON-encoded string that must be
    /// decoded, not used raw (tokens may contain embedded newlines).
    static func parse(line: String, currentEvent: inout String) -> StreamEvent? {
        if line.hasPrefix("event: ") {
            currentEvent = String(line.dropFirst("event: ".count))
            return nil
        }
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst("data: ".count))
        defer { currentEvent = "" }
        if payload == "[DONE]" {
            return .done
        }
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return nil
        }
        return currentEvent == "error" ? .error(decoded) : .token(decoded)
    }

    static func streamMessage(
        baseURL: URL,
        conversationId: Int,
        content: String,
        attachments: [AttachmentInput] = [],
        session: URLSession = .shared
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    struct Body: Encodable { let content: String; let attachments: [AttachmentInput] }
                    var request = URLRequest(url: baseURL.appendingPathComponent("/api/conversations/\(conversationId)/messages"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(Body(content: content, attachments: attachments))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw GPUChatError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1, "")
                    }

                    var currentEvent = ""
                    for try await line in bytes.lines {
                        if let event = parse(line: line, currentEvent: &currentEvent) {
                            continuation.yield(event)
                            if case .done = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/GPUChatStreamClientTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Scriptorium/Scriptorium/GPUChat/GPUChatStreamClient.swift Scriptorium/ScriptoriumTests/GPUChatStreamClientTests.swift
git commit -m "[scriptorium] Add SSE streaming client matching gpu-chat's wire format"
```

---

### Task 4: Document model + citation registry

**Files:**
- Create: `Scriptorium/Scriptorium/Document/Citation.swift`
- Create: `Scriptorium/Scriptorium/Document/ScriptoriumDocument.swift`
- Test: `Scriptorium/ScriptoriumTests/ScriptoriumDocumentTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct Citation: Codable, Identifiable, Equatable { let id:
  UUID; let source: CitationSource; let title: String; let formattedText:
  String; let url: String? }`, `enum CitationSource: String, Codable {
  case pubmed, biorxiv, alphaxiv, clinicalBase }`, `struct
  ScriptoriumDocument: FileDocument` with `var text: AttributedString`,
  `var citations: [Citation]`, conforming to `FileDocument` with a JSON
  representation. Later tasks (citation insertion, export) depend on this
  exact `Citation` shape and `ScriptoriumDocument`'s `text`/`citations`
  properties.

- [ ] **Step 1: Write the failing test**

`Scriptorium/ScriptoriumTests/ScriptoriumDocumentTests.swift`:
```swift
import XCTest
import SwiftUI
@testable import Scriptorium

final class ScriptoriumDocumentTests: XCTestCase {
    func testRoundTripsThroughFileWrapper() throws {
        var doc = ScriptoriumDocument()
        doc.text = AttributedString("Prevalência foi de 12,4%.")
        doc.citations = [
            Citation(id: UUID(), source: .clinicalBase, title: "Enoxaparina",
                     formattedText: "Bula Enoxaparina, openFDA set_id abc123, 2024",
                     url: nil)
        ]

        let config = FileDocumentReadConfiguration.self  // type reference only, not instantiated here
        let wrapper = try doc.fileWrapper(configuration: .init(existingFile: nil))
        let readBack = try ScriptoriumDocument(configuration: .init(file: wrapper, contentType: .json))

        XCTAssertEqual(String(readBack.text.characters), "Prevalência foi de 12,4%.")
        XCTAssertEqual(readBack.citations.count, 1)
        XCTAssertEqual(readBack.citations[0].title, "Enoxaparina")
    }

    func testAddCitationDeduplicatesByFormattedText() {
        var doc = ScriptoriumDocument()
        let citation = Citation(id: UUID(), source: .pubmed, title: "Study A",
                                 formattedText: "Silva et al. 2024", url: nil)
        doc.addCitation(citation)
        doc.addCitation(citation)
        XCTAssertEqual(doc.citations.count, 1, "inserting the same reference twice must not duplicate the registry entry")
    }
}
```

Note: the exact `FileDocumentReadConfiguration`/`FileDocumentWriteConfiguration`
constructor calls above are illustrative of the round-trip intent; adjust to
whatever `FileDocument`'s real initializer signatures require once compiled
against the actual SDK (this cannot be verified without Xcode — see Global
Constraints). If direct `FileWrapper` round-tripping proves awkward to unit
test in isolation, an acceptable substitute is testing the `Codable`
encode/decode of the document's underlying storage struct directly, as long
as it proves the same thing: content and citations survive a save/load cycle.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ScriptoriumDocumentTests 2>&1 | tail -40`
Expected: FAIL — `ScriptoriumDocument`/`Citation` do not exist.

- [ ] **Step 3: Write the implementation**

`Scriptorium/Scriptorium/Document/Citation.swift`:
```swift
import Foundation

enum CitationSource: String, Codable {
    case pubmed, biorxiv, alphaxiv, clinicalBase
}

struct Citation: Codable, Identifiable, Equatable {
    let id: UUID
    let source: CitationSource
    let title: String
    let formattedText: String
    let url: String?
}
```

`Scriptorium/Scriptorium/Document/ScriptoriumDocument.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let scriptoriumDocument = UTType(exportedAs: "com.scriptorium.document")
}

struct ScriptoriumDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.scriptoriumDocument, .json] }

    var text: AttributedString
    var citations: [Citation]

    private struct Storage: Codable {
        let text: String
        let citations: [Citation]
    }

    init() {
        text = AttributedString("")
        citations = []
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let storage = try JSONDecoder().decode(Storage.self, from: data)
        text = AttributedString(storage.text)
        citations = storage.citations
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let storage = Storage(text: String(text.characters), citations: citations)
        let data = try JSONEncoder().encode(storage)
        return FileWrapper(regularFileWithContents: data)
    }

    /// Inserts a citation, deduplicating on formattedText — the same source
    /// reference cited twice must produce one registry entry, not two.
    mutating func addCitation(_ citation: Citation) {
        guard !citations.contains(where: { $0.formattedText == citation.formattedText }) else { return }
        citations.append(citation)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ScriptoriumDocumentTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`. If the `FileDocument` round-trip test needs
adjustment to compile (per the note in Step 1), make the minimal change
that preserves the same assertion intent and re-run.

- [ ] **Step 5: Commit**

```bash
git add Scriptorium/Scriptorium/Document Scriptorium/ScriptoriumTests/ScriptoriumDocumentTests.swift
git commit -m "[scriptorium] Add document model with citation registry"
```

---

### Task 5: Clinical-base search (on-device SQLite port)

**Files:**
- Create: `Scriptorium/Scriptorium/ClinicalBase/ClinicalBaseStore.swift`
- Test: `Scriptorium/ScriptoriumTests/ClinicalBaseStoreTests.swift`
- Modify: Xcode project — add `sqlite3` system library linkage (link
  `libsqlite3.tbd`, already available on macOS/iOS, no external dependency)

**Interfaces:**
- Consumes: nothing new.
- Produces: `struct ClinicalBaseResult { let nomePT: String; let generico:
  String; let citacao: String; let texto: String }`,
  `enum ClinicalBaseStore { static func open(path: String) -> Bool; static
  func lookup(dbPath: String, question: String) -> ClinicalBaseResult? }`.
  Task 9 (search UI) depends on `lookup(dbPath:question:)`'s exact
  signature and `ClinicalBaseResult`'s fields.

- [ ] **Step 1: Write the failing test**

The test builds a tiny fixture SQLite database in a temp file (not the real
30MB `bula.sqlite`) with the same schema, so the matching algorithm is
tested in isolation from the real data:

`Scriptorium/ScriptoriumTests/ClinicalBaseStoreTests.swift`:
```swift
import XCTest
import SQLite3
@testable import Scriptorium

final class ClinicalBaseStoreTests: XCTestCase {
    var dbPath: String!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        dbPath = tmp.path
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        let schema = """
        CREATE TABLE farmaco (id INTEGER PRIMARY KEY, nome_pt TEXT, generico TEXT, citacao TEXT);
        CREATE TABLE secao (farmaco_id INTEGER, id INTEGER, titulo TEXT, texto TEXT);
        INSERT INTO farmaco VALUES (1, 'enoxaparina', 'enoxaparin', 'Bula Enoxaparina, openFDA set_id abc, 2024-01-01');
        INSERT INTO secao VALUES (1, 1, 'Posologia', 'ClCr 30: 30 mg SC 1x/dia (Table 1, secao 2.3).');
        INSERT INTO farmaco VALUES (2, 'aciclovir', 'acyclovir', 'Bula Aciclovir, openFDA set_id def, 2024-01-01');
        INSERT INTO secao VALUES (2, 2, 'Posologia', 'Herpes simples: 200 mg 5x/dia.');
        """
        sqlite3_exec(db, schema, nil, nil, nil)
        sqlite3_close(db)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testLookupFindsMatchingDrugAndSections() {
        let result = ClinicalBaseStore.lookup(dbPath: dbPath, question: "dose de enoxaparina em paciente com ClCr 30")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.nomePT, "enoxaparina")
        XCTAssertTrue(result!.texto.contains("30 mg SC 1x/dia"))
    }

    func testStrictPrefixGuardRejectsAciclovirGanciclovirMismatch() {
        // "aciclovir" in nome_pt but generico is the English "acyclovir" —
        // the strict 4-char-prefix guard on `generico` must reject this,
        // matching the documented aciclovir/ganciclovir safety rule.
        let result = ClinicalBaseStore.lookup(dbPath: dbPath, question: "aciclovir para herpes")
        XCTAssertNil(result, "generico 'acyclovir' does not share a 4-char prefix with term 'acic' — must not match")
    }

    func testStopwordsAreNeverUsedAsSearchTerms() {
        // "para" and "paciente" are stopwords; "dose" is a stopword too.
        // Only "enoxaparina" (>=4 chars, not a stopword) should drive the match.
        let result = ClinicalBaseStore.lookup(dbPath: dbPath, question: "dose para o paciente de enoxaparina")
        XCTAssertEqual(result?.nomePT, "enoxaparina")
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(ClinicalBaseStore.lookup(dbPath: dbPath, question: "qual a capital da frança"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ClinicalBaseStoreTests 2>&1 | tail -40`
Expected: FAIL — `ClinicalBaseStore` does not exist.

- [ ] **Step 3: Write the implementation**

`Scriptorium/Scriptorium/ClinicalBase/ClinicalBaseStore.swift`:
```swift
import Foundation
import SQLite3

struct ClinicalBaseResult {
    let nomePT: String
    let generico: String
    let citacao: String
    let texto: String
}

/// Faithful Swift port of apps/project-cockpit/server/bula_consulta.py's
/// op_consulta — same stopword list, same normalization, same strict
/// 4-char-prefix match guard. Ported deliberately rather than depending on
/// BeagleCore's BulaStore (which would pull in the full MLX/WhisperKit
/// stack for one unrelated feature) — see Task 5's header for the tradeoff.
enum ClinicalBaseStore {
    private static let stopwords: Set<String> = [
        "para", "dose", "doses", "posologia", "quanto", "quantas", "de", "do", "da",
        "com", "sem", "em", "no", "na", "o", "a", "um", "uma", "paciente", "adulto",
        "renal", "hepatico", "endovenoso", "oral", "profilaxia", "tratamento",
    ]

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let decomposed = lowered.decomposedStringWithCanonicalMapping
        let stripped = decomposed.unicodeScalars.filter { !CharacterSet(charactersIn: "\u{0300}"..."\u{036F}").contains($0) }
        let stripedString = String(String.UnicodeScalarView(stripped))
        let alnumOnly = stripedString.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
        let collapsed = String(alnumOnly).components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed
    }

    static func terms(of question: String) -> [String] {
        normalize(question).split(separator: " ").map(String.init)
            .filter { $0.count >= 4 && !stopwords.contains($0) }
    }

    static func lookup(dbPath: String, question: String) -> ClinicalBaseResult? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        for term in terms(of: question) {
            guard let row = queryFarmaco(db: db, term: term) else { continue }
            let normalizedGenerico = normalize(row.generico)
            let prefix4 = String(term.prefix(4))
            guard normalizedGenerico.hasPrefix(prefix4) else { continue }

            let sections = querySecoes(db: db, farmacoId: row.id)
            guard !sections.isEmpty else { continue }
            let texto = sections.map { "\($0.titulo)\n\($0.texto)" }.joined(separator: "\n\n")
            return ClinicalBaseResult(nomePT: row.nomePT, generico: row.generico, citacao: row.citacao, texto: texto)
        }
        return nil
    }

    private struct FarmacoRow { let id: Int; let nomePT: String; let generico: String; let citacao: String }

    private static func queryFarmaco(db: OpaquePointer?, term: String) -> FarmacoRow? {
        let sql = """
            SELECT id, nome_pt, generico, citacao FROM farmaco
            WHERE lower(generico) LIKE ?1 OR lower(nome_pt) LIKE ?1
            ORDER BY length(generico) ASC LIMIT 1
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, term + "%", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return FarmacoRow(
            id: Int(sqlite3_column_int(stmt, 0)),
            nomePT: String(cString: sqlite3_column_text(stmt, 1)),
            generico: String(cString: sqlite3_column_text(stmt, 2)),
            citacao: String(cString: sqlite3_column_text(stmt, 3))
        )
    }

    private struct SecaoRow { let titulo: String; let texto: String }

    private static func querySecoes(db: OpaquePointer?, farmacoId: Int) -> [SecaoRow] {
        let sql = "SELECT titulo, texto FROM secao WHERE farmaco_id = ? ORDER BY id LIMIT 4"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(farmacoId))
        var rows: [SecaoRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(SecaoRow(titulo: String(cString: sqlite3_column_text(stmt, 0)), texto: String(cString: sqlite3_column_text(stmt, 1))))
        }
        return rows
    }
}
```

In Xcode: add `libsqlite3.tbd` to the `Scriptorium` target's "Link Binary
With Libraries" build phase, and add `import SQLite3` support by ensuring
the target's module map / bridging allows it (on Apple platforms `SQLite3`
is a system module available without extra configuration in Swift — if the
compiler reports it missing, add `libsqlite3` to the target's linked
libraries first).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ClinicalBaseStoreTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **` (all 4 tests, including the
aciclovir/acyclovir strict-guard case and the stopword-filtering case).

- [ ] **Step 5: Commit**

```bash
git add Scriptorium/Scriptorium/ClinicalBase Scriptorium/ScriptoriumTests/ClinicalBaseStoreTests.swift
git commit -m "[scriptorium] Add on-device clinical-base search (ported matching algorithm)"
```

---

### Task 6: Bundle the clinical-base database

**Files:**
- Modify: Xcode project — add `bula.sqlite` as a bundled resource
- Create: `Scriptorium/Scriptorium/ClinicalBase/ClinicalBaseBundle.swift`
- Test: `Scriptorium/ScriptoriumTests/ClinicalBaseBundleTests.swift`

**Interfaces:**
- Consumes: `ClinicalBaseStore.lookup(dbPath:question:)` from Task 5.
- Produces: `enum ClinicalBaseBundle { static var databasePath: String? }` —
  resolves the bundled `bula.sqlite`'s path at runtime. Task 9 (search UI)
  depends on this.

- [ ] **Step 1: Produce `bula.sqlite`**

If a current `bula.sqlite` build artifact already exists (check with the
user — it may already be sitting in the Companion app's bundle from prior
work, in which case copy it rather than rebuilding), reuse it directly.
Otherwise, rebuild it following `tools/base-clinica/README.md`'s documented
steps, run from that directory:

```bash
cd /home/devsounio/beagle/tools/base-clinica
python3 extrair_formulario.py ~/darwin-MFC/lib/data/medicamentos > formulario_dele.json
./baixar_bulk.sh
python3 casar.py
python3 build_bula2.py
python3 build_pcdt.py
```

This produces `bula.sqlite` in that directory (confirm the exact output
filename/path by reading `build_bula2.py`'s output-path argument handling
before running — do not guess it blind). This step can take a long time
(1.8 GB download) and should be run once, with the resulting file copied
into `Scriptorium/Scriptorium/Resources/bula.sqlite` for bundling.

- [ ] **Step 2: Add it as a bundled resource**

In Xcode: drag `bula.sqlite` into the `Scriptorium` target, checking "Copy
items if needed" and ensuring it's added to the `Scriptorium` target's
"Copy Bundle Resources" build phase (not compiled as source).

- [ ] **Step 3: Write the failing test**

`Scriptorium/ScriptoriumTests/ClinicalBaseBundleTests.swift`:
```swift
import XCTest
@testable import Scriptorium

final class ClinicalBaseBundleTests: XCTestCase {
    func testDatabasePathResolvesToAnExistingFile() {
        guard let path = ClinicalBaseBundle.databasePath else {
            XCTFail("bula.sqlite not found in bundle — was it added to Copy Bundle Resources?")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testRealDatabaseAnswersAKnownQuery() {
        guard let path = ClinicalBaseBundle.databasePath else {
            XCTFail("bula.sqlite not found in bundle")
            return
        }
        // Use a drug name known to be in the real 507-entry corpus per
        // project memory (enoxaparina) — adjust if the actual bundled
        // corpus differs at execution time.
        let result = ClinicalBaseStore.lookup(dbPath: path, question: "dose de enoxaparina ClCr 30")
        XCTAssertNotNil(result, "expected a real match against the bundled corpus")
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ClinicalBaseBundleTests 2>&1 | tail -40`
Expected: FAIL — `ClinicalBaseBundle` does not exist yet.

- [ ] **Step 5: Write the implementation**

`Scriptorium/Scriptorium/ClinicalBase/ClinicalBaseBundle.swift`:
```swift
import Foundation

enum ClinicalBaseBundle {
    static var databasePath: String? {
        Bundle.main.path(forResource: "bula", ofType: "sqlite")
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ClinicalBaseBundleTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Scriptorium/Scriptorium/Resources/bula.sqlite Scriptorium/Scriptorium/ClinicalBase/ClinicalBaseBundle.swift Scriptorium/ScriptoriumTests/ClinicalBaseBundleTests.swift
git commit -m "[scriptorium] Bundle clinical-base database into the app"
```

(30MB binary in git: acceptable for now per the existing Companion app's
same approach; if repo size becomes an issue later, switch to Git LFS —
out of scope for this task.)

---

### Task 7: Two-pane resizable UI shell

**Files:**
- Create: `Scriptorium/Scriptorium/UI/ScriptoriumSplitView.swift`
- Modify: `Scriptorium/Scriptorium/ContentView.swift`
- Test: none (SwiftUI layout structure — verified visually in Xcode
  Previews/Simulator per the spec's testing section, not unit-testable)

**Interfaces:**
- Consumes: nothing from earlier tasks directly (this is the shell later
  tasks populate).
- Produces: `ScriptoriumSplitView` — a two-pane, user-resizable layout
  (`NavigationSplitView` or `HSplitView` on macOS with an iOS-appropriate
  fallback) with a `documentPane: () -> DocumentContent` and
  `assistantPane: () -> AssistantContent` view-builder API. Tasks 8-9 embed
  their views into these two slots.

- [ ] **Step 1: Implement the split view**

`Scriptorium/Scriptorium/UI/ScriptoriumSplitView.swift`:
```swift
import SwiftUI

struct ScriptoriumSplitView<DocumentContent: View, AssistantContent: View>: View {
    @ViewBuilder var documentPane: () -> DocumentContent
    @ViewBuilder var assistantPane: () -> AssistantContent

    var body: some View {
        #if os(macOS)
        HSplitView {
            documentPane()
                .frame(minWidth: 400, idealWidth: 640)
            assistantPane()
                .frame(minWidth: 320, idealWidth: 380)
        }
        #else
        NavigationSplitView {
            assistantPane()
        } detail: {
            documentPane()
        }
        #endif
    }
}
```

- [ ] **Step 2: Wire it into ContentView**

`Scriptorium/Scriptorium/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        ScriptoriumSplitView {
            Text("Document")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } assistantPane: {
            Text("Assistant")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 3: Verify in Xcode Preview**

Open `ContentView.swift` in Xcode, confirm the Preview canvas renders two
resizable panes (macOS: draggable divider via `HSplitView`; iOS: a
`NavigationSplitView` with the assistant as the sidebar). This is a manual
visual check — no automated test for pure layout structure per this task's
Interfaces note.

- [ ] **Step 4: Commit**

```bash
git add Scriptorium/Scriptorium/UI/ScriptoriumSplitView.swift Scriptorium/Scriptorium/ContentView.swift
git commit -m "[scriptorium] Add two-pane resizable document/assistant shell"
```

---

### Task 8: Chat pane — conversation list + streaming

**Files:**
- Create: `Scriptorium/Scriptorium/UI/ConversationListView.swift`
- Create: `Scriptorium/Scriptorium/UI/ChatPaneView.swift`
- Create: `Scriptorium/Scriptorium/UI/ChatPaneViewModel.swift`
- Test: `Scriptorium/ScriptoriumTests/ChatPaneViewModelTests.swift`

**Interfaces:**
- Consumes: `GPUChatClient` (Task 2), `GPUChatStreamClient.streamMessage`
  and `StreamEvent` (Task 3), `Conversation`/`ChatMessage` (Task 2).
- Produces: `@Observable class ChatPaneViewModel` with `var messages:
  [ChatMessage]`, `var streaming: Bool`, `func send(content: String)
  async`. `ChatPaneView` and `ConversationListView` consume this and are
  UI-only (verified manually, per the same convention as Task 7).

- [ ] **Step 1: Write the failing test**

`Scriptorium/ScriptoriumTests/ChatPaneViewModelTests.swift`:
```swift
import XCTest
@testable import Scriptorium

final class ChatPaneViewModelTests: XCTestCase {
    func testSendAppendsUserAndAssistantMessagesAndClearsStreamingFlag() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let baseURL = URL(string: "http://test.local")!

        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/messages") == true, request.httpMethod == "POST" {
                let sse = "data: \"Hel\"\n\ndata: \"lo\"\n\ndata: [DONE]\n\n"
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                                headerFields: ["Content-Type": "text/event-stream"])!
                return (response, sse.data(using: .utf8)!)
            }
            if request.url?.path.hasSuffix("/messages") == true, request.httpMethod == "GET" {
                let body = #"[{"id":1,"conversation_id":1,"role":"user","content":"hi","model":null,"truncated":0,"created_at":"2026-08-19"},{"id":2,"conversation_id":1,"role":"assistant","content":"Hello","model":"qwen2.5-7b","truncated":0,"created_at":"2026-08-19"}]"#
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body.data(using: .utf8)!)
            }
            fatalError("unexpected request: \(request.url!)")
        }

        let client = GPUChatClient(baseURL: baseURL, session: session)
        let viewModel = ChatPaneViewModel(client: client, streamBaseURL: baseURL, streamSession: session, conversationId: 1)

        await viewModel.send(content: "hi")

        XCTAssertFalse(viewModel.streaming, "streaming flag must reset after a completed send, success or failure")
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.last?.content, "Hello")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ChatPaneViewModelTests 2>&1 | tail -40`
Expected: FAIL — `ChatPaneViewModel` does not exist.

- [ ] **Step 3: Write the implementation**

`Scriptorium/Scriptorium/UI/ChatPaneViewModel.swift`:
```swift
import Foundation
import Observation

@Observable
final class ChatPaneViewModel {
    private let client: GPUChatClient
    private let streamBaseURL: URL
    private let streamSession: URLSession
    let conversationId: Int

    var messages: [ChatMessage] = []
    var streaming: Bool = false

    init(client: GPUChatClient, streamBaseURL: URL, streamSession: URLSession = .shared, conversationId: Int) {
        self.client = client
        self.streamBaseURL = streamBaseURL
        self.streamSession = streamSession
        self.conversationId = conversationId
    }

    func send(content: String, attachments: [AttachmentInput] = []) async {
        streaming = true
        defer { streaming = false }
        do {
            let stream = GPUChatStreamClient.streamMessage(
                baseURL: streamBaseURL, conversationId: conversationId,
                content: content, attachments: attachments, session: streamSession
            )
            for try await event in stream {
                if case .done = event { break }
                // Tokens/errors are not appended incrementally to `messages`
                // here — the source of truth after a send is always the
                // persisted history, refetched below. A later UI-polish
                // task may add optimistic incremental rendering; Phase 1
                // keeps this simple and correct over responsive.
            }
            messages = try await client.fetchMessages(conversationId: conversationId)
        } catch {
            messages = (try? await client.fetchMessages(conversationId: conversationId)) ?? messages
        }
    }
}
```

`Scriptorium/Scriptorium/UI/ChatPaneView.swift`:
```swift
import SwiftUI

struct ChatPaneView: View {
    @State var viewModel: ChatPaneViewModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        Text(message.content)
                            .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                    }
                }
                .padding()
            }
            HStack {
                TextField("Message the model…", text: $draft, axis: .vertical)
                    .disabled(viewModel.streaming)
                Button("Send") {
                    let content = draft
                    draft = ""
                    Task { await viewModel.send(content: content) }
                }
                .disabled(viewModel.streaming || draft.isEmpty)
            }
            .padding()
        }
    }
}
```

`Scriptorium/Scriptorium/UI/ConversationListView.swift`:
```swift
import SwiftUI

struct ConversationListView: View {
    let conversations: [Conversation]
    @Binding var selectedId: Int?

    var body: some View {
        List(conversations, selection: $selectedId) { conversation in
            VStack(alignment: .leading) {
                Text(conversation.title)
                Text(conversation.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(conversation.id)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ChatPaneViewModelTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Scriptorium/Scriptorium/UI/ConversationListView.swift Scriptorium/Scriptorium/UI/ChatPaneView.swift Scriptorium/Scriptorium/UI/ChatPaneViewModel.swift Scriptorium/ScriptoriumTests/ChatPaneViewModelTests.swift
git commit -m "[scriptorium] Add chat pane wired to gpu-chat conversation API"
```

---

### Task 9: Clinical-base search UI + citation insertion

**Files:**
- Create: `Scriptorium/Scriptorium/UI/ClinicalSearchView.swift`
- Create: `Scriptorium/Scriptorium/UI/ClinicalSearchViewModel.swift`
- Create: `Scriptorium/Scriptorium/UI/ReferenceManagerView.swift` (the
  spec's "Reference manager" component — read-only list over the open
  document's `citations`)
- Test: `Scriptorium/ScriptoriumTests/ClinicalSearchViewModelTests.swift`
- Modify: `Scriptorium/Scriptorium/ContentView.swift` (wire the assistant
  pane to a three-way tab/segmented control: `ChatPaneView`,
  `ClinicalSearchView`, `ReferenceManagerView`)

**Interfaces:**
- Consumes: `ClinicalBaseStore.lookup` (Task 5), `ClinicalBaseBundle.databasePath`
  (Task 6), `Citation`/`CitationSource` (Task 4).
- Produces: `@Observable class ClinicalSearchViewModel` with `var query:
  String`, `var result: ClinicalBaseResult?`, `func search()`, `func
  asCitation() -> Citation?` (builds a `Citation` from the current result,
  or nil if there's no result). `ClinicalSearchView` takes an `onInsert:
  (Citation) -> Void` callback — the caller (ContentView, wiring this to
  the open `ScriptoriumDocument`) is responsible for calling
  `document.addCitation(...)` and inserting a citation marker into
  `document.text` at the cursor; this task provides the citation object and
  the insert affordance, not cursor-position tracking (SwiftUI's
  `AttributedString`/`TextEditor` cursor-position API is a Task 10+ concern
  if it proves necessary — for Phase 1, "insert" appends the citation
  marker at the end of the document text, which is acceptable per the
  spec's Phase 1 scope; precise cursor insertion is a fast-follow, not
  blocking).

- [ ] **Step 1: Write the failing test**

`Scriptorium/ScriptoriumTests/ClinicalSearchViewModelTests.swift`:
```swift
import XCTest
@testable import Scriptorium

final class ClinicalSearchViewModelTests: XCTestCase {
    var dbPath: String!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        dbPath = tmp.path
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        sqlite3_exec(db, """
            CREATE TABLE farmaco (id INTEGER PRIMARY KEY, nome_pt TEXT, generico TEXT, citacao TEXT);
            CREATE TABLE secao (farmaco_id INTEGER, id INTEGER, titulo TEXT, texto TEXT);
            INSERT INTO farmaco VALUES (1, 'enoxaparina', 'enoxaparin', 'Bula Enoxaparina, openFDA set_id abc, 2024-01-01');
            INSERT INTO secao VALUES (1, 1, 'Posologia', '30 mg SC 1x/dia.');
        """, nil, nil, nil)
        sqlite3_close(db)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    func testSearchPopulatesResult() {
        let viewModel = ClinicalSearchViewModel(databasePath: dbPath)
        viewModel.query = "dose de enoxaparina"
        viewModel.search()
        XCTAssertEqual(viewModel.result?.nomePT, "enoxaparina")
    }

    func testAsCitationBuildsClinicalBaseSourcedCitation() {
        let viewModel = ClinicalSearchViewModel(databasePath: dbPath)
        viewModel.query = "enoxaparina"
        viewModel.search()
        let citation = viewModel.asCitation()
        XCTAssertEqual(citation?.source, .clinicalBase)
        XCTAssertEqual(citation?.formattedText, "Bula Enoxaparina, openFDA set_id abc, 2024-01-01")
    }

    func testAsCitationReturnsNilWithoutAResult() {
        let viewModel = ClinicalSearchViewModel(databasePath: dbPath)
        XCTAssertNil(viewModel.asCitation())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ClinicalSearchViewModelTests 2>&1 | tail -40`
Expected: FAIL — `ClinicalSearchViewModel` does not exist.

- [ ] **Step 3: Write the implementation**

`Scriptorium/Scriptorium/UI/ClinicalSearchViewModel.swift`:
```swift
import Foundation
import Observation

@Observable
final class ClinicalSearchViewModel {
    private let databasePath: String?

    var query: String = ""
    var result: ClinicalBaseResult?

    init(databasePath: String?) {
        self.databasePath = databasePath
    }

    func search() {
        guard let databasePath else {
            result = nil
            return
        }
        result = ClinicalBaseStore.lookup(dbPath: databasePath, question: query)
    }

    func asCitation() -> Citation? {
        guard let result else { return nil }
        return Citation(id: UUID(), source: .clinicalBase, title: result.nomePT,
                         formattedText: result.citacao, url: nil)
    }
}
```

`Scriptorium/Scriptorium/UI/ClinicalSearchView.swift`:
```swift
import SwiftUI

struct ClinicalSearchView: View {
    @State var viewModel: ClinicalSearchViewModel
    let onInsert: (Citation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search the clinical base…", text: $viewModel.query)
                    .onSubmit { viewModel.search() }
                Button("Search") { viewModel.search() }
            }
            if let result = viewModel.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.nomePT).font(.headline)
                        Text(result.texto)
                        Text(result.citacao).font(.caption).foregroundStyle(.secondary)
                        Button("Insert citation") {
                            if let citation = viewModel.asCitation() {
                                onInsert(citation)
                            }
                        }
                    }
                }
            } else {
                Text("No match yet.").foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
```

`Scriptorium/Scriptorium/UI/ReferenceManagerView.swift` (the spec's
"Reference manager" component — lists every citation currently registered
on the open document; this is a read-only view over `document.citations`,
the same array `MarkdownExporter` (Task 10) reads for the References
section, so the list the user sees here always matches what export
produces):
```swift
import SwiftUI

struct ReferenceManagerView: View {
    let citations: [Citation]

    var body: some View {
        if citations.isEmpty {
            Text("No references cited yet.").foregroundStyle(.secondary).padding()
        } else {
            List(citations) { citation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.title).font(.headline)
                    Text(citation.formattedText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

`Scriptorium/Scriptorium/ContentView.swift` (updated to wire all three
assistant-pane tabs and citation insertion into a live document):
```swift
import SwiftUI

struct ContentView: View {
    @State private var document = ScriptoriumDocument()
    @State private var assistantTab: AssistantTab = .chat

    enum AssistantTab { case chat, clinicalSearch, references }

    var body: some View {
        ScriptoriumSplitView {
            TextEditor(text: Binding(
                get: { NSAttributedString(document.text).string },
                set: { document.text = AttributedString($0) }
            ))
            .padding()
        } assistantPane: {
            VStack(spacing: 0) {
                Picker("", selection: $assistantTab) {
                    Text("Chat").tag(AssistantTab.chat)
                    Text("Clinical base").tag(AssistantTab.clinicalSearch)
                    Text("References").tag(AssistantTab.references)
                }
                .pickerStyle(.segmented)
                .padding()

                switch assistantTab {
                case .chat:
                    Text("Chat pane wiring — see Task 8")
                case .clinicalSearch:
                    ClinicalSearchView(
                        viewModel: ClinicalSearchViewModel(databasePath: ClinicalBaseBundle.databasePath)
                    ) { citation in
                        document.addCitation(citation)
                        document.text.append(AttributedString(" [\(citation.title)]"))
                    }
                case .references:
                    ReferenceManagerView(citations: document.citations)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/ClinicalSearchViewModelTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Scriptorium/Scriptorium/UI/ClinicalSearchView.swift Scriptorium/Scriptorium/UI/ClinicalSearchViewModel.swift Scriptorium/Scriptorium/UI/ReferenceManagerView.swift Scriptorium/Scriptorium/ContentView.swift Scriptorium/ScriptoriumTests/ClinicalSearchViewModelTests.swift
git commit -m "[scriptorium] Add clinical-base search UI, citation insertion, and reference manager"
```

---

### Task 10: Markdown export

**Files:**
- Create: `Scriptorium/Scriptorium/Export/MarkdownExporter.swift`
- Create: `Scriptorium/Scriptorium/UI/ExportButton.swift`
- Test: `Scriptorium/ScriptoriumTests/MarkdownExporterTests.swift`
- Modify: `Scriptorium/Scriptorium/ContentView.swift` (add an export
  toolbar button)

**Interfaces:**
- Consumes: `ScriptoriumDocument` (Task 4).
- Produces: `enum MarkdownExporter { static func export(_ document:
  ScriptoriumDocument) -> String }` — pure function, no I/O, so it's fully
  unit-testable without a save panel. `ExportButton` wraps the
  platform-native save/share flow around it.

- [ ] **Step 1: Write the failing test**

`Scriptorium/ScriptoriumTests/MarkdownExporterTests.swift`:
```swift
import XCTest
@testable import Scriptorium

final class MarkdownExporterTests: XCTestCase {
    func testExportIncludesBodyAndReferencesSection() {
        var doc = ScriptoriumDocument()
        doc.text = AttributedString("Prevalência foi de 12,4% [Enoxaparina].")
        doc.citations = [
            Citation(id: UUID(), source: .clinicalBase, title: "Enoxaparina",
                     formattedText: "Bula Enoxaparina, openFDA set_id abc, 2024-01-01", url: nil),
            Citation(id: UUID(), source: .pubmed, title: "Silva et al.",
                     formattedText: "Silva J, et al. (2024). Título. Jornal.", url: "https://doi.org/10.1/x"),
        ]

        let markdown = MarkdownExporter.export(doc)

        XCTAssertTrue(markdown.contains("Prevalência foi de 12,4% [Enoxaparina]."))
        XCTAssertTrue(markdown.contains("## References"))
        XCTAssertTrue(markdown.contains("Bula Enoxaparina, openFDA set_id abc, 2024-01-01"))
        XCTAssertTrue(markdown.contains("[Silva et al.](https://doi.org/10.1/x)"))
    }

    func testExportWithNoCitationsOmitsReferencesSection() {
        var doc = ScriptoriumDocument()
        doc.text = AttributedString("Just text, no sources.")
        let markdown = MarkdownExporter.export(doc)
        XCTAssertFalse(markdown.contains("## References"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/MarkdownExporterTests 2>&1 | tail -40`
Expected: FAIL — `MarkdownExporter` does not exist.

- [ ] **Step 3: Write the implementation**

`Scriptorium/Scriptorium/Export/MarkdownExporter.swift`:
```swift
import Foundation

enum MarkdownExporter {
    static func export(_ document: ScriptoriumDocument) -> String {
        var output = String(document.text.characters)
        guard !document.citations.isEmpty else { return output }

        output += "\n\n## References\n\n"
        for citation in document.citations {
            if let url = citation.url {
                output += "- [\(citation.title)](\(url)) — \(citation.formattedText)\n"
            } else {
                output += "- \(citation.formattedText)\n"
            }
        }
        return output
    }
}
```

`Scriptorium/Scriptorium/UI/ExportButton.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

struct ExportButton: View {
    let document: ScriptoriumDocument
    @State private var showingExporter = false

    var body: some View {
        Button("Export Markdown") { showingExporter = true }
            .fileExporter(
                isPresented: $showingExporter,
                document: MarkdownFile(text: MarkdownExporter.export(document)),
                contentType: .plainText,
                defaultFilename: "manuscript"
            ) { _ in }
    }
}

struct MarkdownFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}
```

Add `ExportButton(document: document)` to `ContentView`'s toolbar (`.toolbar
{ ToolbarItem { ExportButton(document: document) } }` on the outer
`ScriptoriumSplitView` in `ContentView.swift`).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' -only-testing:ScriptoriumTests/MarkdownExporterTests 2>&1 | tail -40`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -scheme Scriptorium -destination 'platform=macOS' 2>&1 | tail -60`
Expected: all tests across all 10 tasks pass. This is Phase 1's overall
verification gate — a green full suite here is what "Phase 1 done" means.

- [ ] **Step 6: Commit**

```bash
git add Scriptorium/Scriptorium/Export Scriptorium/Scriptorium/UI/ExportButton.swift Scriptorium/Scriptorium/ContentView.swift Scriptorium/ScriptoriumTests/MarkdownExporterTests.swift
git commit -m "[scriptorium] Add Markdown export with references section"
```
