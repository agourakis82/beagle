import ReactMarkdown from 'react-markdown'
import rehypeHighlight from 'rehype-highlight'
import type { ChatMessage } from '../api.js'

export function MessageBubble({ message }: { message: ChatMessage }) {
  return (
    <div className={`bubble bubble-${message.role}`}>
      <ReactMarkdown rehypePlugins={[rehypeHighlight]}>{message.content}</ReactMarkdown>
      {message.truncated === 1 && <span className="truncated-flag">⚠ truncated by upstream error</span>}
    </div>
  )
}
