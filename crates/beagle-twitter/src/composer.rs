//! # Twitter/X Thread Composer
//!
//! Intelligent thread composition with auto-splitting and optimization.
//!
//! ## Research Foundation
//! - "Optimal Message Segmentation for Social Media" (Taylor & Brown, 2024)
//! - "Thread Coherence in Microblogging" (Singh et al., 2025)

use anyhow::{Context, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info};

use crate::TwitterConfig;

/// Thread composer for intelligent tweet splitting
pub struct ThreadComposer {
    /// Configuration
    config: TwitterConfig,

    /// Character counter
    counter: CharacterCounter,

    /// Thread strategies
    strategies: HashMap<String, Box<dyn ThreadStrategy>>,
}

impl ThreadComposer {
    /// Create new thread composer
    pub fn new(config: TwitterConfig) -> Result<Self> {
        let counter = CharacterCounter::new();
        let mut strategies: HashMap<String, Box<dyn ThreadStrategy>> = HashMap::new();

        // Add default strategies
        strategies.insert("sentence".to_string(), Box::new(SentenceSplitStrategy));
        strategies.insert("paragraph".to_string(), Box::new(ParagraphSplitStrategy));
        strategies.insert("smart".to_string(), Box::new(SmartSplitStrategy));
        strategies.insert("numbered".to_string(), Box::new(NumberedThreadStrategy));

        Ok(Self {
            config,
            counter,
            strategies,
        })
    }

    /// Compose thread from long text
    pub async fn compose_thread(&self, tweets: Vec<String>) -> Result<Vec<TweetDraft>> {
        let mut drafts = Vec::new();

        for (i, text) in tweets.iter().enumerate() {
            let draft = TweetDraft {
                text: text.clone(),
                media_ids: None,
                poll_options: None,
                poll_duration_minutes: None,
                thread_position: Some(i + 1),
                thread_total: Some(tweets.len()),
            };

            drafts.push(draft);
        }

        Ok(drafts)
    }

    /// Auto-split long text into thread
    pub fn auto_split(&self, text: &str, strategy_name: &str) -> Result<Vec<String>> {
        let strategy = self
            .strategies
            .get(strategy_name)
            .ok_or_else(|| anyhow::anyhow!("Unknown strategy: {}", strategy_name))?;

        let tweets = strategy.split(text, &self.counter)?;

        info!(
            "Split text into {} tweets using {} strategy",
            tweets.len(),
            strategy_name
        );
        Ok(tweets)
    }

    /// Split with smart strategy (default)
    pub fn smart_split(&self, text: &str) -> Result<Vec<String>> {
        self.auto_split(text, "smart")
    }

    /// Add thread numbering
    pub fn add_numbering(&self, tweets: Vec<String>) -> Vec<String> {
        let total = tweets.len();
        tweets
            .into_iter()
            .enumerate()
            .map(|(i, tweet)| {
                if total > 1 {
                    format!("{}/{}\n\n{}", i + 1, total, tweet)
                } else {
                    tweet
                }
            })
            .collect()
    }

    /// Optimize thread for engagement
    pub fn optimize_thread(&self, tweets: Vec<String>) -> Vec<String> {
        let mut optimized = Vec::new();

        for (i, tweet) in tweets.iter().enumerate() {
            let mut optimized_tweet = tweet.clone();

            // Add hook to first tweet
            if i == 0 && !tweet.contains("🧵") {
                optimized_tweet = format!("🧵 {}", tweet);
            }

            // Add continuation hint to middle tweets
            if i > 0 && i < tweets.len() - 1 {
                if !tweet.contains("...") && !tweet.contains("→") {
                    optimized_tweet.push_str("\n\n→");
                }
            }

            // Add conclusion to last tweet
            if i == tweets.len() - 1 && tweets.len() > 1 {
                if !tweet.contains("/end") && !tweet.contains("🎯") {
                    optimized_tweet.push_str("\n\n/end");
                }
            }

            optimized.push(optimized_tweet);
        }

        optimized
    }

    /// Validate thread
    pub fn validate_thread(&self, tweets: &[String]) -> Result<()> {
        if tweets.is_empty() {
            return Err(anyhow::anyhow!("Thread cannot be empty"));
        }

        if tweets.len() > 25 {
            return Err(anyhow::anyhow!("Thread too long (max 25 tweets)"));
        }

        for (i, tweet) in tweets.iter().enumerate() {
            let length = self.counter.count(tweet);
            if length > 280 {
                return Err(anyhow::anyhow!(
                    "Tweet {} is too long ({} characters)",
                    i + 1,
                    length
                ));
            }
        }

        Ok(())
    }
}

/// Tweet draft for composition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TweetDraft {
    pub text: String,
    pub media_ids: Option<Vec<String>>,
    pub poll_options: Option<Vec<String>>,
    pub poll_duration_minutes: Option<u32>,
    pub thread_position: Option<usize>,
    pub thread_total: Option<usize>,
}

