# Conclave Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app (Conclave) where the user can hold a single conversation while switching which model answers each turn ("thread mode"), and separately fan one prompt out to several models in parallel with a designated model synthesizing a final answer ("chairman mode") — both against the existing gpu-chat backend, extended with one new route and a two-column schema addition.

**Architecture:** Backend: extend `apps/gpu-chat/server` (Fastify + better-sqlite3, already deployed) with a `POST /api/conversations/:id/chairman-messages` SSE route that reuses the existing `streamChatCompletion` LiteLLM client, plus two new nullable columns on `messages` (`chairman_group_id`, `is_synthesis`) added via a `PRAGMA table_info` migration check. Client: a new Swift Package + xcodegen app shell (`~/Developer/Conclave` on the Mac), following the Swift Package + `App/` structure already proven for Scriptorium, with its own copy of the GPUChat networking layer (independent from Scriptorium's copy — these are separate apps by design, not a shared framework).

**Tech Stack:** Fastify, better-sqlite3, Vitest (backend, unchanged versions already in `apps/gpu-chat/server/package.json`); Swift 6, SwiftUI, `swift-tools-version: 6.2`, macOS 26 (Xcode 26+/27 SDK), XCTest, xcodegen.

**Spec:** `docs/superpowers/specs/2026-08-19-conclave-design.md`

## Global Constraints

- Repo location for the new client: `~/Developer/Conclave` on the Mac, reached via `ssh mac` from this Linux session — this Linux session cannot build or run Swift/Xcode tooling directly. Every Swift task's verification steps are real `swift build`/`swift test`/`xcodebuild` commands to run over `ssh mac '...'`, not commands assumed runnable here.
- Backend tasks (Task 1, Task 2) run directly in this session against `/home/devsounio/beagle/apps/gpu-chat/server` — Node/Vitest are available here.
- Swift Package: `swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]` — required for the `glassEffect`/`GlassEffectContainer` APIs (the `.v26` platform constant needs tools-version 6.2; using 6.0 fails with `'v26' is unavailable`).
- Every `glassEffect(...)` call MUST be wrapped in an ancestor `GlassEffectContainer`. A real bug was hit and fixed in Scriptorium: an unwrapped `glassEffect` on a message bubble produced a rendered element 786pt tall positioned 633pt above the visible window — the effect's sampling region is unbounded without a container. This plan's view tasks wrap every message-list/card `glassEffect` in a `GlassEffectContainer` from the start.
- The app's `Info.plist` (via xcodegen's `info.properties`) MUST include an `NSAppTransportSecurity` / `NSExceptionDomains` entry for `tail21cbc4.ts.net` with `NSExceptionAllowsInsecureHTTPLoads: true` — the backend is plain HTTP over the tailnet, and without this the app silently fails to load anything (confirmed root cause of an "app looks broken" report in Scriptorium).
- Swift 6 strict concurrency: real `Sendable` conformance on model/client types; `@MainActor` + `@Observable` on view models. No `@unchecked Sendable` anywhere.
- `TextEditor`/text-bearing views bind directly to their richest natural type (e.g. a view model's `@Observable` properties) rather than round-tripping through an intermediate `String` conversion on every keystroke/update, per the lesson from Scriptorium's document editor.
- Manual verification note (not an automated step, called out per-task where relevant): macOS persists window frame/state per bundle identifier across relaunches. If a build is relaunched and a stale window size/position from an earlier run appears, clear it before concluding there's a layout bug: `rm -rf "$HOME/Library/Saved Application State/dev.sounio.conclave.savedState"` and `defaults delete dev.sounio.conclave` on the Mac, then relaunch.

---

## Task 1: Backend — schema migration and grouped-message support

**Files:**
- Modify: `apps/gpu-chat/server/src/db.ts`
- Test: `apps/gpu-chat/server/src/db.test.ts` (create if it doesn't already exist as a dedicated file — check first with `ls apps/gpu-chat/server/src/*.test.ts`; if `db.ts` is already covered inside another test file, add these cases there instead of creating a duplicate)

**Interfaces:**
- Consumes: nothing new — extends the existing `Message` interface and `addMessage`/`listMessages` functions already in `db.ts`.
- Produces: `Message.chairman_group_id: string | null`, `Message.is_synthesis: number`; `addMessage(db, conversationId, role, content, model, truncated = false, chairmanGroupId: string | null = null, isSynthesis = false): Message` — the two new parameters are optional and default to the current (non-grouped) behavior, so every existing call site in `chat.ts` and `compare.ts` keeps compiling unchanged.

- [ ] **Step 1: Check whether `db.ts` already has a dedicated test file**

Run: `ls /home/devsounio/beagle/apps/gpu-chat/server/src/*.test.ts`

If `db.test.ts` exists, add the tests below to it. If not, create it with this header:

```typescript
import { describe, it, expect } from 'vitest'
import { openDb, addMessage, listMessages, createConversation } from './db.js'
```

- [ ] **Step 2: Write the failing tests**

```typescript
describe('grouped (chairman) messages', () => {
  it('re-running openDb on an existing database does not error (idempotent migration)', () => {
    const db = openDb(':memory:')
    expect(() => openDb(':memory:')).not.toThrow()
    // openDb on a *fresh* :memory: db always starts from empty, so this
    // only proves openDb itself doesn't throw twice in a row — the real
    // idempotency proof is Step 2b below, against one shared db handle.
    db.close()
  })

  it('adding the migration columns twice on the same handle does not error', () => {
    const db = openDb(':memory:')
    // openDb already ran the migration once during construction above.
    // Calling the same migration routine again against the same handle
    // must be a no-op, not a duplicate-column error.
    expect(() => openDb.__migrateForTest?.(db)).not.toThrow()
  })

  it('stores and retrieves chairman_group_id and is_synthesis on a message', () => {
    const db = openDb(':memory:')
    const conv = createConversation(db, 'Chairman test', 'qwen2.5-14b')
    const groupId = 'group-123'
    addMessage(db, conv.id, 'user', 'prompt', null)
    addMessage(db, conv.id, 'assistant', 'participant reply', 'qwen2.5-7b', false, groupId, false)
    addMessage(db, conv.id, 'assistant', 'synthesis', 'qwen2.5-14b', false, groupId, true)

    const messages = listMessages(db, conv.id)
    const participant = messages.find((m) => m.model === 'qwen2.5-7b')
    const synthesis = messages.find((m) => m.is_synthesis === 1)

    expect(participant?.chairman_group_id).toBe(groupId)
    expect(participant?.is_synthesis).toBe(0)
    expect(synthesis?.chairman_group_id).toBe(groupId)
    expect(synthesis?.model).toBe('qwen2.5-14b')
  })

  it('existing non-grouped messages have null chairman_group_id and is_synthesis 0', () => {
    const db = openDb(':memory:')
    const conv = createConversation(db, 'Plain thread', 'qwen2.5-14b')
    addMessage(db, conv.id, 'user', 'hi', null)
    const [message] = listMessages(db, conv.id)
    expect(message.chairman_group_id).toBeNull()
    expect(message.is_synthesis).toBe(0)
  })
})
```

Drop the `openDb.__migrateForTest` test (Step 2's second `it`) once you've written the real migration function in Step 4 — replace it with a direct call to the exported migration function by its real name, shown in Step 4.

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /home/devsounio/beagle/apps/gpu-chat/server && npx vitest run src/db.test.ts`
Expected: FAIL — `chairman_group_id`/`is_synthesis` do not exist on `Message`, and `addMessage` doesn't accept the extra parameters.

- [ ] **Step 4: Implement the migration and extend `addMessage`**

In `apps/gpu-chat/server/src/db.ts`, extend the `Message` interface:

```typescript
export interface Message {
  id: number
  conversation_id: number
  role: 'user' | 'assistant' | 'system'
  content: string
  model: string | null
  truncated: number
  chairman_group_id: string | null
  is_synthesis: number
  created_at: string
}
```

Add a migration function and call it from `openDb`, right after the existing `db.exec(...)` block:

```typescript
function migrateChairmanColumns(db: Database.Database): void {
  const columns = db.prepare("PRAGMA table_info(messages)").all() as Array<{ name: string }>
  const names = new Set(columns.map((c) => c.name))
  if (!names.has('chairman_group_id')) {
    db.exec('ALTER TABLE messages ADD COLUMN chairman_group_id TEXT')
  }
  if (!names.has('is_synthesis')) {
    db.exec('ALTER TABLE messages ADD COLUMN is_synthesis INTEGER NOT NULL DEFAULT 0')
  }
}
```

Call it at the end of `openDb`, before `return db`:

```typescript
export function openDb(path: string): Database.Database {
  const db = new Database(path)
  db.pragma('journal_mode = WAL')
  db.exec(`
    CREATE TABLE IF NOT EXISTS conversations (
      ... (unchanged)
    );
    CREATE TABLE IF NOT EXISTS messages (
      ... (unchanged — do NOT add the new columns to the CREATE TABLE
           statement; a fresh database gets them via migrateChairmanColumns
           below just like an existing one, so there is exactly one code
           path that adds these columns, not two that could drift)
    );
    ... (attachments, prompt_templates unchanged)
  `)
  migrateChairmanColumns(db)
  return db
}
```

Update `addMessage`:

```typescript
export function addMessage(
  db: Database.Database,
  conversationId: number,
  role: Message['role'],
  content: string,
  model: string | null,
  truncated = false,
  chairmanGroupId: string | null = null,
  isSynthesis = false,
): Message {
  const info = db
    .prepare(
      'INSERT INTO messages (conversation_id, role, content, model, truncated, chairman_group_id, is_synthesis) VALUES (?, ?, ?, ?, ?, ?, ?)',
    )
    .run(conversationId, role, content, model, truncated ? 1 : 0, chairmanGroupId, isSynthesis ? 1 : 0)
  return db.prepare('SELECT * FROM messages WHERE id = ?').get(info.lastInsertRowid) as Message
}
```

`listMessages` needs no change — it already does `SELECT *`, which picks up the new columns automatically.

Now replace the Step 2 `__migrateForTest` placeholder test with a real one, exporting `migrateChairmanColumns` for the test to call directly:

```typescript
export function migrateChairmanColumns(db: Database.Database): void { /* as above */ }
```

```typescript
it('calling migrateChairmanColumns twice on the same handle does not error', () => {
  const db = openDb(':memory:')
  expect(() => migrateChairmanColumns(db)).not.toThrow()
  db.close()
})
```

Update the test file's import line accordingly:

```typescript
import { openDb, addMessage, listMessages, createConversation, migrateChairmanColumns } from './db.js'
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /home/devsounio/beagle/apps/gpu-chat/server && npx vitest run src/db.test.ts`
Expected: PASS, all cases green.

- [ ] **Step 6: Run the full existing backend suite to confirm no regression**

Run: `cd /home/devsounio/beagle/apps/gpu-chat/server && npx vitest run`
Expected: PASS — `chat.test.ts`, `compare.test.ts`, `models.test.ts`, `templates.test.ts` all still green (they call `addMessage` with the old 5-argument shape, which the new optional parameters keep compiling and behaving identically).

- [ ] **Step 7: Commit**

```bash
cd /home/devsounio/beagle
git add apps/gpu-chat/server/src/db.ts apps/gpu-chat/server/src/db.test.ts
git commit -m "[backend] Add chairman_group_id/is_synthesis columns to messages"
```

---

## Task 2: Backend — chairman-messages SSE route

**Files:**
- Create: `apps/gpu-chat/server/src/routes/chairman.ts`
- Create: `apps/gpu-chat/server/src/routes/chairman.test.ts`
- Modify: `apps/gpu-chat/server/src/app.ts` (register the new route — read this file first to see how `registerChatRoutes`/`registerCompareRoutes` are currently wired in, and follow the same pattern)

**Interfaces:**
- Consumes: `streamChatCompletion(baseUrl, model, messages): AsyncGenerator<string>` and `ChatMessage` from `../litellm-client.js` (Task 1's context, unchanged); `addMessage(db, conversationId, role, content, model, truncated, chairmanGroupId, isSynthesis)` and `getConversation(db, id)` from `../db.js` (Task 1's new signature).
- Produces: `registerChairmanRoutes(app: FastifyInstance, db: Database.Database, litellmBaseUrl: string): void`, mounted at `POST /api/conversations/:id/chairman-messages`. SSE event framing: `event: participant:<model>` for each participant model's tokens/errors/done, `event: chairman` for the synthesis model's tokens/error/done. Later Swift tasks (Task 6) parse exactly this framing.

- [ ] **Step 1: Read `app.ts` to see the existing route-registration pattern**

Run: `cat /home/devsounio/beagle/apps/gpu-chat/server/src/app.ts`

Find where `registerChatRoutes`, `registerCompareRoutes`, `registerModelsRoute`, `registerTemplateRoutes` are called (each takes `app`, `db`, and `litellmBaseUrl` per Task 1's context) and mirror that exact call shape for the new `registerChairmanRoutes`.

- [ ] **Step 2: Write the failing tests**

```typescript
import { describe, it, expect, vi, afterEach } from 'vitest'
import { buildApp } from '../app.js'
import * as litellmClient from '../litellm-client.js'
import { openDb, createConversation } from '../db.js'

afterEach(() => vi.restoreAllMocks())

async function* fakeStream(tokens: string[]) {
  for (const t of tokens) yield t
}

describe('POST /api/conversations/:id/chairman-messages', () => {
  it('streams each participant then the chairman synthesis, and persists all of them grouped', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, model) {
      if (model === 'qwen2.5-7b') yield* fakeStream(['A'])
      else if (model === 'qwen2.5-14b') yield* fakeStream(['B'])
      else yield* fakeStream(['synthesis of A and B'])
    })

    const db = openDb(':memory:')
    const conv = createConversation(db, 'Chairman run', 'qwen2.5-32b')
    const app = buildApp({ db, litellmBaseUrl: 'http://unused:4000' })

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/chairman-messages`,
      payload: { prompt: 'compare X and Y', participantModels: ['qwen2.5-7b', 'qwen2.5-14b'], chairmanModel: 'qwen2.5-32b' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: participant:qwen2.5-7b\ndata: "A"')
    expect(res.body).toContain('event: participant:qwen2.5-7b\ndata: [DONE]')
    expect(res.body).toContain('event: participant:qwen2.5-14b\ndata: "B"')
    expect(res.body).toContain('event: chairman\ndata: "synthesis of A and B"')
    expect(res.body).toContain('event: chairman\ndata: [DONE]')

    const { listMessages } = await import('../db.js')
    const messages = listMessages(db, conv.id)
    const userMsg = messages.find((m) => m.role === 'user')
    const participantMsgs = messages.filter((m) => m.chairman_group_id && m.is_synthesis === 0)
    const synthesisMsg = messages.find((m) => m.is_synthesis === 1)

    expect(userMsg?.content).toBe('compare X and Y')
    expect(participantMsgs).toHaveLength(2)
    expect(participantMsgs.every((m) => m.chairman_group_id === synthesisMsg?.chairman_group_id)).toBe(true)
    expect(synthesisMsg?.model).toBe('qwen2.5-32b')
    expect(synthesisMsg?.content).toBe('synthesis of A and B')
  })

  it('synthesizes from whichever participants succeed when one participant fails', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, model) {
      if (model === 'qwen2.5-7b') throw new Error('LiteLLM chat completion failed: 500')
      if (model === 'qwen2.5-14b') yield* fakeStream(['ok reply'])
      else yield* fakeStream(['synthesis from the survivor'])
    })

    const db = openDb(':memory:')
    const conv = createConversation(db, 'Partial failure', 'qwen2.5-32b')
    const app = buildApp({ db, litellmBaseUrl: 'http://unused:4000' })

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/chairman-messages`,
      payload: { prompt: 'p', participantModels: ['qwen2.5-7b', 'qwen2.5-14b'], chairmanModel: 'qwen2.5-32b' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: participant:qwen2.5-7b\ndata: error:')
    expect(res.body).toContain('event: participant:qwen2.5-14b\ndata: "ok reply"')
    expect(res.body).toContain('event: chairman\ndata: "synthesis from the survivor"')
  })

  it('skips the chairman synthesis entirely when every participant fails', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, model) {
      throw new Error(`LiteLLM chat completion failed: 500 (${model})`)
    })

    const db = openDb(':memory:')
    const conv = createConversation(db, 'Total failure', 'qwen2.5-32b')
    const app = buildApp({ db, litellmBaseUrl: 'http://unused:4000' })

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/chairman-messages`,
      payload: { prompt: 'p', participantModels: ['qwen2.5-7b', 'qwen2.5-14b'], chairmanModel: 'qwen2.5-32b' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: chairman\ndata: error:')
    expect(res.body).not.toContain('event: chairman\ndata: "')

    const { listMessages } = await import('../db.js')
    const synthesisMsg = listMessages(db, conv.id).find((m) => m.is_synthesis === 1)
    expect(synthesisMsg).toBeUndefined()
  })

  it('returns 404 for an unknown conversation', async () => {
    const db = openDb(':memory:')
    const app = buildApp({ db, litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'POST',
      url: '/api/conversations/999/chairman-messages',
      payload: { prompt: 'p', participantModels: ['m'], chairmanModel: 'm' },
    })
    expect(res.statusCode).toBe(404)
  })
})
```

Check `app.ts`'s `buildApp` signature first (Step 1) — the tests above assume it accepts `{ db, litellmBaseUrl }` directly in addition to (or instead of) `{ dbPath, litellmBaseUrl }` as seen in `compare.test.ts`. If `buildApp` only accepts `dbPath`, adapt these tests to use `dbPath: ':memory:'` and fetch the `db` handle a different way (e.g. add a `getDb()` accessor if `app.ts` doesn't already expose one) — match whatever `buildApp` actually supports rather than inventing a new signature for it in this task.

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /home/devsounio/beagle/apps/gpu-chat/server && npx vitest run src/routes/chairman.test.ts`
Expected: FAIL — `chairman.ts` doesn't exist yet.

- [ ] **Step 4: Implement the route**

```typescript
import { randomUUID } from 'node:crypto'
import { FastifyInstance } from 'fastify'
import Database from 'better-sqlite3'
import { addMessage, getConversation } from '../db.js'
import { streamChatCompletion, ChatMessage } from '../litellm-client.js'

export function registerChairmanRoutes(app: FastifyInstance, db: Database.Database, litellmBaseUrl: string): void {
  app.post<{
    Params: { id: string }
    Body: { prompt: string; participantModels: string[]; chairmanModel: string }
  }>('/api/conversations/:id/chairman-messages', async (req, reply) => {
    const conversationId = Number(req.params.id)
    const conversation = getConversation(db, conversationId)
    if (!conversation) {
      reply.code(404)
      return { error: 'conversation not found' }
    }

    const { prompt, participantModels, chairmanModel } = req.body
    addMessage(db, conversationId, 'user', prompt, null)

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    })

    const groupId = randomUUID()
    const promptMessages: ChatMessage[] = [{ role: 'user', content: prompt }]

    const participantResults = await Promise.all(
      participantModels.map(async (model) => {
        let assembled = ''
        let failed = false
        try {
          for await (const token of streamChatCompletion(litellmBaseUrl, model, promptMessages)) {
            assembled += token
            reply.raw.write(`event: participant:${model}\ndata: ${JSON.stringify(token)}\n\n`)
          }
        } catch (err) {
          failed = true
          const message = (err as Error).message
          reply.raw.write(`event: participant:${model}\ndata: error:${JSON.stringify(message)}\n\n`)
        }
        reply.raw.write(`event: participant:${model}\ndata: [DONE]\n\n`)
        if (!failed) {
          addMessage(db, conversationId, 'assistant', assembled, model, false, groupId, false)
        }
        return { model, assembled, failed }
      }),
    )

    const survivors = participantResults.filter((r) => !r.failed)
    if (survivors.length === 0) {
      reply.raw.write(`event: chairman\ndata: error:${JSON.stringify('all participants failed')}\n\n`)
      reply.raw.write('event: chairman\ndata: [DONE]\n\n')
      reply.raw.end()
      return reply
    }

    const synthesisPrompt =
      `Original prompt: ${prompt}\n\n` +
      survivors.map((r) => `--- ${r.model} ---\n${r.assembled}`).join('\n\n') +
      '\n\nSynthesize the single best answer from the responses above.'
    const synthesisMessages: ChatMessage[] = [{ role: 'user', content: synthesisPrompt }]

    let synthesisAssembled = ''
    try {
      for await (const token of streamChatCompletion(litellmBaseUrl, chairmanModel, synthesisMessages)) {
        synthesisAssembled += token
        reply.raw.write(`event: chairman\ndata: ${JSON.stringify(token)}\n\n`)
      }
      addMessage(db, conversationId, 'assistant', synthesisAssembled, chairmanModel, false, groupId, true)
    } catch (err) {
      const message = (err as Error).message
      reply.raw.write(`event: chairman\ndata: error:${JSON.stringify(message)}\n\n`)
    }
    reply.raw.write('event: chairman\ndata: [DONE]\n\n')
    reply.raw.end()
    return reply
  })
}
```

- [ ] **Step 5: Register the route in `app.ts`**

Follow the exact pattern found in Step 1 for the other `register*Routes` calls — add:

```typescript
import { registerChairmanRoutes } from './routes/chairman.js'
// ...
registerChairmanRoutes(app, db, litellmBaseUrl)
```

in the same place the other routes are registered.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /home/devsounio/beagle/apps/gpu-chat/server && npx vitest run src/routes/chairman.test.ts`
Expected: PASS, all four cases green.

