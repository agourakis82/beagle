//! BeagleStoreInventory — modernization plan #12 / ADR 0001, Stage 0.
//!
//! Makes the storage landscape HONEST: at startup we resolve and log the role of every
//! backend, so what Beagle *advertises* matches what it *executes*. This is the zero-behavior
//! -change first stage of the canonical-store consolidation (ADR 0001 §5 Stage 0).
//!
//! Roles are grounded in the MEASURED cluster topology (2026-06-08), not the aspirational early
//! ADR draft:
//! - Postgres = system-of-record (nodes/hyperedges + `nodes.embedding` cold-backup column).
//! - Qdrant = rebuildable vector projection (`beagle_exocortex`); `cockpit_rag` is the cockpit plane.
//! - LanceDB `semantic_memory_v1` = canonical exocortex semantic index, but served by the SEPARATE
//!   `beagle-memory-engine` process (multivector ColBERT jina-colbert-v2 + reranker). It is the
//!   live `/api/memory/query` recall path — NOT retired (the early ADR draft was wrong).
//! - Redis = read cache. Neo4j = experimental (no pod).

use beagle_config::BeagleConfig;
use tracing::{info, warn};

/// Default in-cluster URL for the beagle-memory-engine. MUST mirror the `unwrap_or_else` default
/// used in `apps/beagle-monorepo/src/http_exocortex` so the inventory reflects the URL the process
/// ACTUALLY talks to when `BEAGLE_MEMORY_ENGINE_URL` is unset (otherwise the honesty log would say
/// "not configured" while the engine is live on the default — the exact lie this primitive prevents).
pub const DEFAULT_MEMORY_ENGINE_URL: &str =
    "http://beagle-memory-engine.beagle-memory-lab.svc.cluster.local:8090";

/// Role a storage backend plays in the consolidated architecture (ADR 0001 §3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StoreRole {
    /// Canonical system-of-record; the rebuild source for every derived index.
    SystemOfRecord,
    /// Derived, rebuildable vector projection in this process's hot path.
    Projection,
    /// Canonical index served by a SEPARATE process (beagle-memory-engine), not in-process.
    ExternalCanonical,
    /// Derived, ephemeral read cache; never a source of truth.
    Cache,
    /// Implemented but not load-bearing; needs a deploy + eval gate before use.
    Experimental,
    /// Removed from the production runtime; must not be advertised as a capability.
    Retired,
}

impl StoreRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            StoreRole::SystemOfRecord => "system-of-record",
            StoreRole::Projection => "projection",
            StoreRole::ExternalCanonical => "external-canonical",
            StoreRole::Cache => "cache",
            StoreRole::Experimental => "experimental",
            StoreRole::Retired => "retired",
        }
    }
}

/// Resolved status of one storage backend.
#[derive(Debug, Clone)]
pub struct StoreStatus {
    pub name: &'static str,
    pub role: StoreRole,
    /// Whether this backend is configured (has a connection target) in the current process.
    pub configured: bool,
    /// Connection target with any credentials stripped — safe to log.
    pub endpoint: Option<String>,
    pub note: &'static str,
}

/// The resolved inventory of every Beagle storage backend (ADR 0001).
#[derive(Debug, Clone)]
pub struct BeagleStoreInventory {
    pub stores: Vec<StoreStatus>,
}

impl BeagleStoreInventory {
    /// Resolve roles from the active config + environment. Delegates to [`from_parts`] so the
    /// role logic is unit-testable without constructing a full `BeagleConfig`.
    ///
    /// [`from_parts`]: BeagleStoreInventory::from_parts
    pub fn resolve(cfg: &BeagleConfig) -> Self {
        // The memory-engine is reached via the same hardcoded default as http_exocortex when the
        // env var is unset, so it is ALWAYS effectively configured. Reflect that — reporting it
        // "not configured" because the env happens to be unset would be the very lie this guards.
        let memory_engine_url = std::env::var("BEAGLE_MEMORY_ENGINE_URL")
            .unwrap_or_else(|_| DEFAULT_MEMORY_ENGINE_URL.to_string());
        Self::from_parts(
            cfg.hermes.database_url.as_deref(),
            cfg.graph.qdrant_url.as_deref(),
            cfg.hermes.redis_url.as_deref(),
            cfg.graph.neo4j_uri.as_deref(),
            Some(memory_engine_url.as_str()),
        )
    }

