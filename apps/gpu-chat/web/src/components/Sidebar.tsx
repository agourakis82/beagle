import type { Conversation } from '../api.js'

interface SidebarProps {
  conversations: Conversation[]
  selectedId: number | null
  onSelect: (id: number) => void
  onNew: () => void
}

export function Sidebar({ conversations, selectedId, onSelect, onNew }: SidebarProps) {
  return (
    <div className="sidebar">
      <button onClick={onNew}>+ New conversation</button>
      <ul>
        {conversations.map((c) => (
          <li key={c.id} className={c.id === selectedId ? 'active' : ''} onClick={() => onSelect(c.id)}>
            <div>{c.title}</div>
            <div className="model-tag">{c.model}</div>
          </li>
        ))}
      </ul>
    </div>
  )
}
