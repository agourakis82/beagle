import { describe, it, expect, vi, afterEach } from 'vitest'
import { buildApp } from '../app.js'
import * as litellmClient from '../litellm-client.js'

afterEach(() => vi.restoreAllMocks())

describe('GET /api/models/health', () => {
  it('probes every listed model and returns a healthy/unhealthy map', async () => {
    vi.spyOn(litellmClient, 'listModels').mockResolvedValue([{ id: 'alive-model' }, { id: 'dead-model' }])
    vi.spyOn(litellmClient, 'probeModelHealth').mockImplementation(async (_url, model) => model === 'alive-model')

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({ method: 'GET', url: '/api/models/health' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ 'alive-model': true, 'dead-model': false })
  })

  it('returns 502 when the model list itself cannot be fetched', async () => {
    vi.spyOn(litellmClient, 'listModels').mockRejectedValue(new Error('LiteLLM /v1/models failed: 503'))
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({ method: 'GET', url: '/api/models/health' })
    expect(res.statusCode).toBe(502)
    expect(res.json()).toEqual({ error: 'LiteLLM /v1/models failed: 503' })
  })

  it('caches results for 60s (does not re-probe within the window)', async () => {
    vi.spyOn(litellmClient, 'listModels').mockResolvedValue([{ id: 'alive-model' }])
    const probeSpy = vi.spyOn(litellmClient, 'probeModelHealth').mockResolvedValue(true)

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    await app.inject({ method: 'GET', url: '/api/models/health' })
    await app.inject({ method: 'GET', url: '/api/models/health' })

    expect(probeSpy).toHaveBeenCalledTimes(1)
  })

  it('never runs more than 5 probes concurrently, even with many models', async () => {
    const modelCount = 20
    vi.spyOn(litellmClient, 'listModels').mockResolvedValue(
      Array.from({ length: modelCount }, (_, i) => ({ id: `model-${i}` })),
    )

    let inFlight = 0
    let maxInFlight = 0
    vi.spyOn(litellmClient, 'probeModelHealth').mockImplementation(async () => {
      inFlight += 1
      maxInFlight = Math.max(maxInFlight, inFlight)
      await new Promise((resolve) => setTimeout(resolve, 5))
      inFlight -= 1
      return true
    })

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({ method: 'GET', url: '/api/models/health' })

    expect(res.statusCode).toBe(200)
    expect(Object.keys(res.json())).toHaveLength(modelCount)
    expect(maxInFlight).toBeLessThanOrEqual(5)
  })
})
