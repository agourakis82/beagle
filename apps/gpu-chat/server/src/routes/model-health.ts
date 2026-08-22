import { FastifyInstance } from 'fastify'
import { listModels, probeModelHealth } from '../litellm-client.js'

const CACHE_TTL_MS = 60_000

// Node's global fetch (undici) caps concurrent connections per origin by
// default (6). Firing one probe per model — the cluster's LiteLLM config
// currently lists ~40 — starts every AbortController timer at dispatch
// time, but most requests then sit queued behind the connection limit.
// A model whose probe queues past its own timeout aborts before it ever
// reaches the wire, producing a false "dead" even though a lone request to
// the same model completes in well under a second. Capping concurrency
// below the pool limit keeps every in-flight probe's timeout budget
// meaningful.
const PROBE_CONCURRENCY = 5

async function mapWithConcurrency<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length)
  let next = 0
  async function worker(): Promise<void> {
    while (next < items.length) {
      const index = next++
      results[index] = await fn(items[index])
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => worker()))
  return results
}

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
    const results = await mapWithConcurrency(
      models,
      PROBE_CONCURRENCY,
      async (m) => [m.id, await probeModelHealth(litellmBaseUrl, m.id)] as const,
    )
    const data = Object.fromEntries(results)
    cache = { data, fetchedAt: now }
    return data
  })
}
