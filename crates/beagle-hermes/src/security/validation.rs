//! Input Validation

use anyhow::{bail, Result};
use tracing::warn;

pub struct Validator;

impl Validator {
    /// Validate insight text (prevent injection attacks)
    pub fn validate_insight_text(text: &str) -> Result<()> {
        // Length check
        if text.len() > 10_000 {
            bail!("Insight text too long (max 10,000 characters)");
        }

        if text.is_empty() {
            bail!("Insight text cannot be empty");
        }

        // No SQL injection patterns
        let sql_keywords = [
            "DROP", "DELETE", "UPDATE", "INSERT", "SELECT", "UNION", "EXEC",
        ];
        let text_upper = text.to_uppercase();
        for keyword in sql_keywords {
            if text_upper.contains(&format!(" {} ", keyword))
                || text_upper.starts_with(&format!("{} ", keyword))
                || text_upper.ends_with(&format!(" {}", keyword))
            {
                warn!("Potential SQL injection attempt detected: {}", text);
                // Don't fail, just log (defense in depth)
            }
        }

        // No script injection
        if text.contains("<script") || text.contains("javascript:") {
            bail!("Script injection detected in insight text");
        }

        Ok(())
    }

    /// Validate manuscript title
    pub fn validate_title(title: &str) -> Result<()> {
        if title.len() > 500 {
            bail!("Title too long (max 500 characters)");
        }

        if title.trim().is_empty() {
            bail!("Title cannot be empty");
        }

        // No HTML tags
        if title.contains('<') || title.contains('>') {
            bail!("Title cannot contain HTML tags");
        }

        Ok(())
    }

    /// Validate concept name
    pub fn validate_concept_name(name: &str) -> Result<()> {
        if name.len() > 200 {
            bail!("Concept name too long (max 200 characters)");
        }

        if name.trim().is_empty() {
            bail!("Concept name cannot be empty");
        }

        // Only alphanumeric, spaces, hyphens, underscores
        if !name
            .chars()
            .all(|c| c.is_alphanumeric() || c.is_whitespace() || c == '-' || c == '_')
        {
            bail!("Concept name contains invalid characters");
        }

        Ok(())
    }

    /// Validate UUID format
    pub fn validate_uuid(uuid_str: &str) -> Result<()> {
        uuid::Uuid::parse_str(uuid_str)?;
        Ok(())
    }

    /// Sanitize text for display (remove potentially dangerous content)
    pub fn sanitize_text(text: &str) -> String {
        text.replace("<script", "&lt;script")
            .replace("</script>", "&lt;/script&gt;")
            .replace("javascript:", "")
            .trim()
            .to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_insight_text() {
        // Valid text
        assert!(Validator::validate_insight_text("This is a valid insight.").is_ok());

        // Too long
        let long_text = "a".repeat(10_001);
        assert!(Validator::validate_insight_text(&long_text).is_err());

        // Empty
        assert!(Validator::validate_insight_text("").is_err());

        // Script injection
        assert!(Validator::validate_insight_text("Test <script>alert('xss')</script>").is_err());
    }

    #[test]
    fn test_validate_title() {
        assert!(Validator::validate_title("Valid Title").is_ok());
        assert!(Validator::validate_title("").is_err());

        let long_title = "a".repeat(501);
        assert!(Validator::validate_title(&long_title).is_err());
    }

    #[test]
    fn test_sanitize_text() {
        let malicious = "<script>alert('xss')</script>Hello";
        let sanitized = Validator::sanitize_text(malicious);

        assert!(!sanitized.contains("<script"));
        assert!(sanitized.contains("Hello"));
    }
}
