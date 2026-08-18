import Fastify, { FastifyInstance } from 'fastify'

export interface AppConfig {
  dbPath: string
  litellmBaseUrl: string
}

export function buildApp(config: AppConfig): FastifyInstance {
  const app = Fastify({ logger: true })

  app.get('/api/health', async () => ({ ok: true }))

  return app
}
