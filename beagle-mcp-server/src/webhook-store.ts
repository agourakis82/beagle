/**
 * Webhook Store
 *
 * In-memory webhook storage with periodic JSON file persistence.
 * No database required - uses file-based storage for simplicity.
 */

import { logger } from "./logger.js";
import { readFile, writeFile, mkdir } from "fs/promises";
import { existsSync } from "fs";
import { dirname } from "path";

// Supported event types
export type WebhookEventType =
    | "pipeline.complete"
    | "pipeline.failed"
    | "science_job.complete"
    | "science_job.failed"
    | "memory.ingest_complete";

// Delivery attempt record
export interface DeliveryAttempt {
    id: string;
    webhookId: string;
    eventType: WebhookEventType;
    payload: WebhookPayload;
    url: string;
    status: "pending" | "delivered" | "failed";
    attempts: number;
    lastAttemptAt: string | null;
    error: string | null;
    responseStatus: number | null;
    createdAt: string;
}

// Webhook registration
export interface Webhook {
    id: string;
    url: string;
    secret: string;
    eventTypes: WebhookEventType[];
    filters?: {
        jobType?: string;
        pipelineType?: string;
    };
    isActive: boolean;
    createdAt: string;
    updatedAt: string;
    description?: string;
}

// Event payload structure
export interface WebhookPayload {
    eventId: string;
    eventType: WebhookEventType;
    timestamp: string;
    data: unknown;
}

// Store file path (relative to project root)
const WEBHOOK_STORE_PATH =
    process.env.WEBHOOK_STORE_PATH || "./data/webhooks.json";
const DELIVERY_LOG_PATH =
    process.env.WEBHOOK_DELIVERY_LOG_PATH || "./data/webhook-deliveries.json";

// In-memory storage
const webhooks: Map<string, Webhook> = new Map();
const deliveryAttempts: Map<string, DeliveryAttempt> = new Map();

// Persistence settings
const PERSIST_INTERVAL_MS = 30000; // 30 seconds

/**
 * Initialize store - load from disk if available
 */
export async function initializeStore(): Promise<void> {
    try {
        // Ensure directory exists
        const dir = dirname(WEBHOOK_STORE_PATH);
        if (!existsSync(dir)) {
            await mkdir(dir, { recursive: true });
        }

        // Load webhooks
        if (existsSync(WEBHOOK_STORE_PATH)) {
            const data = await readFile(WEBHOOK_STORE_PATH, "utf-8");
            const parsed = JSON.parse(data) as Webhook[];
            for (const hook of parsed) {
                webhooks.set(hook.id, hook);
            }
            logger.info(`Loaded ${webhooks.size} webhooks from disk`);
        }

        // Load delivery attempts
        if (existsSync(DELIVERY_LOG_PATH)) {
            const data = await readFile(DELIVERY_LOG_PATH, "utf-8");
            const parsed = JSON.parse(data) as DeliveryAttempt[];
            // Only keep recent attempts (last 7 days)
            const cutoff = new Date();
            cutoff.setDate(cutoff.getDate() - 7);

            for (const attempt of parsed) {
                const attemptDate = new Date(attempt.createdAt);
                if (attemptDate > cutoff) {
                    deliveryAttempts.set(attempt.id, attempt);
                }
            }
            logger.info(`Loaded ${deliveryAttempts.size} recent delivery attempts from disk`);
        }
    } catch (error) {
        logger.error("Failed to initialize webhook store", { error });
        // Continue with empty store - not fatal
    }
}

/**
 * Persist webhooks to disk
 */
async function persistWebhooks(): Promise<void> {
    try {
        const data = JSON.stringify(Array.from(webhooks.values()), null, 2);
        await writeFile(WEBHOOK_STORE_PATH, data, "utf-8");
    } catch (error) {
        logger.error("Failed to persist webhooks", { error });
    }
}

/**
 * Persist delivery attempts to disk
 */
async function persistDeliveries(): Promise<void> {
    try {
        const data = JSON.stringify(Array.from(deliveryAttempts.values()), null, 2);
        await writeFile(DELIVERY_LOG_PATH, data, "utf-8");
    } catch (error) {
        logger.error("Failed to persist delivery attempts", { error });
    }
}

/**
 * Start periodic persistence
 */
