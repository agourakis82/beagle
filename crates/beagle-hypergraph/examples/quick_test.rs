//! Quick test example for validating Beagle setup
//!
//! Run with: `cargo run --example quick_test`
//!
//! Prerequisites:
//! - Docker Compose running (`docker compose up -d`)
//! - PostgreSQL healthy on `localhost:5432`

use beagle_hypergraph::prelude::*;
use chrono::Utc;

#[tokio::main]
async fn main() -> Result<()> {
    println!("�� Beagle Quick Test");
    println!("===================\n");

    // 1. Connect to database
    println!("1. Connecting to PostgreSQL...");
    let database_url = "postgresql://beagle_user:beagle_dev_password_CHANGE_IN_PRODUCTION@localhost:5432/beagle_dev";

    let storage = PostgresStorage::new(database_url).await.map_err(|e| {
        eprintln!("   ✗ Connection failed: {e}");
        e
    })?;
    println!("   ✓ Connected!");

    // 2. Create Hypergraph
    let hypergraph = Hypergraph::new(storage);

    // 3. Create test node
    println!("\n2. Creating test node...");
    let node = hypergraph
        .create_node(
            "This is a test thought from MacBook Pro M3 Max!".into(),
            ContentType::Thought,
            serde_json::json!({
                "test": true,
                "device": "macbook-m3-max",
                "timestamp": Utc::now().to_rfc3339()
            }),
            "quick-test-device",
        )
        .await?;
    println!("   ✓ Created node: {}", node.id);
    println!("   Content: {}", node.content);

    // 4. Retrieve node
    println!("\n3. Retrieving node...");
    let retrieved = hypergraph.get_node(node.id).await?;
    println!("   ✓ Retrieved: {}", retrieved.content);
    assert_eq!(retrieved.id, node.id);

    // 5. Create another node and hyperedge
    println!("\n4. Creating hyperedge...");
    let node2 = hypergraph
        .create_node(
            "Related memory".into(),
            ContentType::Memory,
            serde_json::json!({}),
            "quick-test-device",
        )
        .await?;

    let edge = hypergraph
        .create_hyperedge(
            vec![node.id, node2.id],
            "relates".into(),
            "quick-test-device",
            false,
            serde_json::json!({}),
        )
        .await?;
    println!("   ✓ Created hyperedge: {}", edge.id);
    println!("   Connecting {} nodes", edge.node_ids.len());

    // 6. Query neighborhood
    println!("\n5. Querying neighborhood (depth=1)...");
    let neighbors = hypergraph.explore(node.id, 1).await?;
    println!("   ✓ Found {} nodes in neighborhood", neighbors.len());
    for (n, dist) in neighbors.iter() {
        let snippet: String = n.content.chars().take(50).collect();
        println!("     - Distance {dist}: {snippet}");
    }

    // 7. Health check (implicit through previous operations)
    println!("\n6. Database health check...");
    println!("   ✓ Health check passed!");

    // Success summary
    println!("\n✅ All tests passed! Beagle setup is working correctly.");
    println!("\nNext steps:");
    println!("  - Review code in beagle-hypergraph/src/");
    println!("  - Run full test suite: cargo test");
    println!("  - Start implementing Week 1 Sprint 1 features");

    Ok(())
}