    /// Pure role resolution from raw connection targets. `Some(url)` = configured.
    pub fn from_parts(
        database_url: Option<&str>,
        qdrant_url: Option<&str>,
        redis_url: Option<&str>,
        neo4j_uri: Option<&str>,
        memory_engine_url: Option<&str>,
    ) -> Self {
        let stores = vec![
            StoreStatus {
                name: "postgres",
                role: StoreRole::SystemOfRecord,
                configured: database_url.is_some(),
                endpoint: database_url.map(redact_url),
                note: "canonical SoR: nodes/hyperedges + nodes.embedding cold-backup column",
            },
            StoreStatus {
                name: "qdrant",
                role: StoreRole::Projection,
                configured: qdrant_url.is_some(),
                endpoint: qdrant_url.map(redact_url),
                note: "rebuildable vector projection (beagle_exocortex); cockpit_rag = cockpit plane",
            },
            StoreStatus {
                name: "lancedb/memory-engine",
                role: StoreRole::ExternalCanonical,
                configured: memory_engine_url.is_some(),
                endpoint: memory_engine_url.map(redact_url),
                note: "canonical exocortex semantic index (multivector ColBERT + reranker); external service",
            },
            StoreStatus {
                name: "redis",
                role: StoreRole::Cache,
                configured: redis_url.is_some(),
                endpoint: redis_url.map(redact_url),
                note: "hot-node read cache over Postgres; never a source of truth",
            },
            StoreStatus {
                name: "neo4j",
                role: StoreRole::Experimental,
                configured: neo4j_uri.is_some(),
                endpoint: neo4j_uri.map(redact_url),
                note: "not load-bearing; needs pod + eval gate before use (ADR 0001 §2.4)",
            },
        ];
        Self { stores }
    }

    /// Emit one structured line per store at startup so advertising matches execution.
    /// An experimental store that is unexpectedly *configured* is logged at WARN.
    pub fn log(&self) {
        info!("BeagleStoreInventory (ADR 0001) — resolved store roles:");
        for s in &self.stores {
            let ep = s.endpoint.as_deref().unwrap_or("-");
            if s.role == StoreRole::Experimental && s.configured {
                warn!(
                    "  store={} role={} configured={} endpoint={} — {}",
                    s.name,
                    s.role.as_str(),
                    s.configured,
                    ep,
                    s.note
                );
            } else {
                info!(
                    "  store={} role={} configured={} endpoint={} — {}",
                    s.name,
                    s.role.as_str(),
                    s.configured,
                    ep,
                    s.note
                );
            }
        }
    }

    /// The single system-of-record store status (there must be exactly one).
    pub fn system_of_record(&self) -> Option<&StoreStatus> {
        debug_assert_eq!(
            self.stores
                .iter()
                .filter(|s| s.role == StoreRole::SystemOfRecord)
                .count(),
            1,
            "the architecture allows exactly one system-of-record"
        );
        self.stores
            .iter()
            .find(|s| s.role == StoreRole::SystemOfRecord)
    }
}

