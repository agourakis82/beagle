//! Output parsing utilities

use regex::Regex;
use serde::de::DeserializeOwned;

use crate::error::{SignatureError, SignatureResult};

/// Parser for extracting structured output from LLM responses
pub struct OutputParser;

impl OutputParser {
    /// Parse JSON from a response, handling common formats
    pub fn parse_json<T: DeserializeOwned>(response: &str) -> SignatureResult<T> {
        // Try direct JSON parse first
        if let Ok(value) = serde_json::from_str(response) {
            return Ok(value);
        }

        // Try to extract JSON from markdown code blocks
        if let Some(json_str) = Self::extract_json_block(response) {
            if let Ok(value) = serde_json::from_str(&json_str) {
                return Ok(value);
            }
        }

        // Try to find JSON object in response
        if let Some(json_str) = Self::extract_json_object(response) {
            if let Ok(value) = serde_json::from_str(&json_str) {
                return Ok(value);
            }
        }

        // Try to find JSON array in response
        if let Some(json_str) = Self::extract_json_array(response) {
            if let Ok(value) = serde_json::from_str(&json_str) {
                return Ok(value);
            }
        }

        Err(SignatureError::ParseError(format!(
            "Could not parse JSON from response: {}...",
            &response[..response.len().min(200)]
        )))
    }

    /// Extract JSON from markdown code blocks
    fn extract_json_block(response: &str) -> Option<String> {
        // Match ```json ... ``` or ``` ... ```
        let re = Regex::new(r"```(?:json)?\s*\n?([\s\S]*?)\n?```").ok()?;
        re.captures(response)
            .and_then(|caps| caps.get(1))
            .map(|m| m.as_str().trim().to_string())
    }

