// db.mjs — connection pool + schema migration runner for memory-pg.
//
// Phase 0, Task 0.2. `ensureSchema` applies the SQL files in `sql/` in
// lexical order (000_extensions.sql, 001_core.sql, ...) idempotently — every
// statement uses IF NOT EXISTS so re-running is safe.

import pg from "pg";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SQL_DIR = join(__dirname, "..", "sql");

/**
 * Build a node-postgres Pool from a DSN.
 * @param {string} [dsn] - postgres connection string; defaults to MEMORY_PG_DSN.
 * @returns {pg.Pool}
 */
export function makePool(dsn = process.env.MEMORY_PG_DSN) {
  if (!dsn) {
    throw new Error("makePool: no DSN provided (set MEMORY_PG_DSN or pass dsn)");
  }
  return new pg.Pool({ connectionString: dsn });
}

/**
 * Run every *.sql file in sql/ in lexical order against the pool.
 * Idempotent: the SQL uses CREATE EXTENSION/TABLE/INDEX IF NOT EXISTS.
 * @param {pg.Pool} pool
 */
export async function ensureSchema(pool) {
  const entries = await readdir(SQL_DIR);
  const files = entries.filter((f) => f.endsWith(".sql")).sort();
  for (const file of files) {
    const sql = await readFile(join(SQL_DIR, file), "utf8");
    await pool.query(sql);
  }
}
