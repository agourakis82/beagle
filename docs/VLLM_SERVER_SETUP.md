# 🚀 vLLM Server Setup - T560 (L4 24GB)

## Visão Geral

Este documento descreve a configuração completa do servidor de inferência vLLM no T560 para servir o modelo **Qwen 2.5 32B GPTQ** (quantizado para caber em 18GB).

## Hardware

- **GPU**: NVIDIA L4 24GB
- **CUDA**: 12.4+
- **Driver**: 545+
- **Espaço em disco**: ~50GB livre (para modelo + ambiente)

## Arquitetura

```
T560
├── vLLM Server (porta 8001)
│   ├── Qwen 2.5 32B GPTQ (~18GB)
│   ├── GPU Memory: 90% utilization
│   └── Max context: 8192 tokens
└── OpenAI-compatible API
    ├── /v1/models
    ├── /v1/completions
    └── /v1/chat/completions
```

## Setup Rápido

### 1. Executar Script de Setup (LOCALMENTE na T560)

```bash
# Na máquina T560 (local)
cd ~/beagle/scripts/infrastructure
chmod +x setup_vllm_t560.sh
./setup_vllm_t560.sh
```

**Nota**: Execute diretamente na máquina T560, não via SSH.

O script faz automaticamente:
- ✅ Atualiza sistema
- ✅ Instala CUDA 12.4 (se necessário)
- ✅ Instala Python 3.11
- ✅ Cria virtual environment
- ✅ Instala vLLM + PyTorch
- ✅ Configura HuggingFace
- ✅ Baixa modelo Qwen 2.5 32B GPTQ
- ✅ Cria script de start

**Tempo estimado**: 30-60 minutos (principalmente download do modelo)

### 2. Iniciar Servidor

```bash
# Em tmux (para manter rodando)
tmux new -s vllm
~/start_vllm.sh

# Detach: Ctrl+B, D
# Reattach: tmux attach -t vllm
```

### 3. Testar

```bash
# Teste básico
curl http://localhost:8001/v1/models

# Teste completo
~/beagle/scripts/infrastructure/test_vllm.sh
```

## Uso Detalhado

### Variáveis de Ambiente

```bash
# Porta do servidor (padrão: 8001)
export VLLM_PORT=8001

# Host (padrão: 0.0.0.0 = todas interfaces)
export VLLM_HOST=0.0.0.0

# Diretório do modelo
export MODEL_DIR=~/models/qwen-32b-gptq
```

### Iniciar com Opções Customizadas

```bash
~/start_vllm.sh \
  --max-model-len 16384 \
  --gpu-memory-utilization 0.95 \
  --tensor-parallel-size 1
```

### Acessar de Outro Host (Opcional)

Se quiser acessar o servidor de outra máquina na rede:

1. **Obter IP do T560**:
   ```bash
   ip addr show | grep "inet "
   # Exemplo: 192.168.1.100
   ```

2. **Configurar firewall** (se necessário):
   ```bash
   sudo ufw allow 8001/tcp
   ```

3. **Usar no código**:
   ```rust
   // Em beagle-llm
   let client = AnthropicClient::new(
       "http://192.168.1.100:8001/v1/completions".to_string(),
       api_key,
   );
   ```

**Nota**: Para uso local, use `http://localhost:8001` ou `http://127.0.0.1:8001`

## API Endpoints

### Listar Modelos

```bash
curl http://localhost:8001/v1/models
```

**Resposta**:
```json
{
  "object": "list",
  "data": [
    {
      "id": "qwen-32b-gptq",
      "object": "model",
      "created": 1234567890,
      "owned_by": "vllm"
    }
  ]
}
```

### Completions

```bash
curl -X POST http://localhost:8001/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-32b-gptq",
    "prompt": "Explain pharmacokinetics:",
    "max_tokens": 200,
    "temperature": 0.7
  }'
```

### Chat Completions