    /// Extract JSON object from response
    fn extract_json_object(response: &str) -> Option<String> {
        let mut depth = 0;
        let mut start = None;
        let chars: Vec<char> = response.chars().collect();

        for (i, &c) in chars.iter().enumerate() {
            match c {
                '{' => {
                    if depth == 0 {
                        start = Some(i);
                    }
                    depth += 1;
                }
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        if let Some(s) = start {
                            return Some(response[s..=i].to_string());
                        }
                    }
                }
                _ => {}
            }
        }

        None
    }

    /// Extract JSON array from response
    fn extract_json_array(response: &str) -> Option<String> {
        let mut depth = 0;
        let mut start = None;
        let chars: Vec<char> = response.chars().collect();

        for (i, &c) in chars.iter().enumerate() {
            match c {
                '[' => {
                    if depth == 0 {
                        start = Some(i);
                    }
                    depth += 1;
                }
                ']' => {
                    depth -= 1;
                    if depth == 0 {
                        if let Some(s) = start {
                            return Some(response[s..=i].to_string());
                        }
                    }
                }
                _ => {}
            }
        }

        None
    }

    /// Parse key-value pairs from a response
    pub fn parse_key_value(
        response: &str,
    ) -> SignatureResult<std::collections::HashMap<String, String>> {
        let mut result = std::collections::HashMap::new();

        // Match patterns like "Key: Value" or "**Key**: Value"
        let re = Regex::new(r"(?m)^\*?\*?([A-Za-z_][A-Za-z0-9_]*)\*?\*?:\s*(.+)$")
            .map_err(|e| SignatureError::ParseError(e.to_string()))?;

        for cap in re.captures_iter(response) {
            let key = cap
                .get(1)
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();
            let value = cap
                .get(2)
                .map(|m| m.as_str().trim().to_string())
                .unwrap_or_default();
            result.insert(key, value);
        }

        if result.is_empty() {
            return Err(SignatureError::ParseError(
                "No key-value pairs found in response".to_string(),
            ));
        }

        Ok(result)
    }

    /// Parse a numbered list from response
    pub fn parse_numbered_list(response: &str) -> Vec<String> {
        let re = Regex::new(r"(?m)^\d+\.\s*(.+)$").unwrap();
        re.captures_iter(response)
            .filter_map(|cap| cap.get(1).map(|m| m.as_str().trim().to_string()))
            .collect()
    }

    /// Parse a bulleted list from response
    pub fn parse_bulleted_list(response: &str) -> Vec<String> {
        let re = Regex::new(r"(?m)^[-*•]\s*(.+)$").unwrap();
        re.captures_iter(response)
            .filter_map(|cap| cap.get(1).map(|m| m.as_str().trim().to_string()))
            .collect()
    }

    /// Extract sections by headers
    pub fn parse_sections(response: &str) -> std::collections::HashMap<String, String> {
        let mut sections = std::collections::HashMap::new();
        let re = Regex::new(r"(?m)^#+\s*(.+)$").unwrap();

        let headers: Vec<(usize, String)> = re
            .captures_iter(response)
            .filter_map(|cap| {
                let full_match = cap.get(0)?;
                let header = cap.get(1)?.as_str().trim().to_string();
                Some((full_match.start(), header))
            })
            .collect();

        for (i, (start, header)) in headers.iter().enumerate() {
            let content_start = response[*start..]
                .find('\n')
                .map(|p| start + p + 1)
                .unwrap_or(*start);
            let content_end = headers
                .get(i + 1)
                .map(|(s, _)| *s)
                .unwrap_or(response.len());
            let content = response[content_start..content_end].trim().to_string();
            sections.insert(header.clone(), content);
        }

        sections
    }

    /// Extract score from response (looks for patterns like "Score: 0.85")
    pub fn extract_score(response: &str) -> Option<f32> {
        let re = Regex::new(r"(?i)score[:\s]+([0-9]+\.?[0-9]*)").ok()?;
        re.captures(response)
            .and_then(|caps| caps.get(1))
            .and_then(|m| m.as_str().parse().ok())
    }

    /// Extract confidence from response
    pub fn extract_confidence(response: &str) -> Option<f32> {
        let re = Regex::new(r"(?i)confidence[:\s]+([0-9]+\.?[0-9]*)").ok()?;
        re.captures(response)
            .and_then(|caps| caps.get(1))
            .and_then(|m| m.as_str().parse().ok())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Debug, Deserialize, PartialEq)]
    struct TestOutput {
        answer: String,
        confidence: f32,
    }

    #[test]
    fn test_parse_direct_json() {
        let response = r#"{"answer": "42", "confidence": 0.95}"#;
        let output: TestOutput = OutputParser::parse_json(response).unwrap();
        assert_eq!(output.answer, "42");
        assert_eq!(output.confidence, 0.95);
    }

    #[test]
    fn test_parse_json_from_code_block() {
        let response = r#"
Here's my answer:

```json
{"answer": "42", "confidence": 0.95}
```

Hope that helps!
"#;
        let output: TestOutput = OutputParser::parse_json(response).unwrap();
        assert_eq!(output.answer, "42");
    }

    #[test]
    fn test_parse_json_embedded() {
        let response = r#"
Based on my analysis, the result is:

{"answer": "The meaning of life", "confidence": 0.99}

This is derived from...
"#;
        let output: TestOutput = OutputParser::parse_json(response).unwrap();
        assert_eq!(output.answer, "The meaning of life");
    }

    #[test]
    fn test_parse_key_value() {
        let response = r#"
**Summary**: This is a test
Score: 0.85
Confidence: high
"#;
        let kv = OutputParser::parse_key_value(response).unwrap();
        assert_eq!(kv.get("Summary").unwrap(), "This is a test");
        assert_eq!(kv.get("Score").unwrap(), "0.85");
    }

    #[test]
    fn test_parse_numbered_list() {
        let response = r#"
1. First item
2. Second item
3. Third item
"#;
        let items = OutputParser::parse_numbered_list(response);
        assert_eq!(items.len(), 3);
        assert_eq!(items[0], "First item");
    }

    #[test]
    fn test_parse_sections() {
        let response = r#"
# Strengths
The document is well written.

## Weaknesses
Some citations are missing.

# Suggestions
Add more references.
"#;
        let sections = OutputParser::parse_sections(response);
        assert!(sections.contains_key("Strengths"));
        assert!(sections.get("Strengths").unwrap().contains("well written"));
    }

    #[test]
    fn test_extract_score() {
        assert_eq!(OutputParser::extract_score("Score: 0.85"), Some(0.85));
        assert_eq!(OutputParser::extract_score("The score is 0.9"), Some(0.9));
        assert_eq!(OutputParser::extract_score("no score here"), None);
    }
}
