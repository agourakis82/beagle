import { useEffect, useState } from 'react'
import type { PromptTemplate } from '../api.js'
import { fetchTemplates, createTemplate, deleteTemplate } from '../api.js'

interface TemplateLibraryProps {
  onApply: (systemPrompt: string) => void
}

export function TemplateLibrary({ onApply }: TemplateLibraryProps) {
  const [templates, setTemplates] = useState<PromptTemplate[]>([])
  const [name, setName] = useState('')
  const [systemPrompt, setSystemPrompt] = useState('')
  const [creating, setCreating] = useState(false)

  useEffect(() => {
    fetchTemplates().then(setTemplates)
  }, [])

  async function handleCreate() {
    if (!name.trim() || !systemPrompt.trim()) return
    const t = await createTemplate(name, systemPrompt)
    setTemplates((prev) => [t, ...prev])
    setName('')
    setSystemPrompt('')
    setCreating(false)
  }

  async function handleDelete(id: number) {
    await deleteTemplate(id)
    setTemplates((prev) => prev.filter((t) => t.id !== id))
  }

  return (
    <div className="template-library">
      <div className="template-library-header">
        <span className="sidebar-section-label">Templates</span>
        <button className="btn btn-ghost btn-small" onClick={() => setCreating((v) => !v)}>
          {creating ? 'Cancel' : '+ New'}
        </button>
      </div>

      {creating && (
        <div className="template-form">
          <input
            className="text-input"
            placeholder="Template name"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <textarea
            className="text-input template-form-prompt"
            placeholder="System prompt"
            value={systemPrompt}
            onChange={(e) => setSystemPrompt(e.target.value)}
          />
          <button className="btn btn-primary btn-small" onClick={handleCreate}>
            Save template
          </button>
        </div>
      )}

      {templates.length === 0 ? (
        <p className="sidebar-empty">No saved templates.</p>
      ) : (
        <ul className="template-list">
          {templates.map((t) => (
            <li key={t.id} className="template-chip">
              <button className="template-chip-apply" onClick={() => onApply(t.system_prompt)}>
                {t.name}
              </button>
              <button
                className="template-chip-remove"
                onClick={() => handleDelete(t.id)}
                aria-label={`Delete template ${t.name}`}
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
