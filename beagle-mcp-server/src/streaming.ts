/**
 * Streaming support for MCP Server
 *
 * Implements Server-Sent Events (SSE) style streaming for long-running
 * LLM completions and other async operations.
 *
 * Features:
 * - Chunked responses for better UX with long LLM outputs
 * - Progress tracking for pipeline runs
 * - Real-time updates from BEAGLE core
 */

import { logger } from "./logger.js";

export interface StreamChunk {
    type: "chunk" | "progress" | "complete" | "error";
    data: unknown;
    timestamp: number;
}

export interface StreamOptions {
    chunkSize?: number;
    progressInterval?: number;
    timeout?: number;
}

export class StreamingManager {
    private activeStreams = new Map<string, ReadableStreamDefaultController<StreamChunk>>();
    private streamCounter = 0;

    /**
     * Creates a new stream ID
     */
    createStreamId(): string {
        return `stream-${Date.now()}-${++this.streamCounter}`;
    }

    /**
     * Registers a stream controller
     */
    registerStream(streamId: string, controller: ReadableStreamDefaultController<StreamChunk>): void {
        this.activeStreams.set(streamId, controller);
        logger.debug(`Registered stream: ${streamId}`);
    }

    /**
     * Unregisters a stream
     */
    unregisterStream(streamId: string): void {
        this.activeStreams.delete(streamId);
        logger.debug(`Unregistered stream: ${streamId}`);
    }

    /**
     * Sends a chunk to a specific stream
     */
    sendChunk(streamId: string, data: unknown): boolean {
        const controller = this.activeStreams.get(streamId);
        if (!controller) {
            logger.warn(`Attempted to send chunk to unknown stream: ${streamId}`);
            return false;
        }

        try {
            controller.enqueue({
                type: "chunk",
                data,
                timestamp: Date.now(),
            });
            return true;
        } catch (error) {
            logger.error(`Failed to send chunk to stream ${streamId}:`, error);
            return false;
        }
    }

    /**
     * Sends progress update to a stream
     */
    sendProgress(streamId: string, progress: number, message?: string): boolean {
        const controller = this.activeStreams.get(streamId);
        if (!controller) return false;

        try {
            controller.enqueue({
                type: "progress",
                data: { progress, message },
                timestamp: Date.now(),
            });
            return true;
        } catch (error) {
            logger.error(`Failed to send progress to stream ${streamId}:`, error);
            return false;
        }
    }

    /**
     * Completes a stream
     */
    completeStream(streamId: string, finalData?: unknown): void {
        const controller = this.activeStreams.get(streamId);
        if (!controller) return;

        try {
            controller.enqueue({
                type: "complete",
                data: finalData,
                timestamp: Date.now(),
            });
            controller.close();
        } catch (error) {
            logger.error(`Failed to complete stream ${streamId}:`, error);
        } finally {
            this.unregisterStream(streamId);
        }
    }

    /**
     * Errors a stream
     */
    errorStream(streamId: string, error: string): void {
        const controller = this.activeStreams.get(streamId);
        if (!controller) return;

        try {
            controller.enqueue({
                type: "error",
                data: { error },
                timestamp: Date.now(),
            });
            controller.close();
        } catch (e) {
            logger.error(`Failed to error stream ${streamId}:`, e);
        } finally {
            this.unregisterStream(streamId);
        }
    }

    /**
     * Gets active stream count
     */
    getActiveStreamCount(): number {
        return this.activeStreams.size;
    }

    /**
     * Cleanup old streams (call periodically)
     */
    cleanup(maxAgeMs: number = 30 * 60 * 1000): number {
        const now = Date.now();
        let cleaned = 0;

        for (const [streamId, controller] of this.activeStreams.entries()) {
            // Extract timestamp from stream ID (format: stream-{timestamp}-{counter})
            const match = streamId.match(/stream-(\d+)-/);
            if (match) {
                const streamTime = parseInt(match[1], 10);
                if (now - streamTime > maxAgeMs) {
                    try {
                        controller.error(new Error("Stream timeout"));
                    } catch (e) {
                        // Ignore errors during cleanup
                    }
                    this.activeStreams.delete(streamId);
                    cleaned++;
                }
            }
        }

        if (cleaned > 0) {
            logger.info(`Cleaned up ${cleaned} old streams`);
        }

        return cleaned;
    }
}

// Singleton instance
export const streamingManager = new StreamingManager();

// Cleanup every 10 minutes
setInterval(() => streamingManager.cleanup(), 10 * 60 * 1000);

/**
 * Utility to create a streaming response from an async generator
 */
export async function* createTextStream(
    text: string,
    options: StreamOptions = {}
): AsyncGenerator<string, void, unknown> {
    const chunkSize = options.chunkSize || 50;
    const progressInterval = options.progressInterval || 50;

    for (let i = 0; i < text.length; i += chunkSize) {
        const chunk = text.slice(i, i + chunkSize);
        yield chunk;

        // Small delay between chunks for natural streaming feel
        if (i + chunkSize < text.length) {
            await new Promise(resolve => setTimeout(resolve, progressInterval));
        }
    }
}

/**
 * Formats a chunk for MCP streaming response
 */
export function formatStreamChunk(chunk: string, index: number): unknown {
    return {
        index,
        content: chunk,
        done: false,
    };
}

/**
 * Formats final chunk for MCP streaming response
 */
export function formatStreamComplete(finalContent?: string, metadata?: Record<string, unknown>): unknown {
    return {
        content: finalContent || "",
        done: true,
        metadata,
    };
}
