//! BEAGLE Twitter Auto-Post - Posta threads bilíngues automaticamente

use anyhow::{Context, Result};
use beagle_bilingual::{generate_bilingual_thread, to_bilingual};
use serde_json::json;
use tracing::{error, info};

pub struct BeagleTwitter {
    bearer_token: String,
    client: reqwest::Client,
}

impl BeagleTwitter {
    pub fn new(bearer_token: impl Into<String>) -> Self {
        Self {
            bearer_token: bearer_token.into(),
            client: reqwest::Client::new(),
        }
    }

    /// Posta thread bilíngue quando paper > 98%
    pub async fn auto_post_bilingual_thread(
        &self,
        title_pt: &str,
        abstract_pt: &str,
        paper_url: &str,
    ) -> Result<Vec<String>> {
        info!("🐦 Auto-posting thread bilíngue no Twitter...");

        let thread = generate_bilingual_thread(title_pt, abstract_pt, paper_url).await?;

        let mut tweet_ids = Vec::new();
        let mut previous_tweet_id: Option<String> = None;

        for (i, tweet) in thread.iter().enumerate() {
            let tweet_id = self.post_tweet(tweet, previous_tweet_id.as_deref()).await?;
            tweet_ids.push(tweet_id.clone());
            previous_tweet_id = Some(tweet_id);

            info!("✅ Tweet {}/{} postado", i + 1, thread.len());

            // Delay entre tweets (evita rate limit)
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
        }

        info!(
            "✅ Thread bilíngue completa postada — {} tweets",
            tweet_ids.len()
        );
        Ok(tweet_ids)
    }

    /// Posta tweet individual
    async fn post_tweet(&self, text: &str, reply_to: Option<&str>) -> Result<String> {
        let url = "https://api.twitter.com/2/tweets";

        let mut body = json!({
            "text": text
        });

        if let Some(reply_id) = reply_to {
            body["reply"] = json!({
                "in_reply_to_tweet_id": reply_id
            });
        }

        let response = self
            .client
            .post(url)
            .bearer_auth(&self.bearer_token)
            .json(&body)
            .send()
            .await
            .context("Falha ao postar tweet")?;

        if !response.status().is_success() {
            let text = response.text().await.unwrap_or_default();
            error!("❌ Twitter API error: {}", text);
            return Err(anyhow::anyhow!("Twitter API error: {}", text));
        }

        let json: serde_json::Value = response.json().await.context("Falha ao parsear resposta")?;
        let tweet_id = json["data"]["id"]
            .as_str()
            .context("Tweet ID não encontrado")?
            .to_string();

        info!("✅ Tweet postado — ID: {}", tweet_id);
        Ok(tweet_id)
    }
}

/// Auto-posta thread bilíngue quando score > 98
pub async fn auto_post_if_ready(
    title_pt: &str,
    abstract_pt: &str,
    paper_url: &str,
    score: f64,
) -> Result<Option<Vec<String>>> {
    if score < 98.0 {
        info!("ℹ️  Score {} < 98.0, não postando ainda", score);
        return Ok(None);
    }

    let bearer_token =
        std::env::var("TWITTER_BEARER_TOKEN").context("TWITTER_BEARER_TOKEN não configurado")?;

    let twitter = BeagleTwitter::new(bearer_token);
    let tweet_ids = twitter
        .auto_post_bilingual_thread(title_pt, abstract_pt, paper_url)
        .await?;

    Ok(Some(tweet_ids))
}
