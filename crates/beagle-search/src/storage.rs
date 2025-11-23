//! Paper storage in Neo4j graph database
//!
//! Provides functions to store search results as knowledge graph:
//! - Papers as nodes with metadata
//! - Authors as nodes linked to papers
//! - Citations as relationships between papers
//! - Categories/topics as nodes

use crate::types::{Author, Paper};
use serde_json::json;
use std::collections::HashMap;

/// Neo4j Cypher queries for paper storage

/// Store a paper in Neo4j graph
///
/// Creates:
/// - Paper node with properties (id, title, abstract, etc.)
/// - Author nodes (if not exist) and AUTHORED relationships
/// - Category nodes and BELONGS_TO relationships
///
/// Returns the Neo4j element ID of the created paper node
pub fn create_paper_query(paper: &Paper) -> (String, HashMap<String, serde_json::Value>) {
    let mut params = HashMap::new();

    // Paper properties
    params.insert("id".to_string(), json!(paper.id));
    params.insert("source".to_string(), json!(paper.source));
    params.insert("title".to_string(), json!(paper.title));
    params.insert("abstract".to_string(), json!(paper.abstract_text));

    if let Some(ref journal) = paper.journal {
        params.insert("journal".to_string(), json!(journal));
    }

    if let Some(ref doi) = paper.doi {
        params.insert("doi".to_string(), json!(doi));
    }

    if let Some(ref url) = paper.url {
        params.insert("url".to_string(), json!(url));
    }

    if let Some(ref pdf_url) = paper.pdf_url {
        params.insert("pdf_url".to_string(), json!(pdf_url));
    }

    if let Some(published) = paper.published_date {
        params.insert("published_date".to_string(), json!(published.to_rfc3339()));
    }

    if let Some(citations) = paper.citation_count {
        params.insert("citation_count".to_string(), json!(citations as i64));
    }

    // Build Cypher query using MERGE to avoid duplicates
    let cypher = format!(
        r#"
        MERGE (p:Paper {{id: $id, source: $source}})
        ON CREATE SET
            p.title = $title,
            p.abstract = $abstract,
            p.journal = $journal,
            p.doi = $doi,
            p.url = $url,
            p.pdf_url = $pdf_url,
            p.published_date = $published_date,
            p.citation_count = $citation_count,
            p.created_at = datetime(),
            p.indexed_at = datetime()
        ON MATCH SET
            p.indexed_at = datetime()
        RETURN elementId(p) as id
        "#
    );

    (cypher, params)
}

/// Create author nodes and link to paper
///
/// For each author:
/// - MERGE author node (by last_name + first_name)
/// - CREATE AUTHORED relationship to paper
pub fn create_authors_query(
    paper_id: &str,
    authors: &[Author],
) -> Vec<(String, HashMap<String, serde_json::Value>)> {
    let mut queries = Vec::new();

    for (idx, author) in authors.iter().enumerate() {
        let mut params = HashMap::new();
        params.insert("paper_id".to_string(), json!(paper_id));
        params.insert("last_name".to_string(), json!(author.last_name));
        params.insert("position".to_string(), json!(idx as i64));

        if let Some(ref first) = author.first_name {
            params.insert("first_name".to_string(), json!(first));
        }

        if let Some(ref initials) = author.initials {
            params.insert("initials".to_string(), json!(initials));
        }

        if let Some(ref affiliation) = author.affiliation {
            params.insert("affiliation".to_string(), json!(affiliation));
        }

        let cypher = r#"
            MATCH (p:Paper {id: $paper_id})
            MERGE (a:Author {last_name: $last_name, first_name: $first_name})
            ON CREATE SET
                a.initials = $initials,
                a.affiliation = $affiliation
            MERGE (a)-[r:AUTHORED {position: $position}]->(p)
            RETURN elementId(a) as id
        "#
        .to_string();

        queries.push((cypher, params));
    }

    queries
}

/// Create category nodes and link to paper
///
/// For each category (e.g., "cs.AI", "q-bio.QM"):
/// - MERGE category node
/// - CREATE BELONGS_TO relationship
pub fn create_categories_query(
    paper_id: &str,
    categories: &[String],
) -> Vec<(String, HashMap<String, serde_json::Value>)> {
    let mut queries = Vec::new();

    for category in categories {
        let mut params = HashMap::new();
        params.insert("paper_id".to_string(), json!(paper_id));
        params.insert("category".to_string(), json!(category));

        // Parse category hierarchy (e.g., "cs.AI" -> domain: "cs", subdomain: "AI")
        let parts: Vec<&str> = category.split('.').collect();
        if let Some(domain) = parts.first() {
            params.insert("domain".to_string(), json!(domain));
            if let Some(subdomain) = parts.get(1) {
                params.insert("subdomain".to_string(), json!(subdomain));
            }
        }

        let cypher = r#"
            MATCH (p:Paper {id: $paper_id})
            MERGE (c:Category {name: $category})
            ON CREATE SET
                c.domain = $domain,
                c.subdomain = $subdomain
            MERGE (p)-[:BELONGS_TO]->(c)
            RETURN elementId(c) as id
        "#
        .to_string();

        queries.push((cypher, params));
    }

    queries
}

