import { useRef, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import rehypeHighlight from 'rehype-highlight'
import type { ModelInfo } from '../api.js'
import { streamCompare, saveCompare } from '../api.js'

interface CompareViewProps {
  models: ModelInfo[]
}

const CHANNEL_CLASSES = ['channel-a', 'channel-b', 'channel-c', 'channel-d']

export function CompareView({ models }: CompareViewProps) {
  const [selected, setSelected] = useState<string[]>([])
  const [prompt, setPrompt] = useState('')
  const [responses, setResponses] = useState<Record<string, string>>({})
  const [done, setDone] = useState<Record<string, boolean>>({})
  const [running, setRunning] = useState(false)
  const pendingByModel = useRef<Record<string, string>>({})
  const flushHandle = useRef<number | null>(null)

  function scheduleFlush() {
    if (flushHandle.current !== null) return
    flushHandle.current = requestAnimationFrame(() => {
      flushHandle.current = null
      const pending = pendingByModel.current
      pendingByModel.current = {}
      const models = Object.keys(pending)
      if (models.length === 0) return
      setResponses((prev) => {
        const next = { ...prev }
        for (const model of models) {
          next[model] = (next[model] ?? '') + pending[model]
        }
        return next
      })
    })
  }

  function toggleModel(id: string) {
    setSelected((prev) => (prev.includes(id) ? prev.filter((m) => m !== id) : [...prev, id]))
  }

  async function run() {
    if (!prompt.trim() || selected.length < 2) return
    setResponses({})
    setDone({})
    pendingByModel.current = {}
    setRunning(true)
    try {
      await streamCompare(
        prompt,
        selected,
        (model, token) => {
          pendingByModel.current[model] = (pendingByModel.current[model] ?? '') + token
          scheduleFlush()
        },
        (model) => setDone((prev) => ({ ...prev, [model]: true })),
        (model, message) => {
          pendingByModel.current[model] = (pendingByModel.current[model] ?? '') + '\n\n⚠ Error: ' + message
          scheduleFlush()
          setDone((prev) => ({ ...prev, [model]: true }))
        },
      )
    } catch (err) {
      console.error(err)
    } finally {
      if (flushHandle.current !== null) {
        cancelAnimationFrame(flushHandle.current)
        flushHandle.current = null
      }
      if (Object.keys(pendingByModel.current).length > 0) {
        const pending = pendingByModel.current
        pendingByModel.current = {}
        setResponses((prev) => {
          const next = { ...prev }
          for (const model of Object.keys(pending)) {
            next[model] = (next[model] ?? '') + pending[model]
          }
          return next
        })
      }
      setRunning(false)
    }
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
        <div className="compare-model-picker">
          {models.map((m) => (
            <label key={m.id} className={`model-chip${selected.includes(m.id) ? ' selected' : ''}`}>
              <input
                type="checkbox"
                checked={selected.includes(m.id)}
                onChange={() => toggleModel(m.id)}
                hidden
              />
              {m.id}
            </label>
          ))}
        </div>
        <div className="compare-prompt-row">
          <textarea
            className="text-input compare-prompt"
            placeholder="Prompt every selected model with…"
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
          />
          <div className="compare-actions">
            <button className="btn btn-primary" onClick={run} disabled={running || selected.length < 2}>
              Compare
            </button>
            <button
              className="btn btn-ghost"
              onClick={save}
              disabled={running || Object.keys(responses).length === 0}
            >
              Save as conversations
            </button>
          </div>
        </div>
      </div>

      {selected.length === 0 ? (
        <p className="messages-empty">Pick two or more models above to compare.</p>
      ) : (
        <div className="compare-columns">
          {selected.map((model, i) => (
            <div key={model} className="compare-column">
              <div className="compare-column-header">
                <span
                  className={`channel-dot ${CHANNEL_CLASSES[i % CHANNEL_CLASSES.length]}`}
                  aria-hidden="true"
                />
                <span className="compare-column-title">{model}</span>
              </div>
              <div className="compare-column-body">
                <ReactMarkdown rehypePlugins={[rehypeHighlight]}>{responses[model] ?? ''}</ReactMarkdown>
                {!done[model] && running && (
                  <span className="typing-dots" aria-label="Generating">
                    <i />
                    <i />
                    <i />
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
