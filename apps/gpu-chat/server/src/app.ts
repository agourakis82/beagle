import Fastify, { FastifyInstance } from 'fastify'
import { openDb } from './db.js'
import { registerModelsRoute } from './routes/models.js'
import { registerTemplatesRoutes } from './routes/templates.js'

export interface AppConfig {
  dbPath: string
  litellmBaseUrl: string
}

export function buildApp(config: AppConfig): FastifyInstance {
  const app = Fastify({ logger: true })
  const db = openDb(config.dbPath)

  app.get('/api/health', async () => ({ ok: true }))
  registerModelsRoute(app, config.litellmBaseUrl)
  registerTemplatesRoutes(app, db)

  return app
}
