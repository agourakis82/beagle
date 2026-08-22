import Fastify, { FastifyInstance } from 'fastify'
import fastifyStatic from '@fastify/static'
import { existsSync } from 'node:fs'
import { openDb } from './db.js'
import { registerModelsRoute } from './routes/models.js'
import { registerModelHealthRoute } from './routes/model-health.js'
import { registerTemplatesRoutes } from './routes/templates.js'
import { registerChatRoutes } from './routes/chat.js'
import { registerCompareRoutes } from './routes/compare.js'
import { registerChairmanRoutes } from './routes/chairman.js'

export interface AppConfig {
  dbPath: string
  litellmBaseUrl: string
  webDistPath?: string
}

export function buildApp(config: AppConfig): FastifyInstance {
  const app = Fastify({ logger: true })
  const db = openDb(config.dbPath)

  app.get('/api/health', async () => ({ ok: true }))
  registerModelsRoute(app, config.litellmBaseUrl)
  registerModelHealthRoute(app, config.litellmBaseUrl)
  registerTemplatesRoutes(app, db)
  registerChatRoutes(app, db, config.litellmBaseUrl)
  registerCompareRoutes(app, db, config.litellmBaseUrl)
  registerChairmanRoutes(app, db, config.litellmBaseUrl)

  if (config.webDistPath && existsSync(config.webDistPath)) {
    app.register(fastifyStatic, { root: config.webDistPath })
    app.setNotFoundHandler((req, reply) => {
      if (req.raw.url?.startsWith('/api/')) {
        reply.code(404).send({ error: 'not found' })
        return
      }
      reply.sendFile('index.html')
    })
  }

  return app
}
