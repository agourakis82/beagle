//! Prompt modules that wrap signatures with techniques

use async_trait::async_trait;
use serde::{de::DeserializeOwned, Serialize};

use crate::error::SignatureResult;
use crate::signature::PromptSignature;

/// Configuration for prompt modules
#[derive(Debug, Clone)]
pub struct ModuleConfig {
    /// Temperature for LLM calls
    pub temperature: Option<f32>,
    /// Maximum tokens for response
    pub max_tokens: Option<usize>,
    /// Number of retries on failure
    pub retries: usize,
    /// Timeout in milliseconds
    pub timeout_ms: u64,
}

impl Default for ModuleConfig {
    fn default() -> Self {
        Self {
            temperature: None,
            max_tokens: None,
            retries: 2,
            timeout_ms: 30000,
        }
    }
}

/// Trait for prompt modules that wrap signatures
#[async_trait]
pub trait PromptModule<S: PromptSignature>: Send + Sync {
    /// Execute the module with the given input
    ///
    /// The LLM client should be provided externally.
    async fn execute<F, Fut>(
        &self,
        input: &S::Input,
        llm_fn: F,
    ) -> SignatureResult<S::Output>
    where
        F: Fn(String) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = Result<String, String>> + Send;

    /// Get the underlying signature
    fn signature(&self) -> &S;

    /// Get module configuration
    fn config(&self) -> &ModuleConfig;

    /// Generate the prompt for this module
    fn generate_prompt(&self, input: &S::Input) -> String;
}

/// Simple prediction module (no additional techniques)
pub struct Predict<S: PromptSignature> {
    signature: S,
    config: ModuleConfig,
}

impl<S: PromptSignature> Predict<S> {
    /// Create a new Predict module
    pub fn new(signature: S) -> Self {
        Self {
            signature,
            config: ModuleConfig::default(),
        }
    }

    /// Create with custom config
    pub fn with_config(signature: S, config: ModuleConfig) -> Self {
        Self { signature, config }
    }
}

#[async_trait]
impl<S> PromptModule<S> for Predict<S>
where
    S: PromptSignature + Send + Sync,
    S::Input: Serialize + Send + Sync,
    S::Output: DeserializeOwned + Send + Sync,
{
    async fn execute<F, Fut>(
        &self,
        input: &S::Input,
        llm_fn: F,
    ) -> SignatureResult<S::Output>
    where
        F: Fn(String) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = Result<String, String>> + Send,
    {
        // Validate input
        self.signature.validate_input(input)?;

        // Generate prompt
        let prompt = self.generate_prompt(input);

        // Call LLM
        let response = llm_fn(prompt)
            .await
            .map_err(|e| crate::error::SignatureError::LlmError(e))?;

        // Parse output
        let output = self.signature.parse_output(&response)?;

        // Validate output
        self.signature.validate_output(&output)?;

        Ok(output)
    }

    fn signature(&self) -> &S {
        &self.signature
    }

    fn config(&self) -> &ModuleConfig {
        &self.config
    }

    fn generate_prompt(&self, input: &S::Input) -> String {
        self.signature.to_prompt(input)
    }
}

/// Chain of Thought module - adds reasoning before output
pub struct ChainOfThought<S: PromptSignature> {
    signature: S,
    config: ModuleConfig,
    reasoning_prefix: String,
}

impl<S: PromptSignature> ChainOfThought<S> {
    /// Create a new ChainOfThought module
    pub fn new(signature: S) -> Self {
        Self {
            signature,
            config: ModuleConfig::default(),
            reasoning_prefix: "Let me think through this step by step:".to_string(),
        }
    }

    /// Create with custom reasoning prefix
    pub fn with_prefix(signature: S, prefix: impl Into<String>) -> Self {
        Self {
            signature,
            config: ModuleConfig::default(),
            reasoning_prefix: prefix.into(),
        }
    }

    /// Create with custom config
    pub fn with_config(signature: S, config: ModuleConfig) -> Self {
        Self {
            signature,
            config,
            reasoning_prefix: "Let me think through this step by step:".to_string(),
        }
    }
}

