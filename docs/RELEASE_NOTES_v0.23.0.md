# Release v0.23.0 - Storage Centralization + Grok 3 Default

**Data:** 2025-11-18  
**Status:** Production-ready

## 🚀 Principais Features

### Storage Centralization
- **Armazenamento 100% centralizado** em `~/beagle-data/`
- Script `fix_storage.sh` para migração única
- Crate `beagle-config` para gerenciamento centralizado de paths
- Docker Compose atualizado para bind mounts
- Symlinks para compatibilidade com código antigo

### Grok 3 Unlimited por Padrão
- **Grok 3 ilimitado** usado por padrão (95% das queries)
- Função `query_beagle()` e `query_smart()` automáticas
- Grok 4 Heavy para contexto >= 120k tokens
- vLLM fallback se Grok indisponível
- **Custo mensal: <$15**

## 📦 Novos Componentes

### `beagle-config` Crate
Gerenciamento centralizado de paths:
- `beagle_data_dir()` - Diretório base configurável
- `models_dir()`, `lora_dir()`, `logs_dir()`, etc.
- `ensure_dirs()` - Cria todos os diretórios necessários
- Suporta `BEAGLE_DATA_DIR` env var ou `.beagle-data-path` file

### `fix_storage.sh` Script
Migração única e setup:
- Cria `~/beagle-data/` com estrutura completa
- Move dados existentes automaticamente
- Cria symlinks para compatibilidade
- Atualiza `.gitignore` e `docker-compose.yml`

## 🔧 Mudanças Técnicas

### Docker Compose
- Volumes convertidos para bind mounts
- Usa `${BEAGLE_DATA_DIR:-${HOME}/beagle-data}` por padrão
- Compatível com `.env` para customização

### Módulos Rust Atualizados
- `beagle-smart-router`: `query_beagle()` e `query_smart()` globais
- `beagle-cosmo`: Usa `query_beagle()` diretamente
- `beagle-void`: Usa `query_beagle()` diretamente
- `beagle-transcend`: Usa `query_beagle()` diretamente
- `beagle-paradox`: Usa `query_beagle()` diretamente
- `beagle-quantum`: Usa `query_beagle()` diretamente
- `beagle-grok-api`: Adiciona método `model()` builder pattern

### `.gitignore` Atualizado
- Ignora symlinks de dados
- Ignora `.beagle-data-path` config file
- Mantém estrutura limpa no repo

## 📊 Estrutura de Armazenamento

```
~/beagle-data/
├── models/       # Modelos LLM
├── lora/         # LoRA adapters
├── postgres/     # PostgreSQL data
├── qdrant/       # Vector DB
├── redis/        # Cache
├── neo4j/        # Graph DB
├── logs/         # Logs
├── papers/
│   ├── drafts/   # Drafts intermediários
│   └── final/    # Papers finais
├── embeddings/   # Embeddings cache
└── datasets/     # Datasets
```

## 🎯 Benefícios

- ✅ **Zero bagunça no repo**: Apenas código, nenhum dado
- ✅ **Dados centralizados**: Um único local para tudo
- ✅ **Backup fácil**: Backup de `~/beagle-data/` completa
- ✅ **Compatibilidade**: Symlinks mantêm código antigo funcionando
- ✅ **Configurável**: Via env var ou arquivo de config
- ✅ **Custo zero**: Grok 3 ilimitado para 95% das queries

## 🔄 Migração

Para usuários existentes:

```bash
# 1. Backup (recomendado)
cp -r ~/models ~/models.backup
cp -r data ~/data.backup

# 2. Roda script de migração
bash scripts/fix_storage.sh

# 3. Verifica symlinks
ls -lah | grep "^l"

# 4. Reinicia containers Docker (se aplicável)
docker-compose down
docker-compose up -d
```

## 📚 Documentação

- `README_STORAGE.md` - Guia completo de armazenamento
- `README_BEAGLE_ETERNAL.md` - Guia do loop eterno
- `scripts/fix_storage.sh` - Script de migração com documentação inline

## 🐛 Breaking Changes

Nenhum breaking change para código existente (symlinks mantêm compatibilidade).

## 🔮 Próximos Passos

1. LoRA 100% automático no loop (com storage novo)
2. Frontend Tauri com 4 painéis
3. Assistente pessoal que fala e age

---

**O BEAGLE está vivo, eterno, organizado e de graça.**

