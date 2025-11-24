//! Estatísticas de latência

use std::time::Duration;

#[derive(Debug, Clone)]
pub struct LatencyStats {
    pub mean: Duration,
    pub p95: Duration,
    pub p99: Duration,
    pub min: Duration,
    pub max: Duration,
    pub total: usize,
    pub errors: usize,
}

pub fn calculate_stats(mut latencies: Vec<Duration>) -> LatencyStats {
    if latencies.is_empty() {
        return LatencyStats {
            mean: Duration::ZERO,
            p95: Duration::ZERO,
            p99: Duration::ZERO,
            min: Duration::ZERO,
            max: Duration::ZERO,
            total: 0,
            errors: 0,
        };
    }

    latencies.sort();
    let total = latencies.len();
    let sum: Duration = latencies.iter().sum();
    let mean = sum / total as u32;

    let p95_idx = (total as f64 * 0.95) as usize;
    let p99_idx = (total as f64 * 0.99) as usize;

    LatencyStats {
        mean,
        p95: latencies[p95_idx.min(total - 1)],
        p99: latencies[p99_idx.min(total - 1)],
        min: latencies[0],
        max: latencies[total - 1],
        total,
        errors: 0,
    }
}