#[async_trait]
impl<S> PromptModule<S> for ChainOfThought<S>
where
    S: PromptSignature + Send + Sync,
    S::Input: Serialize + Send + Sync,
    S::Output: DeserializeOwned + Send + Sync,
{
    async fn execute<F, Fut>(
        &self,
        input: &S::Input,
        llm_fn: F,
    ) -> SignatureResult<S::Output>
    where
        F: Fn(String) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = Result<String, String>> + Send,
    {
        // Validate input
        self.signature.validate_input(input)?;

        // Generate prompt with CoT
        let prompt = self.generate_prompt(input);

        // Call LLM
        let response = llm_fn(prompt)
            .await
            .map_err(|e| crate::error::SignatureError::LlmError(e))?;

        // Parse output (skip reasoning, find JSON)
        let output = self.signature.parse_output(&response)?;

        // Validate output
        self.signature.validate_output(&output)?;

        Ok(output)
    }

    fn signature(&self) -> &S {
        &self.signature
    }

    fn config(&self) -> &ModuleConfig {
        &self.config
    }

    fn generate_prompt(&self, input: &S::Input) -> String {
        let base_prompt = self.signature.to_prompt(input);

        format!(
            "{}\n\n{}\n\n<reasoning>\n[Your step-by-step reasoning here]\n</reasoning>\n\n\
            After your reasoning, provide the final output as JSON.\n\nOutput:\n",
            base_prompt, self.reasoning_prefix
        )
    }
}

/// ReAct module - enables tool use with reasoning
pub struct ReAct<S: PromptSignature> {
    signature: S,
    config: ModuleConfig,
    tools: Vec<ToolDefinition>,
    max_iterations: usize,
}

/// Definition of a tool for ReAct
#[derive(Debug, Clone)]
pub struct ToolDefinition {
    /// Tool name
    pub name: String,
    /// Tool description
    pub description: String,
    /// Parameter schema (JSON Schema)
    pub parameters: serde_json::Value,
}

impl<S: PromptSignature> ReAct<S> {
    /// Create a new ReAct module
    pub fn new(signature: S, tools: Vec<ToolDefinition>) -> Self {
        Self {
            signature,
            config: ModuleConfig::default(),
            tools,
            max_iterations: 5,
        }
    }

    /// Set maximum iterations
    pub fn with_max_iterations(mut self, max: usize) -> Self {
        self.max_iterations = max;
        self
    }
}

#[async_trait]
impl<S> PromptModule<S> for ReAct<S>
where
    S: PromptSignature + Send + Sync,
    S::Input: Serialize + Send + Sync,
    S::Output: DeserializeOwned + Send + Sync,
{
    async fn execute<F, Fut>(
        &self,
        input: &S::Input,
        llm_fn: F,
    ) -> SignatureResult<S::Output>
    where
        F: Fn(String) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = Result<String, String>> + Send,
    {
        // Validate input
        self.signature.validate_input(input)?;

        // Generate prompt with ReAct format
        let prompt = self.generate_prompt(input);

        // For now, just do a single call (full ReAct loop would need tool execution)
        let response = llm_fn(prompt)
            .await
            .map_err(|e| crate::error::SignatureError::LlmError(e))?;

        // Parse output
        let output = self.signature.parse_output(&response)?;

        // Validate output
        self.signature.validate_output(&output)?;

        Ok(output)
    }

    fn signature(&self) -> &S {
        &self.signature
    }

    fn config(&self) -> &ModuleConfig {
        &self.config
    }

    fn generate_prompt(&self, input: &S::Input) -> String {
        let base_prompt = self.signature.to_prompt(input);

        let tools_desc: Vec<String> = self
            .tools
            .iter()
            .map(|t| format!("- {}: {}", t.name, t.description))
            .collect();

        format!(
            "{}\n\nAvailable Tools:\n{}\n\n\
            Use the following format:\n\
            Thought: [your reasoning about what to do]\n\
            Action: [tool name or 'finish']\n\
            Action Input: [input for the tool as JSON]\n\
            Observation: [result from tool]\n\
            ... (repeat Thought/Action/Observation as needed)\n\
            Thought: I have enough information to answer\n\
            Action: finish\n\
            Action Input: [your final JSON output]\n",
            base_prompt,
            tools_desc.join("\n")
        )
    }
}

