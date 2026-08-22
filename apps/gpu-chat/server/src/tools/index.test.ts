import { describe, it, expect } from 'vitest'
import { tools, toolDefinitions, findTool } from './index.js'

describe('tool registry', () => {
  it('contains exactly the two Phase 1 built-in tools', () => {
    expect(tools.map((t) => t.name).sort()).toEqual(['calculate', 'get_current_time'])
  })

  it('toolDefinitions() converts each tool into OpenAI function-tool shape', () => {
    const defs = toolDefinitions()
    expect(defs).toHaveLength(2)
    for (const def of defs) {
      expect(def.type).toBe('function')
      expect(typeof def.function.name).toBe('string')
      expect(typeof def.function.description).toBe('string')
      expect(typeof def.function.parameters).toBe('object')
    }
  })

  it('findTool returns the matching tool by name, or undefined', () => {
    expect(findTool('calculate')?.name).toBe('calculate')
    expect(findTool('nonexistent-tool')).toBeUndefined()
  })
})
