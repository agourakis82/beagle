import { useEffect, useState } from 'react'
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
          setMessages((prev) => {
            const next = [...prev]
            next[next.length - 1] = { ...next[next.length - 1], content: next[next.length - 1].content + token }
            return next
          })
        },
        async () => {
          setStreaming(false)
          setMessages(await fetchMessages(conversationId))
        },
        pendingAttachments,
        (message) => {
          setMessages((prev) => {
            const next = [...prev]
            next[next.length - 1] = {
              ...next[next.length - 1],
              content: next[next.length - 1].content + '\n\n⚠ Error: ' + message,
            }
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
        <label>
          Model:{' '}
          <select value={currentModel} onChange={(e) => handleModelChange(e.target.value)}>
            {!models.some((m) => m.id === currentModel) && currentModel && (
              <option value={currentModel}>{currentModel}</option>
            )}
            {models.map((m) => (
              <option key={m.id} value={m.id}>
                {m.id}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="messages">
        {messages.map((m) => (
          <MessageBubble key={m.id} message={m} />
        ))}
      </div>
      <AttachmentPanel
        attachments={attachments}
        onAdd={(a) => setAttachments((prev) => [...prev, a])}
        onRemove={(filename) => setAttachments((prev) => prev.filter((a) => a.filename !== filename))}
      />
      <div className="composer">
        <textarea value={draft} onChange={(e) => setDraft(e.target.value)} disabled={streaming} />
        <button onClick={send} disabled={streaming}>
          Send
        </button>
      </div>
    </div>
  )
}
