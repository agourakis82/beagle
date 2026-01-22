# Repository Guidelines

## Project Structure & Module Organization
- `Cargo.toml` defines the Rust workspace; most crates live in `crates/` and shared binaries live in `src/` or crate-specific `src/` folders.
- `apps/` contains app-level packages (e.g., Tauri/IDE, monorepo app).
- `beagle-julia/` holds Julia pipelines and tests; `beagle-mcp-server/` is the Node MCP server.
- `tests/` includes integration tests; `docs/` has technical documentation and release notes.
- Supporting assets and tooling live in `scripts/`, `examples/`, `data/`, and `docker/`.

## Build, Test, and Development Commands
- `make fmt` runs Rust formatting (rustfmt).
- `make lint` runs `cargo clippy` with warnings as errors.
- `make rust-test` runs all Rust tests with output.
- `make julia-test` runs Julia tests in `beagle-julia/`.
- `make ci-local` runs the full local CI pipeline.
- `cargo run -p beagle-monorepo --bin core_server` starts the core server.
- `cd beagle-mcp-server && npm install && npm run build` builds the MCP server.

## Coding Style & Naming Conventions
- Rust edition is 2021; use rustfmt and keep clippy clean (`-D warnings`).
- Prefer workspace dependencies (`workspace = true`) and avoid hardcoded paths.
- Always resolve data paths via `beagle_config::beagle_data_dir()` or config (`BEAGLE_DATA_DIR`).
- Naming: `PascalCase` for types, `snake_case` for functions/fields, `UPPER_SNAKE_CASE` for constants.

## Testing Guidelines
- Rust unit tests live alongside code with `#[cfg(test)]`.
- Integration tests and external-service requirements are documented in `tests/README_TESTING.md`.
- Example: `cargo test --all -- --nocapture` or `cargo test --test v04_integration_tests -- --ignored`.

## Commit & Pull Request Guidelines
- Commit messages follow a conventional style: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `infra:`.
- PRs should include a concise summary, test evidence, and any required config/env changes.
- Link related issues and include screenshots/logs for UI or workflow changes when relevant.

## Configuration & Environment Tips
- Set `BEAGLE_PROFILE` (`dev|lab|prod`) and `BEAGLE_DATA_DIR` before running services.
- Keep `BEAGLE_SAFE_MODE=true` unless explicitly testing irreversible actions.
