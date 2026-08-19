export interface DraftAttachment {
  filename: string
  content: string
  mime_type: string
}

interface AttachmentPanelProps {
  attachments: DraftAttachment[]
  onAdd: (a: DraftAttachment) => void
  onRemove: (filename: string) => void
}

export function AttachmentPanel({ attachments, onAdd, onRemove }: AttachmentPanelProps) {
  async function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    const content = await file.text()
    onAdd({ filename: file.name, content, mime_type: file.type || 'text/plain' })
    e.target.value = ''
  }

  function handlePaste(text: string) {
    if (!text.trim()) return
    onAdd({ filename: `pasted-${attachments.length + 1}.txt`, content: text, mime_type: 'text/plain' })
  }

  return (
    <div className="attachment-panel">
      <div className="attachment-actions">
        <label className="btn btn-ghost btn-small">
          Attach file
          <input type="file" onChange={handleFile} hidden />
        </label>
        <button
          className="btn btn-ghost btn-small"
          type="button"
          onClick={async () => {
            const text = await navigator.clipboard.readText()
            handlePaste(text)
          }}
        >
          Paste as attachment
        </button>
      </div>
      {attachments.length > 0 && (
        <ul className="attachment-chips">
          {attachments.map((a) => (
            <li key={a.filename} className="attachment-chip">
              <span className="attachment-chip-name">{a.filename}</span>
              <span className="attachment-chip-size">{a.content.length.toLocaleString()} ch</span>
              <button
                className="attachment-chip-remove"
                onClick={() => onRemove(a.filename)}
                aria-label={`Remove ${a.filename}`}
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
