import { Tool } from './types.js'

export const getCurrentTimeTool: Tool = {
  name: 'get_current_time',
  description: 'Returns the current date and time in UTC and in America/Sao_Paulo local time.',
  parameters: { type: 'object', properties: {}, required: [] },
  execute: () => {
    const now = new Date()
    const utc = now.toISOString()
    const saoPaulo = new Intl.DateTimeFormat('sv-SE', {
      timeZone: 'America/Sao_Paulo',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
      hour12: false,
    }).format(now).replace(' ', 'T')
    return `Current time — UTC: ${utc} | America/Sao_Paulo: ${saoPaulo}`
  },
}
