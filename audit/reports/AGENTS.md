# Repository Guidelines

## Project Structure & Module Organization
- `crates/`: Rust workspace (config/core/memory/llm/observability/hermes/darwin/health) plus tooling in `beagle-bin/` and agents in `crates/beagle-agents/`.
- `apps/beagle-monorepo/`: CLI/runtime entry for the core server; `beagle-mcp-server/`: Node/TypeScript MCP endpoint; `beagle-julia/`: Julia scientific pipelines; `python/`: auxiliary scripts; `protos/`: shared gRPC definitions.
- `docs/` holds architecture/release notes; ops helpers in `scripts/`, `docker/`, and `k8s/`; `tests/` contains integration suites.
- Sample data/config lives under `data/`, `sql/`, and `observability/`; prefer `BEAGLE_DATA_DIR` over hardcoded paths.

## Build, Test, and Development Commands
- Rust: `cargo build --workspace` to compile, `cargo run -p beagle-monorepo --bin core_server` to start the core server.
- MCP server: `cd beagle-mcp-server && npm install && npm run build && MCP_AUTH_TOKEN=... npm start`.
- Make targets: `make fmt`, `make lint`, `make rust-test`, `make julia-test`, `make test`, `make ci-local` (fmt + lint + tests + path check).
- Integration harness: `./run_tests.sh [quick|env|pubmed|arxiv|neo4j|router|e2e|all]` or `cargo test --test v04_integration_tests -- --ignored --nocapture` (needs `.env`; see `tests/README_TESTING.md`).

## Coding Style & Naming Conventions
- Run `cargo fmt --all` and `cargo clippy --all-targets --all-features -- -D warnings` before committing.
- Naming: snake_case for functions/modules, PascalCase for types/traits, SCREAMING_SNAKE_CASE for consts/env vars; avoid cross-crate cycles and keep new crates under `crates/`.
- Use typed config (`beagle-config`, `beagle-core`); never hardcode model names, URLs, or storage paths—read from env/TOML.

## Testing Guidelines
- Default regression: `cargo test --all -- --nocapture`; add `make julia-test` when touching Julia pipelines.
- Integration suites expect services (Neo4j, optional LLM keys). Provide `.env` with `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`, and provider tokens; `run_tests.sh env` validates setup.
- Mirror patterns in `tests/v04_integration_tests.rs`; mark network/LLM-heavy cases with `#[ignore]` and document dependencies near the test.

## Commit & Pull Request Guidelines
- Use Conventional Commit style (`feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`) and state user impact.
- Target `main`; describe motivation, major changes, required config/env, and the commands executed (fmt/lint/tests). Attach screenshots/logs for UX or ops shifts and link issues or relevant `BEAGLE_*` docs.

## Security & Configuration Tips
- Default safety: `BEAGLE_SAFE_MODE=true`, `BEAGLE_PUBLISH_MODE=dry`, `BEAGLE_PROFILE=dev|lab|prod`, and `BEAGLE_DATA_DIR=~/beagle-data` before running services.
- Keep secrets in env or `.env` (gitignored); set `MCP_AUTH_TOKEN` for MCP. Enable feature flags like `otel` only when telemetry endpoints exist.
- Prefer Docker (`docker-compose*.yml`) for reproducible stacks and shut down external services after tests to avoid stale state.
