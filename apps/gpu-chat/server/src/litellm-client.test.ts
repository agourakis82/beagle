import { describe, it, expect, vi, afterEach } from 'vitest'
import { createServer, Server } from 'node:http'
import { listModels, streamChatCompletion, chatCompletion } from './litellm-client.js'

let server: Server
let baseUrl: string

afterEach(() => {
  server?.close()
  vi.restoreAllMocks()
})

function startMockLiteLLM(handler: Parameters<typeof createServer>[0]) {
  return new Promise<string>((resolve) => {
    server = createServer(handler)
    server.listen(0, () => {
      const port = (server.address() as { port: number }).port
      resolve(`http://127.0.0.1:${port}`)
    })
  })
}

describe('listModels', () => {
  it('parses the models list', async () => {
    baseUrl = await startMockLiteLLM((req, res) => {
      res.writeHead(200, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ data: [{ id: 'qwen2.5-7b' }, { id: 'qwen2.5-14b' }] }))
    })
    const models = await listModels(baseUrl)
    expect(models).toEqual([{ id: 'qwen2.5-7b' }, { id: 'qwen2.5-14b' }])
  })

  it('throws on a non-2xx response', async () => {
    baseUrl = await startMockLiteLLM((req, res) => {
      res.writeHead(503)
      res.end('down')
    })
    await expect(listModels(baseUrl)).rejects.toThrow(/503/)
  })
})

describe('streamChatCompletion', () => {
  it('yields tokens parsed from the SSE stream', async () => {
    baseUrl = await startMockLiteLLM((req, res) => {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' })
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'Hel' } }] })}\n\n`)
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'lo' } }] })}\n\n`)
      res.write('data: [DONE]\n\n')
      res.end()
    })
    const tokens: string[] = []
    for await (const token of streamChatCompletion(baseUrl, 'qwen2.5-7b', [{ role: 'user', content: 'hi' }])) {
      tokens.push(token)
    }
    expect(tokens.join('')).toBe('Hello')
  })

  it('throws on a non-2xx response', async () => {
    baseUrl = await startMockLiteLLM((req, res) => {
      res.writeHead(500)
      res.end('boom')
    })
    await expect(async () => {
      for await (const _ of streamChatCompletion(baseUrl, 'qwen2.5-7b', [{ role: 'user', content: 'hi' }])) {
        // drain
      }
    }).rejects.toThrow(/500/)
  })
})

describe('chatCompletion', () => {
  it('returns content and finish_reason for a plain text response', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        choices: [{ message: { content: 'hello', tool_calls: undefined }, finish_reason: 'stop' }],
      }),
    }) as unknown as typeof fetch

    const result = await chatCompletion('http://unused:4000', 'chat-fast', [{ role: 'user', content: 'hi' }])
    expect(result).toEqual({ content: 'hello', finish_reason: 'stop', tool_calls: undefined })
  })

  it('returns tool_calls when finish_reason is tool_calls', async () => {
    const toolCalls = [{ id: 'call_1', type: 'function', function: { name: 'calculate', arguments: '{"expression":"2+2"}' } }]
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        choices: [{ message: { content: '', tool_calls: toolCalls }, finish_reason: 'tool_calls' }],
      }),
    }) as unknown as typeof fetch

    const result = await chatCompletion('http://unused:4000', 'chat-fast', [{ role: 'user', content: 'what is 2+2' }])
    expect(result.finish_reason).toBe('tool_calls')
    expect(result.tool_calls).toEqual(toolCalls)
  })

  it('throws on a non-ok response', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({ ok: false, status: 500 }) as unknown as typeof fetch
    await expect(chatCompletion('http://unused:4000', 'chat-fast', [{ role: 'user', content: 'hi' }])).rejects.toThrow(
      'LiteLLM chat completion failed: 500',
    )
  })

  it('sends the tools array in the request body when provided', async () => {
    let capturedBody: string | undefined
    globalThis.fetch = vi.fn().mockImplementation(async (_url, init) => {
      capturedBody = init.body as string
      return { ok: true, json: async () => ({ choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }] }) }
    }) as unknown as typeof fetch

    await chatCompletion('http://unused:4000', 'chat-fast', [{ role: 'user', content: 'hi' }], [
      { type: 'function', function: { name: 'calculate', description: 'd', parameters: {} } },
    ])
    const parsed = JSON.parse(capturedBody!)
    expect(parsed.tools).toHaveLength(1)
    expect(parsed.tools[0].function.name).toBe('calculate')
  })
})
