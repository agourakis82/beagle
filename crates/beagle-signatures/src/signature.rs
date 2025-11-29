//! Core signature types and traits

use serde::{de::DeserializeOwned, Serialize};
use std::collections::HashMap;

use crate::error::SignatureResult;

/// Describes a field in a signature
#[derive(Debug, Clone)]
pub struct FieldDescriptor {
    /// Field name
    pub name: String,
    /// Field description (used in prompt generation)
    pub description: String,
    /// Whether the field is required
    pub required: bool,
    /// Default value (JSON)
    pub default: Option<serde_json::Value>,
    /// Field type hint
    pub type_hint: String,
}

impl FieldDescriptor {
    /// Create a new required field
    pub fn required(name: impl Into<String>, description: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            description: description.into(),
            required: true,
            default: None,
            type_hint: "string".to_string(),
        }
    }

    /// Create a new optional field
    pub fn optional(name: impl Into<String>, description: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            description: description.into(),
            required: false,
            default: None,
            type_hint: "string".to_string(),
        }
    }

    /// Set type hint
    pub fn with_type(mut self, type_hint: impl Into<String>) -> Self {
        self.type_hint = type_hint.into();
        self
    }

    /// Set default value
    pub fn with_default(mut self, default: serde_json::Value) -> Self {
        self.default = Some(default);
        self.required = false;
        self
    }
}

/// Marker trait for input fields
pub trait InputField: Serialize + Send + Sync {
    /// Get field descriptors
    fn descriptors() -> Vec<FieldDescriptor>;
}

/// Marker trait for output fields
pub trait OutputField: DeserializeOwned + Send + Sync {
    /// Get field descriptors
    fn descriptors() -> Vec<FieldDescriptor>;
}

/// Metadata for a signature
#[derive(Debug, Clone)]
pub struct SignatureMetadata {
    /// Signature name
    pub name: String,
    /// Description of what the signature does
    pub description: String,
    /// Input field descriptors
    pub inputs: Vec<FieldDescriptor>,
    /// Output field descriptors
    pub outputs: Vec<FieldDescriptor>,
    /// Additional instructions
    pub instructions: Option<String>,
    /// Examples for few-shot learning
    pub examples: Vec<SignatureExample>,
    /// Custom metadata
    pub custom: HashMap<String, String>,
}

impl SignatureMetadata {
    /// Create new metadata
    pub fn new(name: impl Into<String>, description: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            description: description.into(),
            inputs: Vec::new(),
            outputs: Vec::new(),
            instructions: None,
            examples: Vec::new(),
            custom: HashMap::new(),
        }
    }

    /// Add input field
    pub fn with_input(mut self, field: FieldDescriptor) -> Self {
        self.inputs.push(field);
        self
    }

    /// Add output field
    pub fn with_output(mut self, field: FieldDescriptor) -> Self {
        self.outputs.push(field);
        self
    }

    /// Add instructions
    pub fn with_instructions(mut self, instructions: impl Into<String>) -> Self {
        self.instructions = Some(instructions.into());
        self
    }

    /// Add example
    pub fn with_example(mut self, example: SignatureExample) -> Self {
        self.examples.push(example);
        self
    }
}

/// An example for few-shot learning
#[derive(Debug, Clone)]
pub struct SignatureExample {
    /// Input values
    pub input: serde_json::Value,
    /// Expected output values
    pub output: serde_json::Value,
    /// Optional explanation
    pub explanation: Option<String>,
}

impl SignatureExample {
    /// Create a new example
    pub fn new(input: serde_json::Value, output: serde_json::Value) -> Self {
        Self {
            input,
            output,
            explanation: None,
        }
    }

    /// Add explanation
    pub fn with_explanation(mut self, explanation: impl Into<String>) -> Self {
        self.explanation = Some(explanation.into());
        self
    }
}

/// Core trait for typed prompt signatures
///
/// A signature defines the input/output contract for a prompt,
/// similar to DSPy's Signature concept.
pub trait PromptSignature: Send + Sync {
    /// Input type for this signature
    type Input: Serialize + Send + Sync;

    /// Output type for this signature
    type Output: DeserializeOwned + Send + Sync;

    /// Get signature metadata
    fn metadata(&self) -> SignatureMetadata;

