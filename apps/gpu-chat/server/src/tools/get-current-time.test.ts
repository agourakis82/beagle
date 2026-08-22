import { describe, it, expect } from 'vitest'
import { getCurrentTimeTool } from './get-current-time.js'

describe('getCurrentTimeTool', () => {
  it('has the expected name and an empty parameter schema', () => {
    expect(getCurrentTimeTool.name).toBe('get_current_time')
    expect(getCurrentTimeTool.parameters).toEqual({ type: 'object', properties: {}, required: [] })
  })

  it('returns a string containing both UTC and Sao Paulo times', () => {
    const result = getCurrentTimeTool.execute({})
    expect(result).toContain('UTC')
    expect(result).toContain('America/Sao_Paulo')
    // Should be parseable as containing an ISO-ish date (year-month-day)
    expect(result).toMatch(/\d{4}-\d{2}-\d{2}/)
  })
})
