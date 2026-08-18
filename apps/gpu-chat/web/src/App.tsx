import { useEffect, useState } from 'react'
import type { Conversation, ModelInfo } from './api.js'
import { fetchConversations, fetchModels, createConversation } from './api.js'
import { Sidebar } from './components/Sidebar.js'
import { ChatView } from './components/ChatView.js'

export function App() {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [models, setModels] = useState<ModelInfo[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(null)

  useEffect(() => {
    fetchConversations().then(setConversations)
    fetchModels().then(setModels)
  }, [])

  async function handleNew() {
    const model = models[0]?.id ?? 'default'
    const conv = await createConversation('New conversation', model)
    setConversations((prev) => [conv, ...prev])
    setSelectedId(conv.id)
  }

  return (
    <div className="app">
      <Sidebar conversations={conversations} selectedId={selectedId} onSelect={setSelectedId} onNew={handleNew} />
      {selectedId !== null && <ChatView conversationId={selectedId} models={models} />}
    </div>
  )
}