    /// Generate prompt from input
    fn to_prompt(&self, input: &Self::Input) -> String {
        let meta = self.metadata();
        let mut prompt = String::new();

        // Add description
        prompt.push_str(&format!("Task: {}\n\n", meta.description));

        // Add instructions if present
        if let Some(ref instructions) = meta.instructions {
            prompt.push_str(&format!("Instructions:\n{}\n\n", instructions));
        }

        // Add examples if present
        if !meta.examples.is_empty() {
            prompt.push_str("Examples:\n");
            for (i, example) in meta.examples.iter().enumerate() {
                prompt.push_str(&format!("\nExample {}:\n", i + 1));
                prompt.push_str(&format!("Input: {}\n", example.input));
                prompt.push_str(&format!("Output: {}\n", example.output));
                if let Some(ref explanation) = example.explanation {
                    prompt.push_str(&format!("Explanation: {}\n", explanation));
                }
            }
            prompt.push('\n');
        }

        // Add input fields description
        prompt.push_str("Input Fields:\n");
        for field in &meta.inputs {
            prompt.push_str(&format!("- {}: {}\n", field.name, field.description));
        }
        prompt.push('\n');

        // Add output fields description
        prompt.push_str("Output Fields:\n");
        for field in &meta.outputs {
            let required = if field.required { " (required)" } else { "" };
            prompt.push_str(&format!(
                "- {}: {}{}\n",
                field.name, field.description, required
            ));
        }
        prompt.push('\n');

        // Add actual input
        prompt.push_str("Input:\n");
        if let Ok(input_json) = serde_json::to_string_pretty(input) {
            prompt.push_str(&input_json);
        }
        prompt.push_str("\n\n");

        // Add output format instruction
        prompt.push_str("Provide your output as valid JSON with the fields described above.\n");
        prompt.push_str("Output:\n");

        prompt
    }

    /// Parse output from LLM response
    fn parse_output(&self, response: &str) -> SignatureResult<Self::Output> {
        crate::parser::OutputParser::parse_json(response)
    }

    /// Validate input before sending
    fn validate_input(&self, _input: &Self::Input) -> SignatureResult<()> {
        Ok(())
    }

    /// Validate output after parsing
    fn validate_output(&self, _output: &Self::Output) -> SignatureResult<()> {
        Ok(())
    }
}

/// Builder for creating signatures dynamically
pub struct SignatureBuilder {
    metadata: SignatureMetadata,
}

impl SignatureBuilder {
    /// Create a new builder
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            metadata: SignatureMetadata::new(name, ""),
        }
    }

    /// Set description
    pub fn description(mut self, description: impl Into<String>) -> Self {
        self.metadata.description = description.into();
        self
    }

    /// Add input field
    pub fn input(mut self, name: impl Into<String>, description: impl Into<String>) -> Self {
        self.metadata
            .inputs
            .push(FieldDescriptor::required(name, description));
        self
    }

    /// Add optional input field
    pub fn optional_input(
        mut self,
        name: impl Into<String>,
        description: impl Into<String>,
    ) -> Self {
        self.metadata
            .inputs
            .push(FieldDescriptor::optional(name, description));
        self
    }

    /// Add output field
    pub fn output(mut self, name: impl Into<String>, description: impl Into<String>) -> Self {
        self.metadata
            .outputs
            .push(FieldDescriptor::required(name, description));
        self
    }

    /// Add optional output field
    pub fn optional_output(
        mut self,
        name: impl Into<String>,
        description: impl Into<String>,
    ) -> Self {
        self.metadata
            .outputs
            .push(FieldDescriptor::optional(name, description));
        self
    }

    /// Add instructions
    pub fn instructions(mut self, instructions: impl Into<String>) -> Self {
        self.metadata.instructions = Some(instructions.into());
        self
    }

    /// Add example
    pub fn example(mut self, input: serde_json::Value, output: serde_json::Value) -> Self {
        self.metadata
            .examples
            .push(SignatureExample::new(input, output));
        self
    }

    /// Build the metadata
    pub fn build(self) -> SignatureMetadata {
        self.metadata
    }
}

/// A simple dynamic signature using JSON values
pub struct DynamicSignature {
    metadata: SignatureMetadata,
}

impl DynamicSignature {
    /// Create from metadata
    pub fn new(metadata: SignatureMetadata) -> Self {
        Self { metadata }
    }

    /// Create from builder
    pub fn from_builder(builder: SignatureBuilder) -> Self {
        Self::new(builder.build())
    }
}

impl PromptSignature for DynamicSignature {
    type Input = serde_json::Value;
    type Output = serde_json::Value;

    fn metadata(&self) -> SignatureMetadata {
        self.metadata.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_field_descriptor() {
        let field =
            FieldDescriptor::required("document", "The document to analyze").with_type("string");

        assert_eq!(field.name, "document");
        assert!(field.required);
        assert_eq!(field.type_hint, "string");
    }

    #[test]
    fn test_signature_builder() {
        let metadata = SignatureBuilder::new("Summarize")
            .description("Summarize a document")
            .input("document", "The document to summarize")
            .output("summary", "A concise summary")
            .instructions("Keep the summary under 100 words")
            .build();

        assert_eq!(metadata.name, "Summarize");
        assert_eq!(metadata.inputs.len(), 1);
        assert_eq!(metadata.outputs.len(), 1);
        assert!(metadata.instructions.is_some());
    }

    #[test]
    fn test_dynamic_signature() {
        let sig = DynamicSignature::from_builder(
            SignatureBuilder::new("QA")
                .description("Answer a question")
                .input("question", "The question to answer")
                .output("answer", "The answer"),
        );

        let input = serde_json::json!({"question": "What is 2+2?"});
        let prompt = sig.to_prompt(&input);

        assert!(prompt.contains("Answer a question"));
        assert!(prompt.contains("question"));
        assert!(prompt.contains("What is 2+2?"));
    }
}
