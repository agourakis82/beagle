export interface ChatMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

export interface ModelInfo {
  id: string
}

export async function listModels(baseUrl: string): Promise<ModelInfo[]> {
  const res = await fetch(`${baseUrl}/v1/models`)
  if (!res.ok) {
    throw new Error(`LiteLLM /v1/models failed: ${res.status}`)
  }
  const body = (await res.json()) as { data: ModelInfo[] }
  return body.data
}

/**
 * Cheap per-model liveness probe. Several models in this cluster's LiteLLM
 * config point at scale-to-0 GPU deployments (shared RTX8000 slot, manual
 * switch script) — they stay listed in /v1/models forever even when no
 * pod is backing them, which previously meant picking one of those model
 * names from a client's model picker just hung the request indefinitely.
 * A short, aborted completion request is the only reliable signal LiteLLM
 * exposes short of its own /health endpoint, which probes every configured
 * deployment sequentially with a long timeout and is too slow to call on
 * every model-list load.
 */
export async function probeModelHealth(baseUrl: string, model: string, timeoutMs = 4000): Promise<boolean> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const res = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, messages: [{ role: 'user', content: 'ping' }], max_tokens: 1 }),
      signal: controller.signal,
    })
    return res.ok
  } catch {
    return false
  } finally {
    clearTimeout(timer)
  }
}

export async function* streamChatCompletion(
  baseUrl: string,
  model: string,
  messages: ChatMessage[],
): AsyncGenerator<string> {
  const res = await fetch(`${baseUrl}/v1/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages, stream: true }),
  })
  if (!res.ok || !res.body) {
    throw new Error(`LiteLLM chat completion failed: ${res.status}`)
  }

  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed.startsWith('data:')) continue
      const data = trimmed.slice('data:'.length).trim()
      if (data === '[DONE]') return
      const parsed = JSON.parse(data) as { choices: Array<{ delta: { content?: string } }> }
      const token = parsed.choices[0]?.delta?.content
      if (token) yield token
    }
  }
}
