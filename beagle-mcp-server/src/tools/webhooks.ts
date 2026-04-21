/**
 * Webhook Management Tools
 *
 * MCP tools for registering, managing, and testing webhooks.
 */

import { z } from "zod";
import { BeagleClient } from "../beagle-client.js";
import { McpTool } from "./index.js";
import {
    registerWebhook,
    unregisterWebhook,
    getWebhook,
    listWebhooks,
    setWebhookActive,
    getDeliveryAttempts,
    WebhookEventType,
    initializeStore,
    startPersistence,
} from "../webhook-store.js";
import { sendTestEvent, generateSignature } from "../webhooks.js";
import { sanitizeOutput } from "../security.js";
import { logger } from "../logger.js";

// Initialize store on module load
initializeStore().then(() => {
    startPersistence();
    logger.info("Webhook store initialized");
});

// Valid event types
const VALID_EVENT_TYPES: WebhookEventType[] = [
    "pipeline.complete",
    "pipeline.failed",
    "science_job.complete",
    "science_job.failed",
    "memory.ingest_complete",
];

// Schemas
const RegisterWebhookSchema = z.object({
    url: z.string().url().describe("URL to send webhook events to"),
    secret: z
        .string()
        .min(16)
        .describe("Secret for HMAC-SHA256 signature verification (min 16 chars)"),
    event_types: z
        .array(z.enum(["pipeline.complete", "pipeline.failed", "science_job.complete", "science_job.failed", "memory.ingest_complete"]))
        .min(1)
        .describe("Event types to subscribe to"),
    description: z.string().optional().describe("Optional description for this webhook"),
    filters: z
        .object({
            job_type: z.string().optional().describe("Filter: only specific job types"),
            pipeline_type: z.string().optional().describe("Filter: only specific pipeline types"),
        })
        .optional()
        .describe("Optional filters to limit which events trigger this webhook"),
});

const UnregisterWebhookSchema = z.object({
    webhook_id: z.string().describe("ID of the webhook to unregister"),
});

const GetWebhookSchema = z.object({
    webhook_id: z.string().describe("ID of the webhook to retrieve"),
});

const TestWebhookSchema = z.object({
    webhook_id: z.string().describe("ID of the webhook to test"),
});

const SetWebhookStatusSchema = z.object({
    webhook_id: z.string().describe("ID of the webhook"),
    active: z.boolean().describe("Set to true to activate, false to deactivate"),
});

const GetWebhookDeliveriesSchema = z.object({
    webhook_id: z.string().describe("ID of the webhook"),
});

const GenerateSignatureSchema = z.object({
    payload: z.string().describe("JSON payload to sign"),
    secret: z.string().describe("Webhook secret"),
});

