import { describe, it, expect } from 'vitest'
import { searchTool, formatAnswer } from './search.js'

describe('searchTool', () => {
  it('has the expected name and a required query string parameter', () => {
    expect(searchTool.name).toBe('search')
    expect(searchTool.parameters).toEqual({
      type: 'object',
      properties: { query: { type: 'string', description: 'The search query' } },
      required: ['query'],
    })
  })

  it('rejects a non-string query', async () => {
    const result = await searchTool.execute({ query: 42 })
    expect(result).toBe('Error: "query" must be a non-empty string')
  })

  it('rejects an empty query', async () => {
    const result = await searchTool.execute({ query: '   ' })
    expect(result).toBe('Error: "query" must be a non-empty string')
  })
})

describe('formatAnswer', () => {
  it('renders a placeholder-concat summary with a corroboration-width note', () => {
    const out = formatAnswer({
      summary: 'Fact one. Fact two.',
      summary_kind: 'placeholder-concat',
      confidence_low: 0.68,
      confidence_high: 1.32,
      confidence_semantics: 'independent-corroboration-width',
    })
    expect(out).toContain('Fact one. Fact two.')
    expect(out).toContain('concatenation of relevant source sentences')
    expect(out).toContain('0.68-1.32')
    expect(out).toContain('less independent corroboration')
  })

  it('renders surfaced conflicts', () => {
    const out = formatAnswer({
      summary: 'Summary text.',
      summary_kind: 'placeholder-concat',
      confidence_low: 15.0,
      confidence_high: 25.0,
      confidence_semantics: 'independent-corroboration-width',
      conflicts: [
        {
          claim_a: { text: 'X is true', source_url: 'https://a.example' },
          claim_b: { text: 'X is false', source_url: 'https://b.example' },
          note: 'possible disagreement (negation marker near shared term) -- not a confirmed semantic conflict',
        },
      ],
    })
    expect(out).toContain('Possible conflicts found')
    expect(out).toContain('X is true')
    expect(out).toContain('https://a.example')
    expect(out).toContain('X is false')
    expect(out).toContain('https://b.example')
  })

  it('renders a plain summary with no extra notes for unrecognized markers', () => {
    const out = formatAnswer({
      summary: 'Plain text.',
      summary_kind: 'some-future-kind',
      confidence_low: 0,
      confidence_high: 1,
      confidence_semantics: 'some-future-semantics',
    })
    expect(out).toBe('Plain text.')
  })
})
