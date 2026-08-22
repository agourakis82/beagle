import { describe, it, expect, beforeEach } from 'vitest'
import Database from 'better-sqlite3'
import {
  openDb, createConversation, listConversations, getConversation,
  addMessage, listMessages, addAttachment, createTemplate, listTemplates, deleteTemplate, migrateChairmanColumns,
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

describe('grouped (chairman) messages', () => {
  it('re-running openDb on an existing database does not error (idempotent migration)', () => {
    const db1 = openDb(':memory:')
    expect(() => openDb(':memory:')).not.toThrow()
    db1.close()
  })

  it('calling migrateChairmanColumns twice on the same handle does not error', () => {
    const db1 = openDb(':memory:')
    expect(() => migrateChairmanColumns(db1)).not.toThrow()
    db1.close()
  })

  it('stores and retrieves chairman_group_id and is_synthesis on a message', () => {
    const db1 = openDb(':memory:')
    const conv = createConversation(db1, 'Chairman test', 'qwen2.5-14b')
    const groupId = 'group-123'
    addMessage(db1, conv.id, 'user', 'prompt', null)
    addMessage(db1, conv.id, 'assistant', 'participant reply', 'qwen2.5-7b', false, groupId, false)
    addMessage(db1, conv.id, 'assistant', 'synthesis', 'qwen2.5-14b', false, groupId, true)

    const messages = listMessages(db1, conv.id)
    const participant = messages.find((m) => m.model === 'qwen2.5-7b')
    const synthesis = messages.find((m) => m.is_synthesis === 1)

    expect(participant?.chairman_group_id).toBe(groupId)
    expect(participant?.is_synthesis).toBe(0)
    expect(synthesis?.chairman_group_id).toBe(groupId)
    expect(synthesis?.model).toBe('qwen2.5-14b')
    db1.close()
  })

  it('existing non-grouped messages have null chairman_group_id and is_synthesis 0', () => {
    const db1 = openDb(':memory:')
    const conv = createConversation(db1, 'Plain thread', 'qwen2.5-14b')
    addMessage(db1, conv.id, 'user', 'hi', null)
    const [message] = listMessages(db1, conv.id)
    expect(message.chairman_group_id).toBeNull()
    expect(message.is_synthesis).toBe(0)
    db1.close()
  })
})