```bash
curl -X POST http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-32b-gptq",
    "messages": [
      {"role": "user", "content": "What is PBPK modeling?"}
    ],
    "max_tokens": 200,
    "temperature": 0.7
  }'
```

## Monitoramento

### GPU Usage

```bash
# Em tempo real
watch -n 1 nvidia-smi

# Ou
nvidia-smi -l 1
```

### Logs do Servidor

```bash
# Se rodando em tmux
tmux attach -t vllm

# Ou verificar logs do sistema
journalctl -u vllm -f  # Se configurado como serviço
```

### Performance

- **Throughput**: ~10-20 tokens/s (depende do prompt)
- **Latência**: ~200-500ms primeiro token
- **GPU Memory**: ~18-20GB usado
- **Context Window**: 8192 tokens (configurável)

## Troubleshooting

### Servidor não inicia

1. **Verificar GPU**:
   ```bash
   nvidia-smi
   ```

2. **Verificar modelo**:
   ```bash
   ls -lh ~/models/qwen-32b-gptq
   ```

3. **Verificar virtual environment**:
   ```bash
   source ~/vllm-env/bin/activate
   python -c "import vllm; print(vllm.__version__)"
   ```

### Out of Memory

- Reduzir `--gpu-memory-utilization` (padrão: 0.90)
- Reduzir `--max-model-len` (padrão: 8192)
- Usar modelo menor ou quantização mais agressiva

### Conexão Recusada

1. **Verificar firewall**:
   ```bash
   sudo ufw status
   sudo ufw allow 8001/tcp
   ```

2. **Verificar se servidor está rodando**:
   ```bash
   netstat -tlnp | grep 8001
   ```

3. **Verificar host binding**:
   - Se `VLLM_HOST=127.0.0.1`, só aceita conexões locais
   - Use `VLLM_HOST=0.0.0.0` para aceitar de qualquer IP

### Modelo não encontrado

```bash
# Re-baixar modelo
huggingface-cli login
huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 \
  --local-dir ~/models/qwen-32b-gptq
```

## Integração com Beagle

### Configurar beagle-llm

```rust
// Em crates/beagle-llm/src/client.rs
pub struct AnthropicClient {
    base_url: String,  // http://192.168.1.100:8001/v1
    api_key: String,
}

// Usar endpoint OpenAI-compatible
let client = AnthropicClient::new(
    "http://192.168.1.100:8001/v1".to_string(),
    "dummy".to_string(),  // vLLM não precisa de key real
);
```

### Roteamento

Adicionar vLLM como opção no roteamento de modelos:

```rust
match model_type {
    ModelType::Qwen32B => {
        // Usar vLLM server
        self.vllm_client.complete(request).await
    }
    _ => {
        // Usar Claude/Gemini
        self.anthropic_client.complete(request).await
    }
}
```

## Manutenção

### Atualizar vLLM

```bash
source ~/vllm-env/bin/activate
pip install --upgrade vllm
```

### Atualizar Modelo

```bash
# Baixar nova versão
huggingface-cli download Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4 \
  --local-dir ~/models/qwen-32b-gptq-new

# Testar
VLLM_MODEL_DIR=~/models/qwen-32b-gptq-new ~/start_vllm.sh

# Se OK, substituir
mv ~/models/qwen-32b-gptq ~/models/qwen-32b-gptq-old
mv ~/models/qwen-32b-gptq-new ~/models/qwen-32b-gptq
```

### Backup

```bash
# Backup do modelo (18GB)
tar -czf qwen-32b-gptq-backup.tar.gz ~/models/qwen-32b-gptq

# Backup do virtual environment (opcional)
tar -czf vllm-env-backup.tar.gz ~/vllm-env
```

## Referências

- [vLLM Documentation](https://docs.vllm.ai/)
- [Qwen 2.5 Models](https://huggingface.co/Qwen/Qwen2.5-32B-Instruct-GPTQ-Int4)
- [OpenAI API Compatibility](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html)

---

**Última atualização**: 2025-01-XX
**Status**: ✅ Configurado e testado

