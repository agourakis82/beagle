import { useState } from 'react'
import ReactMarkdown from 'react-markdown'
import rehypeHighlight from 'rehype-highlight'
import type { ModelInfo } from '../api.js'
import { streamCompare, saveCompare } from '../api.js'

interface CompareViewProps {
  models: ModelInfo[]
}

export function CompareView({ models }: CompareViewProps) {
  const [selected, setSelected] = useState<string[]>([])
  const [prompt, setPrompt] = useState('')
  const [responses, setResponses] = useState<Record<string, string>>({})
  const [done, setDone] = useState<Record<string, boolean>>({})
  const [running, setRunning] = useState(false)

  function toggleModel(id: string) {
    setSelected((prev) => (prev.includes(id) ? prev.filter((m) => m !== id) : [...prev, id]))
  }

  async function run() {
    if (!prompt.trim() || selected.length < 2) return
    setResponses({})
    setDone({})
    setRunning(true)
    await streamCompare(
      prompt,
      selected,
      (model, token) => setResponses((prev) => ({ ...prev, [model]: (prev[model] ?? '') + token })),
      (model) => setDone((prev) => ({ ...prev, [model]: true })),
    )
    setRunning(false)
  }

  async function save() {
    await saveCompare(
      prompt,
      selected.map((model) => ({ model, response: responses[model] ?? '' })),
    )
  }

  return (
    <div className="compare-view">
      <div className="compare-controls">
        {models.map((m) => (
          <label key={m.id}>
            <input type="checkbox" checked={selected.includes(m.id)} onChange={() => toggleModel(m.id)} />
            {m.id}
          </label>
        ))}
        <textarea value={prompt} onChange={(e) => setPrompt(e.target.value)} />
        <button onClick={run} disabled={running || selected.length < 2}>
          Compare
        </button>
        <button onClick={save} disabled={running || Object.keys(responses).length === 0}>
          Save as conversations
        </button>
      </div>
      <div className="compare-columns">
        {selected.map((model) => (
          <div key={model} className="compare-column">
            <h3>{model}</h3>
            <ReactMarkdown rehypePlugins={[rehypeHighlight]}>{responses[model] ?? ''}</ReactMarkdown>
            {!done[model] && running && <span className="streaming-indicator">…</span>}
          </div>
        ))}
      </div>
    </div>
  )
}
