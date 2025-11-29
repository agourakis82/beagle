//! Consolidated LLM Routing Types with Q1 SOTA Standards
//!
//! Unifies RequestMeta and ProviderTier types to avoid duplication and ensure
//! consistency across the codebase. Based on multi-criteria decision analysis
//! and provider capability modeling.
//!
//! References:
//! - Saaty, T.L. (1980). "The Analytic Hierarchy Process"
//! - Roy, B. (1996). "Multicriteria Methodology for Decision Aiding"
//! - Hwang, C.L. & Yoon, K. (1981). "Multiple Attribute Decision Making"

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Unified request metadata for intelligent LLM routing
///
/// This structure captures all relevant features of a request to enable
/// optimal provider selection based on capability matching.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RequestMeta {
    // Quality Requirements
    /// Requires highest quality output (Q1 journal standard)
    pub requires_high_quality: bool,

    /// Requires PhD-level reasoning and domain expertise
    pub requires_phd_level_reasoning: bool,

    /// Has high bias risk (needs careful provider selection)
    pub high_bias_risk: bool,

    /// Is a critical section requiring maximum reliability
    pub critical_section: bool,

    // Capability Requirements
    /// Requires mathematical proofs or symbolic reasoning
    pub requires_math: bool,

    /// Requires vision/multimodal capabilities
    pub requires_vision: bool,

    /// Requires code generation or analysis
    pub requires_code: bool,

    /// Requires real-time response (<1s latency)
    pub requires_realtime: bool,

    // Operational Requirements
    /// Must run offline (no internet connection)
    pub offline_required: bool,

    /// Approximate token count for cost estimation
    pub approximate_tokens: usize,

    /// Maximum acceptable cost in USD
    pub max_cost_usd: Option<f64>,

    /// Required language support
    pub language: Option<String>,

    // Advanced Features
    /// Requires tool/function calling
    pub requires_tools: bool,

    /// Requires long context (>100k tokens)
    pub requires_long_context: bool,

    /// Requires deterministic outputs
    pub requires_deterministic: bool,

    /// Custom metadata for provider-specific features
    pub custom_metadata: HashMap<String, String>,
}

impl Default for RequestMeta {
    fn default() -> Self {
        Self {
            requires_high_quality: false,
            requires_phd_level_reasoning: false,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            requires_vision: false,
            requires_code: false,
            requires_realtime: false,
            offline_required: false,
            approximate_tokens: 1000,
            max_cost_usd: None,
            language: None,
            requires_tools: false,
            requires_long_context: false,
            requires_deterministic: false,
            custom_metadata: HashMap::new(),
        }
    }
}

impl RequestMeta {
    /// Create a basic request with minimal requirements
    pub fn basic() -> Self {
        Self::default()
    }

    /// Create a high-quality request for critical tasks
    pub fn high_quality() -> Self {
        Self {
            requires_high_quality: true,
            critical_section: true,
            ..Default::default()
        }
    }

    /// Create a request for mathematical/scientific tasks
    pub fn scientific() -> Self {
        Self {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            requires_math: true,
            ..Default::default()
        }
    }

    /// Create a request for code-related tasks
    pub fn coding() -> Self {
        Self {
            requires_code: true,
            requires_deterministic: true,
            ..Default::default()
        }
    }

    /// Calculate a priority score for this request
    pub fn priority_score(&self) -> f64 {
        let mut score = 0.0;

        // Critical factors (highest weight)
        if self.critical_section {
            score += 10.0;
        }
        if self.high_bias_risk {
            score += 8.0;
        }

        // Quality factors (high weight)
        if self.requires_high_quality {
            score += 6.0;
        }
        if self.requires_phd_level_reasoning {
            score += 5.0;
        }

        // Capability factors (medium weight)
        if self.requires_math {
            score += 4.0;
        }
        if self.requires_vision {
            score += 3.0;
        }
        if self.requires_code {
            score += 3.0;
        }
        if self.requires_tools {
            score += 2.0;
        }

        // Operational factors (low weight)
        if self.requires_realtime {
            score += 2.0;
        }
        if self.offline_required {
            score += 1.0;
        }

        score
    }

