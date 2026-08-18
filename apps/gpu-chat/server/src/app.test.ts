import { describe, it, expect } from 'vitest'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { buildApp } from './app.js'

describe('app', () => {
  it('responds to GET /api/health with ok:true', async () => {
    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000' })
    const res = await app.inject({ method: 'GET', url: '/api/health' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ ok: true })
  })

  it('serves static frontend files when webDistPath is provided', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'gpu-chat-web-'))
    writeFileSync(join(dir, 'index.html'), '<html>gpu-chat</html>')

    const app = buildApp({ dbPath: ':memory:', litellmBaseUrl: 'http://unused:4000', webDistPath: dir })
    const res = await app.inject({ method: 'GET', url: '/' })
    expect(res.statusCode).toBe(200)
    expect(res.body).toContain('gpu-chat')
  })
})
