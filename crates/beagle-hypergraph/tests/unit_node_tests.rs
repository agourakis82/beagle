mod common;

use beagle_hypergraph::{
    models::{ContentType, Node},
    types::Embedding,
};

use common::init_test_logging;

#[test]
fn test_node_builder_minimal() {
    init_test_logging();

    let node = Node::builder()
        .content("Test content")
        .content_type(ContentType::Thought)
        .device_id("device-1")
        .build()
        .unwrap();

    assert_eq!(node.content, "Test content");
    assert_eq!(node.content_type, ContentType::Thought);
    assert_eq!(node.device_id, "device-1");
    assert!(node.created_at <= chrono::Utc::now());
    assert!(node.updated_at >= node.created_at);
    assert!(node.deleted_at.is_none());
}

#[test]
fn test_node_builder_with_metadata() {
    init_test_logging();

    let metadata = serde_json::json!({
        "priority": 5,
        "tags": ["important", "urgent"],
    });

    let node = Node::builder()
        .content("Test with metadata")
        .content_type(ContentType::Task)
        .metadata(metadata.clone())
        .device_id("device-1")
        .build()
        .unwrap();

    assert_eq!(node.metadata, metadata);
}

#[test]
fn test_node_builder_with_embedding() {
    init_test_logging();

    let embedding = vec![0.1; 1536];

    let node = Node::builder()
        .content("Test with embedding")
        .content_type(ContentType::Context)
        .embedding(embedding.clone())
        .device_id("device-1")
        .build()
        .unwrap();

    let expected = Some(Embedding::from(embedding));
    assert_eq!(node.embedding, expected);
}

#[test]
fn test_node_builder_validation_empty_content() {
    init_test_logging();

    let result = Node::builder()
        .content("")
        .content_type(ContentType::Thought)
        .device_id("device-1")
        .build();

    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("content"));
}

#[test]
fn test_node_builder_validation_long_content() {
    init_test_logging();

    let long_content = "a".repeat(100_001);

    let result = Node::builder()
        .content(long_content)
        .content_type(ContentType::Note)
        .device_id("device-1")
        .build();

    assert!(result.is_err());
}

#[test]
fn test_node_builder_validation_invalid_embedding_dimension() {
    init_test_logging();

    let wrong_embedding = vec![0.1; 512];

    let result = Node::builder()
        .content("Test")
        .content_type(ContentType::Context)
        .embedding(wrong_embedding)
        .device_id("device-1")
        .build();

    assert!(result.is_err());
}

#[test]
fn test_node_builder_default_version() {
    init_test_logging();

    let node = Node::builder()
        .content("Test")
        .content_type(ContentType::Thought)
        .device_id("device-1")
        .build()
        .unwrap();

    assert_eq!(node.version, 0);
}

#[test]
fn test_node_unique_ids() {
    init_test_logging();

    let node1 = Node::builder()
        .content("Node 1")
        .content_type(ContentType::Thought)
        .device_id("device-1")
        .build()
        .unwrap();

    let node2 = Node::builder()
        .content("Node 2")
        .content_type(ContentType::Thought)
        .device_id("device-1")
        .build()
        .unwrap();

    assert_ne!(node1.id, node2.id);
}

#[test]
fn test_node_serialization_roundtrip() {
    init_test_logging();

    let node = Node::builder()
        .content("Serialization test")
        .content_type(ContentType::Memory)
        .metadata(serde_json::json!({"key": "value"}))
        .device_id("device-1")
        .build()
        .unwrap();

    let json = serde_json::to_string(&node).unwrap();
    let deserialized: Node = serde_json::from_str(&json).unwrap();

    assert_eq!(node.id, deserialized.id);
    assert_eq!(node.content, deserialized.content);
    assert_eq!(node.content_type, deserialized.content_type);
}

#[test]
fn test_content_type_serialization() {
    init_test_logging();

    let types = vec![
        ContentType::Thought,
        ContentType::Memory,
        ContentType::Task,
        ContentType::Note,
        ContentType::Context,
    ];

    for content_type in types {
        let json = serde_json::to_string(&content_type).unwrap();
        let deserialized: ContentType = serde_json::from_str(&json).unwrap();
        assert_eq!(content_type, deserialized);
    }
}
