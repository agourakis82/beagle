/**
 * Security utilities for MCP server
 * 
 * Implements protections against:
 * - MCP-UPD (Unintended Privacy Disclosure)
 * - Prompt injection
 * - Incorrect server implementation
 */

/**
 * Sanitize output to prevent prompt injection and MCP-UPD
 */
export function sanitizeOutput(
  data: unknown,
  options: { isMemoryQuery?: boolean } = {}
): unknown {
  if (typeof data === 'string') {
    return sanitizeString(data, options);
  }
  
  if (Array.isArray(data)) {
    return data.map(item => sanitizeOutput(item, options));
  }
  
  if (data && typeof data === 'object') {
    const sanitized: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(data)) {
      sanitized[key] = sanitizeOutput(value, options);
    }
    return sanitized;
  }
  
  return data;
}

/**
 * Sanitize string to remove potential prompt injection markers
 */
function sanitizeString(str: string, options: { isMemoryQuery?: boolean } = {}): string {
  let sanitized = str;
  
  // Remove common prompt injection patterns
  const injectionPatterns = [
    /###\s*(SYSTEM|TOOL|ASSISTANT|USER):/gi,
    /<\|(system|tool|assistant|user)\|>/gi,
    /\[INST\].*?\[\/INST\]/gis,
    /```(system|tool|command)/gi,
  ];
  
  for (const pattern of injectionPatterns) {
    sanitized = sanitized.replace(pattern, '[REDACTED]');
  }
  
  // For memory queries, add explicit delimiters
  if (options.isMemoryQuery && !sanitized.includes('BEGIN_MEMORY')) {
    sanitized = `BEGIN_MEMORY_DATA\n${sanitized}\nEND_MEMORY_DATA`;
  }
  
  return sanitized;
}

/**
 * Validate that input doesn't contain dangerous patterns
 */
export function validateInput(input: string): { valid: boolean; error?: string } {
  // Check for potential command injection
  const dangerousPatterns = [
    /[;&|`$(){}[\]]/g, // Shell metacharacters
    /eval\(/gi,
    /exec\(/gi,
    /require\(/gi,
    /import\(/gi,
  ];
  
  for (const pattern of dangerousPatterns) {
    if (pattern.test(input)) {
      return {
        valid: false,
        error: 'Input contains potentially dangerous patterns',
      };
    }
  }
  
  return { valid: true };
}

