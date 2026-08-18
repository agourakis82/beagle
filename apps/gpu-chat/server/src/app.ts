import Fastify, { FastifyInstance } from 'fastify'
import { registerModelsRoute } from './routes/models.js'

export interface AppConfig {
  dbPath: string
  litellmBaseUrl: string
}

export function buildApp(config: AppConfig): FastifyInstance {
  const app = Fastify({ logger: true })

  app.get('/api/health', async () => ({ ok: true }))
  registerModelsRoute(app, config.litellmBaseUrl)

  return app
}
