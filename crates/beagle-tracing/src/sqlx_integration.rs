// SQLx integration for database query tracing
//
// References:
// - OpenTelemetry Database Semantic Conventions
// - SQLx instrumentation best practices

use crate::create_db_span;
use sqlx::{Database, Decode, Encode, Type};
use std::time::Instant;
use tracing::Instrument;

// ========================= SQLx Query Tracing =========================

pub trait TracedQuery {
    async fn execute_traced<'q, DB>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<DB::QueryResult, sqlx::Error>
    where
        DB: Database,
        Self: Sized + sqlx::Execute<'q, DB>;

    async fn fetch_all_traced<'q, DB, T>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<Vec<T>, sqlx::Error>
    where
        DB: Database,
        T: for<'r> sqlx::FromRow<'r, DB::Row>,
        Self: Sized + sqlx::Execute<'q, DB>;

    async fn fetch_one_traced<'q, DB, T>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<T, sqlx::Error>
    where
        DB: Database,
        T: for<'r> sqlx::FromRow<'r, DB::Row>,
        Self: Sized + sqlx::Execute<'q, DB>;

    async fn fetch_optional_traced<'q, DB, T>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<Option<T>, sqlx::Error>
    where
        DB: Database,
        T: for<'r> sqlx::FromRow<'r, DB::Row>,
        Self: Sized + sqlx::Execute<'q, DB>;
}

impl<'q> TracedQuery for sqlx::query::Query<'q, sqlx::Postgres, sqlx::postgres::PgArguments> {
    async fn execute_traced<'a, DB>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<DB::QueryResult, sqlx::Error>
    where
        DB: Database,
        Self: Sized + sqlx::Execute<'a, DB>,
    {
        let sql = self.sql();
        let span = create_db_span("execute", sql);
        let start = Instant::now();

        async {
            let result = self.execute(pool).await;

            let duration = start.elapsed();
            span.record("db.duration_ms", duration.as_millis() as i64);

            match &result {
                Ok(query_result) => {
                    span.record("db.rows_affected", query_result.rows_affected() as i64);
                    span.record("otel.status_code", "OK");
                }
                Err(e) => {
                    span.record("error", true);
                    span.record("error.message", &format!("{}", e));
                    span.record("otel.status_code", "ERROR");
                }
            }

            result
        }
        .instrument(span)
        .await
    }

    async fn fetch_all_traced<'a, DB, T>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<Vec<T>, sqlx::Error>
    where
        DB: Database,
        T: for<'r> sqlx::FromRow<'r, DB::Row>,
        Self: Sized + sqlx::Execute<'a, DB>,
    {
        let sql = self.sql();
        let span = create_db_span("fetch_all", sql);
        let start = Instant::now();

        async {
            let result = self.fetch_all(pool).await;

            let duration = start.elapsed();
            span.record("db.duration_ms", duration.as_millis() as i64);

            match &result {
                Ok(rows) => {
                    span.record("db.row_count", rows.len() as i64);
                    span.record("otel.status_code", "OK");
                }
                Err(e) => {
                    span.record("error", true);
                    span.record("error.message", &format!("{}", e));
                    span.record("otel.status_code", "ERROR");
                }
            }

            result
        }
        .instrument(span)
        .await
    }

    async fn fetch_one_traced<'a, DB, T>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<T, sqlx::Error>
    where
        DB: Database,
        T: for<'r> sqlx::FromRow<'r, DB::Row>,
        Self: Sized + sqlx::Execute<'a, DB>,
    {
        let sql = self.sql();
        let span = create_db_span("fetch_one", sql);
        let start = Instant::now();

        async {
            let result = self.fetch_one(pool).await;

            let duration = start.elapsed();
            span.record("db.duration_ms", duration.as_millis() as i64);

            match &result {
                Ok(_) => {
                    span.record("db.row_count", 1);
                    span.record("otel.status_code", "OK");
                }
                Err(e) => {
                    span.record("error", true);
                    span.record("error.message", &format!("{}", e));
                    span.record("otel.status_code", "ERROR");
                }
            }

            result
        }
        .instrument(span)
        .await
    }