/// Program of Thought module - generates code to solve problems
pub struct ProgramOfThought<S: PromptSignature> {
    signature: S,
    config: ModuleConfig,
    language: String,
}

impl<S: PromptSignature> ProgramOfThought<S> {
    /// Create a new ProgramOfThought module
    pub fn new(signature: S) -> Self {
        Self {
            signature,
            config: ModuleConfig::default(),
            language: "python".to_string(),
        }
    }

    /// Set programming language
    pub fn with_language(mut self, language: impl Into<String>) -> Self {
        self.language = language.into();
        self
    }
}

#[async_trait]
impl<S> PromptModule<S> for ProgramOfThought<S>
where
    S: PromptSignature + Send + Sync,
    S::Input: Serialize + Send + Sync,
    S::Output: DeserializeOwned + Send + Sync,
{
    async fn execute<F, Fut>(
        &self,
        input: &S::Input,
        llm_fn: F,
    ) -> SignatureResult<S::Output>
    where
        F: Fn(String) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = Result<String, String>> + Send,
    {
        // Validate input
        self.signature.validate_input(input)?;

        // Generate prompt
        let prompt = self.generate_prompt(input);

        // Call LLM
        let response = llm_fn(prompt)
            .await
            .map_err(|e| crate::error::SignatureError::LlmError(e))?;

        // Parse output
        let output = self.signature.parse_output(&response)?;

        // Validate output
        self.signature.validate_output(&output)?;

        Ok(output)
    }

    fn signature(&self) -> &S {
        &self.signature
    }

    fn config(&self) -> &ModuleConfig {
        &self.config
    }

    fn generate_prompt(&self, input: &S::Input) -> String {
        let base_prompt = self.signature.to_prompt(input);

        format!(
            "{}\n\n\
            Solve this by writing {} code.\n\n\
            ```{}\n\
            # Write your solution here\n\
            # The code should compute and print the final answer\n\
            ```\n\n\
            After the code, provide your final answer as JSON.\n\nOutput:\n",
            base_prompt, self.language, self.language
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signature::{DynamicSignature, SignatureBuilder};

    fn create_test_signature() -> DynamicSignature {
        DynamicSignature::from_builder(
            SignatureBuilder::new("TestSignature")
                .description("A test signature")
                .input("question", "The question")
                .output("answer", "The answer"),
        )
    }

    #[test]
    fn test_predict_prompt_generation() {
        let sig = create_test_signature();
        let module = Predict::new(sig);

        let input = serde_json::json!({"question": "What is 2+2?"});
        let prompt = module.generate_prompt(&input);

        assert!(prompt.contains("A test signature"));
        assert!(prompt.contains("What is 2+2?"));
    }

    #[test]
    fn test_cot_prompt_generation() {
        let sig = create_test_signature();
        let module = ChainOfThought::new(sig);

        let input = serde_json::json!({"question": "What is 2+2?"});
        let prompt = module.generate_prompt(&input);

        assert!(prompt.contains("step by step"));
        assert!(prompt.contains("<reasoning>"));
    }

    #[test]
    fn test_react_prompt_generation() {
        let sig = create_test_signature();
        let tools = vec![ToolDefinition {
            name: "calculator".to_string(),
            description: "Performs calculations".to_string(),
            parameters: serde_json::json!({}),
        }];
        let module = ReAct::new(sig, tools);

        let input = serde_json::json!({"question": "What is 2+2?"});
        let prompt = module.generate_prompt(&input);

        assert!(prompt.contains("calculator"));
        assert!(prompt.contains("Thought:"));
        assert!(prompt.contains("Action:"));
    }
}
