import { describe, it, expect } from 'vitest'
import { buildApp } from '../app.js'

describe('template routes', () => {
  it('creates, lists, and deletes a template', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })

    const createRes = await app.inject({
      method: 'POST',
      url: '/api/templates',
      payload: { name: 'Terse reviewer', system_prompt: 'Answer in one sentence.' },
    })
    expect(createRes.statusCode).toBe(200)
    const created = createRes.json()
    expect(created.name).toBe('Terse reviewer')

    const listRes = await app.inject({ method: 'GET', url: '/api/templates' })
    expect(listRes.json()).toHaveLength(1)

    const deleteRes = await app.inject({ method: 'DELETE', url: `/api/templates/${created.id}` })
    expect(deleteRes.statusCode).toBe(200)

    const listAfter = await app.inject({ method: 'GET', url: '/api/templates' })
    expect(listAfter.json()).toHaveLength(0)
  })

  it('rejects a template with an empty name', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({
      method: 'POST',
      url: '/api/templates',
      payload: { name: '', system_prompt: 'x' },
    })
    expect(res.statusCode).toBe(400)
  })
})
