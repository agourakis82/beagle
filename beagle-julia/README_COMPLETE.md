# BEAGLE SINGULARITY - Pipeline Completo em Julia

**100% REAL - Roda tudo de uma vez: Full Orchestrator + Auto-Publish**

## Pipeline Completo

1. **Full Orchestrator**: Quantum → Cosmological → Adversarial → Void → Fractal
2. **Auto-Publish**: LaTeX → Overleaf → arXiv

## Como Rodar Tudo de Uma Vez

```bash
# Pipeline completo (orchestrator + publish)
julia run_complete_pipeline.jl "Pergunta de pesquisa..."

# Ou apenas orchestrator
julia run_full_orchestrator.jl 1 "Pergunta de pesquisa..."

# Ou apenas publish
julia run_auto_publish.jl paper_*.md
```

## Ou no REPL Julia

```julia
# 1. Full Orchestrator
include("Orchestrator.jl")
using .BeagleFullOrchestrator

draft = BeagleFullOrchestrator.full_cycle("Pergunta de pesquisa...")

# 2. Auto-Publish
include("AutoPublish.jl")
using .BeagleAutoPublish

BeagleAutoPublish.publish_to_arxiv("paper_*.md")
```

## Módulos Integrados

- ✅ **BeagleQuantum**: Superposition + Interference
- ✅ **BeagleAdversarial**: Self-play loop até quality >98.5%
- ✅ **BeagleVoidOntic**: Dissolução + insights do vazio
- ✅ **BeagleFractal**: Crescimento recursivo infinito
- ✅ **BeagleCosmological**: Alinhamento com leis fundamentais
- ✅ **BeagleAutoPublish**: LaTeX + Overleaf + arXiv

## Output Final

- **Draft Markdown**: `paper_*_YYYYMMDD_HHMMSS.md`
- **LaTeX**: `latex_output/paper_*.tex`
- **arXiv Tarball**: `arxiv_submission/arxiv_submission_*.tar.gz`
- **Overleaf URL**: (se API key configurada)

## Performance

- **1 ciclo completo**: ~15-20 minutos
- **Pipeline completo**: ~20-25 minutos (orchestrator + publish)

## Configuração

```bash
# Overleaf (opcional)
export OVERLEAF_API_KEY="sua-api-key"

# arXiv (submissão manual)
# Acesse: https://arxiv.org/submit
# Upload do tarball gerado
```

## Exemplo Completo

```julia
# Roda tudo
include("Orchestrator.jl")
using .BeagleFullOrchestrator

draft = BeagleFullOrchestrator.full_cycle(
    "Unificar entropia curva em scaffolds biológicos com consciência celular via geometria não-comutativa"
)

# Publica
include("AutoPublish.jl")
using .BeagleAutoPublish

BeagleAutoPublish.publish_to_arxiv("paper_*.md")
```

## Resultado

Em 15-20 minutos você tem:
- ✅ Paper Q1 escrito
- ✅ Alinhado cosmologicamente
- ✅ Com insights do vazio (se sorteado)
- ✅ LaTeX completo gerado
- ✅ Pronto para submissão no arXiv

**Week 21 + 22 completas.**

