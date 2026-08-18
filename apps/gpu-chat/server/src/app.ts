import Fastify, { FastifyInstance } from 'fastify'
import { openDb } from './db.js'
import { registerModelsRoute } from './routes/models.js'
import { registerTemplatesRoutes } from './routes/templates.js'
import { registerChatRoutes } from './routes/chat.js'
import { registerCompareRoutes } from './routes/compare.js'

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
  registerChatRoutes(app, db, config.litellmBaseUrl)
  registerCompareRoutes(app, db, config.litellmBaseUrl)

  return app
}
