import { randomUUID } from 'node:crypto'
import { FastifyInstance } from 'fastify'
import Database from 'better-sqlite3'
import { addMessage, getConversation } from '../db.js'
import { streamChatCompletion, ChatMessage } from '../litellm-client.js'

export function registerChairmanRoutes(app: FastifyInstance, db: Database.Database, litellmBaseUrl: string): void {
  app.post<{
    Params: { id: string }
    Body: { prompt: string; participantModels: string[]; chairmanModel: string }
  }>('/api/conversations/:id/chairman-messages', async (req, reply) => {
    const conversationId = Number(req.params.id)
    const conversation = getConversation(db, conversationId)
    if (!conversation) {
      reply.code(404)
      return { error: 'conversation not found' }
    }

    const { prompt, participantModels, chairmanModel } = req.body

    if (!Array.isArray(participantModels) || participantModels.length === 0 || typeof chairmanModel !== 'string' || !chairmanModel) {
      reply.code(400)
      return { error: 'participantModels must be a non-empty array and chairmanModel must be a non-empty string' }
    }

    addMessage(db, conversationId, 'user', prompt, null)

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    })

    const groupId = randomUUID()
    const promptMessages: ChatMessage[] = [{ role: 'user', content: prompt }]

    const participantResults = await Promise.all(
      participantModels.map(async (model) => {
        let assembled = ''
        let failed = false
        try {
          for await (const token of streamChatCompletion(litellmBaseUrl, model, promptMessages)) {
            assembled += token
            reply.raw.write(`event: participant:${model}\ndata: ${JSON.stringify(token)}\n\n`)
          }
        } catch (err) {
          failed = true
          const message = (err as Error).message
          reply.raw.write(`event: participant:${model}\ndata: error:${JSON.stringify(message)}\n\n`)
        }
        reply.raw.write(`event: participant:${model}\ndata: [DONE]\n\n`)
        if (!failed) {
          addMessage(db, conversationId, 'assistant', assembled, model, false, groupId, false)
        }
        return { model, assembled, failed }
      }),
    )

    const survivors = participantResults.filter((r) => !r.failed)
    if (survivors.length === 0) {
      reply.raw.write(`event: chairman\ndata: error:${JSON.stringify('all participants failed')}\n\n`)
      reply.raw.write('event: chairman\ndata: [DONE]\n\n')
      reply.raw.end()
      return reply
    }

    const synthesisPrompt =
      `Original prompt: ${prompt}\n\n` +
      survivors.map((r) => `--- ${r.model} ---\n${r.assembled}`).join('\n\n') +
      '\n\nSynthesize the single best answer from the responses above.'
    const synthesisMessages: ChatMessage[] = [{ role: 'user', content: synthesisPrompt }]

    let synthesisAssembled = ''
    try {
      for await (const token of streamChatCompletion(litellmBaseUrl, chairmanModel, synthesisMessages)) {
        synthesisAssembled += token
        reply.raw.write(`event: chairman\ndata: ${JSON.stringify(token)}\n\n`)
      }
      addMessage(db, conversationId, 'assistant', synthesisAssembled, chairmanModel, false, groupId, true)
    } catch (err) {
      const message = (err as Error).message
      reply.raw.write(`event: chairman\ndata: error:${JSON.stringify(message)}\n\n`)
    }
    reply.raw.write('event: chairman\ndata: [DONE]\n\n')
    reply.raw.end()
    return reply
  })
}
