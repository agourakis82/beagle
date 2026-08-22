import { Tool } from './types.js'

// Recursive-descent parser over: number, + - * / ( ) and unary +/-.
// Deliberately NOT a regex blocklist and NOT eval()/Function() — a parser
// that only knows how to build numbers, operators, and parentheses cannot
// be tricked into running arbitrary code by an input it never assigns any
// meaning to, unlike a blocklist that can always miss an encoding it
// didn't anticipate.

class ExpressionParser {
  private pos = 0
  constructor(private readonly text: string) {}

  parse(): number {
    const value = this.parseExpression()
    this.skipWhitespace()
    if (this.pos < this.text.length) {
      throw new Error(`Unexpected character at position ${this.pos}: "${this.text[this.pos]}"`)
    }
    return value
  }

  private skipWhitespace(): void {
    while (this.pos < this.text.length && /\s/.test(this.text[this.pos])) this.pos++
  }

  private peek(): string | undefined {
    this.skipWhitespace()
    return this.text[this.pos]
  }

  private parseExpression(): number {
    let value = this.parseTerm()
    for (;;) {
      const op = this.peek()
      if (op === '+' || op === '-') {
        this.pos++
        const rhs = this.parseTerm()
        value = op === '+' ? value + rhs : value - rhs
      } else {
        return value
      }
    }
  }

  private parseTerm(): number {
    let value = this.parseFactor()
    for (;;) {
      const op = this.peek()
      if (op === '*' || op === '/') {
        this.pos++
        const rhs = this.parseFactor()
        if (op === '/') {
          if (rhs === 0) throw new Error('Division by zero')
          value = value / rhs
        } else {
          value = value * rhs
        }
      } else {
        return value
      }
    }
  }

  private parseFactor(): number {
    const ch = this.peek()
    if (ch === '+') { this.pos++; return this.parseFactor() }
    if (ch === '-') { this.pos++; return -this.parseFactor() }
    if (ch === '(') {
      this.pos++
      const value = this.parseExpression()
      if (this.peek() !== ')') throw new Error('Expected closing parenthesis')
      this.pos++
      return value
    }
    return this.parseNumber()
  }

  private parseNumber(): number {
    this.skipWhitespace()
    const start = this.pos
    while (this.pos < this.text.length && /[0-9.]/.test(this.text[this.pos])) this.pos++
    if (this.pos === start) throw new Error(`Expected a number at position ${this.pos}`)
    const raw = this.text.slice(start, this.pos)
    const value = Number(raw)
    if (Number.isNaN(value)) throw new Error(`Invalid number: "${raw}"`)
    return value
  }
}

export function evaluateExpression(expression: string): number {
  if (expression.trim().length === 0) throw new Error('Empty expression')
  return new ExpressionParser(expression).parse()
}

export const calculateTool: Tool = {
  name: 'calculate',
  description: 'Evaluates a basic arithmetic expression and returns the numeric result.',
  parameters: {
    type: 'object',
    properties: { expression: { type: 'string', description: 'A basic arithmetic expression, e.g. "12 * (3 + 4)"' } },
    required: ['expression'],
  },
  execute: (args) => {
    const expression = args.expression
    if (typeof expression !== 'string') {
      return 'Error: "expression" must be a string'
    }
    try {
      return String(evaluateExpression(expression))
    } catch (err) {
      return `Error: ${(err as Error).message}`
    }
  },
}
