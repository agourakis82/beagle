import { describe, it, expect, vi, afterEach } from 'vitest'
import { buildApp } from '../app.js'
import * as litellmClient from '../litellm-client.js'

afterEach(() => vi.restoreAllMocks())

async function* fakeStream(tokens: string[]) {
  for (const t of tokens) yield t
}

describe('POST /api/compare', () => {
  it('streams tagged tokens for each model', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, model) {
      yield* model === 'qwen2.5-7b' ? fakeStream(['a']) : fakeStream(['b'])
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'POST',
      url: '/api/compare',
      payload: { prompt: 'hi', models: ['qwen2.5-7b', 'qwen2.5-14b'] },
    })
    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: qwen2.5-7b\ndata: a')
    expect(res.body).toContain('event: qwen2.5-14b\ndata: b')
  })

  it('still emits [DONE] for a model whose stream throws mid-way, without affecting other models', async () => {
    vi.spyOn(litellmClient, 'streamChatCompletion').mockImplementation(async function* (_url, model) {
      if (model === 'qwen2.5-7b') {
        yield 'ok'
        throw new Error('LiteLLM chat completion failed: 500')
      }
      yield* fakeStream(['b'])
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'POST',
      url: '/api/compare',
      payload: { prompt: 'hi', models: ['qwen2.5-7b', 'qwen2.5-14b'] },
    })
    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: qwen2.5-7b\ndata: ok')
    expect(res.body).toContain('event: qwen2.5-7b\ndata: [DONE]')
    expect(res.body).toContain('event: qwen2.5-14b\ndata: b')
    expect(res.body).toContain('event: qwen2.5-14b\ndata: [DONE]')
  })
})

describe('POST /api/compare/save', () => {
  it('creates one conversation per model with the shared prompt', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'POST',
      url: '/api/compare/save',
      payload: {
        prompt: 'hi',
        results: [
          { model: 'qwen2.5-7b', response: 'reply A' },
          { model: 'qwen2.5-14b', response: 'reply B' },
        ],
      },
    })
    expect(res.statusCode).toBe(200)
    const { conversationIds } = res.json()
    expect(conversationIds).toHaveLength(2)

    const listRes = await app.inject({ method: 'GET', url: '/api/conversations' })
    expect(listRes.json()).toHaveLength(2)
  })
})
