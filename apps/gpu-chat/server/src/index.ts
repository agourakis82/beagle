import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { buildApp } from './app.js'

const __dirname = dirname(fileURLToPath(import.meta.url))

const app = buildApp({
  dbPath: process.env.GPU_CHAT_DB_PATH ?? './data/gpu-chat.db',
  litellmBaseUrl: process.env.LITELLM_BASE_URL ?? 'http://litellm:4000',
  webDistPath: process.env.GPU_CHAT_WEB_DIST ?? join(__dirname, '../../web/dist'),
})

app.listen({ port: Number(process.env.PORT ?? 8090), host: '0.0.0.0' })
