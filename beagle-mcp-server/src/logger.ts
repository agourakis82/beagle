/**
 * Simple logger for MCP server
 */

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LOG_LEVELS: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const currentLevel: LogLevel = (process.env.MCP_LOG_LEVEL as LogLevel) || 'info';

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVELS[level] >= LOG_LEVELS[currentLevel];
}

function formatMessage(level: LogLevel, message: string, meta?: unknown): string {
  const timestamp = new Date().toISOString();
  const metaStr = meta ? ` ${JSON.stringify(meta)}` : '';
  return `[${timestamp}] [${level.toUpperCase()}] ${message}${metaStr}`;
}

// The stdio MCP transport reserves stdout exclusively for JSON-RPC frames; any stray
// stdout (console.log/info/debug) corrupts the stream and the client throws
// "Expected ',' or ']' ... in JSON" on the log line. Route ALL log levels to stderr.
function emit(line: string): void {
  process.stderr.write(line + '\n');
}

export const logger = {
  debug: (message: string, meta?: unknown) => {
    if (shouldLog('debug')) {
      emit(formatMessage('debug', message, meta));
    }
  },
  info: (message: string, meta?: unknown) => {
    if (shouldLog('info')) {
      emit(formatMessage('info', message, meta));
    }
  },
  warn: (message: string, meta?: unknown) => {
    if (shouldLog('warn')) {
      emit(formatMessage('warn', message, meta));
    }
  },
  error: (message: string, meta?: unknown) => {
    if (shouldLog('error')) {
      emit(formatMessage('error', message, meta));
    }
  },
};

