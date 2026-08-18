# GPU Chat — Design Spec

**Date:** 2026-08-18
**Status:** Approved for implementation
**Location:** `apps/gpu-chat/` (new app, beagle monorepo)
**Branch:** `feature/gpu-chat`

## Purpose

A standalone web app for chatting with the LLMs already served on the user's own GPUs
(vLLM on r770, Ollama on DGX Spark, and whatever else is registered behind the LiteLLM
router at `:4000/v1`). Independent of the Companion app and the Loom/cockpit — a focused
work tool, not a platform feature.

## Non-goals

- No multi-user auth. Single operator, tailnet-only exposure — same trust model as the
  rest of the internal tooling.
- No RAG / vector search over attachments. Attachments are pasted/uploaded verbatim as
  context blocks in the prompt, nothing more.
- Not a replacement for the Companion's biography/emotion features — no persona, no
  memory-pg integration.

## Architecture

Single container, two logical halves:

- **Backend** — Fastify (TypeScript). Talks to the LiteLLM router for chat completions
  and model listing. Persists conversations/messages/attachments/templates in SQLite
  (`better-sqlite3`), file-backed on a small PVC.
- **Frontend** — React + Vite, built to static assets and served by the same Fastify
  process in production (no separate frontend server/container).

```
Browser ── HTTP/SSE ── Fastify (apps/gpu-chat) ── HTTP ── LiteLLM router (:4000/v1)
                              │
                          SQLite (PVC)
```

LiteLLM already aggregates vLLM (r770), Ollama (DGX Spark `.24`), and any other
registered backend behind one OpenAI-compatible API — gpu-chat only ever talks to that
one endpoint, never to vLLM/Ollama directly. This keeps the app ignorant of cluster
topology; adding/removing a GPU backend is a LiteLLM config change, not a gpu-chat change.

## Data model (SQLite)

```sql
conversations(id, title, model, created_at)
messages(id, conversation_id, role, content, model, truncated, created_at)
attachments(id, message_id, filename, content, mime_type, created_at)
prompt_templates(id, name, system_prompt, created_at)
```

- `messages.model` records which model actually produced an assistant message (matters
  once conversations can switch models mid-thread).
- `messages.truncated` flags a message whose stream ended early due to an upstream error.

## Backend components (`apps/gpu-chat/server/`)

- `db.ts` — schema init + typed query helpers.
- `litellm-client.ts` — thin `fetch` wrapper for `POST /v1/chat/completions`
  (`stream: true`) and `GET /v1/models`. Propagates upstream errors as-is; no retry,
  no fallback model substitution — if LiteLLM or the backend behind it is down, the
  caller sees that directly.
- `routes/chat.ts` — `POST /api/conversations/:id/messages`: opens an SSE response,
  forwards LiteLLM's stream token-by-token, writes the assembled message to SQLite when
  the stream ends (or marks `truncated` if it errors mid-stream).
- `routes/compare.ts` — `POST /api/compare`: takes a prompt + list of models, fans out
  parallel streams (one SSE event stream per model, tagged by model name). Ephemeral by
  default — only persisted if the user explicitly saves the comparison, in which case it
  writes one `conversations` row per model with the shared prompt as the first message.
- `routes/templates.ts` — CRUD over `prompt_templates`.
- `routes/models.ts` — `GET /api/models`, short-TTL in-memory cache (30s) wrapping
  LiteLLM's `/v1/models` so the dropdown doesn't hammer the router on every render.

## Frontend components (`apps/gpu-chat/web/`)

- Sidebar: conversation list (title, model, last-updated).
- Chat view: message list rendered via `react-markdown` + `rehype-highlight`
  (code blocks with copy-to-clipboard), per-conversation model dropdown sourced from
  `GET /api/models`.
- Compare view: N-column layout, one model per column, shared prompt input, streams
  render independently per column; a "save as conversations" action persists it.
- Attachment panel: paste text/code or upload a small file (text/PDF-with-extracted-text);
  becomes a context block attached to the next outgoing message. No size limit enforced
  in-app beyond what the model's context window can take — oversized attachments surface
  the model's own context-length error rather than being pre-truncated silently.
- Template library: save/apply a named system prompt when starting a new conversation.

## Error handling

- Upstream (LiteLLM/backend) failure surfaces verbatim in the UI — no silent fallback,
  no invented assistant reply.
- A stream that fails mid-response keeps whatever tokens arrived, saved with
  `truncated = true`, and the UI marks it visually as incomplete.
- Attachment content that would overflow the model's context is not pre-checked; the
  resulting API error from LiteLLM is shown as-is.

## Testing

- Backend unit tests (in-memory SQLite) for conversation/message/template CRUD routes.
- One integration test that mocks the LiteLLM HTTP endpoint (a local test server
  returning a canned SSE stream) to verify `routes/chat.ts` end-to-end: request →
  streamed tokens → persisted message.
- No frontend test suite for v1 — manual verification (start dev server, drive the
  golden path in a browser) per project convention for UI changes.

## Deployment

- Built as one container image (multi-stage: Vite build → copy static assets into the
  Fastify image).
- K8s Deployment + Service in `apps/gpu-chat` (manifest to be added alongside the app
  code, following the pattern of other beagle apps' `k8s/` manifests).
- SQLite file lives on a small PVC (single replica — SQLite is not safe for concurrent
  writers across pods, and this app has none of the multi-replica requirements the rest
  of the platform has).
- Reachable over the tailnet like the rest of the internal tooling; no ingress auth
  beyond that.

## Open questions for the implementation plan

None — scope is fully bounded by the above. The implementation plan should sequence:
schema + backend routes + tests → frontend chat view → model dropdown → compare view →
attachments → templates → Dockerfile + K8s manifest.