    /// Check if this request matches provider capabilities
    pub fn matches_capabilities(&self, capabilities: &ProviderCapabilities) -> bool {
        // Check required capabilities
        if self.requires_math && !capabilities.math_support {
            return false;
        }
        if self.requires_vision && !capabilities.vision_support {
            return false;
        }
        if self.requires_code && !capabilities.code_support {
            return false;
        }
        if self.requires_tools && !capabilities.tool_support {
            return false;
        }
        if self.requires_long_context && capabilities.max_context < 100000 {
            return false;
        }
        if self.offline_required && !capabilities.offline_capable {
            return false;
        }

        // Check quality requirements
        if self.requires_high_quality && capabilities.quality_tier < 2 {
            return false;
        }
        if self.requires_phd_level_reasoning && !capabilities.phd_level {
            return false;
        }

        true
    }
}

/// Provider tier with capability levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
pub enum ProviderTier {
    /// Tier -2: Local CLI tools (no API needed)
    LocalCli = -2,

    /// Tier -1: IDE integrations (Copilot, Cursor)
    IdeIntegration = -1,

    /// Tier 0: Direct API access (Claude, GPT-4)
    DirectApi = 0,

    /// Tier 1: Standard cloud (Grok 3, Gemini Pro)
    StandardCloud = 1,

    /// Tier 2: Premium cloud (Grok 4 Heavy, GPT-4 Turbo)
    PremiumCloud = 2,

    /// Tier 3: Specialized (DeepSeek Math, Codex)
    Specialized = 3,

    /// Tier 4: Local models (Gemma, Llama)
    LocalModel = 4,

    /// Tier 5: Fallback/Mock
    Fallback = 5,
}

impl ProviderTier {
    /// Get human-readable name
    pub fn name(&self) -> &'static str {
        match self {
            Self::LocalCli => "Local CLI",
            Self::IdeIntegration => "IDE Integration",
            Self::DirectApi => "Direct API",
            Self::StandardCloud => "Standard Cloud",
            Self::PremiumCloud => "Premium Cloud",
            Self::Specialized => "Specialized",
            Self::LocalModel => "Local Model",
            Self::Fallback => "Fallback",
        }
    }

    /// Get tier cost multiplier (relative to Tier 1)
    pub fn cost_multiplier(&self) -> f64 {
        match self {
            Self::LocalCli => 0.0,       // Free
            Self::IdeIntegration => 0.1, // Subscription-based
            Self::DirectApi => 2.0,      // Direct API premium
            Self::StandardCloud => 1.0,  // Baseline
            Self::PremiumCloud => 5.0,   // Premium pricing
            Self::Specialized => 3.0,    // Specialized premium
            Self::LocalModel => 0.01,    // Compute cost only
            Self::Fallback => 0.0,       // Free/Mock
        }
    }

    /// Check if tier requires API key
    pub fn requires_api_key(&self) -> bool {
        matches!(
            self,
            Self::DirectApi | Self::StandardCloud | Self::PremiumCloud | Self::Specialized
        )
    }

    /// Get default timeout for this tier (milliseconds)
    pub fn default_timeout_ms(&self) -> u64 {
        match self {
            Self::LocalCli => 30000,       // 30s for CLI
            Self::IdeIntegration => 20000, // 20s for IDE
            Self::DirectApi => 60000,      // 60s for direct API
            Self::StandardCloud => 30000,  // 30s standard
            Self::PremiumCloud => 120000,  // 120s for heavy models
            Self::Specialized => 90000,    // 90s for specialized
            Self::LocalModel => 60000,     // 60s for local
            Self::Fallback => 5000,        // 5s for fallback
        }
    }
}

