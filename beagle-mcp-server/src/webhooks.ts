/**
 * Webhook Delivery System
 *
 * Handles webhook delivery with:
 * - HMAC-SHA256 signature verification
 * - Exponential backoff retry (3 attempts)
 * - Delivery attempt logging
 */

import { createHmac } from "crypto";
import { logger } from "./logger.js";
import {
    Webhook,
    WebhookEventType,
    WebhookPayload,
    recordDeliveryAttempt,
    updateDeliveryAttempt,
    findWebhooksForEvent,
    getWebhook,
    getDeliveryAttempts,
} from "./webhook-store.js";

// Retry configuration
const MAX_RETRY_ATTEMPTS = 3;
const INITIAL_RETRY_DELAY_MS = 1000; // 1 second
const RETRY_BACKOFF_MULTIPLIER = 2;

// Request timeout
const WEBHOOK_TIMEOUT_MS = 30000; // 30 seconds

/**
 * Generate HMAC-SHA256 signature for webhook payload
 */
export function generateSignature(payload: string, secret: string): string {
    const hmac = createHmac("sha256", secret);
    hmac.update(payload);
    return `sha256=${hmac.digest("hex")}`;
}

/**
 * Verify webhook signature (for documentation - BEAGLE is sender, not receiver)
 */
export function verifySignature(
    payload: string,
    signature: string,
    secret: string,
): boolean {
    const expected = generateSignature(payload, secret);
    try {
        // Constant-time comparison to prevent timing attacks
        const sigBuf = Buffer.from(signature);
        const expectedBuf = Buffer.from(expected);

        if (sigBuf.length !== expectedBuf.length) {
            return false;
        }

        let result = 0;
        for (let i = 0; i < sigBuf.length; i++) {
            result |= sigBuf[i] ^ expectedBuf[i];
        }
        return result === 0;
    } catch {
        return false;
    }
}

/**
 * Send webhook to a single URL with retry logic
 */
async function sendWebhook(
    webhook: Webhook,
    payload: WebhookPayload,
): Promise<{ success: boolean; attempts: number; lastError?: string }> {
    const payloadString = JSON.stringify(payload);
    const signature = generateSignature(payloadString, webhook.secret);

    let lastError = "";

    for (let attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++) {
        try {
            logger.debug(
                `Sending webhook ${webhook.id} attempt ${attempt}/${MAX_RETRY_ATTEMPTS}`,
                { url: webhook.url, eventType: payload.eventType },
            );

            const controller = new AbortController();
            const timeoutId = setTimeout(
                () => controller.abort(),
                WEBHOOK_TIMEOUT_MS,
            );

            const response = await fetch(webhook.url, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-Webhook-Signature": signature,
                    "X-Webhook-Event": payload.eventType,
                    "X-Webhook-ID": payload.eventId,
                    "User-Agent": "BEAGLE-Webhook/1.0",
                },
                body: payloadString,
                signal: controller.signal,
            });

            clearTimeout(timeoutId);

            // Success: 2xx status codes
            if (response.ok) {
                logger.info(
                    `Webhook ${webhook.id} delivered successfully (attempt ${attempt})`,
                    {
                        url: webhook.url,
                        eventType: payload.eventType,
                        status: response.status,
                    },
                );
                return { success: true, attempts: attempt };
            }

            // Client errors (4xx) - don't retry
            if (response.status >= 400 && response.status < 500) {
                lastError = `Client error ${response.status}: ${response.statusText}`;
                logger.warn(`Webhook ${webhook.id} failed with client error`, {
                    status: response.status,
                    url: webhook.url,
                });
                break;
            }

            // Server errors (5xx) - retry
            lastError = `Server error ${response.status}: ${response.statusText}`;
            logger.warn(`Webhook ${webhook.id} attempt ${attempt} failed`, {
                status: response.status,
                url: webhook.url,
            });
        } catch (error) {
            if (error instanceof Error && error.name === "AbortError") {
                lastError = `Request timeout after ${WEBHOOK_TIMEOUT_MS}ms`;
                logger.warn(`Webhook ${webhook.id} attempt ${attempt} timed out`, {
                    url: webhook.url,
                });
            } else {
                lastError = error instanceof Error ? error.message : String(error);
                logger.warn(
                    `Webhook ${webhook.id} attempt ${webhook.id} failed`,
                    {
                        error: lastError,
                        url: webhook.url,
                    },
                );
            }
        }

        // Wait before retry (except on last attempt)
        if (attempt < MAX_RETRY_ATTEMPTS) {
            const delay =
                INITIAL_RETRY_DELAY_MS *
                Math.pow(RETRY_BACKOFF_MULTIPLIER, attempt - 1);
            logger.debug(`Retrying webhook ${webhook.id} in ${delay}ms`);
            await sleep(delay);
        }
    }

    logger.error(`Webhook ${webhook.id} failed after ${MAX_RETRY_ATTEMPTS} attempts`, {
        url: webhook.url,
        lastError,
    });

    return { success: false, attempts: MAX_RETRY_ATTEMPTS, lastError };
}

