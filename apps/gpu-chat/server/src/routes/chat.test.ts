import { describe, it, expect, vi, afterEach } from 'vitest'
import { buildApp } from '../app.js'
import * as litellmClient from '../litellm-client.js'

afterEach(() => vi.restoreAllMocks())

async function* fakeStream(tokens: string[]) {
  for (const t of tokens) yield t
}

describe('conversation routes', () => {
  it('creates a conversation and lists it', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const createRes = await app.inject({
      method: 'POST',
      url: '/api/conversations',
      payload: { title: 'Test chat', model: 'qwen2.5-7b' },
    })
    expect(createRes.statusCode).toBe(200)
    const listRes = await app.inject({ method: 'GET', url: '/api/conversations' })
    expect(listRes.json()).toHaveLength(1)
  })
})

describe('POST /api/conversations/:id/messages', () => {
  it('streams the assistant reply and persists both messages', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockReturnValue(fakeStream(['Hel', 'lo']))
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })

    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.headers['content-type']).toContain('text/event-stream')
    expect(res.body).toContain('data: "Hel"')
    expect(res.body).toContain('data: "lo"')
    expect(res.body).toContain('data: [DONE]')

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages).toHaveLength(2)
    expect(messages[0]).toMatchObject({ role: 'user', content: 'hi there' })
    expect(messages[1]).toMatchObject({ role: 'assistant', content: 'Hello', truncated: 0 })
  })

  it('marks the assistant message truncated when the stream errors mid-way', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* () {
      yield 'Par'
      throw new Error('LiteLLM chat completion failed: 500')
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages[1]).toMatchObject({ content: 'Par', truncated: 1 })
  })

  it('frames a token with an embedded newline as a single JSON-encoded SSE line and preserves it end to end', async () => {
    const token = 'Hello\nWorld'
    vi.spyOn(litellmClient, 'streamChatCompletion').mockReturnValue(fakeStream([token]))
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })

    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    // The wire format must JSON-encode the token so the embedded \n survives as one SSE
    // "data:" line (the escaped newline is `\n` two chars, not a raw newline byte).
    expect(res.body).toContain(`data: ${JSON.stringify(token)}\n\n`)
    // The old, buggy framing wrote the raw token directly into the frame, which split it
    // across two physical SSE lines ("data: Hello" then a bare "World" line) — assert that
    // broken shape is absent so this test actually fails against the pre-fix code.
    expect(res.body).not.toContain('data: Hello\nWorld\n\n')

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages[1]).toMatchObject({ role: 'assistant', content: token, truncated: 0 })
  })

  it('injects attachment content into the upstream chat messages without mutating stored content', async () => {
    let capturedMessages: Array<{ role: string; content: string }> = []
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, _model, messages) {
      capturedMessages = messages
      yield 'ok'
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })

    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: {
        content: 'please review this',
        attachments: [{ filename: 'notes.txt', content: 'the secret is 42', mime_type: 'text/plain' }],
      },
    })

    const userMessage = capturedMessages.find((m) => m.role === 'user')
    expect(userMessage?.content).toContain('the secret is 42')
    expect(userMessage?.content).toContain('please review this')
    expect(userMessage?.content).toContain('[Attachment: notes.txt]')

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages[0]).toMatchObject({ role: 'user', content: 'please review this' })
  })

  it('sends an error SSE frame when the upstream stream fails', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* () {
      yield 'Par'
      throw new Error('LiteLLM chat completion failed: 500')
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    expect(res.body).toContain('event: error')
    expect(res.body).toContain('data: "LiteLLM chat completion failed: 500"')
  })
})

describe('PATCH /api/conversations/:id', () => {
  it('updates the conversation model', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/conversations/${conv.id}`,
      payload: { model: 'qwen2.5-14b' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ model: 'qwen2.5-14b' })

    const listRes = await app.inject({ method: 'GET', url: '/api/conversations' })
    expect(listRes.json()[0]).toMatchObject({ model: 'qwen2.5-14b' })
  })

  it('404s for an unknown conversation', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/conversations/999',
      payload: { model: 'qwen2.5-14b' },
    })
    expect(res.statusCode).toBe(404)
  })
})