export function startPersistence(): void {
    setInterval(async () => {
        await persistWebhooks();
        await persistDeliveries();
    }, PERSIST_INTERVAL_MS);

    // Also persist on graceful shutdown
    process.on("SIGINT", async () => {
        await persistWebhooks();
        await persistDeliveries();
        process.exit(0);
    });

    process.on("SIGTERM", async () => {
        await persistWebhooks();
        await persistDeliveries();
        process.exit(0);
    });
}

/**
 * Register a new webhook
 */
export async function registerWebhook(
    url: string,
    secret: string,
    eventTypes: WebhookEventType[],
    options?: {
        filters?: { jobType?: string; pipelineType?: string };
        description?: string;
    },
): Promise<Webhook> {
    const id = generateId();
    const now = new Date().toISOString();

    const webhook: Webhook = {
        id,
        url,
        secret,
        eventTypes,
        filters: options?.filters,
        isActive: true,
        createdAt: now,
        updatedAt: now,
        description: options?.description,
    };

    webhooks.set(id, webhook);
    await persistWebhooks();

    logger.info(`Registered webhook ${id}`, { url, eventTypes });
    return webhook;
}

/**
 * Unregister a webhook
 */
export async function unregisterWebhook(id: string): Promise<boolean> {
    const deleted = webhooks.delete(id);
    if (deleted) {
        await persistWebhooks();
        logger.info(`Unregistered webhook ${id}`);
    }
    return deleted;
}

/**
 * Get a webhook by ID
 */
export function getWebhook(id: string): Webhook | undefined {
    return webhooks.get(id);
}

/**
 * List all registered webhooks
 */
export function listWebhooks(): Webhook[] {
    return Array.from(webhooks.values());
}

/**
 * Update webhook status
 */
export async function setWebhookActive(
    id: string,
    isActive: boolean,
): Promise<Webhook | null> {
    const webhook = webhooks.get(id);
    if (!webhook) return null;

    webhook.isActive = isActive;
    webhook.updatedAt = new Date().toISOString();
    await persistWebhooks();

    return webhook;
}

/**
 * Find webhooks subscribed to a specific event type
 */
export function findWebhooksForEvent(
    eventType: WebhookEventType,
    data?: { jobType?: string; pipelineType?: string },
): Webhook[] {
    return Array.from(webhooks.values()).filter((hook) => {
        // Must be active and subscribed to this event
        if (!hook.isActive) return false;
        if (!hook.eventTypes.includes(eventType)) return false;

        // Check filters if present
        if (hook.filters) {
            if (data?.jobType && hook.filters.jobType) {
                if (hook.filters.jobType !== data.jobType) return false;
            }
            if (data?.pipelineType && hook.filters.pipelineType) {
                if (hook.filters.pipelineType !== data.pipelineType) return false;
            }
        }

        return true;
    });
}

/**
 * Record a delivery attempt
 */
export async function recordDeliveryAttempt(
    webhookId: string,
    eventType: WebhookEventType,
    payload: WebhookPayload,
    url: string,
): Promise<DeliveryAttempt> {
    const id = generateId();
    const attempt: DeliveryAttempt = {
        id,
        webhookId,
        eventType,
        payload,
        url,
        status: "pending",
        attempts: 0,
        lastAttemptAt: null,
        error: null,
        responseStatus: null,
        createdAt: new Date().toISOString(),
    };

    deliveryAttempts.set(id, attempt);
    return attempt;
}

/**
 * Update delivery attempt status
 */
export async function updateDeliveryAttempt(
    id: string,
    status: "delivered" | "failed",
    error?: string,
    responseStatus?: number,
): Promise<void> {
    const attempt = deliveryAttempts.get(id);
    if (!attempt) return;

    attempt.status = status;
    attempt.attempts += 1;
    attempt.lastAttemptAt = new Date().toISOString();
    if (error) attempt.error = error;
    if (responseStatus !== undefined) attempt.responseStatus = responseStatus;
}

/**
 * Get delivery attempts for a webhook
 */
export function getDeliveryAttempts(webhookId?: string): DeliveryAttempt[] {
    const attempts = Array.from(deliveryAttempts.values());
    if (webhookId) {
        return attempts.filter((a) => a.webhookId === webhookId);
    }
    return attempts;
}

/**
 * Generate unique ID
 */
function generateId(): string {
    return `wh_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
}
