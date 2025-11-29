//! Health checks and SLA monitoring
//!
//! Provides health check endpoints, service status monitoring,
//! and SLA compliance tracking.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Health status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HealthStatus {
    /// Service is healthy
    Healthy,
    /// Service is degraded but functional
    Degraded,
    /// Service is unhealthy
    Unhealthy,
    /// Health status unknown
    Unknown,
}

impl HealthStatus {
    /// Check if status is healthy
    pub fn is_healthy(&self) -> bool {
        matches!(self, HealthStatus::Healthy)
    }

    /// Check if status is operational (healthy or degraded)
    pub fn is_operational(&self) -> bool {
        matches!(self, HealthStatus::Healthy | HealthStatus::Degraded)
    }

    /// Combine with another status (worst wins)
    pub fn combine(&self, other: &HealthStatus) -> HealthStatus {
        match (self, other) {
            (HealthStatus::Unhealthy, _) | (_, HealthStatus::Unhealthy) => HealthStatus::Unhealthy,
            (HealthStatus::Unknown, _) | (_, HealthStatus::Unknown) => HealthStatus::Unknown,
            (HealthStatus::Degraded, _) | (_, HealthStatus::Degraded) => HealthStatus::Degraded,
            _ => HealthStatus::Healthy,
        }
    }
}

impl Default for HealthStatus {
    fn default() -> Self {
        HealthStatus::Unknown
    }
}

/// Health check definition
#[derive(Clone)]
pub struct HealthCheck {
    /// Check name
    pub name: String,
    /// Check description
    pub description: String,
    /// Check function
    check_fn: Arc<dyn Fn() -> HealthCheckResult + Send + Sync>,
    /// Check interval
    pub interval: Duration,
    /// Timeout for check
    pub timeout: Duration,
    /// Whether check is critical
    pub critical: bool,
}

impl HealthCheck {
    /// Create a new health check
    pub fn new<F>(name: &str, check_fn: F) -> Self
    where
        F: Fn() -> HealthCheckResult + Send + Sync + 'static,
    {
        Self {
            name: name.to_string(),
            description: String::new(),
            check_fn: Arc::new(check_fn),
            interval: Duration::from_secs(30),
            timeout: Duration::from_secs(5),
            critical: false,
        }
    }

    /// Set description
    pub fn with_description(mut self, description: &str) -> Self {
        self.description = description.to_string();
        self
    }

    /// Set interval
    pub fn with_interval(mut self, interval: Duration) -> Self {
        self.interval = interval;
        self
    }

    /// Set timeout
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Mark as critical
    pub fn critical(mut self) -> Self {
        self.critical = true;
        self
    }

    /// Run the health check
    pub fn run(&self) -> HealthCheckResult {
        (self.check_fn)()
    }
}

impl std::fmt::Debug for HealthCheck {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HealthCheck")
            .field("name", &self.name)
            .field("description", &self.description)
            .field("interval", &self.interval)
            .field("timeout", &self.timeout)
            .field("critical", &self.critical)
            .finish()
    }
}

/// Health check result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheckResult {
    /// Check name
    pub name: String,
    /// Status
    pub status: HealthStatus,
    /// Optional message
    pub message: Option<String>,
    /// Check duration
    pub duration_ms: u64,
    /// Timestamp
    pub timestamp: u64,
    /// Additional details
    pub details: HashMap<String, String>,
}

impl HealthCheckResult {
    /// Create healthy result
    pub fn healthy(name: &str) -> Self {
        Self {
            name: name.to_string(),
            status: HealthStatus::Healthy,
            message: None,
            duration_ms: 0,
            timestamp: Self::now(),
            details: HashMap::new(),
        }
    }

    /// Create degraded result
    pub fn degraded(name: &str, message: &str) -> Self {
        Self {
            name: name.to_string(),
            status: HealthStatus::Degraded,
            message: Some(message.to_string()),
            duration_ms: 0,
            timestamp: Self::now(),
            details: HashMap::new(),
        }
    }

    /// Create unhealthy result
    pub fn unhealthy(name: &str, message: &str) -> Self {
        Self {
            name: name.to_string(),
            status: HealthStatus::Unhealthy,
            message: Some(message.to_string()),
            duration_ms: 0,
            timestamp: Self::now(),
            details: HashMap::new(),
        }
    }

    /// Add detail
    pub fn with_detail(mut self, key: &str, value: &str) -> Self {
        self.details.insert(key.to_string(), value.to_string());
        self
    }

