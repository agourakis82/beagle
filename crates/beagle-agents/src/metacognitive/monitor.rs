use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryPerformance {
    pub query_id: Uuid,
    pub query: String,
    pub domain: String,
    pub latency_ms: u64,
    pub quality_score: f64,
    pub user_satisfaction: Option<f64>,
    pub timestamp: DateTime<Utc>,
    pub success: bool,
    pub error: Option<String>,
}

pub struct PerformanceMonitor {
    history: Vec<QueryPerformance>,
    max_history: usize,
}

impl PerformanceMonitor {
    pub fn new(max_history: usize) -> Self {
        Self {
            history: Vec::new(),
            max_history,
        }
    }

    pub fn record(&mut self, performance: QueryPerformance) {
        self.history.push(performance);

        // Keep only recent history
        if self.history.len() > self.max_history {
            self.history.drain(0..self.history.len() - self.max_history);
        }
    }

    pub fn get_recent(&self, n: usize) -> &[QueryPerformance] {
        let start = self.history.len().saturating_sub(n);
        &self.history[start..]
    }

    pub fn get_failures(&self, n: usize) -> Vec<&QueryPerformance> {
        self.history
            .iter()
            .rev()
            .filter(|p| !p.success || p.quality_score < 0.5)
            .take(n)
            .collect()
    }

    pub fn success_rate(&self, last_n: usize) -> f64 {
        let recent = self.get_recent(last_n);
        if recent.is_empty() {
            return 0.5;
        }

        let successes = recent.iter().filter(|p| p.success).count();
        successes as f64 / recent.len() as f64
    }

    pub fn average_quality(&self, last_n: usize) -> f64 {
        let recent = self.get_recent(last_n);
        if recent.is_empty() {
            return 0.5;
        }

        let sum: f64 = recent.iter().map(|p| p.quality_score).sum();
        sum / recent.len() as f64
    }

    pub fn domain_performance(&self) -> HashMap<String, DomainStats> {
        let mut stats: HashMap<String, DomainStats> = HashMap::new();

        for perf in &self.history {
            let entry = stats
                .entry(perf.domain.clone())
                .or_insert(DomainStats::default());
            entry.total += 1;
            entry.quality_sum += perf.quality_score;
            if perf.success {
                entry.successes += 1;
            }
        }

        stats
    }
}

#[derive(Debug, Clone, Default)]
pub struct DomainStats {
    pub total: usize,
    pub successes: usize,
    pub quality_sum: f64,
}

impl DomainStats {
    pub fn success_rate(&self) -> f64 {
        if self.total == 0 {
            return 0.5;
        }
        self.successes as f64 / self.total as f64
    }

    pub fn average_quality(&self) -> f64 {
        if self.total == 0 {
            return 0.5;
        }
        self.quality_sum / self.total as f64
    }
}
