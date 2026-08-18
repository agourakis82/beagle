import { FastifyInstance } from 'fastify'
import Database from 'better-sqlite3'
import {
  createConversation, listConversations, getConversation,
  addMessage, listMessages, addAttachment,
} from '../db.js'
import { streamChatCompletion, ChatMessage } from '../litellm-client.js'

interface AttachmentInput {
  filename: string
  content: string
  mime_type: string
}

export function registerChatRoutes(app: FastifyInstance, db: Database.Database, litellmBaseUrl: string): void {
  app.post<{ Body: { title: string; model: string } }>('/api/conversations', async (req) => {
    const { title, model } = req.body
    return createConversation(db, title, model)
  })

  app.get('/api/conversations', async () => listConversations(db))

  app.get<{ Params: { id: string } }>('/api/conversations/:id/messages', async (req) => {
    return listMessages(db, Number(req.params.id))
  })

  app.post<{
    Params: { id: string }
    Body: { content: string; attachments?: AttachmentInput[] }
  }>('/api/conversations/:id/messages', async (req, reply) => {
    const conversationId = Number(req.params.id)
    const conversation = getConversation(db, conversationId)
    if (!conversation) {
      reply.code(404)
      return { error: 'conversation not found' }
    }

    const userMessage = addMessage(db, conversationId, 'user', req.body.content, null)
    for (const a of req.body.attachments ?? []) {
      addAttachment(db, userMessage.id, a.filename, a.content, a.mime_type)
    }

    const history = listMessages(db, conversationId)
    const chatMessages: ChatMessage[] = history.map((m) => ({
      role: m.role,
      content: m.content,
    }))

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    })

    let assembled = ''
    let truncated = false
    try {
      for await (const token of streamChatCompletion(litellmBaseUrl, conversation.model, chatMessages)) {
        assembled += token
        reply.raw.write(`data: ${token}\n\n`)
      }
    } catch {
      truncated = true
    }

    addMessage(db, conversationId, 'assistant', assembled, conversation.model, truncated)
    reply.raw.write('data: [DONE]\n\n')
    reply.raw.end()
    return reply
  })
}
