#!/usr/bin/env node
/**
 * Example Webhook Receiver for BEAGLE (Node.js/Express)
 *
 * A simple Express server that receives and validates BEAGLE webhooks.
 *
 * Setup:
 *   npm install express
 *
 * Usage:
 *   node webhook-receiver.js [port]
 *
 * Example:
 *   node webhook-receiver.js 8000
 *
 * Then register the webhook in BEAGLE:
 *   beagle_webhook_register
 *     url: http://localhost:8000/webhook
 *     secret: my_test_secret_12345
 *     event_types: ["pipeline.complete"]
 */

const http = require("http");
const crypto = require("crypto");

// Configuration
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || "my_test_secret_12345";
const PORT = parseInt(process.argv[2], 10) || 8000;

/**
 * Verify HMAC-SHA256 signature
 */
function verifySignature(payload, signature, secret) {
    if (!signature.startsWith("sha256=")) {
        return false;
    }

    const expected = `sha256=${crypto
        .createHmac("sha256", secret)
        .update(payload)
        .digest("hex")}`;

    try {
        return crypto.timingSafeEqual(
            Buffer.from(signature),
            Buffer.from(expected)
        );
    } catch {
        return false;
    }
}

/**
 * Handle webhook requests
 */
function handleWebhook(req, res) {
    const chunks = [];

    req.on("data", (chunk) => chunks.push(chunk));

    req.on("end", () => {
        const body = Buffer.concat(chunks);
        const signature = req.headers["x-webhook-signature"] || "";
        const eventType = req.headers["x-webhook-event"] || "unknown";
        const eventId = req.headers["x-webhook-id"] || "unknown";

        console.log("\n" + "=".repeat(60));
        console.log(`Received webhook: ${eventType}`);
        console.log(`Event ID: ${eventId}`);
        console.log("=".repeat(60));

        // Verify signature
        if (!verifySignature(body, signature, WEBHOOK_SECRET)) {
            console.log("WARNING: Invalid signature!");
            res.writeHead(401, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: "Invalid signature" }));
            return;
        }

        console.log("Signature: VERIFIED");

        // Parse and display payload
        try {
            const payload = JSON.parse(body.toString());
            console.log("\nPayload:");
            console.log(JSON.stringify(payload, null, 2));

            // Handle specific event types
            handleEvent(eventType, payload);
        } catch (error) {
            console.log(`Error parsing JSON: ${error.message}`);
            console.log(`Raw body: ${body.toString()}`);
        }

        // Send success response
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ status: "received" }));

        console.log("\n" + "=".repeat(60));
        console.log("Response: 200 OK");
        console.log("=".repeat(60) + "\n");
    });
}

/**
 * Handle specific event types
 */
function handleEvent(eventType, payload) {
    const data = payload.data || {};

    switch (eventType) {
        case "pipeline.complete":
            console.log("\n✅ Pipeline completed!");
            console.log(`  Run ID: ${data.run_id}`);
            console.log(`  Question: ${data.question}`);
            break;

        case "pipeline.failed":
            console.log("\n❌ Pipeline failed!");
            console.log(`  Run ID: ${data.run_id}`);
            console.log(`  Error: ${data.error}`);
            break;

        case "science_job.complete":
            console.log("\n✅ Science job completed!");
            console.log(`  Job ID: ${data.job_id}`);
            console.log(`  Kind: ${data.kind}`);
            break;

        case "science_job.failed":
            console.log("\n❌ Science job failed!");
            console.log(`  Job ID: ${data.job_id}`);
            console.log(`  Error: ${data.error}`);
            break;

        case "memory.ingest_complete":
            console.log("\n✅ Memory ingestion complete!");
            console.log(`  Memory ID: ${data.memory_id}`);
            console.log(`  Source: ${data.source}`);
            break;

        default:
            console.log(`\nUnknown event type: ${eventType}`);
    }
}

// Create server
const server = http.createServer((req, res) => {
    // CORS headers for browser access
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, X-Webhook-Signature, X-Webhook-Event, X-Webhook-ID");

    if (req.method === "OPTIONS") {
        res.writeHead(200);
        res.end();
        return;
    }

    if (req.url === "/webhook" && req.method === "POST") {
        handleWebhook(req, res);
    } else if (req.url === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ status: "ok" }));
    } else {
        res.writeHead(404, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Not found" }));
    }
});

// Start server
server.listen(PORT, () => {
    console.log(`Starting webhook receiver on port ${PORT}`);
    console.log(`Webhook endpoint: http://localhost:${PORT}/webhook`);
    console.log(`Health check: http://localhost:${PORT}/health`);
    console.log(`Secret: ${WEBHOOK_SECRET}`);
    console.log(`\nPress Ctrl+C to stop\n`);
});

// Graceful shutdown
process.on("SIGINT", () => {
    console.log("\nShutting down...");
    server.close(() => {
        process.exit(0);
    });
});
