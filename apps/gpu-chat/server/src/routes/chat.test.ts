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

  it('preserves embedded newlines in a token when persisted', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockReturnValue(fakeStream(['Hello\nWorld']))
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
    expect(messages[1]).toMatchObject({ role: 'assistant', content: 'Hello\nWorld', truncated: 0 })
  })
})
