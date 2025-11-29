//! Distributed tracing with optional OpenTelemetry integration
//!
//! This module provides distributed tracing capabilities with an optional
//! OpenTelemetry backend for exporting traces.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Span context for distributed tracing
#[derive(Debug, Clone)]
pub struct SpanContext {
    pub trace_id: String,
    pub span_id: String,
    pub parent_span_id: Option<String>,
    pub operation_name: String,
    pub start_time: Instant,
    pub attributes: HashMap<String, String>,
    pub events: Vec<SpanEvent>,
    pub status: SpanStatus,
}

impl SpanContext {
    /// Create new span context
    pub fn new(operation_name: &str, parent: Option<&SpanContext>) -> Self {
        let trace_id = if let Some(p) = parent {
            p.trace_id.clone()
        } else {
            uuid::Uuid::new_v4().to_string()
        };

        let parent_span_id = parent.map(|p| p.span_id.clone());

        Self {
            trace_id,
            span_id: uuid::Uuid::new_v4().to_string(),
            parent_span_id,
            operation_name: operation_name.to_string(),
            start_time: Instant::now(),
            attributes: HashMap::new(),
            events: Vec::new(),
            status: SpanStatus::Ok,
        }
    }

    /// Add attribute
    pub fn add_attribute(&mut self, key: &str, value: &str) {
        self.attributes.insert(key.to_string(), value.to_string());
    }

    /// Add event
    pub fn add_event(&mut self, event: SpanEvent) {
        self.events.push(event);
    }

    /// Set status
    pub fn set_status(&mut self, status: SpanStatus) {
        self.status = status;
    }

    /// Get duration
    pub fn duration(&self) -> Duration {
        self.start_time.elapsed()
    }
}

/// Span event
#[derive(Debug, Clone)]
pub struct SpanEvent {
    pub name: String,
    pub timestamp: Instant,
    pub attributes: HashMap<String, String>,
}

/// Span status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SpanStatus {
    Ok,
    Error(String),
    Cancelled,
}

/// Serializable span data for export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpanData {
    pub trace_id: String,
    pub span_id: String,
    pub parent_span_id: Option<String>,
    pub operation_name: String,
    pub duration_ms: u64,
    pub attributes: HashMap<String, String>,
    pub events: Vec<SpanEventData>,
    pub status: SpanStatus,
}

impl From<&SpanContext> for SpanData {
    fn from(ctx: &SpanContext) -> Self {
        Self {
            trace_id: ctx.trace_id.clone(),
            span_id: ctx.span_id.clone(),
            parent_span_id: ctx.parent_span_id.clone(),
            operation_name: ctx.operation_name.clone(),
            duration_ms: ctx.duration().as_millis() as u64,
            attributes: ctx.attributes.clone(),
            events: ctx.events.iter().map(SpanEventData::from).collect(),
            status: ctx.status.clone(),
        }
    }
}

/// Serializable span event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpanEventData {
    pub name: String,
    pub attributes: HashMap<String, String>,
}

impl From<&SpanEvent> for SpanEventData {
    fn from(event: &SpanEvent) -> Self {
        Self {
            name: event.name.clone(),
            attributes: event.attributes.clone(),
        }
    }
}

/// Distributed trace
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DistributedTrace {
    pub trace_id: String,
    pub root_span: SpanData,
    pub spans: Vec<SpanData>,
    pub total_duration_ms: u64,
    pub service_map: HashMap<String, Vec<String>>,
}

impl DistributedTrace {
    /// Build from spans
    pub fn from_spans(spans: Vec<SpanContext>) -> Option<Self> {
        if spans.is_empty() {
            return None;
        }

        // Find root span (no parent)
        let root_span = spans.iter().find(|s| s.parent_span_id.is_none())?;

        // Build service map
        let mut service_map: HashMap<String, Vec<String>> = HashMap::new();
        for span in &spans {
            if let Some(service) = span.attributes.get("service.name") {
                service_map
                    .entry(service.clone())
                    .or_default()
                    .push(span.operation_name.clone());
            }
        }

        // Calculate total duration
        let total_duration = spans.iter().map(|s| s.duration()).max().unwrap_or_default();

        Some(Self {
            trace_id: root_span.trace_id.clone(),
            root_span: SpanData::from(root_span),
            spans: spans.iter().map(SpanData::from).collect(),
            total_duration_ms: total_duration.as_millis() as u64,
            service_map,
        })
    }

