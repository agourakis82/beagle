//! Alerting system for monitoring and notifications
//!
//! Provides configurable alerting rules, thresholds, and notification channels.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

use crate::severity::SeverityLevel;

/// Alert condition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlertRule {
    /// Rule name
    pub name: String,
    /// Metric to monitor
    pub metric: String,
    /// Condition to trigger alert
    pub condition: AlertCondition,
    /// Severity level
    pub severity: SeverityLevel,
    /// Notification channels
    pub channels: Vec<String>,
    /// Cool-down period between alerts
    pub cooldown: Duration,
    /// Description of the alert
    pub description: String,
    /// Whether the rule is enabled
    pub enabled: bool,
}

impl AlertRule {
    /// Create a new alert rule
    pub fn new(name: &str, metric: &str, condition: AlertCondition) -> Self {
        Self {
            name: name.to_string(),
            metric: metric.to_string(),
            condition,
            severity: SeverityLevel::Warning,
            channels: vec!["default".to_string()],
            cooldown: Duration::from_secs(300), // 5 minutes default
            description: String::new(),
            enabled: true,
        }
    }

    /// Set severity
    pub fn with_severity(mut self, severity: SeverityLevel) -> Self {
        self.severity = severity;
        self
    }

    /// Set channels
    pub fn with_channels(mut self, channels: Vec<String>) -> Self {
        self.channels = channels;
        self
    }

    /// Set cooldown
    pub fn with_cooldown(mut self, cooldown: Duration) -> Self {
        self.cooldown = cooldown;
        self
    }

    /// Set description
    pub fn with_description(mut self, description: &str) -> Self {
        self.description = description.to_string();
        self
    }

    /// Check if condition is met
    pub fn check(&self, value: f64) -> bool {
        if !self.enabled {
            return false;
        }
        self.condition.evaluate(value)
    }
}

/// Alert condition types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AlertCondition {
    /// Value exceeds threshold
    GreaterThan(f64),
    /// Value below threshold
    LessThan(f64),
    /// Value equals threshold (with tolerance)
    Equals { value: f64, tolerance: f64 },
    /// Value outside range
    OutsideRange { min: f64, max: f64 },
    /// Value inside range (anomaly detection)
    InsideRange { min: f64, max: f64 },
    /// Rate of change exceeds threshold
    RateOfChange { threshold: f64, window_secs: u64 },
    /// Value absent for duration
    Absent { duration_secs: u64 },
}

impl AlertCondition {
    /// Evaluate condition against a value
    pub fn evaluate(&self, value: f64) -> bool {
        match self {
            AlertCondition::GreaterThan(threshold) => value > *threshold,
            AlertCondition::LessThan(threshold) => value < *threshold,
            AlertCondition::Equals {
                value: expected,
                tolerance,
            } => (value - expected).abs() <= *tolerance,
            AlertCondition::OutsideRange { min, max } => value < *min || value > *max,
            AlertCondition::InsideRange { min, max } => value >= *min && value <= *max,
            AlertCondition::RateOfChange { threshold, .. } => {
                // This requires historical data, simplified here
                value.abs() > *threshold
            }
            AlertCondition::Absent { .. } => {
                // This requires tracking last seen time
                false
            }
        }
    }
}

/// Alert instance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Alert {
    /// Unique alert ID
    pub id: String,
    /// Rule that triggered the alert
    pub rule_name: String,
    /// Metric that triggered
    pub metric: String,
    /// Current value
    pub value: f64,
    /// Severity level
    pub severity: SeverityLevel,
    /// Alert message
    pub message: String,
    /// Timestamp (as Unix timestamp)
    pub timestamp: u64,
    /// Alert state
    pub state: AlertState,
    /// Labels/tags
    pub labels: HashMap<String, String>,
}

impl Alert {
    /// Create a new alert from a rule
    pub fn from_rule(rule: &AlertRule, value: f64) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            rule_name: rule.name.clone(),
            metric: rule.metric.clone(),
            value,
            severity: rule.severity,
            message: format!(
                "Alert '{}': {} = {} ({})",
                rule.name, rule.metric, value, rule.description
            ),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            state: AlertState::Firing,
            labels: HashMap::new(),
        }
    }

    /// Add a label
    pub fn with_label(mut self, key: &str, value: &str) -> Self {
        self.labels.insert(key.to_string(), value.to_string());
        self
    }

    /// Mark as resolved
    pub fn resolve(&mut self) {
        self.state = AlertState::Resolved;
    }
}

/// Alert state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AlertState {
    /// Alert is currently firing
    Firing,
    /// Alert has been resolved
    Resolved,
    /// Alert is pending (not yet confirmed)
    Pending,
    /// Alert was silenced
    Silenced,
}

/// Notification channel
#[derive(Debug, Clone)]
pub struct AlertChannel {
    /// Channel name
    pub name: String,
    /// Channel type
    pub channel_type: ChannelType,
    /// Channel configuration
    pub config: HashMap<String, String>,
    /// Whether channel is enabled
    pub enabled: bool,
}

impl AlertChannel {
    /// Create a new channel
    pub fn new(name: &str, channel_type: ChannelType) -> Self {
        Self {
            name: name.to_string(),
            channel_type,
            config: HashMap::new(),
            enabled: true,
        }
    }

    /// Add configuration
    pub fn with_config(mut self, key: &str, value: &str) -> Self {
        self.config.insert(key.to_string(), value.to_string());
        self
    }

