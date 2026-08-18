import { describe, it, expect, afterEach } from 'vitest'
import { createServer, Server } from 'node:http'
import { listModels, streamChatCompletion } from './litellm-client.js'

let server: Server
let baseUrl: string

afterEach(() => {
  server?.close()
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
