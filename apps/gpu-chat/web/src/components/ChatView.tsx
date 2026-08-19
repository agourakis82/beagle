import { useEffect, useRef, useState } from 'react'
import type { ChatMessage, ModelInfo } from '../api.js'
import { fetchMessages, streamMessage, fetchConversation, updateConversationModel } from '../api.js'
import { MessageBubble } from './MessageBubble.js'
import { AttachmentPanel, type DraftAttachment } from './AttachmentPanel.js'

interface ChatViewProps {
  conversationId: number
  models: ModelInfo[]
  pendingSystemPrompt?: string | null
}

export function ChatView({ conversationId, models, pendingSystemPrompt }: ChatViewProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [draft, setDraft] = useState('')
  const [attachments, setAttachments] = useState<DraftAttachment[]>([])
  const [streaming, setStreaming] = useState(false)
  const [currentModel, setCurrentModel] = useState<string>('')
  const pendingTokens = useRef('')
  const flushHandle = useRef<number | null>(null)

  function scheduleFlush() {
    if (flushHandle.current !== null) return
    flushHandle.current = requestAnimationFrame(() => {
      flushHandle.current = null
      const chunk = pendingTokens.current
      pendingTokens.current = ''
      if (!chunk) return
      setMessages((prev) => {
        const next = [...prev]
        next[next.length - 1] = { ...next[next.length - 1], content: next[next.length - 1].content + chunk }
        return next
      })
    })
  }

  useEffect(() => {
    fetchMessages(conversationId).then(async (existing) => {
      setMessages(existing)
      if (existing.length === 0 && pendingSystemPrompt) {
        setDraft(pendingSystemPrompt)
      }
    })
    fetchConversation(conversationId).then((conv) => setCurrentModel(conv.model))
  }, [conversationId, pendingSystemPrompt])

  async function handleModelChange(model: string) {
    setCurrentModel(model)
    try {
      await updateConversationModel(conversationId, model)
    } catch (err) {
      console.error(err)
    }
  }

  async function send() {
    if (!draft.trim()) return
    const content = draft
    const pendingAttachments = attachments
    setDraft('')
    setAttachments([])
    setStreaming(true)
    setMessages((prev) => [
      ...prev,
      { id: -1, conversation_id: conversationId, role: 'user', content, model: null, truncated: 0, created_at: '' },
      { id: -2, conversation_id: conversationId, role: 'assistant', content: '', model: null, truncated: 0, created_at: '' },
    ])

    try {
      await streamMessage(
        conversationId,
        content,
        (token) => {
          pendingTokens.current += token
          scheduleFlush()
        },
        async () => {
          if (flushHandle.current !== null) {
            cancelAnimationFrame(flushHandle.current)
            flushHandle.current = null
          }
          pendingTokens.current = ''
          setStreaming(false)
          setMessages(await fetchMessages(conversationId))
        },
        pendingAttachments,
        (message) => {
          const errorText = pendingTokens.current + '\n\n⚠ Error: ' + message
          pendingTokens.current = ''
          if (flushHandle.current !== null) {
            cancelAnimationFrame(flushHandle.current)
            flushHandle.current = null
          }
          setMessages((prev) => {
            const next = [...prev]
            next[next.length - 1] = { ...next[next.length - 1], content: next[next.length - 1].content + errorText }
            return next
          })
          setStreaming(false)
        },
      )
    } finally {
      setStreaming(false)
    }
  }

  return (
    <div className="chat-view">
      <div className="model-select-row">
        <span className="model-select-label">Model</span>
        <select
          className="model-select"
          value={currentModel}
          onChange={(e) => handleModelChange(e.target.value)}
        >
          {!models.some((m) => m.id === currentModel) && currentModel && (
            <option value={currentModel}>{currentModel}</option>
          )}
          {models.map((m) => (
            <option key={m.id} value={m.id}>
              {m.id}
            </option>
          ))}
        </select>
      </div>
      <div className="messages">
        {messages.length === 0 ? (
          <p className="messages-empty">Say something to get started.</p>
        ) : (
          messages.map((m, i) => (
            <MessageBubble
              key={m.id}
              message={m}
              streaming={streaming && i === messages.length - 1 && m.role === 'assistant'}
            />
          ))
        )}
      </div>
      <AttachmentPanel
        attachments={attachments}
        onAdd={(a) => setAttachments((prev) => [...prev, a])}
        onRemove={(filename) => setAttachments((prev) => prev.filter((a) => a.filename !== filename))}
      />
      <div className="composer">
        <textarea
          className="composer-input"
          placeholder="Message the model…"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              send()
            }
          }}
          disabled={streaming}
        />
        <button className="send-button" onClick={send} disabled={streaming} aria-label="Send message">
          <span aria-hidden="true">→</span>
        </button>
      </div>
    </div>
  )
}