    /// Set duration
    pub fn with_duration(mut self, duration: Duration) -> Self {
        self.duration_ms = duration.as_millis() as u64;
        self
    }

    fn now() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
    }
}

/// Health monitor managing multiple checks
pub struct HealthMonitor {
    /// Registered health checks
    checks: Arc<RwLock<HashMap<String, HealthCheck>>>,
    /// Latest results
    results: Arc<RwLock<HashMap<String, HealthCheckResult>>>,
    /// Overall status
    overall_status: Arc<RwLock<HealthStatus>>,
}

impl HealthMonitor {
    /// Create new health monitor
    pub fn new() -> Self {
        Self {
            checks: Arc::new(RwLock::new(HashMap::new())),
            results: Arc::new(RwLock::new(HashMap::new())),
            overall_status: Arc::new(RwLock::new(HealthStatus::Unknown)),
        }
    }

    /// Register a health check
    pub async fn register(&self, check: HealthCheck) {
        self.checks.write().await.insert(check.name.clone(), check);
    }

    /// Unregister a health check
    pub async fn unregister(&self, name: &str) {
        self.checks.write().await.remove(name);
        self.results.write().await.remove(name);
    }

    /// Run all health checks
    pub async fn run_all(&self) -> OverallHealth {
        let checks = self.checks.read().await;
        let mut results = Vec::new();
        let mut overall = HealthStatus::Healthy;

        for check in checks.values() {
            let start = Instant::now();
            let mut result = check.run();
            result.duration_ms = start.elapsed().as_millis() as u64;

            // Update overall status
            if check.critical || result.status == HealthStatus::Unhealthy {
                overall = overall.combine(&result.status);
            } else if result.status == HealthStatus::Degraded {
                overall = overall.combine(&HealthStatus::Degraded);
            }

            results.push(result.clone());

            // Store result
            self.results
                .write()
                .await
                .insert(check.name.clone(), result);
        }

        *self.overall_status.write().await = overall;

        OverallHealth {
            status: overall,
            checks: results,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        }
    }

    /// Run a specific health check
    pub async fn run_check(&self, name: &str) -> Option<HealthCheckResult> {
        let checks = self.checks.read().await;
        let check = checks.get(name)?;

        let start = Instant::now();
        let mut result = check.run();
        result.duration_ms = start.elapsed().as_millis() as u64;

        self.results
            .write()
            .await
            .insert(name.to_string(), result.clone());

        Some(result)
    }

    /// Get overall status
    pub async fn get_status(&self) -> HealthStatus {
        *self.overall_status.read().await
    }

    /// Get latest result for a check
    pub async fn get_result(&self, name: &str) -> Option<HealthCheckResult> {
        self.results.read().await.get(name).cloned()
    }

    /// Get all latest results
    pub async fn get_all_results(&self) -> HashMap<String, HealthCheckResult> {
        self.results.read().await.clone()
    }
}

impl Default for HealthMonitor {
    fn default() -> Self {
        Self::new()
    }
}

/// Overall health report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverallHealth {
    /// Overall status
    pub status: HealthStatus,
    /// Individual check results
    pub checks: Vec<HealthCheckResult>,
    /// Timestamp
    pub timestamp: u64,
}

impl OverallHealth {
    /// Check if system is healthy
    pub fn is_healthy(&self) -> bool {
        self.status.is_healthy()
    }

    /// Check if system is operational
    pub fn is_operational(&self) -> bool {
        self.status.is_operational()
    }

    /// Get unhealthy checks
    pub fn unhealthy_checks(&self) -> Vec<&HealthCheckResult> {
        self.checks
            .iter()
            .filter(|c| c.status == HealthStatus::Unhealthy)
            .collect()
    }
}

/// SLA monitor for tracking service level agreements
pub struct SLAMonitor {
    /// SLA definitions
    slas: Arc<RwLock<HashMap<String, SLADefinition>>>,
    /// SLA metrics
    metrics: Arc<RwLock<HashMap<String, SLAMetrics>>>,
}

