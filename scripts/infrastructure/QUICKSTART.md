# 🚀 Quick Start - vLLM Server (T560 Local)

## Execução Local na T560

Como a T560 é uma máquina **local**, execute os scripts diretamente nela:

### Passo 1: Setup Inicial (30-60 min)

```bash
cd ~/beagle/scripts/infrastructure
./setup_vllm_t560.sh
```

O script vai:
- ✅ Instalar CUDA, Python, vLLM
- ✅ Baixar modelo Qwen 2.5 32B GPTQ (~18GB)
- ✅ Configurar tudo automaticamente

### Passo 2: Iniciar Servidor

```bash
# Em tmux (para manter rodando)
tmux new -s vllm
~/start_vllm.sh

# Detach: Ctrl+B, depois D
# Reattach: tmux attach -t vllm
```

### Passo 3: Testar

```bash
# Teste local
./test_vllm.sh

# Ou manualmente
curl http://localhost:8001/v1/models
```

### Passo 4: Usar no Beagle

```rust
// Em beagle-llm, usar localhost
let client = AnthropicClient::new(
    "http://localhost:8001/v1".to_string(),
    "dummy".to_string(),
);
```

## Acesso Remoto (Opcional)

Se quiser acessar de outra máquina na rede:

1. **Descobrir IP da T560**:
   ```bash
   ip addr show | grep "inet " | grep -v "127.0.0.1"
   ```

2. **Permitir acesso externo** (já configurado com `--host 0.0.0.0`)

3. **Testar de outro host**:
   ```bash
   ./test_vllm.sh http://<IP_DA_T560>:8001
   ```

## Troubleshooting

### Servidor não inicia
```bash
# Verificar GPU
nvidia-smi

# Verificar logs
tmux attach -t vllm
```

### Porta já em uso
```bash
# Mudar porta
VLLM_PORT=8002 ~/start_vllm.sh
```

### Modelo não encontrado
```bash
# Verificar se existe
ls -lh ~/models/qwen-32b-gptq

# Re-baixar se necessário
huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 \
  --local-dir ~/models/qwen-32b-gptq
```

---

**Pronto!** Servidor rodando em `http://localhost:8001` 🎉


