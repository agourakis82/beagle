import { Tool } from './types.js'
import { getCurrentTimeTool } from './get-current-time.js'
import { calculateTool } from './calculate.js'

export const tools: Tool[] = [getCurrentTimeTool, calculateTool]

export function toolDefinitions() {
  return tools.map((t) => ({
    type: 'function' as const,
    function: { name: t.name, description: t.description, parameters: t.parameters },
  }))
}

export function findTool(name: string): Tool | undefined {
  return tools.find((t) => t.name === name)
}
