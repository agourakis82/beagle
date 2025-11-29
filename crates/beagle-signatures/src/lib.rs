//! BEAGLE Signatures - DSPy-inspired Typed Prompt Contracts
//!
//! This crate provides a framework for defining typed prompt signatures
//! and prompt optimization, inspired by Stanford's DSPy framework.
//!
//! # Key Concepts
//!
//! - **Signature**: Typed contract defining input/output for a prompt
//! - **Module**: Wrapper that applies prompt techniques (ChainOfThought, ReAct)
//! - **Optimizer**: Auto-tuning for prompt improvement based on metrics
//!
//! # Example
//!
//! ```rust,ignore
//! use beagle_signatures::{Signature, ChainOfThought};
//!
//! #[derive(Signature)]
//! struct SummarizeSignature {
//!     #[input(desc = "Document to summarize")]
//!     document: String,
//!     #[output(desc = "Concise summary")]
//!     summary: String,
//! }
//!
//! let module = ChainOfThought::new(SummarizeSignature::default());
//! let output = module.execute(&ctx, &input).await?;
//! ```

pub mod error;
pub mod module;
pub mod parser;
pub mod signature;

#[cfg(feature = "optimizer")]
pub mod optimizer;

#[cfg(feature = "triad")]
pub mod triad;

// Re-exports
pub use error::{SignatureError, SignatureResult};
pub use module::{ChainOfThought, ModuleConfig, Predict, PromptModule};
pub use parser::OutputParser;
pub use signature::{FieldDescriptor, InputField, OutputField, PromptSignature, SignatureMetadata};

/// Prelude for convenient imports
pub mod prelude {
    pub use crate::error::{SignatureError, SignatureResult};
    pub use crate::module::{ChainOfThought, ModuleConfig, Predict, PromptModule};
    pub use crate::parser::OutputParser;
    pub use crate::signature::{
        FieldDescriptor, InputField, OutputField, PromptSignature, SignatureMetadata,
    };

    #[cfg(feature = "optimizer")]
    pub use crate::optimizer::{ExecutionTrace, OptimizationResult, PromptOptimizer};

    #[cfg(feature = "triad")]
    pub use crate::triad::{ArgosSignature, AthenaSignature, HermesSignature, JudgeSignature};
}