- [ ] **Step 7: Run the full backend suite**

Run: `cd /home/devsounio/beagle/apps/gpu-chat/server && npx vitest run`
Expected: PASS, no regressions in `chat.test.ts`, `compare.test.ts`, `models.test.ts`, `templates.test.ts`.

- [ ] **Step 8: Commit**

```bash
cd /home/devsounio/beagle
git add apps/gpu-chat/server/src/routes/chairman.ts apps/gpu-chat/server/src/routes/chairman.test.ts apps/gpu-chat/server/src/app.ts
git commit -m "[backend] Add POST /api/conversations/:id/chairman-messages route"
```

---

## Task 3: Swift Package scaffold and shared models

**Files:**
- Create: `~/Developer/Conclave/Package.swift`
- Create: `~/Developer/Conclave/Sources/Conclave/GPUChat/ConclaveModels.swift`
- Create: `~/Developer/Conclave/Tests/ConclaveTests/ConclaveModelsTests.swift`

**Interfaces:**
- Produces: `public struct Conversation: Codable, Identifiable, Sendable { let id: Int; let title: String; let model: String; let created_at: String }`; `public struct ChatMessage: Codable, Identifiable, Sendable { let id: Int; let conversation_id: Int; let role: String; let content: String; let model: String?; let truncated: Int; let chairman_group_id: String?; let is_synthesis: Int; let created_at: String }`; `public struct ModelInfo: Codable, Identifiable, Sendable { let id: String }`. Field names match the backend's JSON exactly (Task 1/2's `Message`/`Conversation` shapes) — no `CodingKeys` remapping needed since Swift's `Codable` synthesis matches snake_case JSON keys to identically-named snake_case Swift properties directly.