    /// Get critical path (longest execution path)
    pub fn critical_path(&self) -> Vec<&SpanData> {
        let mut path = Vec::new();
        let mut current = &self.root_span;
        path.push(current);

        while let Some(child) = self
            .spans
            .iter()
            .filter(|s| s.parent_span_id.as_ref() == Some(&current.span_id))
            .max_by_key(|s| s.duration_ms)
        {
            path.push(child);
            current = child;
        }

        path
    }

    /// Get error spans
    pub fn error_spans(&self) -> Vec<&SpanData> {
        self.spans
            .iter()
            .filter(|s| matches!(s.status, SpanStatus::Error(_)))
            .collect()
    }
}

/// Trace collector (without OpenTelemetry dependency)
pub struct TraceCollector {
    active_spans: Arc<RwLock<HashMap<String, SpanContext>>>,
    completed_traces: Arc<RwLock<Vec<DistributedTrace>>>,
    config: TracingConfig,
}

impl TraceCollector {
    /// Create new trace collector
    pub fn new(config: TracingConfig) -> Result<Self> {
        Ok(Self {
            active_spans: Arc::new(RwLock::new(HashMap::new())),
            completed_traces: Arc::new(RwLock::new(Vec::new())),
            config,
        })
    }

    /// Start a new span
    pub async fn start_span(&self, name: &str, parent: Option<SpanContext>) -> Result<SpanContext> {
        let mut span = SpanContext::new(name, parent.as_ref());

        // Add default attributes
        span.add_attribute("service.name", &self.config.service_name);
        span.add_attribute("span.kind", "internal");

        // Store active span
        let mut active = self.active_spans.write().await;
        active.insert(span.span_id.clone(), span.clone());

        Ok(span)
    }

    /// End a span
    pub async fn end_span(&self, span: SpanContext) -> Result<()> {
        // Remove from active spans
        let mut active = self.active_spans.write().await;
        active.remove(&span.span_id);

        // Check if this completes a trace
        if span.parent_span_id.is_none() {
            // This is a root span, collect all child spans
            let child_spans: Vec<SpanContext> = active
                .values()
                .filter(|s| s.trace_id == span.trace_id)
                .cloned()
                .collect();

            // Build complete trace
            let mut all_spans = vec![span.clone()];
            all_spans.extend(child_spans);

            if let Some(trace) = DistributedTrace::from_spans(all_spans) {
                let mut completed = self.completed_traces.write().await;
                completed.push(trace);

                // Keep only recent traces
                if completed.len() > self.config.max_traces {
                    let drain_count = completed.len() - self.config.max_traces;
                    completed.drain(0..drain_count);
                }
            }
        }

        Ok(())
    }

    /// Add event to span
    pub async fn add_span_event(
        &self,
        span_id: &str,
        name: &str,
        attributes: HashMap<String, String>,
    ) -> Result<()> {
        let mut active = self.active_spans.write().await;

        if let Some(span) = active.get_mut(span_id) {
            span.add_event(SpanEvent {
                name: name.to_string(),
                timestamp: Instant::now(),
                attributes,
            });
        }

        Ok(())
    }

    /// Set span status
    pub async fn set_span_status(&self, span_id: &str, status: SpanStatus) -> Result<()> {
        let mut active = self.active_spans.write().await;

        if let Some(span) = active.get_mut(span_id) {
            span.set_status(status);
        }

        Ok(())
    }

    /// Get recent traces
    pub async fn get_recent(&self, limit: usize) -> Result<Vec<DistributedTrace>> {
        let completed = self.completed_traces.read().await;
        let start = completed.len().saturating_sub(limit);
        Ok(completed[start..].to_vec())
    }

    /// Get trace by ID
    pub async fn get_trace(&self, trace_id: &str) -> Result<Option<DistributedTrace>> {
        let completed = self.completed_traces.read().await;
        Ok(completed.iter().find(|t| t.trace_id == trace_id).cloned())
    }

    /// Get active spans
    pub async fn get_active_spans(&self) -> Result<Vec<SpanData>> {
        let active = self.active_spans.read().await;
        Ok(active.values().map(SpanData::from).collect())
    }

    /// Export trace data
    pub async fn export(&self) -> Result<TraceExport> {
        let completed = self.completed_traces.read().await;
        let active = self.active_spans.read().await;

        // Calculate statistics
        let total_traces = completed.len();
        let total_spans: usize = completed.iter().map(|t| t.spans.len()).sum();
        let error_traces = completed
            .iter()
            .filter(|t| !t.error_spans().is_empty())
            .count();

        let avg_duration = if !completed.is_empty() {
            completed.iter().map(|t| t.total_duration_ms).sum::<u64>() / completed.len() as u64
        } else {
            0
        };

        // Service statistics
        let mut service_calls: HashMap<String, usize> = HashMap::new();
        for trace in completed.iter() {
            for (service, ops) in &trace.service_map {
                *service_calls.entry(service.clone()).or_default() += ops.len();
            }
        }

        Ok(TraceExport {
            total_traces,
            total_spans,
            active_spans: active.len(),
            error_traces,
            avg_duration_ms: avg_duration,
            service_calls,
            recent_traces: completed.clone(),
        })
    }
}

