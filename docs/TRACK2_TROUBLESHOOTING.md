# 🔧 Track 2 E2E Test - Troubleshooting Guide

## ❌ Erro: OpenSSL Development Headers Missing

### Problema
```
error: failed to run custom build command for `openssl-sys v0.9.111`
Failed to find OpenSSL development headers.
```

### Solução

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y pkg-config libssl-dev
```

#### Após instalação, re-executar:
```bash
export PATH="$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH"
export ANTHROPIC_API_KEY="sua-chave-aqui"
cargo build --package beagle-hermes --tests
```

---

## ✅ Verificação Rápida do Ambiente

### 1. Verificar Rust/Cargo
```bash
export PATH="$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH"
cargo --version
```

### 2. Verificar OpenSSL
```bash
# Verificar se OpenSSL está instalado
which openssl

# Verificar se headers estão instalados
dpkg -l | grep libssl-dev
```

### 3. Instalar dependências (se necessário)
```bash
sudo apt-get install -y pkg-config libssl-dev
```

---

## 🧪 Executar Testes Após Correção

### Teste Unitário (Sem Infraestrutura)
```bash
export PATH="$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH"
cargo test --package beagle-hermes test_argos_validation -- --nocapture
```

### Testes com API Key
```bash
export PATH="$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH"
export ANTHROPIC_API_KEY="sua-chave-aqui"
cargo test --package beagle-hermes test_athena_paper_search --ignored -- --nocapture
```

---

## 📝 Status Atual

**Problema Identificado:** Faltam headers de desenvolvimento do OpenSSL (`libssl-dev`)

**Ação Necessária:** Instalar `libssl-dev` com sudo

**Comando:**
```bash
sudo apt-get install -y pkg-config libssl-dev
```

**Após instalação, os testes devem compilar e executar corretamente.**

