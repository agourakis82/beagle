import Database from 'better-sqlite3'

export interface Conversation {
  id: number
  title: string
  model: string
  created_at: string
}

export interface Message {
  id: number
  conversation_id: number
  role: 'user' | 'assistant' | 'system'
  content: string
  model: string | null
  truncated: number
  chairman_group_id: string | null
  is_synthesis: number
  created_at: string
}

export interface Attachment {
  id: number
  message_id: number
  filename: string
  content: string
  mime_type: string
  created_at: string
}

export interface PromptTemplate {
  id: number
  name: string
  system_prompt: string
  created_at: string
}

export function migrateChairmanColumns(db: Database.Database): void {
  const columns = db.prepare("PRAGMA table_info(messages)").all() as Array<{ name: string }>
  const names = new Set(columns.map((c) => c.name))
  if (!names.has('chairman_group_id')) {
    db.exec('ALTER TABLE messages ADD COLUMN chairman_group_id TEXT')
  }
  if (!names.has('is_synthesis')) {
    db.exec('ALTER TABLE messages ADD COLUMN is_synthesis INTEGER NOT NULL DEFAULT 0')
  }
}

export function openDb(path: string): Database.Database {
  const db = new Database(path)
  db.pragma('journal_mode = WAL')
  db.exec(`
    CREATE TABLE IF NOT EXISTS conversations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      model TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      conversation_id INTEGER NOT NULL REFERENCES conversations(id),
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      model TEXT,
      truncated INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id INTEGER NOT NULL REFERENCES messages(id),
      filename TEXT NOT NULL,
      content TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS prompt_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      system_prompt TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `)
  migrateChairmanColumns(db)
  return db
}

export function createConversation(db: Database.Database, title: string, model: string): Conversation {
  const info = db.prepare('INSERT INTO conversations (title, model) VALUES (?, ?)').run(title, model)
  return getConversation(db, Number(info.lastInsertRowid))!
}

export function updateConversationModel(db: Database.Database, id: number, model: string): void {
  db.prepare('UPDATE conversations SET model = ? WHERE id = ?').run(model, id)
}

export function listConversations(db: Database.Database): Conversation[] {
  return db.prepare('SELECT * FROM conversations ORDER BY created_at DESC').all() as Conversation[]
}

export function getConversation(db: Database.Database, id: number): Conversation | undefined {
  return db.prepare('SELECT * FROM conversations WHERE id = ?').get(id) as Conversation | undefined
}

export function addMessage(
  db: Database.Database,
  conversationId: number,
  role: Message['role'],
  content: string,
  model: string | null,
  truncated = false,
  chairmanGroupId: string | null = null,
  isSynthesis = false,
): Message {
  const info = db
    .prepare(
      'INSERT INTO messages (conversation_id, role, content, model, truncated, chairman_group_id, is_synthesis) VALUES (?, ?, ?, ?, ?, ?, ?)',
    )
    .run(conversationId, role, content, model, truncated ? 1 : 0, chairmanGroupId, isSynthesis ? 1 : 0)
  return db.prepare('SELECT * FROM messages WHERE id = ?').get(info.lastInsertRowid) as Message
}

export function listMessages(db: Database.Database, conversationId: number): Message[] {
  return db
    .prepare('SELECT * FROM messages WHERE conversation_id = ? ORDER BY id ASC')
    .all(conversationId) as Message[]
}

export function addAttachment(
  db: Database.Database,
  messageId: number,
  filename: string,
  content: string,
  mimeType: string,
): Attachment {
  const info = db
    .prepare('INSERT INTO attachments (message_id, filename, content, mime_type) VALUES (?, ?, ?, ?)')
    .run(messageId, filename, content, mimeType)
  return db.prepare('SELECT * FROM attachments WHERE id = ?').get(info.lastInsertRowid) as Attachment
}

export function listAttachments(db: Database.Database, messageId: number): Attachment[] {
  return db
    .prepare('SELECT * FROM attachments WHERE message_id = ? ORDER BY id ASC')
    .all(messageId) as Attachment[]
}

export function createTemplate(db: Database.Database, name: string, systemPrompt: string): PromptTemplate {
  const info = db
    .prepare('INSERT INTO prompt_templates (name, system_prompt) VALUES (?, ?)')
    .run(name, systemPrompt)
  return db.prepare('SELECT * FROM prompt_templates WHERE id = ?').get(info.lastInsertRowid) as PromptTemplate
}

export function listTemplates(db: Database.Database): PromptTemplate[] {
  return db.prepare('SELECT * FROM prompt_templates ORDER BY created_at DESC').all() as PromptTemplate[]
}

export function deleteTemplate(db: Database.Database, id: number): void {
  db.prepare('DELETE FROM prompt_templates WHERE id = ?').run(id)
}
