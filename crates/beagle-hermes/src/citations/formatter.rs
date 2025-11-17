//! Multi-format citation formatting

use crate::error::Result;

// Citation struct used by formatter (simplified from generator's Paper)
#[derive(Debug, Clone)]
pub struct Citation {
    pub title: String,
    pub authors: Vec<String>,
    pub year: Option<u32>,
    pub doi: Option<String>,
    pub url: Option<String>,
    pub abstract_text: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CitationStyle {
    Vancouver,
    APA,
    ABNT,
    Nature,
    Chicago,
}

pub struct CitationFormatter;

impl CitationFormatter {
    /// Format citation in specified style
    pub fn format(&self, citation: &Citation, style: CitationStyle) -> Result<String> {
        match style {
            CitationStyle::Vancouver => self.format_vancouver(citation),
            CitationStyle::APA => self.format_apa(citation),
            CitationStyle::ABNT => self.format_abnt(citation),
            CitationStyle::Nature => self.format_nature(citation),
            CitationStyle::Chicago => self.format_chicago(citation),
        }
    }

    fn format_vancouver(&self, citation: &Citation) -> Result<String> {
        // Vancouver: Author1 A, Author2 B, Author3 C. Title. Journal. Year;Volume(Issue):Pages. doi:DOI
        let authors = self.format_authors_vancouver(&citation.authors);
        let year = citation.year.map(|y| y.to_string()).unwrap_or_else(|| "n.d.".to_string());
        
        let mut formatted = format!("{}. {}.", authors, citation.title);
        
        if let Some(doi) = &citation.doi {
            formatted.push_str(&format!(" doi:{}", doi));
        }
        
        Ok(formatted)
    }

    fn format_apa(&self, citation: &Citation) -> Result<String> {
        // APA: Author, A. A., Author, B. B., & Author, C. C. (Year). Title. Journal, Volume(Issue), Pages. https://doi.org/DOI
        let authors = self.format_authors_apa(&citation.authors);
        let year = citation.year.map(|y| y.to_string()).unwrap_or_else(|| "n.d.".to_string());
        
        let mut formatted = format!("{}. ({})", authors, year);
        formatted.push_str(&format!(" {}.", citation.title));
        
        if let Some(doi) = &citation.doi {
            formatted.push_str(&format!(" https://doi.org/{}", doi));
        } else if let Some(url) = &citation.url {
            formatted.push_str(&format!(" {}", url));
        }
        
        Ok(formatted)
    }

    fn format_abnt(&self, citation: &Citation) -> Result<String> {
        // ABNT: SOBRENOME, Nome. Título. Local: Editora, Ano.
        let authors = self.format_authors_abnt(&citation.authors);
        let year = citation.year.map(|y| y.to_string()).unwrap_or_else(|| "n.d.".to_string());
        
        Ok(format!("{}. {}. {}", authors, citation.title, year))
    }

    fn format_nature(&self, citation: &Citation) -> Result<String> {
        // Nature: Author1, A. B., Author2, C. D. & Author3, E. F. Title. Journal Volume, Pages (Year).
        let authors = self.format_authors_nature(&citation.authors);
        let year = citation.year.map(|y| y.to_string()).unwrap_or_else(|| "n.d.".to_string());
        
        Ok(format!("{}. {}. ({})", authors, citation.title, year))
    }

    fn format_chicago(&self, citation: &Citation) -> Result<String> {
        // Chicago: Author, First Name, and Second Author. "Title." Journal Volume, no. Issue (Year): Pages.
        let authors = self.format_authors_chicago(&citation.authors);
        let year = citation.year.map(|y| y.to_string()).unwrap_or_else(|| "n.d.".to_string());
        
        Ok(format!("{}. \"{}\". ({})", authors, citation.title, year))
    }

    fn format_authors_vancouver(&self, authors: &[String]) -> String {
        if authors.is_empty() {
            return "Unknown".to_string();
        }
        
        authors
            .iter()
            .map(|a| {
                let parts: Vec<&str> = a.split_whitespace().collect();
                if parts.len() >= 2 {
                    format!("{} {}", parts[0], parts[1..].join(" "))
                } else {
                    a.clone()
                }
            })
            .collect::<Vec<_>>()
            .join(", ")
    }

