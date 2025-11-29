// WebSocket-specific metrics
//
// References:
// - Prometheus best practices
// - RED Method (Rate, Errors, Duration)

use prometheus::{register_counter_vec, register_gauge_vec, register_histogram_vec};
use prometheus::{CounterVec, GaugeVec, HistogramVec};
use std::sync::Arc;

pub struct WebSocketMetrics {
    pub connections_total: CounterVec,
    pub disconnections_total: CounterVec,
    pub messages_sent: CounterVec,
    pub messages_received: CounterVec,
    pub message_size_bytes: HistogramVec,
    pub message_latency_seconds: HistogramVec,
    pub active_connections: GaugeVec,
    pub subscription_count: GaugeVec,
    pub sync_operations: CounterVec,
    pub broadcast_count: CounterVec,
}

impl WebSocketMetrics {
    pub fn new() -> Self {
        Self {
            connections_total: register_counter_vec!(
                "websocket_connections_total",
                "Total number of WebSocket connections",
                &["protocol", "auth_type"]
            )
            .unwrap(),

            disconnections_total: register_counter_vec!(
                "websocket_disconnections_total",
                "Total number of WebSocket disconnections",
                &["reason"]
            )
            .unwrap(),

            messages_sent: register_counter_vec!(
                "websocket_messages_sent_total",
                "Total messages sent",
                &["type", "target"]
            )
            .unwrap(),

            messages_received: register_counter_vec!(
                "websocket_messages_received_total",
                "Total messages received",
                &["type"]
            )
            .unwrap(),

            message_size_bytes: register_histogram_vec!(
                "websocket_message_size_bytes",
                "Message size in bytes",
                &["direction", "type"]
            )
            .unwrap(),

            message_latency_seconds: register_histogram_vec!(
                "websocket_message_latency_seconds",
                "Message processing latency",
                &["type"]
            )
            .unwrap(),

            active_connections: register_gauge_vec!(
                "websocket_active_connections",
                "Number of active connections",
                &["state"]
            )
            .unwrap(),

            subscription_count: register_gauge_vec!(
                "websocket_subscription_count",
                "Number of topic subscriptions",
                &["topic"]
            )
            .unwrap(),

            sync_operations: register_counter_vec!(
                "websocket_sync_operations_total",
                "Total sync operations",
                &["type", "result"]
            )
            .unwrap(),

            broadcast_count: register_counter_vec!(
                "websocket_broadcast_total",
                "Total broadcast messages",
                &["result"]
            )
            .unwrap(),
        }
    }

    pub fn record_connection(&self, protocol: &str, auth_type: &str) {
        self.connections_total
            .with_label_values(&[protocol, auth_type])
            .inc();

        self.active_connections
            .with_label_values(&["connected"])
            .inc();
    }

    pub fn record_disconnection(&self, reason: &str) {
        self.disconnections_total.with_label_values(&[reason]).inc();

        self.active_connections
            .with_label_values(&["connected"])
            .dec();
    }

    pub fn record_message_sent(&self, msg_type: &str, target: &str, size: usize) {
        self.messages_sent
            .with_label_values(&[msg_type, target])
            .inc();

        self.message_size_bytes
            .with_label_values(&["outbound", msg_type])
            .observe(size as f64);
    }

    pub fn record_message_received(&self, msg_type: &str, size: usize) {
        self.messages_received.with_label_values(&[msg_type]).inc();

        self.message_size_bytes
            .with_label_values(&["inbound", msg_type])
            .observe(size as f64);
    }

    pub fn record_sync_operation(&self) {
        self.sync_operations
            .with_label_values(&["sync", "success"])
            .inc();
    }

    pub fn record_broadcast(&self) {
        self.broadcast_count.with_label_values(&["success"]).inc();
    }
}

pub struct ConnectionMetrics {
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub messages_sent: u64,
    pub messages_received: u64,
    pub errors: u64,
    pub latency_ms: f64,
}

pub struct MessageMetrics {
    pub processing_time_ms: f64,
    pub queue_time_ms: f64,
    pub serialization_time_ms: f64,
}
