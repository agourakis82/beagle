import { FastifyInstance } from 'fastify'
import { listModels, ModelInfo } from '../litellm-client.js'

const CACHE_TTL_MS = 30_000

export function registerModelsRoute(app: FastifyInstance, litellmBaseUrl: string): void {
  let cache: { data: ModelInfo[]; fetchedAt: number } | null = null

  app.get('/api/models', async (_req, reply) => {
    const now = Date.now()
    if (cache && now - cache.fetchedAt < CACHE_TTL_MS) {
      return cache.data
    }
    try {
      const data = await listModels(litellmBaseUrl)
      cache = { data, fetchedAt: now }
      return data
    } catch (err) {
      reply.code(502)
      return { error: (err as Error).message }
    }
  })
}
