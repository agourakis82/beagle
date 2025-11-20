SHELL := /usr/bin/env bash

.PHONY: all fmt lint test rust-test julia-test check-paths ci-local help

help:
	@echo "BEAGLE Makefile - Comandos disponíveis:"
	@echo "  make fmt          - Formata código Rust"
	@echo "  make lint         - Roda clippy com warnings como erros"
	@echo "  make rust-test    - Roda testes Rust"
	@echo "  make julia-test   - Roda testes Julia"
	@echo "  make check-paths  - Verifica paths hardcoded"
	@echo "  make test         - Roda todos os testes"
	@echo "  make ci-local     - Executa pipeline completo (fmt + lint + test + check-paths)"

all: fmt lint test

fmt:
	cargo fmt --all

lint:
	cargo clippy --all-targets --all-features -- -D warnings

rust-test:
	cargo test --all -- --nocapture

julia-test:
	cd beagle-julia && julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'

check-paths:
	@if [ -f scripts/check_paths.sh ]; then \
		bash scripts/check_paths.sh; \
	else \
		echo "⚠️  scripts/check_paths.sh não encontrado. Pulando verificação de paths."; \
	fi

test: rust-test julia-test

ci-local: fmt lint test check-paths
	@echo ""
	@echo "✅ CI local completo! Se tudo passou, você está pronto para commitar."