/// Provider capabilities specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderCapabilities {
    /// Provider name
    pub name: String,

    /// Provider tier
    pub tier: ProviderTier,

    /// Quality tier (0-3, where 3 is highest)
    pub quality_tier: u8,

    /// Supports PhD-level reasoning
    pub phd_level: bool,

    /// Maximum context window size
    pub max_context: usize,

    /// Mathematical reasoning support
    pub math_support: bool,

    /// Vision/multimodal support
    pub vision_support: bool,

    /// Code generation support
    pub code_support: bool,

    /// Tool/function calling support
    pub tool_support: bool,

    /// Can run offline
    pub offline_capable: bool,

    /// Average latency in milliseconds
    pub avg_latency_ms: u64,

    /// Cost per 1M tokens (USD)
    pub cost_per_million_tokens: f64,

    /// Supported languages
    pub languages: Vec<String>,

    /// Provider-specific features
    pub custom_features: HashMap<String, bool>,
}

impl ProviderCapabilities {
    /// Create capabilities for Claude via CLI
    pub fn claude_cli() -> Self {
        Self {
            name: "Claude CLI".to_string(),
            tier: ProviderTier::LocalCli,
            quality_tier: 3,
            phd_level: true,
            max_context: 200000,
            math_support: true,
            vision_support: true,
            code_support: true,
            tool_support: true,
            offline_capable: false, // Needs internet for Claude
            avg_latency_ms: 5000,
            cost_per_million_tokens: 0.0, // Free via CLI
            languages: vec!["en".to_string()],
            custom_features: HashMap::from([
                ("artifacts".to_string(), true),
                ("web_search".to_string(), true),
            ]),
        }
    }

    /// Create capabilities for GitHub Copilot
    pub fn github_copilot() -> Self {
        Self {
            name: "GitHub Copilot".to_string(),
            tier: ProviderTier::IdeIntegration,
            quality_tier: 2,
            phd_level: false,
            max_context: 8192,
            math_support: false,
            vision_support: false,
            code_support: true,
            tool_support: false,
            offline_capable: false,
            avg_latency_ms: 1000,
            cost_per_million_tokens: 10.0, // Subscription-based
            languages: vec!["en".to_string()],
            custom_features: HashMap::from([("inline_completion".to_string(), true)]),
        }
    }

    /// Create capabilities for Grok 3
    pub fn grok3() -> Self {
        Self {
            name: "Grok 3".to_string(),
            tier: ProviderTier::StandardCloud,
            quality_tier: 2,
            phd_level: false,
            max_context: 131072,
            math_support: true,
            vision_support: false,
            code_support: true,
            tool_support: false,
            offline_capable: false,
            avg_latency_ms: 3000,
            cost_per_million_tokens: 5.0,
            languages: vec!["en".to_string(), "es".to_string(), "fr".to_string()],
            custom_features: HashMap::new(),
        }
    }

    /// Create capabilities for Grok 4 Heavy
    pub fn grok4_heavy() -> Self {
        Self {
            name: "Grok 4 Heavy".to_string(),
            tier: ProviderTier::PremiumCloud,
            quality_tier: 3,
            phd_level: true,
            max_context: 131072,
            math_support: true,
            vision_support: true,
            code_support: true,
            tool_support: true,
            offline_capable: false,
            avg_latency_ms: 10000,
            cost_per_million_tokens: 30.0,
            languages: vec!["en".to_string()],
            custom_features: HashMap::from([
                ("anti_bias".to_string(), true),
                ("scientific_rigor".to_string(), true),
            ]),
        }
    }

    /// Create capabilities for DeepSeek Math
    pub fn deepseek_math() -> Self {
        Self {
            name: "DeepSeek Math".to_string(),
            tier: ProviderTier::Specialized,
            quality_tier: 3,
            phd_level: true,
            max_context: 32768,
            math_support: true,
            vision_support: false,
            code_support: false,
            tool_support: false,
            offline_capable: false,
            avg_latency_ms: 5000,
            cost_per_million_tokens: 14.0,
            languages: vec!["en".to_string()],
            custom_features: HashMap::from([
                ("theorem_proving".to_string(), true),
                ("symbolic_math".to_string(), true),
            ]),
        }
    }

