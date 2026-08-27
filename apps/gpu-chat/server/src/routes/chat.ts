import { FastifyInstance } from 'fastify'
import Database from 'better-sqlite3'
import {
  createConversation, listConversations, getConversation,
  addMessage, listMessages, addAttachment, listAttachments, updateConversationModel,
} from '../db.js'
import { chatCompletion, ChatMessage } from '../litellm-client.js'
import { toolDefinitions, findTool } from '../tools/index.js'

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

  app.patch<{
    Params: { id: string }
    Body: { model: string }
  }>('/api/conversations/:id', async (req, reply) => {
    const conversationId = Number(req.params.id)
    const conversation = getConversation(db, conversationId)
    if (!conversation) {
      reply.code(404)
      return { error: 'conversation not found' }
    }
    updateConversationModel(db, conversationId, req.body.model)
    return getConversation(db, conversationId)
  })

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
    const chatMessages: ChatMessage[] = history.map((m) => {
      const attachments = listAttachments(db, m.id)
      if (attachments.length === 0) {
        return { role: m.role, content: m.content }
      }
      const attachmentBlocks = attachments
        .map((a) => `[Attachment: ${a.filename}]\n${a.content}\n[End attachment: ${a.filename}]`)
        .join('\n\n')
      return { role: m.role, content: `${attachmentBlocks}\n\n${m.content}` }
    })

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    })

    const MAX_TOOL_ROUNDS = 3
    let workingMessages: ChatMessage[] = [...chatMessages]
    let finalContent = ''
    let truncated = false
    let errorMessage: string | undefined

    try {
      for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
        const result = await chatCompletion(litellmBaseUrl, conversation.model, workingMessages, toolDefinitions())

        if (result.finish_reason !== 'tool_calls' || !result.tool_calls?.length) {
          finalContent = result.content
          break
        }

        workingMessages.push({ role: 'assistant', content: result.content, tool_calls: result.tool_calls })

        for (const call of result.tool_calls) {
          reply.raw.write(
            `event: tool_call\ndata: ${JSON.stringify({ name: call.function.name, arguments: call.function.arguments })}\n\n`,
          )
          const tool = findTool(call.function.name)
          let toolResultText: string
          if (!tool) {
            toolResultText = `Error: unknown tool ${call.function.name}`
          } else {
            try {
              const args = JSON.parse(call.function.arguments || '{}')
              toolResultText = await tool.execute(args)
            } catch (err) {
              toolResultText = `Error: ${(err as Error).message}`
            }
          }
          reply.raw.write(
            `event: tool_result\ndata: ${JSON.stringify({ name: call.function.name, result: toolResultText })}\n\n`,
          )
          workingMessages.push({ role: 'tool', tool_call_id: call.id, content: toolResultText })
        }

        if (round === MAX_TOOL_ROUNDS - 1) {
          // Still wants tools after the last tools-enabled round — force a
          // final, tool-free answer so the loop always terminates.
          const forced = await chatCompletion(litellmBaseUrl, conversation.model, workingMessages)
          finalContent = forced.content
        }
      }
    } catch (err) {
      truncated = true
      errorMessage = (err as Error).message
    }

    // Only the original user message (already persisted above) and this final
    // answer are saved — the tool-call/tool-result exchange is ephemeral
    // orchestration state, not part of the persisted conversation history.
    addMessage(db, conversationId, 'assistant', finalContent, conversation.model, truncated)
    reply.raw.write(`data: ${JSON.stringify(finalContent)}\n\n`)
    if (errorMessage) {
      reply.raw.write(`event: error\ndata: ${JSON.stringify(errorMessage)}\n\n`)
    }
    reply.raw.write('data: [DONE]\n\n')
    reply.raw.end()
    return reply
  })
}