    fn format_authors_apa(&self, authors: &[String]) -> String {
        if authors.is_empty() {
            return "Unknown".to_string();
        }
        
        if authors.len() == 1 {
            return self.format_single_author_apa(&authors[0]);
        }
        
        let formatted: Vec<String> = authors
            .iter()
            .map(|a| self.format_single_author_apa(a))
            .collect();
        
        if formatted.len() == 2 {
            format!("{} & {}", formatted[0], formatted[1])
        } else {
            let last = formatted.last().unwrap().clone();
            let rest = formatted[..formatted.len() - 1].join(", ");
            format!("{}, & {}", rest, last)
        }
    }

    fn format_single_author_apa(&self, author: &str) -> String {
        let parts: Vec<&str> = author.split_whitespace().collect();
        if parts.len() >= 2 {
            let last = parts.last().unwrap();
            let first = parts[0];
            let middle = if parts.len() > 2 {
                parts[1..parts.len() - 1].iter().map(|p| p.chars().next().unwrap_or(' ')).collect::<String>()
            } else {
                String::new()
            };
            format!("{}, {}.{}", last, first.chars().next().unwrap_or(' '), middle)
        } else {
            author.to_string()
        }
    }

    fn format_authors_abnt(&self, authors: &[String]) -> String {
        if authors.is_empty() {
            return "DESCONHECIDO".to_string();
        }
        
        authors
            .iter()
            .map(|a| {
                let parts: Vec<&str> = a.split_whitespace().collect();
                if parts.len() >= 2 {
                    let last = parts.last().unwrap().to_uppercase();
                    let first = parts[0];
                    format!("{}, {}", last, first)
                } else {
                    a.to_uppercase()
                }
            })
            .collect::<Vec<_>>()
            .join("; ")
    }

    fn format_authors_nature(&self, authors: &[String]) -> String {
        if authors.is_empty() {
            return "Unknown".to_string();
        }
        
        if authors.len() == 1 {
            return self.format_single_author_nature(&authors[0]);
        }
        
        let formatted: Vec<String> = authors
            .iter()
            .map(|a| self.format_single_author_nature(a))
            .collect();
        
        if formatted.len() == 2 {
            format!("{} & {}", formatted[0], formatted[1])
        } else {
            let last = formatted.last().unwrap().clone();
            let rest = formatted[..formatted.len() - 1].join(", ");
            format!("{} & {}", rest, last)
        }
    }

    fn format_single_author_nature(&self, author: &str) -> String {
        let parts: Vec<&str> = author.split_whitespace().collect();
        if parts.len() >= 2 {
            let last = parts.last().unwrap();
            let first_initials: String = parts[..parts.len() - 1]
                .iter()
                .map(|p| p.chars().next().unwrap_or(' '))
                .collect();
            format!("{}, {}", last, first_initials)
        } else {
            author.to_string()
        }
    }

    fn format_authors_chicago(&self, authors: &[String]) -> String {
        if authors.is_empty() {
            return "Unknown".to_string();
        }
        
        if authors.len() == 1 {
            return authors[0].clone();
        }
        
        if authors.len() == 2 {
            return format!("{} and {}", authors[0], authors[1]);
        }
        
        let last = authors.last().unwrap().clone();
        let rest = authors[..authors.len() - 1].join(", ");
        format!("{}, and {}", rest, last)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vancouver_formatting() {
        let citation = Citation {
            title: "Test Paper".to_string(),
            authors: vec!["John Doe".to_string(), "Jane Smith".to_string()],
            year: Some(2024),
            doi: Some("10.1234/test".to_string()),
            url: None,
            abstract_text: None,
        };
        
        let formatter = CitationFormatter;
        let formatted = formatter.format(&citation, CitationStyle::Vancouver).unwrap();
        
        assert!(formatted.contains("Test Paper"));
        assert!(formatted.contains("doi:10.1234/test"));
    }

    #[test]
    fn test_apa_formatting() {
        let citation = Citation {
            title: "Test Paper".to_string(),
            authors: vec!["John Doe".to_string()],
            year: Some(2024),
            doi: Some("10.1234/test".to_string()),
            url: None,
            abstract_text: None,
        };
        
        let formatter = CitationFormatter;
        let formatted = formatter.format(&citation, CitationStyle::APA).unwrap();
        
        assert!(formatted.contains("(2024)"));
        assert!(formatted.contains("Test Paper"));
    }
}
