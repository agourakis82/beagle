//! Performance profiling and flame graph generation
//!
//! Provides CPU profiling, memory profiling, and flame graph visualization.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Profiler for collecting performance data
pub struct Profiler {
    /// Active profiles
    profiles: Arc<RwLock<HashMap<String, ProfileSession>>>,
    /// Configuration
    config: ProfilerConfig,
}

impl Profiler {
    /// Create new profiler
    pub fn new(config: ProfilerConfig) -> Self {
        Self {
            profiles: Arc::new(RwLock::new(HashMap::new())),
            config,
        }
    }

    /// Start a new profile session
    pub async fn start_session(&self, name: &str) -> Result<String> {
        let session_id = uuid::Uuid::new_v4().to_string();
        let session = ProfileSession {
            id: session_id.clone(),
            name: name.to_string(),
            start_time: Instant::now(),
            spans: Vec::new(),
            stack_samples: Vec::new(),
            memory_samples: Vec::new(),
            active: true,
        };

        self.profiles
            .write()
            .await
            .insert(session_id.clone(), session);

        Ok(session_id)
    }

    /// Stop a profile session
    pub async fn stop_session(&self, session_id: &str) -> Option<ProfileData> {
        let mut profiles = self.profiles.write().await;
        let session = profiles.get_mut(session_id)?;
        session.active = false;

        let duration = session.start_time.elapsed();

        Some(ProfileData {
            session_id: session.id.clone(),
            name: session.name.clone(),
            duration,
            spans: session.spans.clone(),
            stack_samples: session.stack_samples.clone(),
            memory_samples: session.memory_samples.clone(),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        })
    }

    /// Record a span (timed section)
    pub async fn record_span(&self, session_id: &str, span: ProfileSpan) {
        if let Some(session) = self.profiles.write().await.get_mut(session_id) {
            if session.active {
                session.spans.push(span);
            }
        }
    }

    /// Record a stack sample
    pub async fn record_stack_sample(&self, session_id: &str, sample: StackSample) {
        if let Some(session) = self.profiles.write().await.get_mut(session_id) {
            if session.active {
                session.stack_samples.push(sample);
            }
        }
    }

    /// Record a memory sample
    pub async fn record_memory_sample(&self, session_id: &str, sample: MemorySample) {
        if let Some(session) = self.profiles.write().await.get_mut(session_id) {
            if session.active {
                session.memory_samples.push(sample);
            }
        }
    }

    /// Create a span guard for automatic timing
    pub fn span(&self, session_id: String, name: String) -> SpanGuard {
        SpanGuard {
            session_id,
            name,
            start: Instant::now(),
            profiler: self.profiles.clone(),
        }
    }

    /// Generate flame graph from profile data
    pub fn generate_flame_graph(&self, data: &ProfileData) -> FlameGraph {
        let mut nodes = HashMap::new();
        let mut root_children = Vec::new();

        // Build flame graph from stack samples
        for sample in &data.stack_samples {
            let mut current_path = String::new();

            for (i, frame) in sample.frames.iter().enumerate() {
                if i > 0 {
                    current_path.push(';');
                }
                current_path.push_str(frame);

                let node = nodes.entry(current_path.clone()).or_insert(FlameNode {
                    name: frame.clone(),
                    value: 0,
                    children: Vec::new(),
                });
                node.value += sample.count;

                if i == 0 && !root_children.contains(&current_path) {
                    root_children.push(current_path.clone());
                }
            }
        }

        FlameGraph {
            title: format!("Flame Graph: {}", data.name),
            nodes,
            total_samples: data.stack_samples.iter().map(|s| s.count).sum(),
            duration: data.duration,
        }
    }

    /// Get all active sessions
    pub async fn active_sessions(&self) -> Vec<String> {
        self.profiles
            .read()
            .await
            .iter()
            .filter(|(_, s)| s.active)
            .map(|(id, _)| id.clone())
            .collect()
    }
}

impl Default for Profiler {
    fn default() -> Self {
        Self::new(ProfilerConfig::default())
    }
}

/// Profiler configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfilerConfig {
    /// Sample rate (samples per second)
    pub sample_rate: u32,
    /// Maximum samples to store
    pub max_samples: usize,
    /// Enable memory profiling
    pub memory_profiling: bool,
    /// Enable CPU profiling
    pub cpu_profiling: bool,
}

impl Default for ProfilerConfig {
    fn default() -> Self {
        Self {
            sample_rate: 100,
            max_samples: 100000,
            memory_profiling: true,
            cpu_profiling: true,
        }
    }
}

/// Profile session
struct ProfileSession {
    id: String,
    name: String,
    start_time: Instant,
    spans: Vec<ProfileSpan>,
    stack_samples: Vec<StackSample>,
    memory_samples: Vec<MemorySample>,
    active: bool,
}

/// Profile data output
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileData {
    /// Session ID
    pub session_id: String,
    /// Profile name
    pub name: String,
    /// Total duration
    #[serde(with = "serde_duration")]
    pub duration: Duration,
    /// Recorded spans
    pub spans: Vec<ProfileSpan>,
    /// Stack samples
    pub stack_samples: Vec<StackSample>,
    /// Memory samples
    pub memory_samples: Vec<MemorySample>,
    /// Timestamp
    pub timestamp: u64,
}

mod serde_duration {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};
    use std::time::Duration;

    pub fn serialize<S>(duration: &Duration, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        duration.as_millis().serialize(serializer)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Duration, D::Error>
    where
        D: Deserializer<'de>,
    {
        let millis = u64::deserialize(deserializer)?;
        Ok(Duration::from_millis(millis))
    }
}

