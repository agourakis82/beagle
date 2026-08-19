import { useRef, useState } from 'react'
import type { PropsWithChildren } from 'react'
import ReactMarkdown from 'react-markdown'
import rehypeHighlight from 'rehype-highlight'
import type { ChatMessage } from '../api.js'

function CodeBlock({ children, ...rest }: PropsWithChildren<Record<string, unknown>>) {
  const [copied, setCopied] = useState(false)
  const preRef = useRef<HTMLPreElement>(null)

  function handleCopy() {
    const textContent = preRef.current?.textContent ?? ''
    navigator.clipboard?.writeText(textContent).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

  return (
    <div className="code-block-wrapper">
      <button className="copy-code-button" onClick={handleCopy} type="button">
        {copied ? 'Copied!' : 'Copy'}
      </button>
      <pre ref={preRef} {...rest}>
        {children}
      </pre>
    </div>
  )
}

export function MessageBubble({ message, streaming = false }: { message: ChatMessage; streaming?: boolean }) {
  return (
    <div className={`bubble bubble-${message.role}${streaming ? ' bubble-streaming' : ''}`}>
      <ReactMarkdown rehypePlugins={[rehypeHighlight]} components={{ pre: CodeBlock }}>
        {message.content}
      </ReactMarkdown>
      {streaming && <span className="stream-cursor" aria-hidden="true" />}
      {message.truncated === 1 && <span className="truncated-flag">⚠ truncated by upstream error</span>}
    </div>
  )
}
