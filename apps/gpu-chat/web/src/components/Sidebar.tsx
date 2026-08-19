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
      <button className="btn btn-primary btn-new" onClick={onNew}>
        <span className="btn-new-icon" aria-hidden="true">
          +
        </span>
        New conversation
      </button>
      {conversations.length === 0 ? (
        <p className="sidebar-empty">Nothing here yet.</p>
      ) : (
        <ul className="conversation-list">
          {conversations.map((c) => (
            <li key={c.id}>
              <button
                className={`conversation-item${c.id === selectedId ? ' active' : ''}`}
                onClick={() => onSelect(c.id)}
              >
                <span className="conversation-title">{c.title}</span>
                <span className="model-tag">{c.model}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
