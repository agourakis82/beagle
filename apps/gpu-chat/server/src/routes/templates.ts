import { FastifyInstance } from 'fastify'
import Database from 'better-sqlite3'
import { createTemplate, listTemplates, deleteTemplate } from '../db.js'

export function registerTemplatesRoutes(app: FastifyInstance, db: Database.Database): void {
  app.get('/api/templates', async () => listTemplates(db))

  app.post<{ Body: { name: string; system_prompt: string } }>('/api/templates', async (req, reply) => {
    const { name, system_prompt } = req.body
    if (!name?.trim() || !system_prompt?.trim()) {
      reply.code(400)
      return { error: 'name and system_prompt are required' }
    }
    return createTemplate(db, name, system_prompt)
  })

  app.delete<{ Params: { id: string } }>('/api/templates/:id', async (req) => {
    deleteTemplate(db, Number(req.params.id))
    return { ok: true }
  })
}
