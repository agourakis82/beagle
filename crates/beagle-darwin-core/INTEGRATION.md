# Integração do Darwin Core no beagle-server

## Opção 1: Integração Direta (Recomendado)

Adicione no `crates/beagle-server/src/main.rs`:

```rust
use beagle_darwin_core::darwin_routes;

// No seu Router principal:
let app = Router::new()
    .merge(api::routes::health_routes())
    .merge(api::routes::node_routes())
    // ... outras rotas ...
    .merge(darwin_routes())  // ← Adicione esta linha
    .with_state(state);
```

## Opção 2: Via módulo de rotas

Crie `crates/beagle-server/src/api/routes/darwin.rs`:

```rust
use axum::Router;
use beagle_darwin_core::darwin_routes;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    // Converte Router vazio para Router<AppState>
    darwin_routes()
}
```

E adicione no `crates/beagle-server/src/api/routes/mod.rs`:

```rust
pub mod darwin;

pub fn darwin_routes() -> Router<AppState> {
    Router::new().merge(darwin::router())
}
```

## Teste a Integração

```bash
# Inicia o servidor
cargo run --package beagle-server

# Testa o endpoint
curl -X POST http://localhost:8080/darwin/rag \
  -H "Content-Type: application/json" \
  -d '{"question": "o que é KEC?"}'
```

## Endpoints Disponíveis

Após integração, os seguintes endpoints estarão disponíveis:

- `POST /darwin/rag` - GraphRAG query
- `POST /darwin/self-rag` - Self-RAG com gatekeeping
- `POST /darwin/plugin` - Plugin system

Todos os endpoints retornam JSON e seguem o padrão do beagle-server.

