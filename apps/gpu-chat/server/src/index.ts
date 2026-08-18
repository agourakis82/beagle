import { buildApp } from './app.js'

const app = buildApp({
  dbPath: process.env.GPU_CHAT_DB_PATH ?? './data/gpu-chat.db',
  litellmBaseUrl: process.env.LITELLM_BASE_URL ?? 'http://litellm:4000',
})

app.listen({ port: Number(process.env.PORT ?? 8090), host: '0.0.0.0' })
