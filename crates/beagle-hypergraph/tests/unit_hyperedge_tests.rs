mod common;

use beagle_hypergraph::models::Hyperedge;
use uuid::Uuid;

use common::init_test_logging;

fn hyperedge(edge_type: &str, node_ids: Vec<Uuid>) -> Hyperedge {
    Hyperedge::new(
        edge_type.to_string(),
        node_ids,
        false,
        "device-1".to_string(),
    )
    .expect("hyperedge inválido em teste")
}

#[test]
fn test_hyperedge_creation() {
    init_test_logging();

    let node_ids = vec![Uuid::new_v4(), Uuid::new_v4()];
    let edge = hyperedge("connects", node_ids.clone());

    assert_eq!(edge.edge_type, "connects");
    assert_eq!(edge.node_ids, node_ids);
    assert!(!edge.directed);
}

#[test]
fn test_hyperedge_add_node() {
    init_test_logging();

    let mut edge = hyperedge("test", vec![Uuid::new_v4(), Uuid::new_v4()]);

    let new_node = Uuid::new_v4();
    let added = edge.add_node(new_node);

    assert!(added);
    assert_eq!(edge.node_count(), 3);
    assert!(edge.contains_node(new_node));
}

#[test]
fn test_hyperedge_add_duplicate_node() {
    init_test_logging();

    let node_id = Uuid::new_v4();
    let mut edge = hyperedge("test", vec![node_id, Uuid::new_v4()]);

    let added = edge.add_node(node_id);

    assert!(!added);
    assert_eq!(edge.node_count(), 2);
}

#[test]
fn test_hyperedge_remove_node() {
    init_test_logging();

    let node_id = Uuid::new_v4();
    let mut edge = hyperedge("test", vec![node_id, Uuid::new_v4(), Uuid::new_v4()]);

    let removed = edge.remove_node(node_id).expect("remoção deve ocorrer");

    assert!(removed);
    assert_eq!(edge.node_count(), 2);
    assert!(!edge.contains_node(node_id));
}

#[test]
fn test_hyperedge_intersection() {
    init_test_logging();

    let shared1 = Uuid::new_v4();
    let shared2 = Uuid::new_v4();
    let unique1 = Uuid::new_v4();
    let unique2 = Uuid::new_v4();

    let edge1 = hyperedge("e1", vec![shared1, shared2, unique1]);
    let edge2 = hyperedge("e2", vec![shared1, shared2, unique2]);

    let intersection = edge1.intersection(&edge2);

    assert_eq!(intersection.len(), 2);
    assert!(intersection.contains(&shared1));
    assert!(intersection.contains(&shared2));
}

#[test]
fn test_hyperedge_union() {
    init_test_logging();

    let node1 = Uuid::new_v4();
    let node2 = Uuid::new_v4();
    let node3 = Uuid::new_v4();

    let edge1 = hyperedge("e1", vec![node1, node2]);
    let edge2 = hyperedge("e2", vec![node2, node3]);

    let union = edge1.union(&edge2);

    assert_eq!(union.len(), 3);
    assert!(union.contains(&node1));
    assert!(union.contains(&node2));
    assert!(union.contains(&node3));
}

#[test]
fn test_hyperedge_difference() {
    init_test_logging();

    let shared = Uuid::new_v4();
    let unique1 = Uuid::new_v4();
    let unique2 = Uuid::new_v4();

    let edge1 = hyperedge("e1", vec![shared, unique1]);
    let edge2 = hyperedge("e2", vec![shared, unique2]);

    let difference = edge1.difference(&edge2);

    assert_eq!(difference.len(), 1);
    assert!(difference.contains(&unique1));
    assert!(!difference.contains(&shared));
}

#[test]
fn test_hyperedge_serialization() {
    init_test_logging();

    let edge = hyperedge("test-edge", vec![Uuid::new_v4(), Uuid::new_v4()]);

    let json = serde_json::to_string(&edge).unwrap();
    let deserialized: Hyperedge = serde_json::from_str(&json).unwrap();

    assert_eq!(edge.id, deserialized.id);
    assert_eq!(edge.edge_type, deserialized.edge_type);
    assert_eq!(edge.node_ids, deserialized.node_ids);
    assert_eq!(edge.directed, deserialized.directed);
}