impl SLAMonitor {
    /// Create new SLA monitor
    pub fn new() -> Self {
        Self {
            slas: Arc::new(RwLock::new(HashMap::new())),
            metrics: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Define an SLA
    pub async fn define_sla(&self, sla: SLADefinition) {
        let name = sla.name.clone();
        self.slas.write().await.insert(name.clone(), sla);
        self.metrics.write().await.insert(
            name,
            SLAMetrics {
                total_requests: 0,
                successful_requests: 0,
                total_latency_ms: 0,
                violations: 0,
            },
        );
    }

    /// Record a request
    pub async fn record(&self, sla_name: &str, success: bool, latency_ms: u64) {
        let slas = self.slas.read().await;
        let sla = match slas.get(sla_name) {
            Some(s) => s.clone(),
            None => return,
        };
        drop(slas);

        let mut metrics = self.metrics.write().await;
        if let Some(m) = metrics.get_mut(sla_name) {
            m.total_requests += 1;
            if success {
                m.successful_requests += 1;
            }
            m.total_latency_ms += latency_ms;

            // Check for violations
            if !success || latency_ms > sla.latency_threshold_ms {
                m.violations += 1;
            }
        }
    }

    /// Get SLA compliance
    pub async fn get_compliance(&self, sla_name: &str) -> Option<SLACompliance> {
        let slas = self.slas.read().await;
        let sla = slas.get(sla_name)?;

        let metrics = self.metrics.read().await;
        let m = metrics.get(sla_name)?;

        if m.total_requests == 0 {
            return Some(SLACompliance {
                sla_name: sla_name.to_string(),
                availability: 100.0,
                avg_latency_ms: 0,
                compliance_percent: 100.0,
                target_availability: sla.availability_target,
                target_latency_ms: sla.latency_threshold_ms,
                is_compliant: true,
            });
        }

        let availability = (m.successful_requests as f64 / m.total_requests as f64) * 100.0;
        let avg_latency = m.total_latency_ms / m.total_requests;
        let compliance =
            ((m.total_requests - m.violations) as f64 / m.total_requests as f64) * 100.0;

        let is_compliant =
            availability >= sla.availability_target && avg_latency <= sla.latency_threshold_ms;

        Some(SLACompliance {
            sla_name: sla_name.to_string(),
            availability,
            avg_latency_ms: avg_latency,
            compliance_percent: compliance,
            target_availability: sla.availability_target,
            target_latency_ms: sla.latency_threshold_ms,
            is_compliant,
        })
    }
}

impl Default for SLAMonitor {
    fn default() -> Self {
        Self::new()
    }
}

/// SLA definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SLADefinition {
    /// SLA name
    pub name: String,
    /// Availability target (percentage, e.g., 99.9)
    pub availability_target: f64,
    /// Latency threshold in milliseconds
    pub latency_threshold_ms: u64,
    /// Description
    pub description: String,
}

/// Internal SLA metrics
struct SLAMetrics {
    total_requests: u64,
    successful_requests: u64,
    total_latency_ms: u64,
    violations: u64,
}

/// SLA compliance report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SLACompliance {
    /// SLA name
    pub sla_name: String,
    /// Current availability
    pub availability: f64,
    /// Average latency
    pub avg_latency_ms: u64,
    /// Compliance percentage
    pub compliance_percent: f64,
    /// Target availability
    pub target_availability: f64,
    /// Target latency
    pub target_latency_ms: u64,
    /// Whether SLA is being met
    pub is_compliant: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_health_status_combine() {
        assert_eq!(
            HealthStatus::Healthy.combine(&HealthStatus::Healthy),
            HealthStatus::Healthy
        );
        assert_eq!(
            HealthStatus::Healthy.combine(&HealthStatus::Degraded),
            HealthStatus::Degraded
        );
        assert_eq!(
            HealthStatus::Degraded.combine(&HealthStatus::Unhealthy),
            HealthStatus::Unhealthy
        );
    }

    #[tokio::test]
    async fn test_health_monitor() {
        let monitor = HealthMonitor::new();

        let check = HealthCheck::new("test", || HealthCheckResult::healthy("test"));

        monitor.register(check).await;

        let health = monitor.run_all().await;
        assert!(health.is_healthy());
        assert_eq!(health.checks.len(), 1);
    }

    #[tokio::test]
    async fn test_sla_monitor() {
        let monitor = SLAMonitor::new();

        monitor
            .define_sla(SLADefinition {
                name: "api".to_string(),
                availability_target: 99.0,
                latency_threshold_ms: 100,
                description: "API SLA".to_string(),
            })
            .await;

        // Record successful requests
        for _ in 0..99 {
            monitor.record("api", true, 50).await;
        }
        // Record one failure
        monitor.record("api", false, 200).await;

        let compliance = monitor.get_compliance("api").await.unwrap();
        assert_eq!(compliance.availability, 99.0);
        assert!(compliance.is_compliant);
    }
}
