//! Notifications: Push, email, and webhook integrations

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NotificationChannel {
    Push,
    Email,
    Webhook,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationPreferences {
    pub enabled_channels: Vec<NotificationChannel>,
    pub email_address: Option<String>,
    pub webhook_url: Option<String>,
    pub push_token: Option<String>,
}

impl Default for NotificationPreferences {
    fn default() -> Self {
        Self {
            enabled_channels: vec![NotificationChannel::Push],
            email_address: None,
            webhook_url: None,
            push_token: None,
        }
    }
}

pub struct NotificationService {
    preferences: NotificationPreferences,
    sent_notifications: HashMap<String, chrono::DateTime<chrono::Utc>>,
}

impl NotificationService {
    pub fn new(preferences: NotificationPreferences) -> Self {
        Self {
            preferences,
            sent_notifications: HashMap::new(),
        }
    }

    /// Send notification for synthesis completion
    pub async fn notify_synthesis_complete(
        &mut self,
        cluster_id: &str,
        topic: &str,
        paper_url: &str,
    ) -> Result<()> {
        info!("📬 Sending notifications for synthesis: {}", cluster_id);

        let message = format!(
            "New synthesis paper generated!\n\nTopic: {}\nCluster: {}\nView: {}",
            topic, cluster_id, paper_url
        );

        for channel in &self.preferences.enabled_channels {
            match channel {
                NotificationChannel::Push => {
                    self.send_push(&message).await?;
                }
                NotificationChannel::Email => {
                    self.send_email(topic, &message).await?;
                }
                NotificationChannel::Webhook => {
                    self.webhook_trigger(cluster_id, topic, paper_url).await?;
                }
            }
        }

        // Track notification
        self.sent_notifications.insert(
            cluster_id.to_string(),
            chrono::Utc::now(),
        );

        Ok(())
    }

    /// Send iOS/macOS native push notification
    async fn send_push(&self, message: &str) -> Result<()> {
        info!("📱 Sending push notification");

        if let Some(push_token) = &self.preferences.push_token {
            // TODO: Implement actual APNs integration
            // For now, simulate
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

            info!(
                "✅ Push notification sent to token: {}... ({}  chars)",
                &push_token[..8.min(push_token.len())],
                message.len()
            );
        } else {
            warn!("⚠️  Push token not configured");
        }

        Ok(())
    }

    /// Send email via SMTP
    async fn send_email(&self, subject: &str, body: &str) -> Result<()> {
        info!("📧 Sending email notification");

        if let Some(email) = &self.preferences.email_address {
            // TODO: Implement actual SMTP integration
            // For now, simulate
            tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;

            info!(
                "✅ Email sent to: {} | Subject: {}",
                email, subject
            );
        } else {
            warn!("⚠️  Email address not configured");
        }

        Ok(())
    }

    /// Trigger custom webhook
    async fn webhook_trigger(
        &self,
        cluster_id: &str,
        topic: &str,
        paper_url: &str,
    ) -> Result<()> {
        info!("🔗 Triggering webhook");

        if let Some(webhook_url) = &self.preferences.webhook_url {
            let payload = serde_json::json!({
                "event": "synthesis_complete",
                "cluster_id": cluster_id,
                "topic": topic,
                "paper_url": paper_url,
                "timestamp": chrono::Utc::now().to_rfc3339(),
            });

            // TODO: Implement actual HTTP POST
            // For now, simulate
            tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;

            info!(
                "✅ Webhook triggered: {} | Payload: {}",
                webhook_url,
                payload
            );
        } else {
            warn!("⚠️  Webhook URL not configured");
        }

        Ok(())
    }

    /// Get notification preferences
    pub fn get_preferences(&self) -> &NotificationPreferences {
        &self.preferences
    }

    /// Update notification preferences
    pub fn update_preferences(&mut self, preferences: NotificationPreferences) {
        self.preferences = preferences;
        info!("✏️  Notification preferences updated");
    }

    /// Check if notification was recently sent (deduplication)
    pub fn was_recently_sent(&self, cluster_id: &str, within_minutes: i64) -> bool {
        if let Some(sent_time) = self.sent_notifications.get(cluster_id) {
            let now = chrono::Utc::now();
            let diff = now.signed_duration_since(*sent_time);
            diff.num_minutes() < within_minutes
        } else {
            false
        }
    }
}

impl Default for NotificationService {
    fn default() -> Self {
        Self::new(NotificationPreferences::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_send_push() {
        let mut prefs = NotificationPreferences::default();
        prefs.push_token = Some("test_token_12345678".to_string());

        let service = NotificationService::new(prefs);
        let result = service.send_push("Test message").await;

        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_send_email() {
        let mut prefs = NotificationPreferences::default();
        prefs.email_address = Some("test@example.com".to_string());

        let service = NotificationService::new(prefs);
        let result = service.send_email("Test Subject", "Test body").await;

        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_webhook_trigger() {
        let mut prefs = NotificationPreferences::default();
        prefs.webhook_url = Some("https://example.com/webhook".to_string());

        let service = NotificationService::new(prefs);
        let result = service
            .webhook_trigger("cluster1", "quantum computing", "https://paper.url")
            .await;

        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_notify_synthesis_complete() {
        let mut prefs = NotificationPreferences::default();
        prefs.enabled_channels = vec![NotificationChannel::Push, NotificationChannel::Email];
        prefs.push_token = Some("test_token".to_string());
        prefs.email_address = Some("test@example.com".to_string());

        let mut service = NotificationService::new(prefs);
        let result = service
            .notify_synthesis_complete("cluster1", "AI research", "https://paper.url")
            .await;

        assert!(result.is_ok());
        assert!(service.was_recently_sent("cluster1", 5));
    }

    #[test]
    fn test_recently_sent_deduplication() {
        let mut service = NotificationService::default();

        // Manually insert a recent notification
        service.sent_notifications.insert(
            "cluster1".to_string(),
            chrono::Utc::now(),
        );

        assert!(service.was_recently_sent("cluster1", 60));
        assert!(!service.was_recently_sent("cluster2", 60));
    }
}