impl ProfileData {
    /// Get total CPU time
    pub fn total_cpu_time(&self) -> Duration {
        self.spans.iter().map(|s| s.duration).sum()
    }

    /// Get hottest functions (most time spent)
    pub fn hot_functions(&self, top_n: usize) -> Vec<(&str, Duration)> {
        let mut time_by_name: HashMap<&str, Duration> = HashMap::new();

        for span in &self.spans {
            *time_by_name.entry(&span.name).or_default() += span.duration;
        }

        let mut sorted: Vec<_> = time_by_name.into_iter().collect();
        sorted.sort_by(|a, b| b.1.cmp(&a.1));
        sorted.truncate(top_n);
        sorted
    }

    /// Get peak memory usage
    pub fn peak_memory(&self) -> u64 {
        self.memory_samples
            .iter()
            .map(|s| s.heap_used)
            .max()
            .unwrap_or(0)
    }
}

/// Profile span (timed section)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileSpan {
    /// Span name
    pub name: String,
    /// Duration
    #[serde(with = "serde_duration")]
    pub duration: Duration,
    /// Start offset from session start
    #[serde(with = "serde_duration")]
    pub start_offset: Duration,
    /// Additional metadata
    pub metadata: HashMap<String, String>,
}

/// Stack sample
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StackSample {
    /// Stack frames (bottom to top)
    pub frames: Vec<String>,
    /// Sample count
    pub count: u64,
    /// Timestamp offset
    pub offset_ms: u64,
}

/// Memory sample
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySample {
    /// Heap memory used (bytes)
    pub heap_used: u64,
    /// Heap memory total (bytes)
    pub heap_total: u64,
    /// Stack memory used (bytes)
    pub stack_used: u64,
    /// Timestamp offset
    pub offset_ms: u64,
}

/// Flame graph representation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlameGraph {
    /// Graph title
    pub title: String,
    /// Nodes by path
    pub nodes: HashMap<String, FlameNode>,
    /// Total samples
    pub total_samples: u64,
    /// Total duration
    #[serde(with = "serde_duration")]
    pub duration: Duration,
}

impl FlameGraph {
    /// Export to folded stack format (for flamegraph.pl)
    pub fn to_folded(&self) -> String {
        let mut lines = Vec::new();

        for (path, node) in &self.nodes {
            if node.value > 0 {
                lines.push(format!("{} {}", path, node.value));
            }
        }

        lines.sort();
        lines.join("\n")
    }

    /// Get top functions by sample count
    pub fn top_functions(&self, n: usize) -> Vec<(&str, u64)> {
        let mut funcs: Vec<_> = self
            .nodes
            .iter()
            .map(|(_, node)| (node.name.as_str(), node.value))
            .collect();

        funcs.sort_by(|a, b| b.1.cmp(&a.1));
        funcs.truncate(n);
        funcs
    }
}

/// Flame graph node
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlameNode {
    /// Function name
    pub name: String,
    /// Sample count (width)
    pub value: u64,
    /// Child nodes
    pub children: Vec<String>,
}

/// RAII guard for automatic span timing
pub struct SpanGuard {
    session_id: String,
    name: String,
    start: Instant,
    profiler: Arc<RwLock<HashMap<String, ProfileSession>>>,
}

impl Drop for SpanGuard {
    fn drop(&mut self) {
        let duration = self.start.elapsed();
        let span = ProfileSpan {
            name: self.name.clone(),
            duration,
            start_offset: Duration::ZERO, // Would need session start time
            metadata: HashMap::new(),
        };

        // We can't use async in Drop, so we use try_write
        if let Ok(mut profiles) = self.profiler.try_write() {
            if let Some(session) = profiles.get_mut(&self.session_id) {
                if session.active {
                    session.spans.push(span);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_profiler() {
        let profiler = Profiler::default();

        let session_id = profiler.start_session("test").await.unwrap();

        // Record some spans
        profiler
            .record_span(
                &session_id,
                ProfileSpan {
                    name: "function_a".to_string(),
                    duration: Duration::from_millis(100),
                    start_offset: Duration::ZERO,
                    metadata: HashMap::new(),
                },
            )
            .await;

        profiler
            .record_span(
                &session_id,
                ProfileSpan {
                    name: "function_b".to_string(),
                    duration: Duration::from_millis(50),
                    start_offset: Duration::from_millis(100),
                    metadata: HashMap::new(),
                },
            )
            .await;

        let data = profiler.stop_session(&session_id).await.unwrap();

        assert_eq!(data.spans.len(), 2);
        assert_eq!(data.total_cpu_time(), Duration::from_millis(150));
    }

    #[test]
    fn test_flame_graph() {
        let profiler = Profiler::default();

        let data = ProfileData {
            session_id: "test".to_string(),
            name: "test".to_string(),
            duration: Duration::from_secs(1),
            spans: Vec::new(),
            stack_samples: vec![
                StackSample {
                    frames: vec!["main".to_string(), "process".to_string()],
                    count: 10,
                    offset_ms: 0,
                },
                StackSample {
                    frames: vec![
                        "main".to_string(),
                        "process".to_string(),
                        "compute".to_string(),
                    ],
                    count: 5,
                    offset_ms: 100,
                },
            ],
            memory_samples: Vec::new(),
            timestamp: 0,
        };

        let flame_graph = profiler.generate_flame_graph(&data);
        assert_eq!(flame_graph.total_samples, 15);
    }
}
