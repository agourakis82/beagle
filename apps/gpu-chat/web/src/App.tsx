import { useEffect, useState } from 'react'
import type { Conversation, ModelInfo } from './api.js'
import { fetchConversations, fetchModels, createConversation } from './api.js'
import { Sidebar } from './components/Sidebar.js'
import { ChatView } from './components/ChatView.js'
import { CompareView } from './components/CompareView.js'
import { TemplateLibrary } from './components/TemplateLibrary.js'

export function App() {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [models, setModels] = useState<ModelInfo[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [view, setView] = useState<'chat' | 'compare'>('chat')
  const [pendingSystemPrompt, setPendingSystemPrompt] = useState<string | null>(null)

  useEffect(() => {
    fetchConversations().then(setConversations)
    fetchModels().then(setModels)
  }, [])

  async function handleNew() {
    const model = models[0]?.id ?? 'default'
    const conv = await createConversation('New conversation', model)
    setConversations((prev) => [conv, ...prev])
    setSelectedId(conv.id)
    setView('chat')
    setPendingSystemPrompt(null)
  }

  return (
    <div className="app">
      <div className="sidebar-column">
        <Sidebar
          conversations={conversations}
          selectedId={selectedId}
          onSelect={(id) => { setSelectedId(id); setView('chat') }}
          onNew={handleNew}
        />
        <TemplateLibrary onApply={setPendingSystemPrompt} />
      </div>
      <div className="main">
        <div className="view-tabs">
          <button onClick={() => setView('chat')} className={view === 'chat' ? 'active' : ''}>Chat</button>
          <button onClick={() => setView('compare')} className={view === 'compare' ? 'active' : ''}>Compare</button>
        </div>
        {view === 'chat' && selectedId !== null && (
          <ChatView conversationId={selectedId} models={models} pendingSystemPrompt={pendingSystemPrompt} />
        )}
        {view === 'compare' && <CompareView models={models} />}
      </div>
    </div>
  )
}
