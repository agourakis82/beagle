//! Twitter Integration - Posta threads bilíngues automaticamente

use crate::generate_bilingual_thread;
use anyhow::{Context, Result};
use reqwest::Client;
use tracing::{error, info};

#[derive(Debug)]
pub struct BeagleTwitter {
    bearer_token: String,
    client: Client,
}

impl BeagleTwitter {
    pub fn new(bearer_token: impl Into<String>) -> Self {
        Self {
            bearer_token: bearer_token.into(),
            client: Client::new(),
        }
    }

    /// Posta thread bilíngue no Twitter
    pub async fn thread(&self, tweets: Vec<String>) -> Result<()> {
        if tweets.is_empty() {
            return Ok(());
        }

        info!("🐦 Postando thread com {} tweets...", tweets.len());

        let mut previous_tweet_id: Option<String> = None;

        for (i, tweet) in tweets.iter().enumerate() {
            let tweet_id = if let Some(prev_id) = previous_tweet_id {
                // Resposta ao tweet anterior
                self.reply_tweet(tweet, &prev_id).await?
            } else {
                // Primeiro tweet
                self.post_tweet(tweet).await?
            };

            previous_tweet_id = Some(tweet_id.clone());
            info!("✅ Tweet {} postado: {}", i + 1, tweet_id);

            // Aguarda um pouco entre tweets (rate limiting)
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
        }

        info!("🎉 Thread bilíngue postada com sucesso!");
        Ok(())
    }

    /// Posta thread bilíngue de paper automaticamente
    pub async fn thread_paper(
        &self,
        title_pt: &str,
        abstract_pt: &str,
        paper_url: &str,
    ) -> Result<()> {
        let thread = generate_bilingual_thread(title_pt, abstract_pt, paper_url).await?;
        self.thread(thread).await
    }

    async fn post_tweet(&self, text: &str) -> Result<String> {
        let url = "https://api.twitter.com/2/tweets";

        let payload = serde_json::json!({
            "text": text
        });

        let response = self
            .client
            .post(url)
            .bearer_auth(&self.bearer_token)
            .json(&payload)
            .send()
            .await
            .context("Falha ao postar tweet")?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            error!("❌ Erro ao postar tweet: {}", error_text);
            return Err(anyhow::anyhow!("Erro ao postar tweet: {}", error_text));
        }

        let data: serde_json::Value = response.json().await?;
        let tweet_id = data["data"]["id"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Tweet ID não encontrado"))?
            .to_string();

        Ok(tweet_id)
    }

    async fn reply_tweet(&self, text: &str, reply_to_id: &str) -> Result<String> {
        let url = "https://api.twitter.com/2/tweets";

        let payload = serde_json::json!({
            "text": text,
            "reply": {
                "in_reply_to_tweet_id": reply_to_id
            }
        });

        let response = self
            .client
            .post(url)
            .bearer_auth(&self.bearer_token)
            .json(&payload)
            .send()
            .await
            .context("Falha ao responder tweet")?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            error!("❌ Erro ao responder tweet: {}", error_text);
            return Err(anyhow::anyhow!("Erro ao responder tweet: {}", error_text));
        }

        let data: serde_json::Value = response.json().await?;
        let tweet_id = data["data"]["id"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Tweet ID não encontrado"))?
            .to_string();

        Ok(tweet_id)
    }
}
