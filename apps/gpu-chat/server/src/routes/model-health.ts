import { FastifyInstance } from 'fastify'
import { listModels, probeModelHealth } from '../litellm-client.js'

const CACHE_TTL_MS = 60_000

export function registerModelHealthRoute(app: FastifyInstance, litellmBaseUrl: string): void {
  let cache: { data: Record<string, boolean>; fetchedAt: number } | null = null

  app.get('/api/models/health', async (_req, reply) => {
    const now = Date.now()
    if (cache && now - cache.fetchedAt < CACHE_TTL_MS) {
      return cache.data
    }
    let models
    try {
      models = await listModels(litellmBaseUrl)
    } catch (err) {
      reply.code(502)
      return { error: (err as Error).message }
    }
    const results = await Promise.all(
      models.map(async (m) => [m.id, await probeModelHealth(litellmBaseUrl, m.id)] as const),
    )
    const data = Object.fromEntries(results)
    cache = { data, fetchedAt: now }
    return data
  })
}