    async fn fetch_optional_traced<'a, DB, T>(
        self,
        pool: &sqlx::Pool<DB>,
    ) -> Result<Option<T>, sqlx::Error>
    where
        DB: Database,
        T: for<'r> sqlx::FromRow<'r, DB::Row>,
        Self: Sized + sqlx::Execute<'a, DB>,
    {
        let sql = self.sql();
        let span = create_db_span("fetch_optional", sql);
        let start = Instant::now();

        async {
            let result = self.fetch_optional(pool).await;

            let duration = start.elapsed();
            span.record("db.duration_ms", duration.as_millis() as i64);

            match &result {
                Ok(Some(_)) => {
                    span.record("db.row_count", 1);
                    span.record("otel.status_code", "OK");
                }
                Ok(None) => {
                    span.record("db.row_count", 0);
                    span.record("otel.status_code", "OK");
                }
                Err(e) => {
                    span.record("error", true);
                    span.record("error.message", &format!("{}", e));
                    span.record("otel.status_code", "ERROR");
                }
            }

            result
        }
        .instrument(span)
        .await
    }
}

// ========================= Transaction Tracing =========================

pub async fn trace_transaction<'a, F, R>(
    pool: &sqlx::Pool<sqlx::Postgres>,
    operation_name: &str,
    func: F,
) -> Result<R, sqlx::Error>
where
    F: FnOnce(&mut sqlx::Transaction<'a, sqlx::Postgres>) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<R, sqlx::Error>> + Send + 'a>>,
{
    let span = tracing::info_span!(
        "database_transaction",
        otel.name = %format!("db:transaction:{}", operation_name),
        otel.kind = ?opentelemetry::trace::SpanKind::Client,
        db.operation = "transaction",
        db.transaction.name = %operation_name,
        db.system = "postgresql",
    );

    let start = Instant::now();

    async {
        let mut tx = pool.begin().await?;

        match func(&mut tx).await {
            Ok(result) => {
                tx.commit().await?;

                let duration = start.elapsed();
                span.record("db.duration_ms", duration.as_millis() as i64);
                span.record("db.transaction.status", "committed");
                span.record("otel.status_code", "OK");

                Ok(result)
            }
            Err(e) => {
                tx.rollback().await?;

                let duration = start.elapsed();
                span.record("db.duration_ms", duration.as_millis() as i64);
                span.record("db.transaction.status", "rolled_back");
                span.record("error", true);
                span.record("error.message", &format!("{}", e));
                span.record("otel.status_code", "ERROR");

                Err(e)
            }
        }
    }
    .instrument(span)
    .await
}

// ========================= Connection Pool Tracing =========================

pub fn trace_pool_metrics(pool: &sqlx::Pool<sqlx::Postgres>) {
    let span = tracing::info_span!(
        "database_pool_metrics",
        otel.name = "db:pool:metrics",
        otel.kind = ?opentelemetry::trace::SpanKind::Internal,
    );

    let _enter = span.enter();

    span.record("db.pool.size", pool.size() as i64);
    span.record("db.pool.idle", pool.num_idle() as i64);
    span.record("db.pool.max_size", pool.max_size() as i64);
    span.record("db.pool.min_idle", pool.min_idle() as i64);

    if pool.is_closed() {
        span.record("db.pool.status", "closed");
    } else {
        span.record("db.pool.status", "open");
    }
}

// ========================= Prepared Statement Tracing =========================

pub async fn trace_prepare<'q>(
    pool: &sqlx::Pool<sqlx::Postgres>,
    query: &'q str,
) -> Result<sqlx::postgres::PgStatement<'q>, sqlx::Error> {
    let span = create_db_span("prepare", query);
    let start = Instant::now();

    async {
        let result = pool.prepare(query).await;

        let duration = start.elapsed();
        span.record("db.duration_ms", duration.as_millis() as i64);

        match &result {
            Ok(_) => {
                span.record("otel.status_code", "OK");
            }
            Err(e) => {
                span.record("error", true);
                span.record("error.message", &format!("{}", e));
                span.record("otel.status_code", "ERROR");
            }
        }

        result
    }
    .instrument(span)
    .await
}

// ========================= Migration Tracing =========================

pub async fn trace_migration(
    pool: &sqlx::Pool<sqlx::Postgres>,
) -> Result<(), sqlx::migrate::MigrateError> {
    let span = tracing::info_span!(
        "database_migration",
        otel.name = "db:migrate",
        otel.kind = ?opentelemetry::trace::SpanKind::Client,
        db.operation = "migrate",
        db.system = "postgresql",
    );

    let start = Instant::now();

    async {
        let result = sqlx::migrate!().run(pool).await;

        let duration = start.elapsed();
        span.record("db.duration_ms", duration.as_millis() as i64);

        match &result {
            Ok(_) => {
                span.record("db.migration.status", "success");
                span.record("otel.status_code", "OK");
            }
            Err(e) => {
                span.record("db.migration.status", "failed");
                span.record("error", true);
                span.record("error.message", &format!("{}", e));
                span.record("otel.status_code", "ERROR");
            }
        }

        result
    }
    .instrument(span)
    .await
}