impl Default for TraceCollector {
    fn default() -> Self {
        Self::new(TracingConfig::default()).unwrap()
    }
}

/// Trace export data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceExport {
    pub total_traces: usize,
    pub total_spans: usize,
    pub active_spans: usize,
    pub error_traces: usize,
    pub avg_duration_ms: u64,
    pub service_calls: HashMap<String, usize>,
    pub recent_traces: Vec<DistributedTrace>,
}

/// Tracing configuration
#[derive(Debug, Clone)]
pub struct TracingConfig {
    pub service_name: String,
    pub max_traces: usize,
    pub sampling_rate: f64,
}

impl Default for TracingConfig {
    fn default() -> Self {
        Self {
            service_name: "beagle-observer".to_string(),
            max_traces: 1000,
            sampling_rate: 1.0,
        }
    }
}

/// Trace context propagation
pub struct TracePropagator;

impl TracePropagator {
    /// Extract trace context from headers
    pub fn extract(headers: &HashMap<String, String>) -> Option<(String, String)> {
        let trace_id = headers.get("x-trace-id")?;
        let parent_id = headers.get("x-span-id")?;
        Some((trace_id.clone(), parent_id.clone()))
    }

    /// Inject trace context into headers
    pub fn inject(span: &SpanContext, headers: &mut HashMap<String, String>) {
        headers.insert("x-trace-id".to_string(), span.trace_id.clone());
        headers.insert("x-span-id".to_string(), span.span_id.clone());
        headers.insert(
            "x-parent-span-id".to_string(),
            span.parent_span_id.clone().unwrap_or_default(),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_trace_collector() {
        let config = TracingConfig::default();
        let collector = TraceCollector::new(config).unwrap();

        // Start root span
        let root = collector.start_span("root_operation", None).await.unwrap();

        // Start child span
        let child = collector
            .start_span("child_operation", Some(root.clone()))
            .await
            .unwrap();

        // Add event to child
        let mut attributes = HashMap::new();
        attributes.insert("key".to_string(), "value".to_string());
        collector
            .add_span_event(&child.span_id, "test_event", attributes)
            .await
            .unwrap();

        // End spans
        collector.end_span(child).await.unwrap();
        collector.end_span(root).await.unwrap();

        // Get traces
        let traces = collector.get_recent(10).await.unwrap();
        assert!(!traces.is_empty());
    }

    #[tokio::test]
    async fn test_distributed_trace() {
        let mut spans = Vec::new();

        // Create trace hierarchy
        let root = SpanContext::new("root", None);
        let child1 = SpanContext::new("child1", Some(&root));
        let child2 = SpanContext::new("child2", Some(&root));
        let grandchild = SpanContext::new("grandchild", Some(&child1));

        spans.push(root.clone());
        spans.push(child1);
        spans.push(child2);
        spans.push(grandchild);

        // Build trace
        let trace = DistributedTrace::from_spans(spans).unwrap();
        assert_eq!(trace.trace_id, root.trace_id);
        assert_eq!(trace.spans.len(), 4);

        // Test critical path
        let path = trace.critical_path();
        assert!(!path.is_empty());
    }

    #[test]
    fn test_span_context() {
        let root = SpanContext::new("root", None);
        assert!(root.parent_span_id.is_none());
        assert!(!root.trace_id.is_empty());

        let child = SpanContext::new("child", Some(&root));
        assert_eq!(child.trace_id, root.trace_id);
        assert_eq!(child.parent_span_id, Some(root.span_id.clone()));
    }

    #[test]
    fn test_trace_propagator() {
        let span = SpanContext::new("test", None);
        let mut headers = HashMap::new();

        TracePropagator::inject(&span, &mut headers);

        assert_eq!(headers.get("x-trace-id"), Some(&span.trace_id));
        assert_eq!(headers.get("x-span-id"), Some(&span.span_id));

        let (trace_id, span_id) = TracePropagator::extract(&headers).unwrap();
        assert_eq!(trace_id, span.trace_id);
        assert_eq!(span_id, span.span_id);
    }
}
