import { describe, it, expect, vi, afterEach } from 'vitest'
import { buildApp } from '../app.js'
import * as litellmClient from '../litellm-client.js'

afterEach(() => vi.restoreAllMocks())

async function* fakeStream(tokens: string[]) {
  for (const t of tokens) yield t
}

async function createConversation(app: ReturnType<typeof buildApp>, title: string, model: string) {
  const res = await app.inject({
    method: 'POST',
    url: '/api/conversations',
    payload: { title, model },
  })
  return res.json()
}

async function listMessages(app: ReturnType<typeof buildApp>, conversationId: number) {
  const res = await app.inject({ method: 'GET', url: `/api/conversations/${conversationId}/messages` })
  return res.json()
}

describe('POST /api/conversations/:id/chairman-messages', () => {
  it('streams each participant then the chairman synthesis, and persists all of them grouped', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, model) {
      if (model === 'qwen2.5-7b') yield* fakeStream(['A'])
      else if (model === 'qwen2.5-14b') yield* fakeStream(['B'])
      else yield* fakeStream(['synthesis of A and B'])
    })

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = await createConversation(app, 'Chairman run', 'qwen2.5-32b')

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

    const messages = await listMessages(app, conv.id)
    const userMsg = messages.find((m: any) => m.role === 'user')
    const participantMsgs = messages.filter((m: any) => m.chairman_group_id && m.is_synthesis === 0)
    const synthesisMsg = messages.find((m: any) => m.is_synthesis === 1)

    expect(userMsg?.content).toBe('compare X and Y')
    expect(participantMsgs).toHaveLength(2)
    expect(participantMsgs.every((m: any) => m.chairman_group_id === synthesisMsg?.chairman_group_id)).toBe(true)
    expect(synthesisMsg?.model).toBe('qwen2.5-32b')
    expect(synthesisMsg?.content).toBe('synthesis of A and B')
  })

  it('synthesizes from whichever participants succeed when one participant fails', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, model) {
      if (model === 'qwen2.5-7b') throw new Error('LiteLLM chat completion failed: 500')
      if (model === 'qwen2.5-14b') yield* fakeStream(['ok reply'])
      else yield* fakeStream(['synthesis from the survivor'])
    })

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = await createConversation(app, 'Partial failure', 'qwen2.5-32b')

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

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = await createConversation(app, 'Total failure', 'qwen2.5-32b')

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/chairman-messages`,
      payload: { prompt: 'p', participantModels: ['qwen2.5-7b', 'qwen2.5-14b'], chairmanModel: 'qwen2.5-32b' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: chairman\ndata: error:')
    expect(res.body).not.toContain('event: chairman\ndata: "')

    const messages = await listMessages(app, conv.id)
    const synthesisMsg = messages.find((m: any) => m.is_synthesis === 1)
    expect(synthesisMsg).toBeUndefined()
  })

  it('returns 404 for an unknown conversation', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'POST',
      url: '/api/conversations/999/chairman-messages',
      payload: { prompt: 'p', participantModels: ['m'], chairmanModel: 'm' },
    })
    expect(res.statusCode).toBe(404)
  })
})
