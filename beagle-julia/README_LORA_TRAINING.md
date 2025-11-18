# LoRA Training Completo - Dataset + Training + Integração

**100% REAL - Ciclo fechado de aprendizado incremental**

## Módulos

1. **GenerateLoRADataset.jl**: Extrai pares (bad → good) do adversarial loop
2. **TrainLoRALux.jl**: Treina LoRA adapter com Lux.jl no M3 Max
3. **IntegrateLoRATraining.jl**: Integração automática completa

## Pipeline Completo

```
Adversarial Loop → Salva drafts intermediários
                  ↓
Generate Dataset → Extrai pares (bad → good)
                  ↓
Train LoRA      → Treina adapter com Lux.jl
                  ↓
Aplicar LoRA    → Melhora próximos drafts
```

## Uso

### 1. Gera Dataset do Adversarial

```julia
include("generate_lora_dataset.jl")
using .GenerateLoRADataset

# Gera dataset dos drafts salvos pelo adversarial
GenerateLoRADataset.generate_dataset("drafts_adversarial/", "drafts_paired.jsonl")

# Ou auto-detecta diretório
GenerateLoRADataset.demo()
```

### 2. Treina LoRA com Dataset

```julia
include("train_lora_lux.jl")
using .TrainLoRALux

# Treina com dataset gerado
TrainLoRALux.train_from_jsonl("drafts_paired.jsonl"; epochs=10, learning_rate=2e-4f0)

# Ou demo completo
TrainLoRALux.demo()
```

### 3. Ciclo Integrado Completo

```julia
include("integrate_lora_training.jl")
using .IntegrateLoRATraining

# Roda tudo: adversarial → dataset → LoRA training
IntegrateLoRATraining.run_integrated_cycle(
    "Pergunta de pesquisa...";
    max_adversarial_iters=6,
    enable_lora_training=true
)

# Ou via CLI
julia run_integrated_cycle.jl "Pergunta de pesquisa..."
```

## Requisitos

- **Julia 1.10+** com pacotes:
  ```julia
  ] add Lux Optimisers Zygote JLD2 HTTP JSON3 Dates
  ```
- **Embedding endpoint** rodando em `http://t560.local:8001/v1` com BGE-large
- **vLLM rodando** em `http://t560.local:8000/v1` com Llama-3.3-70B

## Output

### GenerateLoRADataset
- `drafts_paired.jsonl`: Dataset com pares (bad → good)
- Formato JSONL: uma linha JSON por par

### TrainLoRALux
- `lora_adapter_lux/lora_adapter_YYYYMMDD_HHMMSS.jld2`: Adapter treinado
- Metadata completa: dimensões, rank, alpha, exemplos treinados

### IntegrateLoRATraining
- `drafts_adversarial/`: Drafts intermediários salvos
- `drafts_paired_*.jsonl`: Dataset gerado automaticamente
- `lora_adapter_lux/`: Adapter treinado automaticamente

## Performance

- **Geração de dataset**: ~5 segundos
- **LoRA training (20 exemplos)**: ~5-10 minutos (depende do embedding server)
- **Ciclo integrado completo**: ~15-25 minutos

## Formato Dataset JSONL

```jsonl
{"prompt": "Escreve uma seção científica...", "completion": "Draft bom...", "bad_example": "Draft ruim...", "iteration": 1, ...}
{"prompt": "...", "completion": "...", "bad_example": "...", "iteration": 2, ...}
```

## Características

- **Embeddings reais**: Usa BGE-large via HTTP para obter embeddings 1024D
- **LoRA eficiente**: Rank 8, Alpha 16 (balance entre qualidade e velocidade)
- **Training incremental**: Cada ciclo adversarial melhora o LoRA
- **Ciclo fechado**: O sistema aprende continuamente com seus próprios outputs

## Próximos Passos

1. Integrar LoRA no adversarial loop (usar adapter para melhorar próximos drafts)
2. Converter adapter para formato vLLM (usar diretamente no vLLM com `--lora-path`)
3. Loop infinito de melhoria contínua (adversarial → LoRA → aplicar → repeat)