- [ ] **Step 1: Create the package on the Mac**

Run over SSH:

```bash
ssh mac 'mkdir -p ~/Developer/Conclave/Sources/Conclave/GPUChat ~/Developer/Conclave/Tests/ConclaveTests'
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Conclave",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Conclave", targets: ["Conclave"]),
    ],
    targets: [
        .target(name: "Conclave"),
        .testTarget(name: "ConclaveTests", dependencies: ["Conclave"]),
    ]
)
```

Copy this file to the Mac:

```bash
scp Package.swift mac:~/Developer/Conclave/Package.swift
```

(Write it locally first to a scratch path, e.g. your session's tmp directory, then `scp` it — this plan assumes the same local-draft-then-scp workflow already used for Scriptorium, since this Linux session has no direct filesystem access to the Mac.)

- [ ] **Step 3: Write the failing model tests**

```swift
import XCTest
@testable import Conclave

final class ConclaveModelsTests: XCTestCase {
    func testChatMessageDecodesGroupedFields() throws {
        let json = """
        {
          "id": 1, "conversation_id": 1, "role": "assistant", "content": "hi",
          "model": "qwen2.5-7b", "truncated": 0,
          "chairman_group_id": "abc", "is_synthesis": 0,
          "created_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        XCTAssertEqual(message.chairman_group_id, "abc")
        XCTAssertEqual(message.is_synthesis, 0)
    }

    func testChatMessageDecodesNullGroupFields() throws {
        let json = """
        {
          "id": 1, "conversation_id": 1, "role": "user", "content": "hi",
          "model": null, "truncated": 0,
          "chairman_group_id": null, "is_synthesis": 0,
          "created_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        XCTAssertNil(message.chairman_group_id)
        XCTAssertNil(message.model)
    }

    func testConversationDecodes() throws {
        let json = """
        {"id": 1, "title": "t", "model": "qwen2.5-7b", "created_at": "2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let conversation = try JSONDecoder().decode(Conversation.self, from: json)
        XCTAssertEqual(conversation.title, "t")
    }
}
```

Copy to the Mac: `scp ConclaveModelsTests.swift mac:~/Developer/Conclave/Tests/ConclaveTests/ConclaveModelsTests.swift`

- [ ] **Step 4: Run tests to verify they fail**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: FAIL — `Conclave` module doesn't define these types yet (build error, not a test assertion failure).

- [ ] **Step 5: Implement the models**

```swift
import Foundation

public struct Conversation: Codable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let model: String
    public let created_at: String
}

public struct ChatMessage: Codable, Identifiable, Sendable {
    public let id: Int
    public let conversation_id: Int
    public let role: String
    public let content: String
    public let model: String?
    public let truncated: Int
    public let chairman_group_id: String?
    public let is_synthesis: Int
    public let created_at: String
}

public struct ModelInfo: Codable, Identifiable, Sendable {
    public let id: String
}

public enum ConclaveError: Error, Sendable {
    case httpStatus(Int)
}
```

Copy to the Mac: `scp ConclaveModels.swift mac:~/Developer/Conclave/Sources/Conclave/GPUChat/ConclaveModels.swift`

- [ ] **Step 6: Run tests to verify they pass**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: PASS, 3/3 tests.

- [ ] **Step 7: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git init -q 2>/dev/null; git add -A && git commit -m "[conclave] Scaffold Swift Package with shared GPUChat models"'
```

(`git init -q` is a no-op if the repo already exists from a prior task run — the `2>/dev/null` swallows the "already a git repository" message so the command doesn't fail the step.)

---

## Task 4: ConclaveClient — REST networking layer

**Files:**
- Create: `~/Developer/Conclave/Sources/Conclave/GPUChat/ConclaveClient.swift`
- Create: `~/Developer/Conclave/Tests/ConclaveTests/ConclaveClientTests.swift`

**Interfaces:**
- Consumes: `Conversation`, `ChatMessage`, `ModelInfo` (Task 3).
- Produces: `public final class ConclaveClient: Sendable { public init(baseURL: URL, session: URLSession = .shared); func fetchModels() async throws -> [ModelInfo]; func fetchConversations() async throws -> [Conversation]; func createConversation(title: String, model: String) async throws -> Conversation; func updateConversationModel(id: Int, model: String) async throws -> Conversation; func fetchMessages(conversationId: Int) async throws -> [ChatMessage] }`. Later tasks (5, 6, 7, 8) hold a `ConclaveClient` instance and call these methods.

- [ ] **Step 1: Write the failing tests (mock URLProtocol pattern)**

```swift
import XCTest
@testable import Conclave

final class MockURLProtocol: URLProtocol {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
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

final class ConclaveClientTests: XCTestCase {
    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testFetchModelsDecodesArray() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/models")
            let json = #"[{"id":"qwen2.5-7b"},{"id":"qwen2.5-14b"}]"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: makeSession())
        let models = try await client.fetchModels()
        XCTAssertEqual(models.map(\.id), ["qwen2.5-7b", "qwen2.5-14b"])
    }

    func testNon2xxThrowsHTTPStatusError() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: makeSession())
        do {
            _ = try await client.fetchModels()
            XCTFail("expected throw")
        } catch ConclaveError.httpStatus(let code) {
            XCTAssertEqual(code, 500)
        }
    }

    func testCreateConversationPostsAndDecodes() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/conversations")
            let json = #"{"id":1,"title":"t","model":"qwen2.5-7b","created_at":"2026-01-01T00:00:00Z"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: makeSession())
        let conversation = try await client.createConversation(title: "t", model: "qwen2.5-7b")
        XCTAssertEqual(conversation.id, 1)
    }

    func testFetchMessagesDecodesGroupedFields() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/conversations/1/messages")
            let json = """
            [{"id":1,"conversation_id":1,"role":"assistant","content":"a","model":"m",
              "truncated":0,"chairman_group_id":"g","is_synthesis":1,"created_at":"2026-01-01T00:00:00Z"}]
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: makeSession())
        let messages = try await client.fetchMessages(conversationId: 1)
        XCTAssertEqual(messages.first?.is_synthesis, 1)
    }
}
```

Copy to the Mac: `scp ConclaveClientTests.swift mac:~/Developer/Conclave/Tests/ConclaveTests/ConclaveClientTests.swift`

- [ ] **Step 2: Run tests to verify they fail**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -40'`
Expected: FAIL — `ConclaveClient` doesn't exist.

- [ ] **Step 3: Implement the client**

```swift
import Foundation

public final class ConclaveClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private func send<Response: Decodable>(
        path: String, method: String = "GET", body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ConclaveError.httpStatus(code)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    public func fetchModels() async throws -> [ModelInfo] {
        try await send(path: "/api/models")
    }

    public func fetchConversations() async throws -> [Conversation] {
        try await send(path: "/api/conversations")
    }

    public func createConversation(title: String, model: String) async throws -> Conversation {
        let body = try JSONEncoder().encode(["title": title, "model": model])
        return try await send(path: "/api/conversations", method: "POST", body: body)
    }

    public func updateConversationModel(id: Int, model: String) async throws -> Conversation {
        let body = try JSONEncoder().encode(["model": model])
        return try await send(path: "/api/conversations/\(id)", method: "PATCH", body: body)
    }

    public func fetchMessages(conversationId: Int) async throws -> [ChatMessage] {
        try await send(path: "/api/conversations/\(conversationId)/messages")
    }
}
```

Copy to the Mac: `scp ConclaveClient.swift mac:~/Developer/Conclave/Sources/Conclave/GPUChat/ConclaveClient.swift`

- [ ] **Step 4: Run tests to verify they pass**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -40'`
Expected: PASS, 4/4 new tests plus the 3 from Task 3 (7 total).

- [ ] **Step 5: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git add -A && git commit -m "[conclave] Add ConclaveClient REST networking layer"'
```

---

## Task 5: ThreadStreamClient — SSE parsing for thread mode

**Files:**
- Create: `~/Developer/Conclave/Sources/Conclave/GPUChat/ThreadStreamClient.swift`
- Create: `~/Developer/Conclave/Tests/ConclaveTests/ThreadStreamClientTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure parsing logic + a plain `URLSession`-driven stream).
- Produces: `public enum ThreadStreamEvent: Equatable, Sendable { case token(String), error(String), done }`; `public static func parse(line: String, currentEvent: String?) -> ThreadStreamEvent?`; `public static func streamMessage(baseURL: URL, conversationId: Int, content: String, model: String?, session: URLSession = .shared) -> AsyncThrowingStream<ThreadStreamEvent, Error>`. Task 7's `ThreadViewModel` consumes `streamMessage`.

- [ ] **Step 1: Write the failing parse tests**

This reuses the exact critical property from Scriptorium's `GPUChatStreamClient`: check for the literal `[DONE]` sentinel **before** attempting a JSON decode, since a token can legitimately contain the substring `[DONE]` inside its own content and must not be misparsed as the stream terminator once JSON-decoded first.

```swift
import XCTest
@testable import Conclave

final class ThreadStreamClientTests: XCTestCase {
    func testParsesTokenErrorAndDoneFrames() {
        XCTAssertEqual(ThreadStreamClient.parse(line: "data: \"hello\"", currentEvent: nil), .token("hello"))
        XCTAssertEqual(ThreadStreamClient.parse(line: "data: \"boom\"", currentEvent: "error"), .error("boom"))
        XCTAssertEqual(ThreadStreamClient.parse(line: "data: [DONE]", currentEvent: nil), .done)
    }

    func testParsesTokenWithEmbeddedDoneSubstring() {
        // The literal characters "[DONE]" appearing *inside* a JSON-encoded
        // token must not be mistaken for the sentinel — the check is against
        // the raw line before JSON decoding, not after.
        let line = "data: \"the string [DONE] appeared mid-sentence\""
        XCTAssertEqual(
            ThreadStreamClient.parse(line: line, currentEvent: nil),
            .token("the string [DONE] appeared mid-sentence")
        )
    }

    func testNonDataLineReturnsNil() {
        XCTAssertNil(ThreadStreamClient.parse(line: "event: error", currentEvent: nil))
        XCTAssertNil(ThreadStreamClient.parse(line: "", currentEvent: nil))
    }
}
```

Copy to the Mac: `scp ThreadStreamClientTests.swift mac:~/Developer/Conclave/Tests/ConclaveTests/ThreadStreamClientTests.swift`

- [ ] **Step 2: Run tests to verify they fail**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: FAIL — `ThreadStreamClient` doesn't exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum ThreadStreamEvent: Equatable, Sendable {
    case token(String)
    case error(String)
    case done
}

public enum ThreadStreamClient {
    public static func parse(line: String, currentEvent: String?) -> ThreadStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return nil
        }
        return currentEvent == "error" ? .error(decoded) : .token(decoded)
    }

    public static func streamMessage(
        baseURL: URL, conversationId: Int, content: String, model: String?, session: URLSession = .shared
    ) -> AsyncThrowingStream<ThreadStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("/api/conversations/\(conversationId)/messages"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(["content": content])

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw ConclaveError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }

                    var currentEvent: String?
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            currentEvent = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard let event = parse(line: line, currentEvent: currentEvent) else { continue }
                        continuation.yield(event)
                        currentEvent = nil
                        if case .done = event { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

Note: `model` is accepted as a parameter for API symmetry with Task 7's per-turn model switcher, but the current backend route (`POST /api/conversations/:id/messages`, Task 1's context) always uses the conversation's stored model — it does not yet accept a per-message model override. Task 7's model switcher therefore calls `ConclaveClient.updateConversationModel` immediately before sending each message when the user has picked a different model than the conversation's current default, rather than passing `model` through this request body. Leave the `model` parameter here unused in the request body (do not add an unsupported field to the JSON payload) — it exists so Task 7's call site reads clearly and so a future backend change to accept a per-message override doesn't require changing this function's signature.

Copy to the Mac: `scp ThreadStreamClient.swift mac:~/Developer/Conclave/Sources/Conclave/GPUChat/ThreadStreamClient.swift`

- [ ] **Step 4: Run tests to verify they pass**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: PASS, 3/3 new tests.

- [ ] **Step 5: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git add -A && git commit -m "[conclave] Add ThreadStreamClient SSE parsing"'
```

---

## Task 6: ChairmanStreamClient — SSE parsing for the multiplexed chairman endpoint

**Files:**
- Create: `~/Developer/Conclave/Sources/Conclave/GPUChat/ChairmanStreamClient.swift`
- Create: `~/Developer/Conclave/Tests/ConclaveTests/ChairmanStreamClientTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure parsing + streaming, mirrors Task 5's shape for the different wire format from Task 2).
- Produces: `public enum ChairmanStreamEvent: Equatable, Sendable { case participantToken(model: String, token: String), participantError(model: String, message: String), participantDone(model: String), chairmanToken(String), chairmanError(String), chairmanDone }`; `public static func parse(eventLine: String?, dataLine: String) -> ChairmanStreamEvent?`; `public static func streamChairmanMessage(baseURL: URL, conversationId: Int, prompt: String, participantModels: [String], chairmanModel: String, session: URLSession = .shared) -> AsyncThrowingStream<ChairmanStreamEvent, Error>`. Task 8's `ChairmanViewModel` consumes `streamChairmanMessage`.

- [ ] **Step 1: Write the failing parse tests**

Task 2's wire format: `event: participant:<model>` / `event: chairman`, and on the `data:` line either a JSON-encoded token, `error:<json-encoded message>`, or the literal `[DONE]`.

```swift
import XCTest
@testable import Conclave

final class ChairmanStreamClientTests: XCTestCase {
    func testParsesParticipantToken() {
        let event = ChairmanStreamClient.parse(eventLine: "participant:qwen2.5-7b", dataLine: "\"A\"")
        XCTAssertEqual(event, .participantToken(model: "qwen2.5-7b", token: "A"))
    }

    func testParsesParticipantError() {
        let event = ChairmanStreamClient.parse(eventLine: "participant:qwen2.5-7b", dataLine: "error:\"boom\"")
        XCTAssertEqual(event, .participantError(model: "qwen2.5-7b", message: "boom"))
    }

    func testParsesParticipantDone() {
        let event = ChairmanStreamClient.parse(eventLine: "participant:qwen2.5-7b", dataLine: "[DONE]")
        XCTAssertEqual(event, .participantDone(model: "qwen2.5-7b"))
    }

    func testParsesChairmanTokenErrorAndDone() {
        XCTAssertEqual(ChairmanStreamClient.parse(eventLine: "chairman", dataLine: "\"final answer\""), .chairmanToken("final answer"))
        XCTAssertEqual(ChairmanStreamClient.parse(eventLine: "chairman", dataLine: "error:\"all participants failed\""), .chairmanError("all participants failed"))
        XCTAssertEqual(ChairmanStreamClient.parse(eventLine: "chairman", dataLine: "[DONE]"), .chairmanDone)
    }

    func testMissingEventLineReturnsNil() {
        XCTAssertNil(ChairmanStreamClient.parse(eventLine: nil, dataLine: "\"A\""))
    }
}
```

Copy to the Mac: `scp ChairmanStreamClientTests.swift mac:~/Developer/Conclave/Tests/ConclaveTests/ChairmanStreamClientTests.swift`

- [ ] **Step 2: Run tests to verify they fail**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: FAIL — `ChairmanStreamClient` doesn't exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum ChairmanStreamEvent: Equatable, Sendable {
    case participantToken(model: String, token: String)
    case participantError(model: String, message: String)
    case participantDone(model: String)
    case chairmanToken(String)
    case chairmanError(String)
    case chairmanDone
}

public enum ChairmanStreamClient {
    public static func parse(eventLine: String?, dataLine: String) -> ChairmanStreamEvent? {
        guard let eventLine else { return nil }

        func decodeString(_ raw: String) -> String? {
            guard let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(String.self, from: data)
        }

        if eventLine.hasPrefix("participant:") {
            let model = String(eventLine.dropFirst("participant:".count))
            if dataLine == "[DONE]" { return .participantDone(model: model) }
            if dataLine.hasPrefix("error:") {
                let raw = String(dataLine.dropFirst("error:".count))
                guard let message = decodeString(raw) else { return nil }
                return .participantError(model: model, message: message)
            }
            guard let token = decodeString(dataLine) else { return nil }
            return .participantToken(model: model, token: token)
        }

        if eventLine == "chairman" {
            if dataLine == "[DONE]" { return .chairmanDone }
            if dataLine.hasPrefix("error:") {
                let raw = String(dataLine.dropFirst("error:".count))
                guard let message = decodeString(raw) else { return nil }
                return .chairmanError(message)
            }
            guard let token = decodeString(dataLine) else { return nil }
            return .chairmanToken(token)
        }

        return nil
    }

    public static func streamChairmanMessage(
        baseURL: URL, conversationId: Int, prompt: String,
        participantModels: [String], chairmanModel: String, session: URLSession = .shared
    ) -> AsyncThrowingStream<ChairmanStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(
                        url: baseURL.appendingPathComponent("/api/conversations/\(conversationId)/chairman-messages")
                    )
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode([
                        "prompt": prompt,
                        "participantModels": participantModels,
                        "chairmanModel": chairmanModel,
                    ] as [String: Any])

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw ConclaveError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }

                    var currentEvent: String?
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            currentEvent = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard line.hasPrefix("data:") else { continue }
                        let dataLine = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard let event = parse(eventLine: currentEvent, dataLine: String(dataLine)) else { continue }
                        continuation.yield(event)
                        currentEvent = nil
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

`JSONEncoder().encode([String: Any])` does not compile directly (`[String: Any]` isn't `Encodable`) — use `JSONSerialization.data(withJSONObject:)` instead for this one request body, since it's a plain string/array dictionary with no nested `Encodable` types:

```swift
request.httpBody = try JSONSerialization.data(withJSONObject: [
    "prompt": prompt,
    "participantModels": participantModels,
    "chairmanModel": chairmanModel,
])
```

Copy to the Mac: `scp ChairmanStreamClient.swift mac:~/Developer/Conclave/Sources/Conclave/GPUChat/ChairmanStreamClient.swift`

- [ ] **Step 4: Run tests to verify they pass**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: PASS, 5/5 new tests.

- [ ] **Step 5: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git add -A && git commit -m "[conclave] Add ChairmanStreamClient SSE parsing"'
```

---

## Task 7: ThreadViewModel and ThreadView

**Files:**
- Create: `~/Developer/Conclave/Sources/Conclave/UI/ThreadViewModel.swift`
- Create: `~/Developer/Conclave/Sources/Conclave/UI/ThreadView.swift`
- Create: `~/Developer/Conclave/Tests/ConclaveTests/ThreadViewModelTests.swift`

**Interfaces:**
- Consumes: `ConclaveClient` (Task 4), `ThreadStreamClient.streamMessage`/`ThreadStreamEvent` (Task 5), `ChatMessage`/`ModelInfo` (Task 3).
- Produces: `@MainActor @Observable public final class ThreadViewModel { public let conversationId: Int; public var messages: [ChatMessage]; public var availableModels: [ModelInfo]; public var selectedModel: String; public var streaming: Bool; public var errorMessage: String?; func loadHistory() async; func send(content: String) async }`; `public struct ThreadView: View`. Task 9's `ContentView` instantiates `ThreadViewModel` and hosts `ThreadView` when a conversation's mode resolves to thread (per Task 9's mode-detection rule).

- [ ] **Step 1: Write the failing view-model tests**

Follows Scriptorium's `ChatPaneViewModelTests` pattern exactly (same `MockURLProtocol` from Task 4, same error-surfacing contract).

```swift
import XCTest
@testable import Conclave

final class ThreadViewModelTests: XCTestCase {
    func makeSession(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testLoadHistoryPopulatesMessages() async throws {
        let session = makeSession { request in
            let json = """
            [{"id":1,"conversation_id":1,"role":"user","content":"hi","model":null,
              "truncated":0,"chairman_group_id":null,"is_synthesis":0,"created_at":"2026-01-01T00:00:00Z"}]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: session)
        let viewModel = ThreadViewModel(client: client, streamBaseURL: URL(string: "http://unused:8090")!, conversationId: 1)
        await viewModel.loadHistory()
        XCTAssertEqual(viewModel.messages.count, 1)
    }

    func testLoadHistoryFailureSurfacesErrorMessage() async throws {
        let session = makeSession { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: session)
        let viewModel = ThreadViewModel(client: client, streamBaseURL: URL(string: "http://unused:8090")!, conversationId: 1)
        await viewModel.loadHistory()
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
```

Copy to the Mac: `scp ThreadViewModelTests.swift mac:~/Developer/Conclave/Tests/ConclaveTests/ThreadViewModelTests.swift`

- [ ] **Step 2: Run tests to verify they fail**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: FAIL — `ThreadViewModel` doesn't exist.

- [ ] **Step 3: Implement `ThreadViewModel`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class ThreadViewModel {
    private let client: ConclaveClient
    private let streamBaseURL: URL
    private let streamSession: URLSession
    public let conversationId: Int

    public var messages: [ChatMessage] = []
    public var availableModels: [ModelInfo] = []
    public var selectedModel: String = ""
    public var streaming: Bool = false
    public var errorMessage: String?

    public init(client: ConclaveClient, streamBaseURL: URL, streamSession: URLSession = .shared, conversationId: Int) {
        self.client = client
        self.streamBaseURL = streamBaseURL
        self.streamSession = streamSession
        self.conversationId = conversationId
    }

    public func loadHistory() async {
        do {
            messages = try await client.fetchMessages(conversationId: conversationId)
            availableModels = try await client.fetchModels()
            if let lastModel = messages.last(where: { $0.model != nil })?.model {
                selectedModel = lastModel
            } else if let firstModel = availableModels.first?.id {
                selectedModel = firstModel
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func send(content: String) async {
        errorMessage = nil
        streaming = true
        defer { streaming = false }
        do {
            if !selectedModel.isEmpty {
                _ = try await client.updateConversationModel(id: conversationId, model: selectedModel)
            }
            let stream = ThreadStreamClient.streamMessage(
                baseURL: streamBaseURL, conversationId: conversationId,
                content: content, model: selectedModel, session: streamSession
            )
            for try await event in stream {
                if case .done = event { break }
                if case .error(let message) = event { errorMessage = message }
            }
            messages = try await client.fetchMessages(conversationId: conversationId)
        } catch {
            errorMessage = error.localizedDescription
            messages = (try? await client.fetchMessages(conversationId: conversationId)) ?? messages
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: PASS, 2/2 new tests.

- [ ] **Step 5: Implement `ThreadView`**

```swift
import SwiftUI

public struct ThreadView: View {
    let viewModel: ThreadViewModel
    @State private var draft = ""

    public init(viewModel: ThreadViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                // `GlassEffectContainer` wraps every glassEffect call in
                // this list — see Global Constraints: an unwrapped
                // glassEffect produced a 786pt-tall, 633pt-off-screen
                // bubble in Scriptorium.
                GlassEffectContainer(spacing: 12) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            bubble(for: message)
                        }
                    }
                    .padding()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }

            composer
        }
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        let isUser = message.role == "user"
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            if let model = message.model {
                Text(model).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassEffect(.regular.tint(isUser ? .blue : .green), in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 8) {
                if !viewModel.availableModels.isEmpty {
                    Picker("Model", selection: Binding(
                        get: { viewModel.selectedModel },
                        set: { viewModel.selectedModel = $0 }
                    )) {
                        ForEach(viewModel.availableModels) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack(spacing: 10) {
                    TextField("Message…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                        .disabled(viewModel.streaming)

                    Button {
                        let content = draft
                        draft = ""
                        Task { await viewModel.send(content: content) }
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(viewModel.streaming || draft.isEmpty)
                }
            }
            .padding(12)
        }
    }
}
```

- [ ] **Step 6: Build to confirm the view compiles**

Run: `ssh mac 'cd ~/Developer/Conclave && swift build 2>&1 | tail -40'`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git add -A && git commit -m "[conclave] Add ThreadViewModel and ThreadView"'
```

---

## Task 8: ChairmanViewModel and ChairmanView

**Files:**
- Create: `~/Developer/Conclave/Sources/Conclave/UI/ChairmanViewModel.swift`
- Create: `~/Developer/Conclave/Sources/Conclave/UI/ChairmanView.swift`
- Create: `~/Developer/Conclave/Tests/ConclaveTests/ChairmanViewModelTests.swift`

**Interfaces:**
- Consumes: `ConclaveClient` (Task 4), `ChairmanStreamClient.streamChairmanMessage`/`ChairmanStreamEvent` (Task 6), `ModelInfo` (Task 3).
- Produces: `@MainActor @Observable public final class ChairmanViewModel { public let conversationId: Int; public var participantModels: [String]; public var chairmanModel: String; public var participantResponses: [String: String]; public var participantErrors: [String: String]; public var synthesis: String; public var synthesisError: String?; public var streaming: Bool; func send(prompt: String) async }`; `public struct ChairmanView: View`. Task 9's `ContentView` instantiates `ChairmanViewModel` and hosts `ChairmanView` when a conversation's mode resolves to chairman.

- [ ] **Step 1: Write the failing view-model test**

This test drives the view model directly against `ChairmanStreamEvent` cases rather than through a mocked HTTP layer, since the streaming path's per-event state transitions are the thing worth unit-testing here — the HTTP-request-shaping itself was already covered by Task 6's `ChairmanStreamClientTests`. Structure `send(prompt:)` so its core event-handling loop is a plain synchronous function `apply(_ event: ChairmanStreamEvent)` that both the real streaming path and this test call directly:

```swift
import XCTest
@testable import Conclave

final class ChairmanViewModelTests: XCTestCase {
    func testApplyingEventsAccumulatesParticipantAndSynthesisState() {
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!)
        let viewModel = ChairmanViewModel(
            client: client, streamBaseURL: URL(string: "http://unused:8090")!, conversationId: 1,
            participantModels: ["qwen2.5-7b", "qwen2.5-14b"], chairmanModel: "qwen2.5-32b"
        )

        viewModel.apply(.participantToken(model: "qwen2.5-7b", token: "A"))
        viewModel.apply(.participantToken(model: "qwen2.5-7b", token: "B"))
        viewModel.apply(.participantError(model: "qwen2.5-14b", message: "timed out"))
        viewModel.apply(.chairmanToken("synth"))
        viewModel.apply(.chairmanDone)

        XCTAssertEqual(viewModel.participantResponses["qwen2.5-7b"], "AB")
        XCTAssertEqual(viewModel.participantErrors["qwen2.5-14b"], "timed out")
        XCTAssertEqual(viewModel.synthesis, "synth")
        XCTAssertFalse(viewModel.streaming)
    }

    func testChairmanErrorSurfacesSeparatelyFromParticipantErrors() {
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!)
        let viewModel = ChairmanViewModel(
            client: client, streamBaseURL: URL(string: "http://unused:8090")!, conversationId: 1,
            participantModels: ["qwen2.5-7b"], chairmanModel: "qwen2.5-32b"
        )
        viewModel.apply(.participantError(model: "qwen2.5-7b", message: "boom"))
        viewModel.apply(.chairmanError("all participants failed"))
        XCTAssertEqual(viewModel.synthesisError, "all participants failed")
        XCTAssertTrue(viewModel.synthesis.isEmpty)
    }
}
```

Copy to the Mac: `scp ChairmanViewModelTests.swift mac:~/Developer/Conclave/Tests/ConclaveTests/ChairmanViewModelTests.swift`

- [ ] **Step 2: Run tests to verify they fail**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: FAIL — `ChairmanViewModel` doesn't exist.

- [ ] **Step 3: Implement `ChairmanViewModel`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class ChairmanViewModel {
    private let client: ConclaveClient
    private let streamBaseURL: URL
    private let streamSession: URLSession
    public let conversationId: Int
    public let participantModels: [String]
    public let chairmanModel: String

    public var participantResponses: [String: String] = [:]
    public var participantErrors: [String: String] = [:]
    public var synthesis: String = ""
    public var synthesisError: String?
    public var streaming: Bool = false

    public init(
        client: ConclaveClient, streamBaseURL: URL, streamSession: URLSession = .shared,
        conversationId: Int, participantModels: [String], chairmanModel: String
    ) {
        self.client = client
        self.streamBaseURL = streamBaseURL
        self.streamSession = streamSession
        self.conversationId = conversationId
        self.participantModels = participantModels
        self.chairmanModel = chairmanModel
    }

    /// Applies one parsed `ChairmanStreamEvent` to view-model state. Kept
    /// as a plain synchronous method (rather than inlined into `send`'s
    /// async loop) so `ChairmanViewModelTests` can drive state transitions
    /// directly without mocking the HTTP layer a second time — Task 6's
    /// `ChairmanStreamClientTests` already covers wire-format parsing.
    func apply(_ event: ChairmanStreamEvent) {
        switch event {
        case .participantToken(let model, let token):
            participantResponses[model, default: ""] += token
        case .participantError(let model, let message):
            participantErrors[model] = message
        case .participantDone:
            break
        case .chairmanToken(let token):
            synthesis += token
        case .chairmanError(let message):
            synthesisError = message
        case .chairmanDone:
            streaming = false
        }
    }

    public func send(prompt: String) async {
        participantResponses = [:]
        participantErrors = [:]
        synthesis = ""
        synthesisError = nil
        streaming = true
        do {
            let stream = ChairmanStreamClient.streamChairmanMessage(
                baseURL: streamBaseURL, conversationId: conversationId, prompt: prompt,
                participantModels: participantModels, chairmanModel: chairmanModel, session: streamSession
            )
            for try await event in stream {
                apply(event)
            }
        } catch {
            synthesisError = error.localizedDescription
        }
        streaming = false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: PASS, 2/2 new tests.

- [ ] **Step 5: Implement `ChairmanView`**

```swift
import SwiftUI

public struct ChairmanView: View {
    let viewModel: ChairmanViewModel
    @State private var draft = ""

    public init(viewModel: ChairmanViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                GlassEffectContainer(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.participantModels, id: \.self) { model in
                            participantCard(model: model)
                        }
                        if !viewModel.synthesis.isEmpty || viewModel.synthesisError != nil {
                            synthesisCard
                        }
                    }
                    .padding()
                }
            }
            composer
        }
    }

    @ViewBuilder
    private func participantCard(model: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let error = viewModel.participantErrors[model] {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text(viewModel.participantResponses[model] ?? "…")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    private var synthesisCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Synthesis · \(viewModel.chairmanModel)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let error = viewModel.synthesisError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text(viewModel.synthesis).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular.tint(.orange), in: RoundedRectangle(cornerRadius: 14))
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Prompt for all \(viewModel.participantModels.count) models…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    .disabled(viewModel.streaming)

                Button {
                    let prompt = draft
                    draft = ""
                    Task { await viewModel.send(prompt: prompt) }
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .disabled(viewModel.streaming || draft.isEmpty)
            }
            .padding(12)
        }
    }
}
```

- [ ] **Step 6: Build to confirm the view compiles**

Run: `ssh mac 'cd ~/Developer/Conclave && swift build 2>&1 | tail -40'`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git add -A && git commit -m "[conclave] Add ChairmanViewModel and ChairmanView"'
```

---

## Task 9: ConversationListView, mode detection, and ContentView routing

**Files:**
- Create: `~/Developer/Conclave/Sources/Conclave/UI/ConversationListViewModel.swift`
- Create: `~/Developer/Conclave/Sources/Conclave/UI/ConversationListView.swift`
- Create: `~/Developer/Conclave/Sources/Conclave/UI/NewConversationSheet.swift`
- Create: `~/Developer/Conclave/Sources/Conclave/UI/ContentView.swift`
- Create: `~/Developer/Conclave/Tests/ConclaveTests/ConversationListViewModelTests.swift`

**Interfaces:**
- Consumes: `ConclaveClient` (Task 4), `Conversation`/`ChatMessage`/`ModelInfo` (Task 3), `ThreadViewModel`/`ThreadView` (Task 7), `ChairmanViewModel`/`ChairmanView` (Task 8).
- Produces: `@MainActor @Observable public final class ConversationListViewModel { public var conversations: [Conversation]; public var models: [ModelInfo]; public var selectedConversationId: Int?; public var errorMessage: String?; func loadConversations() async; func createThreadConversation() async; func createChairmanConversation(participantModels: [String], chairmanModel: String) async; func mode(for conversationId: Int) async -> ConversationMode }`; `public enum ConversationMode: Equatable, Sendable { case thread, chairman(participantModels: [String], chairmanModel: String) }`; `public struct ContentView: View`. Task 10's app shell wraps `ContentView` as the app's single window.

Mode detection (per the spec's open question, resolved here): a conversation's mode is not stored on the `conversations` row — it's derived by fetching that conversation's messages and checking whether any has a non-null `chairman_group_id` (Task 1/3's field). An empty new conversation's mode is instead known immediately from *how* it was created (`createThreadConversation` vs. `createChairmanConversation`), tracked client-side in `ConversationListViewModel.pendingModes` until the first message round-trip makes it derivable from the messages themselves.

- [ ] **Step 1: Write the failing view-model tests**

```swift
import XCTest
@testable import Conclave

final class ConversationListViewModelTests: XCTestCase {
    func makeSession(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testModeIsThreadWhenNoMessageHasAChairmanGroup() async {
        let session = makeSession { request in
            let json = """
            [{"id":1,"conversation_id":5,"role":"user","content":"hi","model":null,
              "truncated":0,"chairman_group_id":null,"is_synthesis":0,"created_at":"2026-01-01T00:00:00Z"}]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: session)
        let viewModel = ConversationListViewModel(client: client)
        let mode = await viewModel.mode(for: 5)
        XCTAssertEqual(mode, .thread)
    }

    func testModeIsChairmanWhenAMessageHasAChairmanGroup() async {
        let session = makeSession { request in
            let json = """
            [{"id":1,"conversation_id":5,"role":"assistant","content":"a","model":"qwen2.5-7b",
              "truncated":0,"chairman_group_id":"g1","is_synthesis":0,"created_at":"2026-01-01T00:00:00Z"},
             {"id":2,"conversation_id":5,"role":"assistant","content":"synth","model":"qwen2.5-32b",
              "truncated":0,"chairman_group_id":"g1","is_synthesis":1,"created_at":"2026-01-01T00:00:00Z"}]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: session)
        let viewModel = ConversationListViewModel(client: client)
        let mode = await viewModel.mode(for: 5)
        XCTAssertEqual(mode, .chairman(participantModels: ["qwen2.5-7b"], chairmanModel: "qwen2.5-32b"))
    }

    func testPendingModeIsUsedForAFreshlyCreatedConversationBeforeAnyMessages() async {
        let session = makeSession { request in
            if request.httpMethod == "POST" {
                let json = #"{"id":9,"title":"New","model":"qwen2.5-14b","created_at":"2026-01-01T00:00:00Z"}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            let json = "[]".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let client = ConclaveClient(baseURL: URL(string: "http://unused:8090")!, session: session)
        let viewModel = ConversationListViewModel(client: client)
        await viewModel.createChairmanConversation(participantModels: ["a", "b"], chairmanModel: "c")
        let mode = await viewModel.mode(for: 9)
        XCTAssertEqual(mode, .chairman(participantModels: ["a", "b"], chairmanModel: "c"))
    }
}
```

Copy to the Mac: `scp ConversationListViewModelTests.swift mac:~/Developer/Conclave/Tests/ConclaveTests/ConversationListViewModelTests.swift`

- [ ] **Step 2: Run tests to verify they fail**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: FAIL — `ConversationListViewModel`/`ConversationMode` don't exist.

- [ ] **Step 3: Implement `ConversationListViewModel`**

```swift
import Foundation
import Observation

public enum ConversationMode: Equatable, Sendable {
    case thread
    case chairman(participantModels: [String], chairmanModel: String)
}

@MainActor
@Observable
public final class ConversationListViewModel {
    public let client: ConclaveClient

    public var conversations: [Conversation] = []
    public var models: [ModelInfo] = []
    public var selectedConversationId: Int?
    public var errorMessage: String?

    /// Modes for conversations created this session but not yet loaded
    /// from `mode(for:)`'s message-derived path — see Task 9's mode
    /// detection note. Cleared implicitly once messages exist server-side
    /// (mode(for:) always checks messages first).
    private var pendingModes: [Int: ConversationMode] = [:]

    public init(client: ConclaveClient) {
        self.client = client
    }

    public func loadConversations() async {
        do {
            async let fetchedConversations = client.fetchConversations()
            async let fetchedModels = client.fetchModels()
            let (conversationsResult, modelsResult) = try await (fetchedConversations, fetchedModels)
            conversations = conversationsResult
            models = modelsResult
            if selectedConversationId == nil {
                selectedConversationId = conversations.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createThreadConversation() async {
        let modelId = models.first?.id ?? "default"
        do {
            let conversation = try await client.createConversation(title: "New thread", model: modelId)
            conversations.insert(conversation, at: 0)
            pendingModes[conversation.id] = .thread
            selectedConversationId = conversation.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createChairmanConversation(participantModels: [String], chairmanModel: String) async {
        do {
            let conversation = try await client.createConversation(title: "New chairman run", model: chairmanModel)
            conversations.insert(conversation, at: 0)
            pendingModes[conversation.id] = .chairman(participantModels: participantModels, chairmanModel: chairmanModel)
            selectedConversationId = conversation.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func mode(for conversationId: Int) async -> ConversationMode {
        guard let messages = try? await client.fetchMessages(conversationId: conversationId) else {
            return pendingModes[conversationId] ?? .thread
        }
        let grouped = messages.filter { $0.chairman_group_id != nil }
        guard !grouped.isEmpty else {
            return pendingModes[conversationId] ?? .thread
        }
        let participantModels = grouped.filter { $0.is_synthesis == 0 }.compactMap(\.model)
        let chairmanModel = grouped.first { $0.is_synthesis == 1 }?.model ?? ""
        return .chairman(participantModels: participantModels, chairmanModel: chairmanModel)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -30'`
Expected: PASS, 3/3 new tests.

- [ ] **Step 5: Implement `ConversationListView`, `NewConversationSheet`, and `ContentView`**

```swift
import SwiftUI

public struct ConversationListView: View {
    let conversations: [Conversation]
    @Binding var selectedId: Int?

    public init(conversations: [Conversation], selectedId: Binding<Int?>) {
        self.conversations = conversations
        self._selectedId = selectedId
    }

    public var body: some View {
        List(conversations, selection: $selectedId) { conversation in
            VStack(alignment: .leading) {
                Text(conversation.title)
                Text(conversation.model).font(.caption).foregroundStyle(.secondary)
            }
            .tag(conversation.id)
        }
    }
}
```

```swift
import SwiftUI

public struct NewConversationSheet: View {
    let availableModels: [ModelInfo]
    let onCreateThread: () -> Void
    let onCreateChairman: ([String], String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .thread
    @State private var selectedParticipants: Set<String> = []
    @State private var chairmanModel: String = ""

    enum Mode: String, CaseIterable { case thread = "Thread", chairman = "Chairman" }

    public init(
        availableModels: [ModelInfo],
        onCreateThread: @escaping () -> Void,
        onCreateChairman: @escaping ([String], String) -> Void
    ) {
        self.availableModels = availableModels
        self.onCreateThread = onCreateThread
        self.onCreateChairman = onCreateChairman
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if mode == .chairman {
                Text("Participant models").font(.caption).foregroundStyle(.secondary)
                ForEach(availableModels) { model in
                    Toggle(model.id, isOn: Binding(
                        get: { selectedParticipants.contains(model.id) },
                        set: { isOn in
                            if isOn { selectedParticipants.insert(model.id) } else { selectedParticipants.remove(model.id) }
                        }
                    ))
                }
                Picker("Chairman model", selection: $chairmanModel) {
                    ForEach(availableModels) { Text($0.id).tag($0.id) }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    if mode == .thread {
                        onCreateThread()
                    } else {
                        onCreateChairman(Array(selectedParticipants), chairmanModel)
                    }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(mode == .chairman && (selectedParticipants.isEmpty || chairmanModel.isEmpty))
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}
```

```swift
import SwiftUI

public struct ContentView: View {
    @State private var listViewModel: ConversationListViewModel
    @State private var mode: ConversationMode = .thread
    @State private var threadViewModel: ThreadViewModel?
    @State private var chairmanViewModel: ChairmanViewModel?
    @State private var showingNewConversationSheet = false
    let baseURL: URL

    public init(baseURL: URL = URL(string: "http://gpu-chat.tail21cbc4.ts.net:8090")!) {
        self.baseURL = baseURL
        let client = ConclaveClient(baseURL: baseURL)
        self._listViewModel = State(initialValue: ConversationListViewModel(client: client))
    }

    public var body: some View {
        NavigationSplitView {
            ConversationListView(
                conversations: listViewModel.conversations,
                selectedId: Binding(
                    get: { listViewModel.selectedConversationId },
                    set: { listViewModel.selectedConversationId = $0 }
                )
            )
            .toolbar {
                ToolbarItem {
                    Button("New") { showingNewConversationSheet = true }
                }
            }
        } detail: {
            if let threadViewModel {
                ThreadView(viewModel: threadViewModel)
            } else if let chairmanViewModel {
                ChairmanView(viewModel: chairmanViewModel)
            } else {
                Text("Select or create a conversation.").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingNewConversationSheet) {
            NewConversationSheet(
                availableModels: listViewModel.models,
                onCreateThread: { Task { await listViewModel.createThreadConversation() } },
                onCreateChairman: { participants, chairman in
                    Task { await listViewModel.createChairmanConversation(participantModels: participants, chairmanModel: chairman) }
                }
            )
        }
        .task { await listViewModel.loadConversations() }
        .task(id: listViewModel.selectedConversationId) {
            threadViewModel = nil
            chairmanViewModel = nil
            guard let id = listViewModel.selectedConversationId else { return }
            switch await listViewModel.mode(for: id) {
            case .thread:
                let viewModel = ThreadViewModel(client: listViewModel.client, streamBaseURL: baseURL, conversationId: id)
                threadViewModel = viewModel
                await viewModel.loadHistory()
            case .chairman(let participants, let chairman):
                chairmanViewModel = ChairmanViewModel(
                    client: listViewModel.client, streamBaseURL: baseURL, conversationId: id,
                    participantModels: participants, chairmanModel: chairman
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 6: Build to confirm everything compiles**

Run: `ssh mac 'cd ~/Developer/Conclave && swift build 2>&1 | tail -40'`
Expected: `Build complete!`

- [ ] **Step 7: Run the full test suite**

Run: `ssh mac 'cd ~/Developer/Conclave && swift test 2>&1 | tail -20'`
Expected: PASS, all tests from Tasks 3–9 green.

- [ ] **Step 8: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git add -A && git commit -m "[conclave] Add ConversationListView, NewConversationSheet, ContentView routing"'
```

---

## Task 10: Xcode app shell and manual verification

**Files:**
- Create: `~/Developer/Conclave/App/project.yml`
- Create: `~/Developer/Conclave/App/Sources/App/ConclaveApp.swift`

**Interfaces:**
- Consumes: `ContentView` (Task 9).
- Produces: a buildable, launchable macOS app (`dev.sounio.conclave`), verified by hand per Step 4 below.

- [ ] **Step 1: Write `project.yml`**

Following the exact structure already proven for Scriptorium — `info.properties` (not `GENERATE_INFOPLIST_FILE`) so the ATS exception ships correctly:

```yaml
name: ConclaveApp
options:
  bundleIdPrefix: dev.sounio
packages:
  Conclave:
    path: ..
targets:
  ConclaveApp:
    type: application
    platform: macOS
    deploymentTarget: "26.0"
    sources:
      - Sources/App
    dependencies:
      - package: Conclave
    info:
      path: Sources/App/Info.plist
      properties:
        CFBundleDisplayName: Conclave
        NSHumanReadableCopyright: ""
        NSAppTransportSecurity:
          NSExceptionDomains:
            tail21cbc4.ts.net:
              NSIncludesSubdomains: true
              NSExceptionAllowsInsecureHTTPLoads: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.sounio.conclave
        MARKETING_VERSION: "0.1"
        CURRENT_PROJECT_VERSION: "1"
```

Copy to the Mac: `scp project.yml mac:~/Developer/Conclave/App/project.yml`

- [ ] **Step 2: Write `ConclaveApp.swift`**

```swift
import SwiftUI
import Conclave

@main
struct ConclaveAppMain: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
```

Copy to the Mac: `scp ConclaveApp.swift mac:~/Developer/Conclave/App/Sources/App/ConclaveApp.swift`

- [ ] **Step 3: Generate the Xcode project and build**

```bash
ssh mac 'which xcodegen || echo "xcodegen not on PATH — use /opt/homebrew/bin/xcodegen instead, per Scriptorium precedent"'
ssh mac 'cd ~/Developer/Conclave/App && /opt/homebrew/bin/xcodegen generate 2>&1 | tail -10'
ssh mac 'cd ~/Developer/Conclave/App && xcodebuild -project ConclaveApp.xcodeproj -scheme ConclaveApp -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -40'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Launch and manually verify**

```bash
ssh mac 'rm -rf "$HOME/Library/Saved Application State/dev.sounio.conclave.savedState" 2>&1
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -iname "ConclaveApp-*" | head -1)/Build/Products/Debug/ConclaveApp.app
open "$APP"'
```

Then, with the user's own eyes (this Linux session cannot capture the Mac's screen — see Scriptorium's precedent where `screencapture` over SSH failed with "could not create image from display" due to no Screen Recording TCC permission on the SSH session):

1. Confirm the window opens at roughly 1440×900, not a small/stale size (clear Saved Application State per Global Constraints if it looks wrong).
2. Create a new **Thread** conversation, pick a model, send a message, confirm a real response streams in and the model badge shows on the assistant bubble.
3. Switch the model mid-conversation, send another message, confirm the new message's badge shows the new model and prior messages keep their original badges.
4. Create a new **Chairman** conversation with 2+ participant models and a chairman model, send a prompt, confirm each participant's card fills in independently and a synthesis card appears after they finish.
5. Deliberately test a participant failure path if possible (e.g. pick a model ID that doesn't exist) and confirm that participant's card shows an error without blocking the others or the synthesis.

- [ ] **Step 5: Commit**

```bash
ssh mac 'cd ~/Developer/Conclave && git add -A && git commit -m "[conclave] Add xcodegen app shell"'
```

---

## Self-Review Notes

**Spec coverage:**
- Thread mode (conversation list, model-switching composer, message list with model badges) — Tasks 3–7, 9.
- Chairman mode backend route + schema extension — Tasks 1–2.
- Chairman mode UI (participant cards + synthesis card) — Task 8.
- No schema changes for thread mode — confirmed: Task 1 only touches `messages`, and thread mode's existing `POST /api/conversations/:id/messages` route (Task 1's "Consumes" context) is unchanged.
- Concrete SSE event framing decision — made in Task 2 (`event: participant:<model>` / `event: chairman`), consumed by Task 6.
- Concrete schema-migration approach — made in Task 1 (`PRAGMA table_info` + conditional `ALTER TABLE ADD COLUMN`), idempotent across repeated `openDb` calls on the same handle.
- Repo location — `~/Developer/Conclave`, set in Task 3 Step 1 and used throughout.
- Deferred per spec (explicitly not in this plan): iOS port, chairman-mode retry-single-participant polish, global-hotkey overlay.

**Placeholder scan:** no "TBD"/"add error handling"/"similar to Task N" patterns — every step has real code or a real command.

**Type consistency:** `ChatMessage.chairman_group_id`/`is_synthesis` (Task 3) match the backend's `Message.chairman_group_id`/`is_synthesis` (Task 1) in name and nullability; `ConversationMode` (Task 9) is produced and consumed only within Task 9; `ThreadViewModel`/`ChairmanViewModel` constructor signatures used in Task 9's `ContentView` match their definitions in Tasks 7 and 8 exactly (`client:`, `streamBaseURL:`, `conversationId:`, plus Task 8's `participantModels:`/`chairmanModel:`).