export function webhookTools(_client: BeagleClient): McpTool[] {
    return [
        {
            name: "beagle_webhook_register",
            description: `Register a new webhook to receive notifications when async jobs complete.

Instead of polling for job status, external systems can register webhooks to receive:
- pipeline.complete - When a BEAGLE pipeline finishes successfully
- pipeline.failed - When a pipeline fails
- science_job.complete - When a science job (PBPK, Helio, etc.) completes
- science_job.failed - When a science job fails
- memory.ingest_complete - When memory ingestion completes

Each webhook:
- Requires a URL and secret (for HMAC-SHA256 signature verification)
- Can subscribe to multiple event types
- Can optionally filter by job/pipeline type
- Includes 3 retry attempts with exponential backoff

Returns a webhook_id for management.`,
            inputSchema: {
                type: "object",
                properties: {
                    url: {
                        type: "string",
                        description: "URL to send webhook events to (must be HTTPS in production)",
                    },
                    secret: {
                        type: "string",
                        description: "Secret for HMAC-SHA256 signature verification (min 16 chars)",
                    },
                    event_types: {
                        type: "array",
                        items: {
                            type: "string",
                            enum: VALID_EVENT_TYPES,
                        },
                        description: "Event types to subscribe to",
                    },
                    description: {
                        type: "string",
                        description: "Optional description for this webhook",
                    },
                    filters: {
                        type: "object",
                        properties: {
                            job_type: {
                                type: "string",
                                description: "Filter: only specific job types (e.g., 'pbpk', 'helio')",
                            },
                            pipeline_type: {
                                type: "string",
                                description: "Filter: only specific pipeline types",
                            },
                        },
                    },
                },
                required: ["url", "secret", "event_types"],
            },
            handler: async (args: unknown) => {
                const {
                    url,
                    secret,
                    event_types,
                    description,
                    filters,
                } = RegisterWebhookSchema.parse(args);

                const webhook = await registerWebhook(url, secret, event_types, {
                    description,
                    filters: filters
                        ? {
                              jobType: filters.job_type,
                              pipelineType: filters.pipeline_type,
                          }
                        : undefined,
                });

                return sanitizeOutput({
                    success: true,
                    webhook_id: webhook.id,
                    url: webhook.url,
                    event_types: webhook.eventTypes,
                    is_active: webhook.isActive,
                    created_at: webhook.createdAt,
                    message: `Webhook registered successfully. Use webhook_id '${webhook.id}' to manage or test this webhook.`,
                });
            },
        },
        {
            name: "beagle_webhook_list",
            description: `List all registered webhooks with their status and configuration.

Returns:
- webhook_id
- url
- event_types subscribed
- is_active status
- created_at timestamp
- description (if set)`,
            inputSchema: {
                type: "object",
                properties: {},
            },
            handler: async () => {
                const webhooks = listWebhooks();

                return sanitizeOutput({
                    count: webhooks.length,
                    webhooks: webhooks.map((w) => ({
                        webhook_id: w.id,
                        url: w.url,
                        event_types: w.eventTypes,
                        is_active: w.isActive,
                        created_at: w.createdAt,
                        description: w.description,
                    })),
                });
            },
        },
        {
            name: "beagle_webhook_get",
            description: `Get detailed information about a specific webhook.

Returns full configuration including filters and delivery statistics.`,
            inputSchema: {
                type: "object",
                properties: {
                    webhook_id: {
                        type: "string",
                        description: "ID of the webhook to retrieve",
                    },
                },
                required: ["webhook_id"],
            },
            handler: async (args: unknown) => {
                const { webhook_id } = GetWebhookSchema.parse(args);
                const webhook = getWebhook(webhook_id);

                if (!webhook) {
                    return sanitizeOutput({
                        success: false,
                        error: `Webhook '${webhook_id}' not found`,
                    });
                }

                const attempts = getDeliveryAttempts(webhook_id);
                const recentAttempts = attempts.slice(-10).reverse(); // Last 10, newest first

                return sanitizeOutput({
                    webhook_id: webhook.id,
                    url: webhook.url,
                    event_types: webhook.eventTypes,
                    filters: webhook.filters,
                    is_active: webhook.isActive,
                    created_at: webhook.createdAt,
                    updated_at: webhook.updatedAt,
                    description: webhook.description,
                    delivery_stats: {
                        total_attempts: attempts.length,
                        delivered: attempts.filter((a) => a.status === "delivered").length,
                        failed: attempts.filter((a) => a.status === "failed").length,
                        pending: attempts.filter((a) => a.status === "pending").length,
                    },
                    recent_attempts: recentAttempts.map((a) => ({
                        attempt_id: a.id,
                        event_type: a.eventType,
                        status: a.status,
                        attempts: a.attempts,
                        last_attempt_at: a.lastAttemptAt,
                        error: a.error,
                    })),
                });
            },
        },
        {
            name: "beagle_webhook_unregister",
            description: `Unregister (delete) a webhook by ID.

This permanently removes the webhook and stops all deliveries.`,
            inputSchema: {
                type: "object",
                properties: {
                    webhook_id: {
                        type: "string",
                        description: "ID of the webhook to unregister",
                    },
                },
                required: ["webhook_id"],
            },
            handler: async (args: unknown) => {
                const { webhook_id } = UnregisterWebhookSchema.parse(args);
                const deleted = await unregisterWebhook(webhook_id);

                if (!deleted) {
                    return sanitizeOutput({
                        success: false,
                        error: `Webhook '${webhook_id}' not found`,
                    });
                }

                return sanitizeOutput({
                    success: true,
                    message: `Webhook '${webhook_id}' unregistered successfully`,
                });
            },
        },
        {
            name: "beagle_webhook_set_status",
            description: `Activate or deactivate a webhook.

When deactivated, the webhook will not receive any events but remains registered.`,
            inputSchema: {
                type: "object",
                properties: {
                    webhook_id: {
                        type: "string",
                        description: "ID of the webhook",
                    },
                    active: {
                        type: "boolean",
                        description: "Set to true to activate, false to deactivate",
                    },
                },
                required: ["webhook_id", "active"],
            },
            handler: async (args: unknown) => {
                const { webhook_id, active } = SetWebhookStatusSchema.parse(args);
                const webhook = await setWebhookActive(webhook_id, active);

                if (!webhook) {
                    return sanitizeOutput({
                        success: false,
                        error: `Webhook '${webhook_id}' not found`,
                    });
                }

                return sanitizeOutput({
                    success: true,
                    webhook_id: webhook.id,
                    is_active: webhook.isActive,
                    message: `Webhook '${webhook_id}' is now ${active ? "active" : "inactive"}`,
                });
            },
        },
        {
            name: "beagle_webhook_test",
            description: `Send a test event to a registered webhook.

This sends a test 'pipeline.complete' event to verify:
- URL is reachable
- Secret is correct (HMAC signature)
- Endpoint responds with 2xx

Returns delivery result and any error details.`,
            inputSchema: {
                type: "object",
                properties: {
                    webhook_id: {
                        type: "string",
                        description: "ID of the webhook to test",
                    },
                },
                required: ["webhook_id"],
            },
            handler: async (args: unknown) => {
                const { webhook_id } = TestWebhookSchema.parse(args);
                const result = await sendTestEvent(webhook_id);

                return sanitizeOutput({
                    success: result.success,
                    webhook_id,
                    test_event: "pipeline.complete",
                    error: result.error,
                    message: result.success
                        ? "Test event delivered successfully"
                        : `Test event failed: ${result.error}`,
                });
            },
        },
        {
            name: "beagle_webhook_generate_signature",
            description: `Generate HMAC-SHA256 signature for a payload.

Useful for:
- Testing signature verification in your webhook endpoint
- Debugging signature mismatches
- Understanding the signature format

Returns the signature that would be sent in the X-Webhook-Signature header.`,
            inputSchema: {
                type: "object",
                properties: {
                    payload: {
                        type: "string",
                        description: "JSON payload to sign",
                    },
                    secret: {
                        type: "string",
                        description: "Webhook secret",
                    },
                },
                required: ["payload", "secret"],
            },
            handler: async (args: unknown) => {
                const { payload, secret } = GenerateSignatureSchema.parse(args);

                try {
                    // Validate JSON
                    JSON.parse(payload);
                } catch {
                    return sanitizeOutput({
                        success: false,
                        error: "Invalid JSON payload",
                    });
                }

                const signature = generateSignature(payload, secret);

                return sanitizeOutput({
                    success: true,
                    signature,
                    header_name: "X-Webhook-Signature",
                    header_value: signature,
                    example_headers: {
                        "X-Webhook-Signature": signature,
                        "X-Webhook-Event": "pipeline.complete",
                        "Content-Type": "application/json",
                    },
                });
            },
        },
    ];
}
