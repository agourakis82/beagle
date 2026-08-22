import { describe, it, expect, vi, afterEach } from 'vitest'
import { buildApp } from '../app.js'
import * as litellmClient from '../litellm-client.js'

afterEach(() => vi.restoreAllMocks())

describe('conversation routes', () => {
  it('creates a conversation and lists it', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const createRes = await app.inject({
      method: 'POST',
      url: '/api/conversations',
      payload: { title: 'Test chat', model: 'qwen2.5-7b' },
    })
    expect(createRes.statusCode).toBe(200)
    const listRes = await app.inject({ method: 'GET', url: '/api/conversations' })
    expect(listRes.json()).toHaveLength(1)
  })
})

describe('POST /api/conversations/:id/messages', () => {
  it('answers the assistant reply in a single frame and persists both messages', async () => {
    vi.spyOn(litellmClient, 'chatCompletion').mockResolvedValue({
      content: 'Hello',
      finish_reason: 'stop',
      tool_calls: undefined,
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })

    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.headers['content-type']).toContain('text/event-stream')
    expect(res.body).toContain('data: "Hello"')
    expect(res.body).toContain('data: [DONE]')

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages).toHaveLength(2)
    expect(messages[0]).toMatchObject({ role: 'user', content: 'hi there' })
    expect(messages[1]).toMatchObject({ role: 'assistant', content: 'Hello', truncated: 0 })
  })

  it('marks the assistant message truncated when the completion call fails', async () => {
    vi.spyOn(litellmClient, 'chatCompletion').mockRejectedValue(new Error('LiteLLM chat completion failed: 500'))
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages[1]).toMatchObject({ content: '', truncated: 1 })
  })

  it('frames an answer with an embedded newline as a single JSON-encoded SSE line and preserves it end to end', async () => {
    const answer = 'Hello\nWorld'
    vi.spyOn(litellmClient, 'chatCompletion').mockResolvedValue({
      content: answer,
      finish_reason: 'stop',
      tool_calls: undefined,
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })

    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    // The wire format must JSON-encode the final answer so the embedded \n survives as one
    // SSE "data:" line (the escaped newline is `\n` two chars, not a raw newline byte).
    expect(res.body).toContain(`data: ${JSON.stringify(answer)}\n\n`)
    // A buggy framing that wrote the raw answer directly into the frame would split it
    // across two physical SSE lines ("data: Hello" then a bare "World" line) — assert that
    // broken shape is absent.
    expect(res.body).not.toContain('data: Hello\nWorld\n\n')

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages[1]).toMatchObject({ role: 'assistant', content: answer, truncated: 0 })
  })

  it('injects attachment content into the upstream chat messages without mutating stored content', async () => {
    let capturedMessages: Array<{ role: string; content: string }> = []
    vi.spyOn(litellmClient, 'chatCompletion').mockImplementation(async (_url, _model, messages) => {
      capturedMessages = messages
      return { content: 'ok', finish_reason: 'stop', tool_calls: undefined }
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })

    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: {
        content: 'please review this',
        attachments: [{ filename: 'notes.txt', content: 'the secret is 42', mime_type: 'text/plain' }],
      },
    })

    const userMessage = capturedMessages.find((m) => m.role === 'user')
    expect(userMessage?.content).toContain('the secret is 42')
    expect(userMessage?.content).toContain('please review this')
    expect(userMessage?.content).toContain('[Attachment: notes.txt]')

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${conv.id}/messages` })
    const messages = messagesRes.json()
    expect(messages[0]).toMatchObject({ role: 'user', content: 'please review this' })
  })

  it('sends an error SSE frame when the upstream completion call fails', async () => {
    vi.spyOn(litellmClient, 'chatCompletion').mockRejectedValue(new Error('LiteLLM chat completion failed: 500'))
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'POST',
      url: `/api/conversations/${conv.id}/messages`,
      payload: { content: 'hi there' },
    })

    expect(res.body).toContain('event: error')
    expect(res.body).toContain('data: "LiteLLM chat completion failed: 500"')
  })
})

describe('POST /api/conversations/:id/messages — tool calling', () => {
  it('answers directly with no tool calls when the model does not request one', async () => {
    vi.spyOn(litellmClient, 'chatCompletion').mockResolvedValue({
      content: 'The answer is 4', finish_reason: 'stop', tool_calls: undefined,
    })
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const createRes = await app.inject({ method: 'POST', url: '/api/conversations', payload: { title: 't', model: 'chat-fast' } })
    const { id } = createRes.json()

    const res = await app.inject({ method: 'POST', url: `/api/conversations/${id}/messages`, payload: { content: 'what is 2+2' } })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('data: "The answer is 4"')
    expect(res.body).toContain('data: [DONE]')
    expect(res.body).not.toContain('event: tool_call')
  })

  it('executes a real tool call, streams tool_call/tool_result events, and uses the follow-up answer', async () => {
    const toolCall = { id: 'call_1', type: 'function' as const, function: { name: 'calculate', arguments: '{"expression":"2+2"}' } }
    vi.spyOn(litellmClient, 'chatCompletion')
      .mockResolvedValueOnce({ content: '', finish_reason: 'tool_calls', tool_calls: [toolCall] })
      .mockResolvedValueOnce({ content: 'The result is 4', finish_reason: 'stop', tool_calls: undefined })

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const createRes = await app.inject({ method: 'POST', url: '/api/conversations', payload: { title: 't', model: 'chat-fast' } })
    const { id } = createRes.json()

    const res = await app.inject({ method: 'POST', url: `/api/conversations/${id}/messages`, payload: { content: 'what is 2+2' } })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: tool_call\ndata: {"name":"calculate","arguments":"{\\"expression\\":\\"2+2\\"}"}')
    expect(res.body).toContain('event: tool_result\ndata: {"name":"calculate","result":"4"}')
    expect(res.body).toContain('data: "The result is 4"')

    const messagesRes = await app.inject({ method: 'GET', url: `/api/conversations/${id}/messages` })
    const messages = messagesRes.json()
    expect(messages).toHaveLength(2) // only user + final assistant answer persisted, not the tool exchange
    expect(messages[1].content).toBe('The result is 4')
  })

  it('forces a final tool-free answer after 3 rounds of tool calls to guarantee termination', async () => {
    const toolCall = { id: 'call_x', type: 'function' as const, function: { name: 'get_current_time', arguments: '{}' } }
    const alwaysWantsTool = { content: '', finish_reason: 'tool_calls', tool_calls: [toolCall] }
    const spy = vi.spyOn(litellmClient, 'chatCompletion')
      .mockResolvedValueOnce(alwaysWantsTool)
      .mockResolvedValueOnce(alwaysWantsTool)
      .mockResolvedValueOnce(alwaysWantsTool)
      .mockResolvedValueOnce({ content: 'Giving up on tools, here is my answer', finish_reason: 'stop', tool_calls: undefined })

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const createRes = await app.inject({ method: 'POST', url: '/api/conversations', payload: { title: 't', model: 'chat-fast' } })
    const { id } = createRes.json()

    const res = await app.inject({ method: 'POST', url: `/api/conversations/${id}/messages`, payload: { content: 'loop forever' } })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('data: "Giving up on tools, here is my answer"')
    expect(spy).toHaveBeenCalledTimes(4) // 3 tool-enabled rounds + 1 forced tool-free round
    // The 4th call must NOT include tools
    const fourthCallArgs = spy.mock.calls[3]
    expect(fourthCallArgs[3]).toBeUndefined()
  })

  it('surfaces an unknown tool name as a tool-result error without crashing the round', async () => {
    const toolCall = { id: 'call_1', type: 'function' as const, function: { name: 'does_not_exist', arguments: '{}' } }
    vi.spyOn(litellmClient, 'chatCompletion')
      .mockResolvedValueOnce({ content: '', finish_reason: 'tool_calls', tool_calls: [toolCall] })
      .mockResolvedValueOnce({ content: 'I could not find that tool', finish_reason: 'stop', tool_calls: undefined })

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const createRes = await app.inject({ method: 'POST', url: '/api/conversations', payload: { title: 't', model: 'chat-fast' } })
    const { id } = createRes.json()

    const res = await app.inject({ method: 'POST', url: `/api/conversations/${id}/messages`, payload: { content: 'x' } })

    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('event: tool_result\ndata: {"name":"does_not_exist","result":"Error: unknown tool does_not_exist"}')
  })
})

describe('PATCH /api/conversations/:id', () => {
  it('updates the conversation model', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const conv = (
      await app.inject({
        method: 'POST',
        url: '/api/conversations',
        payload: { title: 'Test chat', model: 'qwen2.5-7b' },
      })
    ).json()

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/conversations/${conv.id}`,
      payload: { model: 'qwen2.5-14b' },
    })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ model: 'qwen2.5-14b' })

    const listRes = await app.inject({ method: 'GET', url: '/api/conversations' })
    expect(listRes.json()[0]).toMatchObject({ model: 'qwen2.5-14b' })
  })

  it('404s for an unknown conversation', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/conversations/999',
      payload: { model: 'qwen2.5-14b' },
    })
    expect(res.statusCode).toBe(404)
  })
})
