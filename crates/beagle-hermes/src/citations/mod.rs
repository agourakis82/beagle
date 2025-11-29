pub mod formatter;
pub mod generator;
pub mod verifier;

pub use formatter::{Citation, CitationFormatter, CitationStyle, CitationType};
pub use generator::{Author, CitationGenerator, Paper};
pub use verifier::{CitationVerifier, VerificationResult};

/// Citation manager for handling citations throughout a document
#[derive(Debug, Clone, Default)]
pub struct CitationManager {
    citations: Vec<Citation>,
}

impl CitationManager {
    pub fn new() -> Self {
        Self {
            citations: Vec::new(),
        }
    }

    pub fn add(&mut self, citation: Citation) {
        self.citations.push(citation);
    }

    pub fn get_all(&self) -> &[Citation] {
        &self.citations
    }

    pub fn clear(&mut self) {
        self.citations.clear();
    }

    pub fn len(&self) -> usize {
        self.citations.len()
    }

    pub fn is_empty(&self) -> bool {
        self.citations.is_empty()
    }
}
