import { describe, it, expect, vi, afterEach } from 'vitest'
import { streamMessage, streamCompare } from './api.js'

afterEach(() => vi.restoreAllMocks())

function sseResponse(text: string): Response {
  const bytes = new TextEncoder().encode(text)
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes)
      controller.close()
    },
  })
  return new Response(body, { status: 200 })
}

describe('streamMessage', () => {
  it('JSON.parses a JSON-encoded SSE data line back into the original token, including embedded newlines', async () => {
    const token = 'Hello\nWorld'
    // Exactly what the fixed server now writes: one JSON-encoded "data:" line (the embedded
    // \n is the two-char escape `\n`, not a raw newline byte) followed by the literal [DONE] line.
    const wire = `data: ${JSON.stringify(token)}\n\ndata: [DONE]\n\n`

    const fetchMock = vi.fn().mockResolvedValue(sseResponse(wire))
    vi.stubGlobal('fetch', fetchMock)

    const onToken = vi.fn()
    const onDone = vi.fn()

    await streamMessage(1, 'hi there', onToken, onDone)

    expect(onToken).toHaveBeenCalledTimes(1)
    expect(onToken).toHaveBeenCalledWith(token)
    expect(onDone).toHaveBeenCalledTimes(1)
  })
})

describe('streamCompare', () => {
  it('JSON.parses a JSON-encoded, event-tagged SSE data line back into the original token, including embedded newlines', async () => {
    const token = 'Hello\nWorld'
    const wire = `event: model-a\ndata: ${JSON.stringify(token)}\n\ndata: [DONE]\n\n`

    const fetchMock = vi.fn().mockResolvedValue(sseResponse(wire))
    vi.stubGlobal('fetch', fetchMock)

    const onToken = vi.fn()
    const onModelDone = vi.fn()

    await streamCompare('hi there', ['model-a'], onToken, onModelDone)

    expect(onToken).toHaveBeenCalledTimes(1)
    expect(onToken).toHaveBeenCalledWith('model-a', token)
    expect(onModelDone).toHaveBeenCalledTimes(1)
    expect(onModelDone).toHaveBeenCalledWith('model-a')
  })
})
