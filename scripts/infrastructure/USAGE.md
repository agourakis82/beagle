# 📖 Guia de Uso - Scripts vLLM

## Fluxo Completo

### 1. Setup Inicial (Primeira Vez)

```bash
# Setup completo (instala tudo)
./setup_vllm_t560.sh
```

### 2. Servidor Atual (Mistral-7B)

O servidor já está rodando na porta 8000 com Mistral-7B.

**Gerenciar:**
```bash
# Ver logs
tmux attach -t vllm

# Parar
tmux kill-session -t vllm

# Reiniciar
tmux new -s vllm
~/start_vllm.sh
```

**Testar:**
```bash
./test_vllm.sh http://localhost:8000
```

### 3. Download Qwen 32B (Sem Interferir)

```bash
# Inicia download em sessão tmux separada
./download_qwen32b.sh

# Ver progresso (quando quiser)
tmux attach -t download

# Detach (deixa rodando)
# Ctrl+B, depois D
```

**Características:**
- ✅ Não interfere com servidor atual
- ✅ Roda em background
- ✅ ~18GB, 20-30 minutos
- ✅ Fallback automático se primeiro modelo falhar

### 4. Swap para Qwen 32B

Quando download terminar:

```bash
# Para Mistral-7B e inicia Qwen 32B
./swap_to_qwen.sh
```

**O que faz:**
1. Para servidor atual (Mistral-7B)
2. Aguarda liberação de GPU
3. Inicia Qwen 32B na mesma porta (8000)
4. Testa automaticamente
5. Mostra status

### 5. Verificar Status

```bash
# Listar sessões tmux
tmux list-sessions

# Ver servidor vLLM
tmux attach -t vllm

# Ver download (se ainda rodando)
tmux attach -t download

# Testar API
curl http://localhost:8000/v1/models
```

## Troubleshooting

### Download lento
- Verifique conexão: `ping huggingface.co`
- Use mirror alternativo (script tem fallback)

### GPU out of memory
- Reduzir `--gpu-memory-utilization` em `swap_to_qwen.sh`
- Padrão: 0.90 (90%)

### Porta em uso
- Verificar: `netstat -tlnp | grep 8000`
- Mudar porta: `VLLM_PORT=8001 ./swap_to_qwen.sh`

### Modelo não encontrado
- Verificar: `ls -lh ~/models/qwen-32b-gptq`
- Re-baixar: `./download_qwen32b.sh`

## Estrutura de Sessões TMUX

```
tmux sessions:
├── vllm      → Servidor vLLM (Mistral ou Qwen)
└── download  → Download do modelo (temporário)
```

## Modelos Disponíveis

- **Mistral-7B**: Já rodando (porta 8000)
- **Qwen 32B**: Baixar com `download_qwen32b.sh`

## Próximos Passos

Após swap para Qwen 32B:
1. Testar: `./test_vllm.sh`
2. Integrar com beagle-llm
3. Usar para reasoning avançado
