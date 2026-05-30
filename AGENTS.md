# Repository Guidelines

## Project Structure & Module Organization

- `crates/`: Rust workspace crates (core systems like `beagle-llm`, `beagle-memory`, `beagle-exocortex`, `beagle-search`, `beagle-rag-update`).
- `apps/beagle-monorepo/`: Axum core server + pipeline runner binaries.
- `beagle-mcp-server/`: Node/TypeScript MCP server (ChatGPT/Claude connector).
- `beagle-julia/`, `python/`, `sdk/`: Julia pipelines, Python utilities, and SDK experiments.
- `docs/`: Architecture, release notes, MCP integration guides.
- `tests/`: Workspace integration and smoke tests (see `tests/README_TESTING.md`).
- `docker-compose*.yml`, `k8s/`, `terraform/`: Local dev stack and infra manifests.

## Build, Test, and Development Commands

- `cargo build --workspace`: build all Rust crates.
- `cargo run -p beagle-monorepo --bin beagle-monorepo`: run the core server.
- `cargo run -p beagle-monorepo --bin pipeline -- "<question>"`: run the scientific pipeline.
- `curl -H "Authorization: Bearer $BEAGLE_API_TOKEN" -X POST http://localhost:8080/api/exocortex/process -d '{"query":"..."}'`: Exocortex API (requires auth when enabled).
- `make fmt`: format Rust (`cargo fmt --all`).
- `make lint`: clippy with warnings as errors.
- `make rust-test`: run Rust tests (`cargo test --all -- --nocapture`).
- `cd beagle-mcp-server && npm run dev`: run MCP server in watch mode.

## Coding Style & Naming Conventions

- Rust: `rustfmt` default formatting; prefer `snake_case` for functions/modules and `UpperCamelCase` for types.
- Keep changes scoped; avoid reformatting unrelated code.
- Prefer explicit types and descriptive names for cross-crate APIs.

## Testing Guidelines

- Add tests for new behavior where it is easiest to validate (unit tests in crate + integration tests under `tests/`).
- Naming: keep Rust tests close to the module (`mod tests`) unless they span crates (use `tests/*.rs`).
- Run: `make rust-test` for local verification; add targeted `cargo test -p <crate>` during iteration.

## Commit & Pull Request Guidelines

- Commit messages follow Conventional Commits (e.g., `feat: …`, `fix: …`, `docs: …`, `refactor: …`, `chore: …`, `test: …`, `infra: …`).
- PRs: include a short description, the “why”, and validation steps (commands run + key output paths).

## Security & Configuration

- Never commit API keys. Use `.env.example` and environment variables (e.g., `XAI_API_KEY`, `DEEPSEEK_API_KEY`, `MINIMAX_API_KEY`).
- For routing experiments: set `BEAGLE_ROUTING_POLICY=minimax`; enable Exocortex in pipeline with `EXOCORTEX_ENABLED=true`.
- For unified Qdrant RAG: set `BEAGLE_QDRANT_COLLECTIONS=darwin-repos,darwin-papers,darwin-docs,darwin-books`.
