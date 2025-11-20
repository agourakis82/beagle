# CONTRIBUTING – BEAGLE

Obrigado por se interessar em contribuir com o BEAGLE. Este documento descreve o fluxo básico para desenvolvimento, testes e abertura de Pull Requests.

## 1. Estrutura básica

O BEAGLE é um monorepo com:

- `crates/` – núcleo em Rust (Darwin, Hermes, Quantum, Publish, Config, etc.)
- `beagle-julia/` – orquestrador científico em Julia
- `apps/` – aplicações Tauri, iOS, VisionOS
- `scripts/` – utilitários de CI/auditoria

Leia primeiro: `MONOREPO_README.md`, `CONFIG_OVERVIEW.md` e `REPO_AUDIT_REPORT_BEAGLE.md`.

## 2. Requisitos

- Rust (stable, via `rustup`)
- Julia 1.11+
- Node.js (para Tauri, se for trabalhar na IDE)
- Ferramentas de linha de comando:
  - `git`, `bash`, `make` (opcional)
  - Docker (opcional, para ambientes isolados)

## 3. Setup local

1. Clone o repositório:

   ```bash
   git clone https://github.com/agourakis82/beagle.git
   cd beagle
   ```

2. Configure as variáveis mínimas:

   ```bash
   export BEAGLE_SAFE_MODE=true
   export BEAGLE_DATA_DIR="$HOME/beagle-data"
   ```

3. Rode o script de storage (se disponível):

   ```bash
   bash scripts/fix_storage.sh
   ```

## 4. Testes antes de abrir PR

Sempre execute:

```bash
cargo fmt --all
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all
bash scripts/check_paths.sh
julia --project=beagle-julia -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Se algum comando falhar, corrija antes de abrir o PR.

## 5. Padrão de commits

Use mensagens de commit descritivas, por exemplo:

* `feat: add safe mode to beagle-publish`
* `fix: remove hardcoded model path`
* `refactor: unify config handling`
* `docs: update CONFIG_OVERVIEW`

## 6. Pull Requests

* Abra PRs contra a branch `main` (salvo instruções em contrário).
* Descreva claramente:

  * O problema que está sendo resolvido.
  * O que foi modificado (componentes, arquivos, APIs).
  * Como testar (comandos exatos).

* Se o PR alterar comportamento de autopublicação ou HRV, explique a lógica de segurança.

## 7. Código de conduta

Mantenha respeito, clareza e foco científico. Discussões técnicas são bem-vindas; ataques pessoais não.

## 8. Configuração e SAFE_MODE

**IMPORTANTE**: O BEAGLE usa `SAFE_MODE` por padrão para prevenir ações irreversíveis.

- `BEAGLE_SAFE_MODE=true` (default): Nenhuma publicação real será feita
- `BEAGLE_PUBLISH_MODE=dry` (default): Apenas salva planos, nunca chama APIs reais
- `BEAGLE_DATA_DIR`: Diretório base de dados (default: `~/beagle-data`)

Sempre use `beagle-config` (Rust), `BeagleConfig.jl` (Julia) ou `beagle_config.py` (Python) para acessar configurações. **Nunca hardcode paths ou URLs.**

## 9. Testes de publicação

Se você está trabalhando em módulos de publicação (arXiv, Twitter, etc.):

1. **Sempre** teste com `BEAGLE_SAFE_MODE=true` primeiro
2. Verifique que planos são salvos corretamente
3. Só teste publicação real em ambiente isolado com `BEAGLE_SAFE_MODE=false` e `BEAGLE_PUBLISH_MODE=auto`

## 10. Integração com CI

O CI sempre roda com `BEAGLE_SAFE_MODE=true` e `BEAGLE_PUBLISH_MODE=dry`. Nunca assuma que APIs externas estão disponíveis ou que tokens estão configurados.