    /// Create capabilities for local Gemma
    pub fn gemma_local() -> Self {
        Self {
            name: "Gemma 7B".to_string(),
            tier: ProviderTier::LocalModel,
            quality_tier: 1,
            phd_level: false,
            max_context: 8192,
            math_support: false,
            vision_support: false,
            code_support: true,
            tool_support: false,
            offline_capable: true,
            avg_latency_ms: 2000,
            cost_per_million_tokens: 0.1, // Compute cost
            languages: vec!["en".to_string()],
            custom_features: HashMap::new(),
        }
    }

    /// Calculate match score for a request
    pub fn match_score(&self, meta: &RequestMeta) -> f64 {
        let mut score = 0.0;
        let mut max_score = 0.0;

        // Quality matching (weight: 0.3)
        max_score += 30.0;
        if meta.requires_high_quality {
            score += (self.quality_tier as f64 / 3.0) * 30.0;
        } else {
            score += 30.0; // No quality requirement
        }

        // PhD-level matching (weight: 0.2)
        max_score += 20.0;
        if meta.requires_phd_level_reasoning {
            if self.phd_level {
                score += 20.0;
            }
        } else {
            score += 20.0; // No PhD requirement
        }

        // Capability matching (weight: 0.3)
        max_score += 30.0;
        let mut capability_score: f64 = 30.0;
        if meta.requires_math && !self.math_support {
            capability_score -= 10.0;
        }
        if meta.requires_vision && !self.vision_support {
            capability_score -= 10.0;
        }
        if meta.requires_code && !self.code_support {
            capability_score -= 10.0;
        }
        score += capability_score.max(0.0);

        // Cost matching (weight: 0.1)
        max_score += 10.0;
        if let Some(max_cost) = meta.max_cost_usd {
            let request_cost =
                (meta.approximate_tokens as f64 / 1_000_000.0) * self.cost_per_million_tokens;
            if request_cost <= max_cost {
                score += 10.0;
            } else {
                score += (max_cost / request_cost) * 10.0;
            }
        } else {
            score += 10.0; // No cost constraint
        }

        // Latency matching (weight: 0.1)
        max_score += 10.0;
        if meta.requires_realtime {
            if self.avg_latency_ms <= 1000 {
                score += 10.0;
            } else {
                score += (1000.0 / self.avg_latency_ms as f64) * 10.0;
            }
        } else {
            score += 10.0; // No latency requirement
        }

        score / max_score
    }
}

/// Provider selection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderSelection {
    /// Selected provider capabilities
    pub provider: ProviderCapabilities,

    /// Match score (0.0 to 1.0)
    pub match_score: f64,

    /// Estimated cost for this request
    pub estimated_cost: f64,

    /// Estimated latency
    pub estimated_latency_ms: u64,

    /// Reason for selection
    pub selection_reason: String,

    /// Alternative providers (ranked)
    pub alternatives: Vec<(ProviderCapabilities, f64)>,
}

/// Router statistics for tracking usage
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RouterStatistics {
    /// Total requests routed
    pub total_requests: usize,

    /// Requests per tier
    pub tier_distribution: HashMap<ProviderTier, usize>,

    /// Requests per provider
    pub provider_distribution: HashMap<String, usize>,

    /// Total tokens processed
    pub total_tokens: usize,

    /// Total cost incurred
    pub total_cost_usd: f64,

    /// Average latency per tier
    pub avg_latency_by_tier: HashMap<ProviderTier, f64>,

    /// Success rate per provider
    pub success_rate_by_provider: HashMap<String, f64>,

    /// Failed requests
    pub failed_requests: usize,

    /// Fallback activations
    pub fallback_count: usize,
}

