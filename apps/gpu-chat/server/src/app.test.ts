import { describe, it, expect } from 'vitest'
import { buildApp } from './app.js'

describe('app', () => {
  it('responds to GET /api/health with ok:true', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({ method: 'GET', url: '/api/health' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ ok: true })
  })
})
