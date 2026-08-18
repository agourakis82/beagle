import { describe, it, expect, beforeEach } from 'vitest'
import Database from 'better-sqlite3'
import {
  openDb, createConversation, listConversations, getConversation,
  addMessage, listMessages, addAttachment, createTemplate, listTemplates, deleteTemplate,
} from './db.js'

let db: Database.Database

beforeEach(() => {
  db = openDb(':memory:')
})

describe('conversations', () => {
  it('creates and lists conversations', () => {
    const c = createConversation(db, 'Test chat', 'qwen2.5-7b')
    expect(c.id).toBeGreaterThan(0)
    expect(c.title).toBe('Test chat')
    expect(listConversations(db)).toHaveLength(1)
  })

  it('gets a conversation by id', () => {
    const c = createConversation(db, 'Test chat', 'qwen2.5-7b')
    expect(getConversation(db, c.id)?.title).toBe('Test chat')
    expect(getConversation(db, 9999)).toBeUndefined()
  })
})

describe('messages', () => {
  it('adds and lists messages in order', () => {
    const c = createConversation(db, 'Test chat', 'qwen2.5-7b')
    addMessage(db, c.id, 'user', 'hello', null)
    addMessage(db, c.id, 'assistant', 'hi there', 'qwen2.5-7b')
    const msgs = listMessages(db, c.id)
    expect(msgs.map((m) => m.role)).toEqual(['user', 'assistant'])
    expect(msgs[1].truncated).toBe(0)
  })

  it('marks a message truncated', () => {
    const c = createConversation(db, 'Test chat', 'qwen2.5-7b')
    const m = addMessage(db, c.id, 'assistant', 'partial...', 'qwen2.5-7b', true)
    expect(m.truncated).toBe(1)
  })
})

describe('attachments', () => {
  it('attaches content to a message', () => {
    const c = createConversation(db, 'Test chat', 'qwen2.5-7b')
    const m = addMessage(db, c.id, 'user', 'see attached', null)
    const a = addAttachment(db, m.id, 'notes.txt', 'some content', 'text/plain')
    expect(a.filename).toBe('notes.txt')
  })
})

describe('prompt templates', () => {
  it('creates, lists, and deletes templates', () => {
    const t = createTemplate(db, 'Terse reviewer', 'Answer in one sentence.')
    expect(listTemplates(db)).toHaveLength(1)
    deleteTemplate(db, t.id)
    expect(listTemplates(db)).toHaveLength(0)
  })
})
