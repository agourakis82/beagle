import { Tool } from './types.js'

const EPISTEMIC_SEARCH_URL =
  process.env.EPISTEMIC_SEARCH_URL ?? 'http://epistemic-search.beagle.svc.cluster.local'
const FETCH_TIMEOUT_MS = 65_000 // slightly above the service's own 60s SEARCH_TIMEOUT_SECONDS

export interface SynthesizedAnswer {
  summary: string
  summary_kind: string
  confidence_low: number
  confidence_high: number
  confidence_semantics: string
  conflicts?: Array<{
    claim_a: { text: string; source_url: string }
    claim_b: { text: string; source_url: string }
    note: string
  }>
}

export function formatAnswer(answer: SynthesizedAnswer): string {
  const kindNote =
    answer.summary_kind === 'placeholder-concat'
      ? ' (this is a concatenation of relevant source sentences, not a generated summary)'
      : ''
  const confNote =
    answer.confidence_semantics === 'independent-corroboration-width'
      ? ` [corroboration interval: ${answer.confidence_low.toFixed(2)}-${answer.confidence_high.toFixed(2)}, wider = less independent corroboration]`
      : ''
  let out = `${answer.summary}${kindNote}${confNote}`
  if (answer.conflicts && answer.conflicts.length > 0) {
    out += '\n\nPossible conflicts found:\n'
    for (const c of answer.conflicts) {
      out += `- "${c.claim_a.text}" (${c.claim_a.source_url}) vs. "${c.claim_b.text}" (${c.claim_b.source_url}): ${c.note}\n`
    }
  }
  return out
}

export const searchTool: Tool = {
  name: 'search',
  description:
    "Searches the web and the user's own memory graph for a query, and returns a single synthesized, confidence-calibrated answer (not a list of links).",
  parameters: {
    type: 'object',
    properties: { query: { type: 'string', description: 'The search query' } },
    required: ['query'],
  },
  execute: async (args) => {
    const query = args.query
    if (typeof query !== 'string' || query.trim().length === 0) {
      return 'Error: "query" must be a non-empty string'
    }
    try {
      const res = await fetch(`${EPISTEMIC_SEARCH_URL}/v1/search`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query }),
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      })
      if (!res.ok) {
        return `Error: search backend returned ${res.status}`
      }
      const { raw_stdout } = (await res.json()) as { raw_stdout: string }
      const answer = JSON.parse(raw_stdout) as SynthesizedAnswer
      return formatAnswer(answer)
    } catch (err) {
      return `Error: ${(err as Error).message}`
    }
  },
}
