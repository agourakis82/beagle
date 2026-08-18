export interface ModelInfo {
  id: string
}

export interface Conversation {
  id: number
  title: string
  model: string
  created_at: string
}

export interface ChatMessage {
  id: number
  conversation_id: number
  role: 'user' | 'assistant' | 'system'
  content: string
  model: string | null
  truncated: number
  created_at: string
}

export async function fetchModels(): Promise<ModelInfo[]> {
  const res = await fetch('/api/models')
  if (!res.ok) throw new Error(`Failed to load models: ${res.status}`)
  return res.json()
}

export async function fetchConversations(): Promise<Conversation[]> {
  const res = await fetch('/api/conversations')
  if (!res.ok) throw new Error(`Failed to load conversations: ${res.status}`)
  return res.json()
}

export async function createConversation(title: string, model: string): Promise<Conversation> {
  const res = await fetch('/api/conversations', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, model }),
  })
  if (!res.ok) throw new Error(`Failed to create conversation: ${res.status}`)
  return res.json()
}

export async function fetchMessages(conversationId: number): Promise<ChatMessage[]> {
  const res = await fetch(`/api/conversations/${conversationId}/messages`)
  if (!res.ok) throw new Error(`Failed to load messages: ${res.status}`)
  return res.json()
}

export async function streamMessage(
  conversationId: number,
  content: string,
  onToken: (token: string) => void,
  onDone: () => void,
  attachments?: Array<{ filename: string; content: string; mime_type: string }>,
): Promise<void> {
  const res = await fetch(`/api/conversations/${conversationId}/messages`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content, attachments }),
  })
  if (!res.ok || !res.body) throw new Error(`Failed to send message: ${res.status}`)

  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue
      const data = line.slice('data: '.length)
      if (data === '[DONE]') {
        onDone()
        return
      }
      onToken(JSON.parse(data))
    }
  }
  onDone()
}