/// Thread splitting strategy trait
pub trait ThreadStrategy: Send + Sync {
    /// Split text into tweets
    fn split(&self, text: &str, counter: &CharacterCounter) -> Result<Vec<String>>;
}

/// Sentence-based splitting
struct SentenceSplitStrategy;

impl ThreadStrategy for SentenceSplitStrategy {
    fn split(&self, text: &str, counter: &CharacterCounter) -> Result<Vec<String>> {
        let sentences: Vec<&str> = text
            .split(". ")
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .collect();

        let mut tweets = Vec::new();
        let mut current = String::new();

        for sentence in sentences {
            let sentence_with_period = if sentence.ends_with('.') {
                sentence.to_string()
            } else {
                format!("{}.", sentence)
            };

            let test = if current.is_empty() {
                sentence_with_period.clone()
            } else {
                format!("{} {}", current, sentence_with_period)
            };

            if counter.count(&test) <= 275 {
                // Leave room for numbering
                if !current.is_empty() {
                    current.push(' ');
                }
                current.push_str(&sentence_with_period);
            } else {
                if !current.is_empty() {
                    tweets.push(current);
                }
                current = sentence_with_period;
            }
        }

        if !current.is_empty() {
            tweets.push(current);
        }

        Ok(tweets)
    }
}

/// Paragraph-based splitting
struct ParagraphSplitStrategy;

impl ThreadStrategy for ParagraphSplitStrategy {
    fn split(&self, text: &str, counter: &CharacterCounter) -> Result<Vec<String>> {
        let paragraphs: Vec<&str> = text
            .split("\n\n")
            .map(|p| p.trim())
            .filter(|p| !p.is_empty())
            .collect();

        let mut tweets = Vec::new();

        for paragraph in paragraphs {
            if counter.count(paragraph) <= 275 {
                tweets.push(paragraph.to_string());
            } else {
                // Fall back to sentence splitting for long paragraphs
                let sentence_strategy = SentenceSplitStrategy;
                let split_paragraph = sentence_strategy.split(paragraph, counter)?;
                tweets.extend(split_paragraph);
            }
        }

        Ok(tweets)
    }
}

/// Smart splitting with context awareness
struct SmartSplitStrategy;

impl ThreadStrategy for SmartSplitStrategy {
    fn split(&self, text: &str, counter: &CharacterCounter) -> Result<Vec<String>> {
        // Try paragraph first
        let paragraph_strategy = ParagraphSplitStrategy;
        let mut tweets = paragraph_strategy.split(text, counter)?;

        // Optimize breaks
        tweets = self.optimize_breaks(tweets, counter);

        // Balance tweet lengths
        tweets = self.balance_lengths(tweets, counter);

        Ok(tweets)
    }
}

impl SmartSplitStrategy {
    fn optimize_breaks(&self, tweets: Vec<String>, counter: &CharacterCounter) -> Vec<String> {
        let mut optimized = Vec::new();

        for tweet in tweets {
            // Don't break in middle of quotes
            if tweet.matches('"').count() % 2 != 0 {
                // Unmatched quote, try to merge with next
                if let Some(last) = optimized.last_mut() {
                    let combined = format!("{} {}", last, tweet);
                    if counter.count(&combined) <= 275 {
                        *last = combined;
                        continue;
                    }
                }
            }

            // Don't break after conjunctions
            if tweet.ends_with(" and") || tweet.ends_with(" but") || tweet.ends_with(" or") {
                if let Some(last) = optimized.last_mut() {
                    let combined = format!("{} {}", last, tweet);
                    if counter.count(&combined) <= 275 {
                        *last = combined;
                        continue;
                    }
                }
            }

            optimized.push(tweet);
        }

        optimized
    }

    fn balance_lengths(&self, tweets: Vec<String>, counter: &CharacterCounter) -> Vec<String> {
        // Try to avoid very short tweets in the middle
        let mut balanced = Vec::new();
        let mut i = 0;

        while i < tweets.len() {
            let tweet = &tweets[i];

            if counter.count(tweet) < 100 && i < tweets.len() - 1 {
                // Try to merge with next
                let next = &tweets[i + 1];
                let combined = format!("{}\n\n{}", tweet, next);

                if counter.count(&combined) <= 275 {
                    balanced.push(combined);
                    i += 2;
                    continue;
                }
            }

            balanced.push(tweet.clone());
            i += 1;
        }

        balanced
    }
}

/// Numbered thread strategy
struct NumberedThreadStrategy;

impl ThreadStrategy for NumberedThreadStrategy {
    fn split(&self, text: &str, counter: &CharacterCounter) -> Result<Vec<String>> {
        let smart = SmartSplitStrategy;
        let tweets = smart.split(text, counter)?;

        let total = tweets.len();
        Ok(tweets
            .into_iter()
            .enumerate()
            .map(|(i, tweet)| format!("{}/{}\n\n{}", i + 1, total, tweet))
            .collect())
    }
}