/// Create citation relationship between papers
///
/// Creates: (citing_paper)-[:CITES]->(cited_paper)
pub fn create_citation_query(
    citing_paper_id: &str,
    cited_paper_id: &str,
) -> (String, HashMap<String, serde_json::Value>) {
    let mut params = HashMap::new();
    params.insert("citing_id".to_string(), json!(citing_paper_id));
    params.insert("cited_id".to_string(), json!(cited_paper_id));

    let cypher = r#"
        MATCH (citing:Paper {id: $citing_id})
        MATCH (cited:Paper {id: $cited_id})
        MERGE (citing)-[r:CITES]->(cited)
        ON CREATE SET r.created_at = datetime()
        RETURN elementId(r) as id
    "#
    .to_string();

    (cypher, params)
}

/// Search papers in Neo4j by keyword
///
/// Full-text search across title and abstract
pub fn search_papers_query(
    keyword: &str,
    limit: usize,
) -> (String, HashMap<String, serde_json::Value>) {
    let mut params = HashMap::new();
    params.insert("keyword".to_string(), json!(keyword.to_lowercase()));
    params.insert("limit".to_string(), json!(limit as i64));

    let cypher = r#"
        MATCH (p:Paper)
        WHERE toLower(p.title) CONTAINS $keyword
           OR toLower(p.abstract) CONTAINS $keyword
        RETURN p.id as id,
               p.source as source,
               p.title as title,
               p.abstract as abstract,
               p.published_date as published_date,
               p.citation_count as citation_count
        ORDER BY p.citation_count DESC, p.published_date DESC
        LIMIT $limit
    "#
    .to_string();

    (cypher, params)
}

/// Find related papers via authors (co-authorship network)
pub fn find_related_by_authors_query(
    paper_id: &str,
    depth: usize,
    limit: usize,
) -> (String, HashMap<String, serde_json::Value>) {
    let mut params = HashMap::new();
    params.insert("paper_id".to_string(), json!(paper_id));
    params.insert("depth".to_string(), json!(depth as i64));
    params.insert("limit".to_string(), json!(limit as i64));

    let cypher = format!(
        r#"
        MATCH (p:Paper {{id: $paper_id}})<-[:AUTHORED]-(a:Author)
        MATCH (a)-[:AUTHORED]->(related:Paper)
        WHERE related.id <> $paper_id
        RETURN DISTINCT related.id as id,
                        related.title as title,
                        related.source as source,
                        count(a) as shared_authors
        ORDER BY shared_authors DESC
        LIMIT $limit
        "#
    );

    (cypher, params)
}

/// Find related papers via categories
pub fn find_related_by_category_query(
    paper_id: &str,
    limit: usize,
) -> (String, HashMap<String, serde_json::Value>) {
    let mut params = HashMap::new();
    params.insert("paper_id".to_string(), json!(paper_id));
    params.insert("limit".to_string(), json!(limit as i64));

    let cypher = r#"
        MATCH (p:Paper {id: $paper_id})-[:BELONGS_TO]->(c:Category)
        MATCH (related:Paper)-[:BELONGS_TO]->(c)
        WHERE related.id <> $paper_id
        RETURN DISTINCT related.id as id,
                        related.title as title,
                        related.source as source,
                        count(c) as shared_categories
        ORDER BY shared_categories DESC, related.citation_count DESC
        LIMIT $limit
    "#
    .to_string();

    (cypher, params)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn test_create_paper_query() {
        let mut paper = Paper::new(
            "12345".to_string(),
            "pubmed".to_string(),
            "Test Paper".to_string(),
        );
        paper.abstract_text = "This is a test abstract".to_string();
        paper.doi = Some("10.1234/test".to_string());

        let (cypher, params) = create_paper_query(&paper);

        assert!(cypher.contains("MERGE (p:Paper"));
        assert_eq!(params.get("id").unwrap(), &json!("12345"));
        assert_eq!(params.get("source").unwrap(), &json!("pubmed"));
        assert_eq!(params.get("title").unwrap(), &json!("Test Paper"));
    }

    #[test]
    fn test_create_authors_query() {
        let authors = vec![
            Author {
                first_name: Some("John".to_string()),
                last_name: "Doe".to_string(),
                initials: Some("J.D.".to_string()),
                affiliation: None,
            },
            Author {
                first_name: Some("Jane".to_string()),
                last_name: "Smith".to_string(),
                initials: None,
                affiliation: Some("MIT".to_string()),
            },
        ];

        let queries = create_authors_query("12345", &authors);

        assert_eq!(queries.len(), 2);
        assert!(queries[0].0.contains("MERGE (a:Author"));
        assert!(queries[0].0.contains("AUTHORED"));
    }

    #[test]
    fn test_search_papers_query() {
        let (cypher, params) = search_papers_query("quantum", 10);

        assert!(cypher.contains("WHERE toLower(p.title) CONTAINS"));
        assert_eq!(params.get("keyword").unwrap(), &json!("quantum"));
        assert_eq!(params.get("limit").unwrap(), &json!(10));
    }
}