    /// Send alert through this channel
    pub async fn send(&self, alert: &Alert) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        match self.channel_type {
            ChannelType::Log => {
                tracing::warn!(
                    alert_id = %alert.id,
                    rule = %alert.rule_name,
                    severity = ?alert.severity,
                    "Alert: {}", alert.message
                );
            }
            ChannelType::Webhook => {
                // Would send HTTP request to webhook URL
                tracing::info!("Would send webhook alert: {}", alert.message);
            }
            ChannelType::Email => {
                tracing::info!("Would send email alert: {}", alert.message);
            }
            ChannelType::Slack => {
                tracing::info!("Would send Slack alert: {}", alert.message);
            }
            ChannelType::PagerDuty => {
                tracing::info!("Would send PagerDuty alert: {}", alert.message);
            }
        }

        Ok(())
    }
}

/// Channel type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelType {
    Log,
    Webhook,
    Email,
    Slack,
    PagerDuty,
}

/// Alert manager
pub struct AlertManager {
    /// Alert rules
    rules: Arc<RwLock<HashMap<String, AlertRule>>>,
    /// Notification channels
    channels: Arc<RwLock<HashMap<String, AlertChannel>>>,
    /// Active alerts
    active_alerts: Arc<RwLock<HashMap<String, Alert>>>,
    /// Last alert time per rule (for cooldown)
    last_alert_time: Arc<RwLock<HashMap<String, Instant>>>,
}

impl AlertManager {
    /// Create new alert manager
    pub fn new() -> Self {
        let mut channels = HashMap::new();
        channels.insert(
            "default".to_string(),
            AlertChannel::new("default", ChannelType::Log),
        );

        Self {
            rules: Arc::new(RwLock::new(HashMap::new())),
            channels: Arc::new(RwLock::new(channels)),
            active_alerts: Arc::new(RwLock::new(HashMap::new())),
            last_alert_time: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Add an alert rule
    pub async fn add_rule(&self, rule: AlertRule) {
        self.rules.write().await.insert(rule.name.clone(), rule);
    }

    /// Remove an alert rule
    pub async fn remove_rule(&self, name: &str) {
        self.rules.write().await.remove(name);
    }

    /// Add a notification channel
    pub async fn add_channel(&self, channel: AlertChannel) {
        self.channels
            .write()
            .await
            .insert(channel.name.clone(), channel);
    }

    /// Check a metric value against all rules
    pub async fn check(&self, metric: &str, value: f64) -> Vec<Alert> {
        let rules = self.rules.read().await;
        let mut triggered_alerts = Vec::new();

        for rule in rules.values() {
            if rule.metric != metric {
                continue;
            }

            if !rule.check(value) {
                continue;
            }

            // Check cooldown
            let should_alert = {
                let last_times = self.last_alert_time.read().await;
                if let Some(last_time) = last_times.get(&rule.name) {
                    last_time.elapsed() >= rule.cooldown
                } else {
                    true
                }
            };

            if should_alert {
                let alert = Alert::from_rule(rule, value);
                triggered_alerts.push(alert.clone());

                // Update last alert time
                self.last_alert_time
                    .write()
                    .await
                    .insert(rule.name.clone(), Instant::now());

                // Store active alert
                self.active_alerts
                    .write()
                    .await
                    .insert(alert.id.clone(), alert.clone());

                // Send to channels
                self.send_alert(&alert, &rule.channels).await;
            }
        }

        triggered_alerts
    }

    /// Send alert to specified channels
    async fn send_alert(&self, alert: &Alert, channel_names: &[String]) {
        let channels = self.channels.read().await;

        for channel_name in channel_names {
            if let Some(channel) = channels.get(channel_name) {
                if let Err(e) = channel.send(alert).await {
                    tracing::error!("Failed to send alert to channel {}: {}", channel_name, e);
                }
            }
        }
    }

    /// Get all active alerts
    pub async fn get_active_alerts(&self) -> Vec<Alert> {
        self.active_alerts.read().await.values().cloned().collect()
    }

    /// Resolve an alert
    pub async fn resolve_alert(&self, alert_id: &str) {
        if let Some(alert) = self.active_alerts.write().await.get_mut(alert_id) {
            alert.resolve();
        }
    }

    /// Clear all resolved alerts
    pub async fn clear_resolved(&self) {
        self.active_alerts
            .write()
            .await
            .retain(|_, alert| alert.state != AlertState::Resolved);
    }
}

impl Default for AlertManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_alert_condition() {
        assert!(AlertCondition::GreaterThan(10.0).evaluate(15.0));
        assert!(!AlertCondition::GreaterThan(10.0).evaluate(5.0));

        assert!(AlertCondition::LessThan(10.0).evaluate(5.0));
        assert!(!AlertCondition::LessThan(10.0).evaluate(15.0));

        assert!(AlertCondition::OutsideRange {
            min: 0.0,
            max: 100.0
        }
        .evaluate(150.0));
        assert!(!AlertCondition::OutsideRange {
            min: 0.0,
            max: 100.0
        }
        .evaluate(50.0));
    }

    #[tokio::test]
    async fn test_alert_manager() {
        let manager = AlertManager::new();

        let rule = AlertRule::new("high_cpu", "cpu_percent", AlertCondition::GreaterThan(90.0))
            .with_severity(SeverityLevel::Critical)
            .with_description("CPU usage too high");

        manager.add_rule(rule).await;

        // Should not trigger
        let alerts = manager.check("cpu_percent", 50.0).await;
        assert!(alerts.is_empty());

        // Should trigger
        let alerts = manager.check("cpu_percent", 95.0).await;
        assert_eq!(alerts.len(), 1);
        assert_eq!(alerts[0].rule_name, "high_cpu");
    }
}
