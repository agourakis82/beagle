import { describe, it, expect, vi, afterEach } from 'vitest'
import { buildApp } from '../app.js'
import * as litellmClient from '../litellm-client.js'

afterEach(() => vi.restoreAllMocks())

describe('GET /api/models', () => {
  it('returns the model list from LiteLLM', async () => {
    vi.spyOn(litellmClient, 'listModels').mockResolvedValue([{ id: 'qwen2.5-7b' }])
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({ method: 'GET', url: '/api/models' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual([{ id: 'qwen2.5-7b' }])
  })

  it('returns 502 when LiteLLM is unreachable', async () => {
    vi.spyOn(litellmClient, 'listModels').mockRejectedValue(new Error('LiteLLM /v1/models failed: 503'))
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({ method: 'GET', url: '/api/models' })
    expect(res.statusCode).toBe(502)
    expect(res.json()).toEqual({ error: 'LiteLLM /v1/models failed: 503' })
  })

  it('caches results for 30s (does not call listModels twice within the window)', async () => {
    const spy = vi.spyOn(litellmClient, 'listModels').mockResolvedValue([{ id: 'qwen2.5-7b' }])
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    await app.inject({ method: 'GET', url: '/api/models' })
    await app.inject({ method: 'GET', url: '/api/models' })
    expect(spy).toHaveBeenCalledTimes(1)
  })
})
