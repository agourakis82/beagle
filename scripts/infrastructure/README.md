# Infrastructure Scripts

Scripts para configuração e gerenciamento de infraestrutura do Beagle.

## vLLM Server (T560)

### Scripts Disponíveis

1. **`setup_vllm_t560.sh`** - Setup completo do servidor vLLM
   - Instala CUDA, Python, vLLM
   - Baixa modelo Qwen 2.5 32B GPTQ
   - Configura ambiente completo

2. **`start_vllm.sh`** - Inicia servidor vLLM
   - Ativa virtual environment
   - Inicia servidor na porta 8001
   - Suporta variáveis de ambiente

3. **`test_vllm.sh`** - Testa servidor vLLM
   - Verifica saúde do servidor
   - Testa endpoints de API
   - Valida completions e chat

4. **`download_qwen32b.sh`** - Download do modelo Qwen 32B GPTQ
   - Baixa em sessão tmux separada (não interfere com servidor)
   - ~18GB, 20-30 minutos
   - Roda em background

5. **`swap_to_qwen.sh`** - Troca servidor: Mistral-7B → Qwen 32B
   - Para servidor atual
   - Inicia com Qwen 32B
   - Testa automaticamente

### Uso Rápido (Máquina Local T560)

```bash
# 1. Setup (uma vez) - executar LOCALMENTE na T560
./setup_vllm_t560.sh

# 2. Iniciar servidor
tmux new -s vllm
~/start_vllm.sh
# Ctrl+B, D para detach

# 3. Testar (localhost)
./test_vllm.sh

# Ou testar de outro host na rede:
./test_vllm.sh http://<IP_DA_T560>:8001
```

### Download e Swap para Qwen 32B

```bash
# 1. Download do modelo (em background, não interfere com servidor)
./download_qwen32b.sh

# Ver progresso:
tmux attach -t download

# 2. Quando terminar, fazer swap
./swap_to_qwen.sh

# 3. Testar novo servidor
./test_vllm.sh http://localhost:8000
```

### Documentação Completa

Ver: [`docs/VLLM_SERVER_SETUP.md`](../../docs/VLLM_SERVER_SETUP.md)

## Outros Scripts

- `darwin_infrastructure_audit.py` - Auditoria do cluster Darwin
- `init-db.sql` - Inicialização do banco de dados