/**
 * Trigger webhooks for an event
 */
export async function triggerEvent(
    eventType: WebhookEventType,
    data: unknown,
    context?: { jobType?: string; pipelineType?: string },
): Promise<void> {
    // Find all webhooks subscribed to this event
    const webhooks = findWebhooksForEvent(eventType, context);

    if (webhooks.length === 0) {
        logger.debug(`No webhooks registered for event ${eventType}`);
        return;
    }

    // Create payload
    const payload: WebhookPayload = {
        eventId: generateEventId(),
        eventType,
        timestamp: new Date().toISOString(),
        data,
    };

    logger.info(`Triggering ${webhooks.length} webhooks for event ${eventType}`, {
        eventId: payload.eventId,
    });

    // Send to all webhooks concurrently
    const results = await Promise.allSettled(
        webhooks.map(async (webhook) => {
            // Record delivery attempt
            const attempt = await recordDeliveryAttempt(
                webhook.id,
                eventType,
                payload,
                webhook.url,
            );

            // Send webhook
            const result = await sendWebhook(webhook, payload);

            // Update delivery record
            await updateDeliveryAttempt(
                attempt.id,
                result.success ? "delivered" : "failed",
                result.lastError,
                result.success ? 200 : undefined,
            );

            return { webhook, result };
        }),
    );

    // Log results
    const successful = results.filter(
        (r) => r.status === "fulfilled" && r.value.result.success,
    ).length;
    const failed = results.length - successful;

    logger.info(`Webhook delivery complete for ${eventType}`, {
        successful,
        failed,
        total: webhooks.length,
    });
}

/**
 * Send test event to a specific webhook
 */
export async function sendTestEvent(
    webhookId: string,
): Promise<{ success: boolean; error?: string }> {
    const webhook = getWebhook(webhookId);
    if (!webhook) {
        return { success: false, error: "Webhook not found" };
    }

    if (!webhook.isActive) {
        return { success: false, error: "Webhook is inactive" };
    }

    const testPayload: WebhookPayload = {
        eventId: generateEventId(),
        eventType: "pipeline.complete",
        timestamp: new Date().toISOString(),
        data: {
            test: true,
            message: "This is a test event from BEAGLE webhook system",
            webhook_id: webhookId,
        },
    };

    // Record attempt
    const attempt = await recordDeliveryAttempt(
        webhookId,
        "pipeline.complete",
        testPayload,
        webhook.url,
    );

    // Send
    const result = await sendWebhook(webhook, testPayload);

    // Update record
    await updateDeliveryAttempt(
        attempt.id,
        result.success ? "delivered" : "failed",
        result.lastError,
        result.success ? 200 : undefined,
    );

    return {
        success: result.success,
        error: result.lastError,
    };
}

/**
 * Get webhook delivery statistics
 */
export function getWebhookStats(webhookId: string): {
    total: number;
    delivered: number;
    failed: number;
    pending: number;
} {
    const attempts = getDeliveryAttempts(webhookId);

    return {
        total: attempts.length,
        delivered: attempts.filter((a) => a.status === "delivered").length,
        failed: attempts.filter((a) => a.status === "failed").length,
        pending: attempts.filter((a) => a.status === "pending").length,
    };
}

/**
 * Sleep utility
 */
function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Generate unique event ID
 */
function generateEventId(): string {
    return `evt_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
}

// Export event types for convenience
export { WebhookEventType };
