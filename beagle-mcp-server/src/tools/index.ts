/**
 * MCP Tools Registry
 * 
 * Defines all MCP tools exposed by BEAGLE server.
 */

import { BeagleClient } from '../beagle-client.js';
import { pipelineTools } from './pipeline.js';
import { scienceJobTools } from './science-jobs.js';
import { memoryTools } from './memory.js';
import { feedbackTools } from './feedback.js';
import { experimentalTools } from './experimental.js';

export interface McpTool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>; // JSON Schema
  handler: (args: unknown) => Promise<unknown>;
}

export function defineTools(client: BeagleClient): McpTool[] {
  return [
    ...pipelineTools(client),
    ...scienceJobTools(client),
    ...memoryTools(client),
    ...feedbackTools(client),
    ...experimentalTools(client),
  ];
}

