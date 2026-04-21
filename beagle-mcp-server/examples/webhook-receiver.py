#!/usr/bin/env python3
"""
Example Webhook Receiver for BEAGLE

A simple HTTP server that receives and validates BEAGLE webhooks.
Use this for testing webhook delivery before implementing your own endpoint.

Usage:
    python webhook-receiver.py [port]

Example:
    python webhook-receiver.py 8000

Then register the webhook in BEAGLE:
    beagle_webhook_register
      url: http://localhost:8000/webhook
      secret: my_test_secret_12345
      event_types: ["pipeline.complete"]
"""

import sys
import json
import hmac
import hashlib
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

# Configuration
WEBHOOK_SECRET = "my_test_secret_12345"  # Change this to match your registered secret


def verify_signature(payload: bytes, signature: str, secret: str) -> bool:
    """Verify HMAC-SHA256 signature."""
    if not signature.startswith("sha256="):
        return False

    expected = f"sha256={hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()}"
    return hmac.compare_digest(expected.encode(), signature.encode())


class WebhookHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        """Custom logging with timestamps."""
        timestamp = datetime.now().isoformat()
        print(f"[{timestamp}] {format % args}")

    def do_post(self):
        """Handle POST requests (webhook deliveries)."""
        if self.path != "/webhook":
            self.send_error(404)
            return

        # Read request body
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        # Get signature from header
        signature = self.headers.get("X-Webhook-Signature", "")
        event_type = self.headers.get("X-Webhook-Event", "unknown")
        event_id = self.headers.get("X-Webhook-ID", "unknown")

        print(f"\n{'='*60}")
        print(f"Received webhook: {event_type}")
        print(f"Event ID: {event_id}")
        print(f"{'='*60}")

        # Verify signature
        if not verify_signature(body, signature, WEBHOOK_SECRET):
            print("WARNING: Invalid signature!")
            self.send_error(401, "Invalid signature")
            return

        print("Signature: VERIFIED")

        # Parse and display payload
        try:
            payload = json.loads(body)
            print(f"\nPayload:")
            print(json.dumps(payload, indent=2))

            # Handle specific event types
            self.handle_event(event_type, payload)

        except json.JSONDecodeError as e:
            print(f"Error parsing JSON: {e}")
            print(f"Raw body: {body.decode()}")

        # Send success response
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "received" }).encode())

        print(f"\n{'='*60}")
        print("Response: 200 OK")
        print(f"{'='*60}\n")

    def handle_event(self, event_type: str, payload: dict):
        """Handle specific event types."""
        data = payload.get("data", {})

        if event_type == "pipeline.complete":
            print(f"\n Pipeline completed!")
            print(f"  Run ID: {data.get('run_id')}")
            print(f"  Question: {data.get('question')}")

        elif event_type == "pipeline.failed":
            print(f"\n Pipeline failed!")
            print(f"  Run ID: {data.get('run_id')}")
            print(f"  Error: {data.get('error')}")

        elif event_type == "science_job.complete":
            print(f"\n Science job completed!")
            print(f"  Job ID: {data.get('job_id')}")
            print(f"  Kind: {data.get('kind')}")

        elif event_type == "science_job.failed":
            print(f"\n Science job failed!")
            print(f"  Job ID: {data.get('job_id')}")
            print(f"  Error: {data.get('error')}")

        elif event_type == "memory.ingest_complete":
            print(f"\n Memory ingestion complete!")
            print(f"  Memory ID: {data.get('memory_id')}")
            print(f"  Source: {data.get('source')}")

        else:
            print(f"\n Unknown event type: {event_type}")


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000

    server = HTTPServer(("", port), WebhookHandler)
    print(f"Starting webhook receiver on port {port}")
    print(f"Webhook endpoint: http://localhost:{port}/webhook")
    print(f"Secret: {WEBHOOK_SECRET}")
    print(f"\nPress Ctrl+C to stop\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