impl RouterStatistics {
    /// Record a successful request
    pub fn record_success(
        &mut self,
        provider: &ProviderCapabilities,
        tokens: usize,
        latency_ms: u64,
        cost: f64,
    ) {
        self.total_requests += 1;
        self.total_tokens += tokens;
        self.total_cost_usd += cost;

        *self.tier_distribution.entry(provider.tier).or_insert(0) += 1;
        *self
            .provider_distribution
            .entry(provider.name.clone())
            .or_insert(0) += 1;

        // Update average latency
        let tier_count = self.tier_distribution[&provider.tier] as f64;
        let current_avg = self
            .avg_latency_by_tier
            .get(&provider.tier)
            .copied()
            .unwrap_or(0.0);
        let new_avg = (current_avg * (tier_count - 1.0) + latency_ms as f64) / tier_count;
        self.avg_latency_by_tier.insert(provider.tier, new_avg);

        // Update success rate
        let provider_count = self.provider_distribution[&provider.name] as f64;
        let current_rate = self
            .success_rate_by_provider
            .get(&provider.name)
            .copied()
            .unwrap_or(1.0);
        let new_rate = (current_rate * (provider_count - 1.0) + 1.0) / provider_count;
        self.success_rate_by_provider
            .insert(provider.name.clone(), new_rate);
    }

    /// Record a failed request
    pub fn record_failure(&mut self, provider: &ProviderCapabilities) {
        self.failed_requests += 1;
        self.total_requests += 1;

        *self.tier_distribution.entry(provider.tier).or_insert(0) += 1;
        *self
            .provider_distribution
            .entry(provider.name.clone())
            .or_insert(0) += 1;

        // Update success rate
        let provider_count = self.provider_distribution[&provider.name] as f64;
        let current_rate = self
            .success_rate_by_provider
            .get(&provider.name)
            .copied()
            .unwrap_or(1.0);
        let new_rate = (current_rate * (provider_count - 1.0)) / provider_count;
        self.success_rate_by_provider
            .insert(provider.name.clone(), new_rate);
    }

    /// Record a fallback activation
    pub fn record_fallback(&mut self) {
        self.fallback_count += 1;
    }

    /// Get summary statistics
    pub fn summary(&self) -> String {
        format!(
            "Router Statistics:\n\
            Total Requests: {}\n\
            Total Tokens: {}\n\
            Total Cost: ${:.2}\n\
            Failed Requests: {}\n\
            Fallback Count: {}\n\
            Success Rate: {:.1}%",
            self.total_requests,
            self.total_tokens,
            self.total_cost_usd,
            self.failed_requests,
            self.fallback_count,
            if self.total_requests > 0 {
                ((self.total_requests - self.failed_requests) as f64 / self.total_requests as f64)
                    * 100.0
            } else {
                0.0
            }
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_request_meta_priority() {
        let basic = RequestMeta::basic();
        assert_eq!(basic.priority_score(), 0.0);

        let critical = RequestMeta {
            critical_section: true,
            requires_high_quality: true,
            ..Default::default()
        };
        assert!(critical.priority_score() > 15.0);
    }

    #[test]
    fn test_provider_matching() {
        let meta = RequestMeta::scientific();
        let grok3 = ProviderCapabilities::grok3();
        let grok4 = ProviderCapabilities::grok4_heavy();

        assert!(grok4.match_score(&meta) > grok3.match_score(&meta));
    }

    #[test]
    fn test_tier_ordering() {
        assert!(ProviderTier::LocalCli < ProviderTier::StandardCloud);
        assert!(ProviderTier::StandardCloud < ProviderTier::PremiumCloud);
    }

    #[test]
    fn test_statistics_tracking() {
        let mut stats = RouterStatistics::default();
        let provider = ProviderCapabilities::grok3();

        stats.record_success(&provider, 1000, 3000, 0.005);
        assert_eq!(stats.total_requests, 1);
        assert_eq!(stats.total_tokens, 1000);
        assert!(stats.total_cost_usd > 0.0);

        stats.record_failure(&provider);
        assert_eq!(stats.total_requests, 2);
        assert_eq!(stats.failed_requests, 1);
        assert!(stats.success_rate_by_provider[&provider.name] < 1.0);
    }

    #[test]
    fn test_capability_matching() {
        let math_request = RequestMeta {
            requires_math: true,
            ..Default::default()
        };

        let deepseek = ProviderCapabilities::deepseek_math();
        let copilot = ProviderCapabilities::github_copilot();

        assert!(math_request.matches_capabilities(&deepseek));
        assert!(!math_request.matches_capabilities(&copilot));
    }
}
