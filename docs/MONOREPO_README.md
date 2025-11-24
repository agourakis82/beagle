# BEAGLE MONOREPO — Todos os Projetos Unidos

**Data:** 2025-11-19  
**Status:** ✅ 100% Integrado

## 🎯 O que é este monorepo?

Este é o **monorepo definitivo** que integra **todos os projetos públicos** do BEAGLE:

### Projetos Integrados

1. **Darwin Core** → `beagle-darwin` (Rust) + `darwin-core-original` (Python, submodule)
2. **Darwin Workspace** → `beagle-workspace` (Rust/Julia) + `darwin-workspace-original` (Python, submodule)
3. **PCS Meta Repo** → `pcs-meta-repo-original` (Python, submodule)
4. **Darwin PBPK Platform** → `beagle-workspace` (Julia) + `darwin-pbpk-platform-original` (Python, submodule)
5. **Hyperbolic Semantic Networks** → `beagle-hypergraph` (Rust) + `hyperbolic-semantic-networks-original` (Python, submodule)
6. **Darwin Scaffold Studio** → `darwin-scaffold-studio-original` (Python, submodule)
7. **Darwin Heliobiology** → `beagle-workspace` (Julia) + `darwin-heliobiology-original` (Python, submodule)

### Estrutura

```
beagle-remote/
├── crates/
│   ├── beagle-darwin/          # Darwin Core (Rust, migrado)
│   ├── beagle-darwin-core/      # Darwin Core HTTP API (Rust)
│   ├── beagle-workspace/        # Darwin Workspace (Rust/Julia, migrado)
│   ├── beagle-hypergraph/       # Hypergraph (Rust, migrado)
│   ├── darwin-core-original/    # Darwin Core original (Python, submodule)
│   ├── darwin-workspace-original/ # Darwin Workspace original (Python, submodule)
│   └── ... (outros crates)
├── beagle-julia/                # Módulos Julia (KEC 3.0, PBPK, Heliobiology)
├── apps/
│   └── beagle-monorepo/         # Binário principal
└── Cargo.toml                    # Workspace root
```

## 🚀 Como Rodar

### 1. Inicializar submodules (opcional)

```bash
./scripts/setup_monorepo.sh
git submodule update --init --recursive
```

### 2. Rodar o BEAGLE completo

```bash
cargo run --bin beagle-monorepo
```

### 3. Rodar componentes individuais

```bash
# Darwin Core
cargo run --package beagle-darwin-core

# PBPK Platform
cargo test --package beagle-workspace

# KEC 3.0 (Julia)
julia --project=beagle-julia beagle-julia/kec_3_gpu.jl
```

## 📊 Status de Migração

| Projeto | Status Original | Status Migrado | Linguagem |
|---------|----------------|----------------|-----------|
| Darwin Core | ✅ Submodule | ✅ 100% Rust | Rust |
| Darwin Workspace | ✅ Submodule | ✅ 100% Rust/Julia | Rust/Julia |
| PBPK Platform | ✅ Submodule | ✅ 100% Julia | Julia |
| Heliobiology | ✅ Submodule | ✅ 100% Julia | Julia |
| Hypergraph | ✅ Submodule | ✅ 100% Rust | Rust |

## 🎯 Próximos Passos

1. Migrar `pcs-meta-repo` → Julia (Symbolic Psychiatry)
2. Migrar `darwin-scaffold-studio` → Julia (Images.jl + CUDA.jl)
3. Migrar `hyperbolic-semantic-networks` → Rust (petgraph)

## 📝 Notas

- Os submodules originais (Python) são mantidos para referência
- As versões migradas (Rust/Julia) são os componentes ativos
- Zero Python em produção — tudo Rust/Julia

---

**BEAGLE MONOREPO — Tudo junto, tudo vivo, tudo teu.**

