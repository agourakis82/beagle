use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;

/// Resultado estruturado de `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryPlan {
    pub query: String,
    pub execution_time_ms: f64,
    pub planning_time_ms: f64,
    pub total_cost: f64,
    pub uses_index: bool,
    pub index_name: Option<String>,
    pub rows_estimated: i64,
    pub rows_actual: i64,
}

/// Executa `EXPLAIN ANALYZE` e sintetiza o plano de execução.
pub async fn explain_analyze(pool: &PgPool, query: &str) -> Result<QueryPlan, sqlx::Error> {
    let explain_query = format!("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {}", query);

    let result: Value = sqlx::query_scalar(&explain_query).fetch_one(pool).await?;
    let plan_root = result
        .get(0)
        .and_then(|entry| entry.get("Plan"))
        .cloned()
        .unwrap_or_default();

    let execution_time = result
        .get(0)
        .and_then(|entry| entry.get("Execution Time"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let planning_time = result
        .get(0)
        .and_then(|entry| entry.get("Planning Time"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);

    let (uses_index, index_name) = detect_index_usage(&plan_root);

    Ok(QueryPlan {
        query: query.to_string(),
        execution_time_ms: execution_time,
        planning_time_ms: planning_time,
        total_cost: plan_root
            .get("Total Cost")
            .and_then(Value::as_f64)
            .unwrap_or(0.0),
        uses_index,
        index_name,
        rows_estimated: plan_root
            .get("Plan Rows")
            .and_then(Value::as_i64)
            .unwrap_or_else(|| {
                plan_root
                    .get("Plan Rows")
                    .and_then(Value::as_f64)
                    .map(|v| v as i64)
                    .unwrap_or(0)
            }),
        rows_actual: plan_root
            .get("Actual Rows")
            .and_then(Value::as_i64)
            .unwrap_or_else(|| {
                plan_root
                    .get("Actual Rows")
                    .and_then(Value::as_f64)
                    .map(|v| v as i64)
                    .unwrap_or(0)
            }),
    })
}

fn detect_index_usage(plan: &Value) -> (bool, Option<String>) {
    let node_type = plan
        .get("Node Type")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let index_name = plan
        .get("Index Name")
        .and_then(Value::as_str)
        .map(|s| s.to_string());

    let uses_index = node_type.contains("Index")
        || plan.get("Index Cond").is_some()
        || plan
            .get("Recheck Cond")
            .and_then(Value::as_str)
            .map(|cond| cond.contains("index"))
            .unwrap_or(false);

    if uses_index {
        return (true, index_name);
    }

    if let Some(children) = plan.get("Plans").and_then(Value::as_array) {
        for child in children {
            let (child_uses_index, child_index_name) = detect_index_usage(child);
            if child_uses_index {
                return (true, child_index_name);
            }
        }
    }

    (false, None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_explain_device_query() {
        let database_url =
            std::env::var("DATABASE_URL").expect("DATABASE_URL must be set for integration tests");
        let pool = PgPool::connect(&database_url)
            .await
            .expect("connect to database");

        let query = "SELECT * FROM nodes WHERE device_id = 'test' AND deleted_at IS NULL LIMIT 10";
        let plan = explain_analyze(&pool, query)
            .await
            .expect("explain analyze");

        println!("Query plan: {:?}", plan);

        // Should use idx_nodes_device_active
        assert!(plan.uses_index, "Plano não utilizou índice: {:?}", plan);

        if let Some(index_name) = plan.index_name.clone() {
            assert_eq!(index_name, "idx_nodes_device_active");
        }

        // Execução deve ser sub-50ms em bases otimizadas
        assert!(
            plan.execution_time_ms < 50.0,
            "Execução lenta (>50ms): {:?}",
            plan
        );
    }
}
