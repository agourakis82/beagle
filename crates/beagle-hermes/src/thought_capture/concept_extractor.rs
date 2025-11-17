//! Concept Extraction using spaCy + Transformers (Python bridge)

use anyhow::{Context, Result};
use pyo3::prelude::*;
use pyo3::types::PyList;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractedConcept {
    pub text: String,
    pub concept_type: ConceptType,
    pub confidence: f64,
    pub embedding: Vec<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ConceptType {
    Entity(String), // ENTITY_PERSON, ENTITY_ORG, etc.
    KeyPhrase,
    TechnicalTerm,
}

pub struct ConceptExtractor {
    // Python GIL handle managed internally
}

impl ConceptExtractor {
    pub fn new() -> Result<Self> {
        Ok(Self {})
    }

    /// Extract concepts from text
    pub fn extract(&self, text: &str) -> Result<Vec<ExtractedConcept>> {
        Python::with_gil(|py| -> Result<Vec<ExtractedConcept>> {
            // Load Python module
            let concept_module = PyModule::from_code(
                py,
                include_str!("../../python/concept_extractor.py"),
                "concept_extractor.py",
                "concept_extractor",
            )
            .context("Failed to load concept_extractor.py")?;

            // Call extract_concepts_json
            let result_list: &PyList = concept_module
                .getattr("extract_concepts_json")?
                .call1((text,))?
                .downcast()
                .map_err(PyErr::from)?;

            // Parse concepts
            let mut concepts = Vec::new();
            for item in result_list.iter() {
                let text: String = item.get_item("text")?.extract()?;
                let type_str: String = item.get_item("type")?.extract()?;
                let confidence: f64 = item.get_item("confidence")?.extract()?;
                let embedding_list: Vec<f64> = item.get_item("embedding")?.extract()?;

                let concept_type = Self::parse_concept_type(&type_str);
                let embedding: Vec<f32> = embedding_list.iter().map(|&x| x as f32).collect();

                concepts.push(ExtractedConcept {
                    text,
                    concept_type,
                    confidence,
                    embedding,
                });
            }

            Ok(concepts)
        })
    }

    fn parse_concept_type(type_str: &str) -> ConceptType {
        if type_str.starts_with("ENTITY_") {
            ConceptType::Entity(type_str.strip_prefix("ENTITY_").unwrap().to_string())
        } else if type_str == "KEYPHRASE" {
            ConceptType::KeyPhrase
        } else {
            ConceptType::TechnicalTerm
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_concept_extraction() {
        let extractor = ConceptExtractor::new().unwrap();

        let text =
            "KEC entropy affects collagen scaffold degradation in neural tissue engineering.";
        let concepts = extractor.extract(text).unwrap();

        assert!(!concepts.is_empty());

        // Should extract at least "KEC entropy", "collagen scaffold", etc.
        let concept_texts: Vec<String> = concepts.iter().map(|c| c.text.clone()).collect();
        println!("Extracted concepts: {:?}", concept_texts);

        assert!(concept_texts
            .iter()
            .any(|t| t.to_lowercase().contains("collagen")));
    }
}
