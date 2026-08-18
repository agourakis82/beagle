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

  useEffect(() => {
    fetchTemplates().then(setTemplates)
  }, [])

  async function handleCreate() {
    if (!name.trim() || !systemPrompt.trim()) return
    const t = await createTemplate(name, systemPrompt)
    setTemplates((prev) => [t, ...prev])
    setName('')
    setSystemPrompt('')
  }

  async function handleDelete(id: number) {
    await deleteTemplate(id)
    setTemplates((prev) => prev.filter((t) => t.id !== id))
  }

  return (
    <div className="template-library">
      <ul>
        {templates.map((t) => (
          <li key={t.id}>
            <button onClick={() => onApply(t.system_prompt)}>{t.name}</button>
            <button onClick={() => handleDelete(t.id)}>✕</button>
          </li>
        ))}
      </ul>
      <input placeholder="Template name" value={name} onChange={(e) => setName(e.target.value)} />
      <textarea
        placeholder="System prompt"
        value={systemPrompt}
        onChange={(e) => setSystemPrompt(e.target.value)}
      />
      <button onClick={handleCreate}>Save template</button>
    </div>
  )
}
