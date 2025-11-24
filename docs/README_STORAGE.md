# BEAGLE Storage - Centralização Completa

**Armazenamento 100% centralizado em `~/beagle-data/`**

## 🚀 Setup (Uma vez só)

```bash
# Roda o script de centralização
bash scripts/fix_storage.sh
```

Isso cria:
- `~/beagle-data/` com toda a estrutura
- Symlinks no repo para compatibilidade
- Atualiza docker-compose.yml
- Atualiza .gitignore

## 📁 Estrutura

```
~/beagle-data/
├── models/       # Modelos LLM (Qwen, Mistral, etc)
├── lora/         # LoRA adapters treinados
├── postgres/     # PostgreSQL data
├── qdrant/       # Vector database
├── redis/        # Cache
├── neo4j/        # Graph database
├── logs/         # Logs de todos os módulos
├── papers/
│   ├── drafts/   # Drafts intermediários
│   └── final/    # Papers finais
├── embeddings/   # Embeddings cache
└── datasets/     # Datasets para treinamento
```

## 🔧 Configuração

### Opção 1: Variável de ambiente (recomendado)

```bash
export BEAGLE_DATA_DIR=~/beagle-data
```

### Opção 2: Arquivo .beagle-data-path

O script cria `.beagle-data-path` no repo com:
```
BEAGLE_DATA_DIR=~/beagle-data
```

### Opção 3: Docker Compose

```bash
# .env
BEAGLE_DATA_DIR=~/beagle-data
```

## 💻 Uso no Código Rust

```rust
use beagle_config::{models_dir, lora_dir, logs_dir};

// Paths automáticos
let model_path = models_dir().join("qwen-32b-gptq");
let lora_path = lora_dir().join("adapter.jld2");
let log_file = logs_dir().join("beagle.log");

// Garante que os dirs existem
beagle_config::ensure_dirs()?;
```

## 🐳 Docker

O `docker-compose.yml` usa `${BEAGLE_DATA_DIR:-~/beagle-data}` por padrão.

Configure no `.env`:
```bash
BEAGLE_DATA_DIR=/path/to/beagle-data
```

## 📊 Migração de Dados Existentes

O script `fix_storage.sh` move automaticamente:
- `~/models` → `~/beagle-data/models`
- `data/postgres` → `~/beagle-data/postgres`
- `data/qdrant` → `~/beagle-data/qdrant`
- `data/redis` → `~/beagle-data/redis`
- `lora_adapter/` → `~/beagle-data/lora`

**⚠️ Backup manual recomendado antes de rodar!**

## ✅ Benefícios

- ✅ Zero bagunça no repo (apenas código)
- ✅ Dados centralizados em um lugar só
- ✅ Backup fácil (backup de ~/beagle-data)
- ✅ Compatibilidade com código antigo (symlinks)
- ✅ Configurável via env var ou arquivo

## 🔍 Verificação

```bash
# Ver estrutura criada
ls -lah ~/beagle-data/

# Ver symlinks no repo
ls -lah ~/workspace/beagle-remote/ | grep "^l"

# Verificar paths no código
grep -r "beagle_data_dir\|models_dir\|lora_dir" crates/
```

---

**Nunca mais bagunça de armazenamento. Tudo centralizado e limpo.**

