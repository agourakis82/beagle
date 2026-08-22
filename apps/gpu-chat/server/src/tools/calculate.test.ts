import { describe, it, expect } from 'vitest'
import { evaluateExpression, calculateTool } from './calculate.js'

describe('evaluateExpression', () => {
  it('evaluates basic arithmetic with correct precedence', () => {
    expect(evaluateExpression('2 + 3 * 4')).toBe(14)
    expect(evaluateExpression('(2 + 3) * 4')).toBe(20)
    expect(evaluateExpression('10 / 2 - 1')).toBe(4)
    expect(evaluateExpression('-5 + 3')).toBe(-2)
  })

  it('handles decimals', () => {
    expect(evaluateExpression('1.5 + 2.5')).toBe(4)
  })

  it('rejects letters and injection attempts — a real parser, not a blocklist', () => {
    expect(() => evaluateExpression('1; require("fs")')).toThrow()
    expect(() => evaluateExpression('process.exit()')).toThrow()
    expect(() => evaluateExpression('2 + a')).toThrow()
    expect(() => evaluateExpression('__proto__')).toThrow()
  })

  it('rejects empty or malformed expressions', () => {
    expect(() => evaluateExpression('')).toThrow()
    expect(() => evaluateExpression('2 +')).toThrow()
    expect(() => evaluateExpression('(2 + 3')).toThrow()
  })

  it('rejects division by zero', () => {
    expect(() => evaluateExpression('1 / 0')).toThrow()
  })
})

describe('calculateTool', () => {
  it('has the expected name and a required expression string parameter', () => {
    expect(calculateTool.name).toBe('calculate')
    expect(calculateTool.parameters).toEqual({
      type: 'object',
      properties: { expression: { type: 'string', description: 'A basic arithmetic expression, e.g. "12 * (3 + 4)"' } },
      required: ['expression'],
    })
  })

  it('executes and returns the result as a string', () => {
    expect(calculateTool.execute({ expression: '2 + 2' })).toBe('4')
  })

  it('returns an error string (not a throw) for invalid input at the tool boundary', () => {
    const result = calculateTool.execute({ expression: 'process.exit()' })
    expect(result).toMatch(/error/i)
  })

  it('returns an error string when expression argument is missing or not a string', () => {
    expect(calculateTool.execute({})).toMatch(/error/i)
    expect(calculateTool.execute({ expression: 42 })).toMatch(/error/i)
  })
})
