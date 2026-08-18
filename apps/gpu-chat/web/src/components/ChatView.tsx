import { useEffect, useState } from 'react'
import type { ChatMessage, ModelInfo } from '../api.js'
import { fetchMessages, streamMessage } from '../api.js'
import { MessageBubble } from './MessageBubble.js'
import { AttachmentPanel, type DraftAttachment } from './AttachmentPanel.js'

interface ChatViewProps {
  conversationId: number
  models: ModelInfo[]
}

export function ChatView({ conversationId, models }: ChatViewProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [draft, setDraft] = useState('')
  const [attachments, setAttachments] = useState<DraftAttachment[]>([])
  const [streaming, setStreaming] = useState(false)

  useEffect(() => {
    fetchMessages(conversationId).then(setMessages)
  }, [conversationId])

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
    )
  }

  return (
    <div className="chat-view">
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