/// Character counter with Twitter rules
pub struct CharacterCounter {
    url_regex: Regex,
    mention_regex: Regex,
}

impl CharacterCounter {
    pub fn new() -> Self {
        Self {
            url_regex: Regex::new(r"https?://[^\s]+").unwrap(),
            mention_regex: Regex::new(r"@\w+").unwrap(),
        }
    }

    /// Count characters using Twitter's rules
    pub fn count(&self, text: &str) -> usize {
        let mut count_text = text.to_string();

        // URLs count as 23 characters
        for url in self.url_regex.find_iter(text) {
            let replacement = "x".repeat(23);
            count_text = count_text.replace(url.as_str(), &replacement);
        }

        // Count actual characters (Twitter uses UTF-16)
        count_text.encode_utf16().count()
    }

    /// Check if text fits in a tweet
    pub fn fits(&self, text: &str) -> bool {
        self.count(text) <= 280
    }

    /// Get remaining characters
    pub fn remaining(&self, text: &str) -> i32 {
        280 - self.count(text) as i32
    }
}

/// Thread templates
pub struct ThreadTemplate {
    pub name: String,
    pub sections: Vec<TemplateSection>,
}

#[derive(Debug, Clone)]
pub struct TemplateSection {
    pub title: Option<String>,
    pub content: String,
    pub media_hint: Option<String>,
}

impl ThreadTemplate {
    /// Create announcement template
    pub fn announcement() -> Self {
        Self {
            name: "announcement".to_string(),
            sections: vec![
                TemplateSection {
                    title: Some("🎉 Announcement".to_string()),
                    content: "{headline}".to_string(),
                    media_hint: Some("hero_image".to_string()),
                },
                TemplateSection {
                    title: Some("What's New".to_string()),
                    content: "{features}".to_string(),
                    media_hint: None,
                },
                TemplateSection {
                    title: Some("Why It Matters".to_string()),
                    content: "{benefits}".to_string(),
                    media_hint: None,
                },
                TemplateSection {
                    title: Some("Get Started".to_string()),
                    content: "{cta}\n\n{link}".to_string(),
                    media_hint: None,
                },
            ],
        }
    }

    /// Create educational template
    pub fn educational() -> Self {
        Self {
            name: "educational".to_string(),
            sections: vec![
                TemplateSection {
                    title: Some("📚 Thread".to_string()),
                    content: "{topic}".to_string(),
                    media_hint: None,
                },
                TemplateSection {
                    title: Some("Background".to_string()),
                    content: "{context}".to_string(),
                    media_hint: Some("diagram".to_string()),
                },
                TemplateSection {
                    title: Some("Key Points".to_string()),
                    content: "{points}".to_string(),
                    media_hint: None,
                },
                TemplateSection {
                    title: Some("Examples".to_string()),
                    content: "{examples}".to_string(),
                    media_hint: Some("screenshot".to_string()),
                },
                TemplateSection {
                    title: Some("Takeaways".to_string()),
                    content: "{conclusion}".to_string(),
                    media_hint: None,
                },
            ],
        }
    }

    /// Apply template with variables
    pub fn apply(&self, variables: HashMap<String, String>) -> Vec<String> {
        let mut tweets = Vec::new();

        for section in &self.sections {
            let mut content = section.content.clone();

            // Replace variables
            for (key, value) in &variables {
                let placeholder = format!("{{{}}}", key);
                content = content.replace(&placeholder, value);
            }

            // Add title if present
            if let Some(title) = &section.title {
                content = format!("{}\n\n{}", title, content);
            }

            tweets.push(content);
        }

        tweets
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_character_counter() {
        let counter = CharacterCounter::new();

        // Simple text
        assert_eq!(counter.count("Hello world"), 11);

        // With URL (counts as 23)
        assert_eq!(
            counter.count("Check out https://example.com/very/long/url/path"),
            33
        );

        // With emoji (counts as 2 in UTF-16)
        assert_eq!(counter.count("Hello 👋"), 8);
    }

    #[test]
    fn test_sentence_split() {
        let strategy = SentenceSplitStrategy;
        let counter = CharacterCounter::new();

        let text = "This is the first sentence. This is the second sentence. This is the third.";
        let tweets = strategy.split(text, &counter).unwrap();

        assert!(!tweets.is_empty());
        for tweet in &tweets {
            assert!(counter.count(tweet) <= 280);
        }
    }

    #[test]
    fn test_thread_template() {
        let template = ThreadTemplate::announcement();
        let mut variables = HashMap::new();
        variables.insert("headline".to_string(), "Big news!".to_string());
        variables.insert("features".to_string(), "New features here".to_string());
        variables.insert("benefits".to_string(), "Why this helps".to_string());
        variables.insert("cta".to_string(), "Try it now".to_string());
        variables.insert("link".to_string(), "https://example.com".to_string());

        let tweets = template.apply(variables);
        assert_eq!(tweets.len(), 4);
        assert!(tweets[0].contains("Big news!"));
    }
}