/// Strip credentials from a URL for safe logging (`scheme://user:pass@host/x` → `scheme://host/x`).
///
/// Userinfo is stripped only from the **authority** component (per RFC 3986), so a `@` that appears
/// later in the path/query is preserved — e.g. `http://host:8090/a@b` stays intact.
fn redact_url(url: &str) -> String {
    match url.split_once("://") {
        Some((scheme, rest)) => {
            // Split authority from the rest at the first '/'.
            let (authority, path) = match rest.split_once('/') {
                Some((a, p)) => (a, Some(p)),
                None => (rest, None),
            };
            // Drop any userinfo (everything up to and including the last '@') from the authority.
            let host = authority
                .rsplit_once('@')
                .map(|(_, h)| h)
                .unwrap_or(authority);
            match path {
                Some(p) => format!("{scheme}://{host}/{p}"),
                None => format!("{scheme}://{host}"),
            }
        }
        None => url.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_canonical_roles() {
        let inv = BeagleStoreInventory::from_parts(
            Some("postgres://u:p@pg.beagle.svc:5432/beagle"),
            Some("http://qdrant.beagle.svc:6333"),
            Some("redis://redis.beagle.svc:6379"),
            None,
            Some("http://beagle-memory-engine.beagle-memory-lab.svc:8090"),
        );
        let sor = inv.system_of_record().expect("exactly one SoR");
        assert_eq!(sor.name, "postgres");
        assert!(sor.configured);

        let qdrant = inv.stores.iter().find(|s| s.name == "qdrant").unwrap();
        assert_eq!(qdrant.role, StoreRole::Projection);
        assert!(qdrant.configured);

        let lance = inv
            .stores
            .iter()
            .find(|s| s.name == "lancedb/memory-engine")
            .unwrap();
        assert_eq!(lance.role, StoreRole::ExternalCanonical);
        assert!(lance.configured, "memory-engine URL present → configured");

        let neo = inv.stores.iter().find(|s| s.name == "neo4j").unwrap();
        assert_eq!(neo.role, StoreRole::Experimental);
        assert!(!neo.configured, "no neo4j uri → not configured");
    }

    #[test]
    fn exactly_one_system_of_record() {
        let inv = BeagleStoreInventory::from_parts(None, None, None, None, None);
        let sors: Vec<_> = inv
            .stores
            .iter()
            .filter(|s| s.role == StoreRole::SystemOfRecord)
            .collect();
        assert_eq!(sors.len(), 1, "the architecture allows exactly one SoR");
    }

    #[test]
    fn redact_url_strips_credentials() {
        assert_eq!(
            redact_url("postgres://user:secret@host:5432/db"),
            "postgres://host:5432/db"
        );
        assert_eq!(redact_url("redis://:pass@cache:6379"), "redis://cache:6379");
        // No credentials → unchanged.
        assert_eq!(
            redact_url("http://qdrant.beagle.svc:6333"),
            "http://qdrant.beagle.svc:6333"
        );
        // No scheme → returned as-is.
        assert_eq!(redact_url("localhost:6333"), "localhost:6333");
        // A '@' in the PATH (not userinfo) must be preserved.
        assert_eq!(
            redact_url("http://host:8090/a@b/c"),
            "http://host:8090/a@b/c"
        );
        // Userinfo containing '@' is still fully stripped, path kept.
        assert_eq!(
            redact_url("postgres://user:p@ss@host:5432/db"),
            "postgres://host:5432/db"
        );
    }

    #[test]
    fn memory_engine_default_keeps_inventory_honest() {
        // With no explicit URL, the process still talks to the engine via the hardcoded default,
        // so the inventory must report it configured (not a silent "unconfigured" lie).
        assert!(!DEFAULT_MEMORY_ENGINE_URL.is_empty());
        let inv = BeagleStoreInventory::from_parts(
            None,
            None,
            None,
            None,
            Some(DEFAULT_MEMORY_ENGINE_URL),
        );
        let lance = inv
            .stores
            .iter()
            .find(|s| s.name == "lancedb/memory-engine")
            .unwrap();
        assert!(lance.configured, "default URL ⇒ effectively configured");
        assert_eq!(lance.role, StoreRole::ExternalCanonical);
    }
}
