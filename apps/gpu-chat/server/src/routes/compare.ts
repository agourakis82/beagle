import { FastifyInstance } from 'fastify'
import Database from 'better-sqlite3'
import { streamChatCompletion, ChatMessage } from '../litellm-client.js'
import { createConversation, addMessage } from '../db.js'

export function registerCompareRoutes(app: FastifyInstance, db: Database.Database, litellmBaseUrl: string): void {
  app.post<{ Body: { prompt: string; models: string[] } }>('/api/compare', async (req, reply) => {
    const { prompt, models } = req.body
    const messages: ChatMessage[] = [{ role: 'user', content: prompt }]

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    })

    await Promise.all(
      models.map(async (model) => {
        try {
          for await (const token of streamChatCompletion(litellmBaseUrl, model, messages)) {
            reply.raw.write(`event: ${model}\ndata: ${JSON.stringify(token)}\n\n`)
          }
        } catch {
          // upstream error for this model surfaces as an early [DONE]; the UI marks it incomplete
        }
        reply.raw.write(`event: ${model}\ndata: [DONE]\n\n`)
      }),
    )

    reply.raw.end()
    return reply
  })

  app.post<{
    Body: { prompt: string; results: Array<{ model: string; response: string }> }
  }>('/api/compare/save', async (req) => {
    const { prompt, results } = req.body
    const conversationIds = results.map(({ model, response }) => {
      const conv = createConversation(db, `Compare: ${model}`, model)
      addMessage(db, conv.id, 'user', prompt, null)
      addMessage(db, conv.id, 'assistant', response, model)
      return conv.id
    })
    return { conversationIds }
  })
}
