# BeagleAutoPublish.jl - Auto-Publish para arXiv/Overleaf

**100% REAL - Gera LaTeX completo e publica automaticamente**

## Features

- ✅ **Markdown → LaTeX**: Conversão automática completa
- ✅ **Overleaf Integration**: Cria projeto automaticamente (com API key)
- ✅ **arXiv Ready**: Prepara arquivo .tex pronto para submissão
- ✅ **Metadata**: Gera metadata completa (título, autores, abstract)
- ✅ **Auto-formatting**: Formatação científica padrão

## Uso

```julia
include("AutoPublish.jl")
using .BeagleAutoPublish

# Auto-publish último draft encontrado
BeagleAutoPublish.demo()

# Ou com arquivo específico
BeagleAutoPublish.auto_publish("paper_final_20251118_120000.md")

# Ou com título customizado
BeagleAutoPublish.auto_publish(
    "draft.md";
    title="Título Customizado",
    authors="Demetrios Chiuratto et al.",
    overleaf_api_key="sua-api-key"  # Opcional
)

# Ou via CLI
julia run_auto_publish.jl paper_final_20251118_120000.md
```

## Requisitos

- **Julia 1.10+** com pacotes instalados:
  ```julia
  ] add HTTP JSON3 Dates
  ```
- **Overleaf API Key** (opcional, para upload automático):
  ```bash
  export OVERLEAF_API_KEY="sua-api-key"
  ```

## Processo

1. **Parse Markdown**: Extrai seções (Introduction, Methods, etc.)
2. **Conversão LaTeX**: Converte Markdown para LaTeX científico
3. **Geração Template**: Usa template LaTeX completo
4. **Overleaf Upload**: Cria projeto automaticamente (se API key configurada)
5. **arXiv Prep**: Prepara arquivo pronto para submissão manual

## Output

Arquivos gerados em `latex_output/`:
- `paper_YYYYMMDD_HHMMSS_Title.tex`: LaTeX completo
- `metadata_YYYYMMDD_HHMMSS.json`: Metadata do paper
- URL do Overleaf (se criado)

## LaTeX Template

Usa template científico completo com:
- Abstract
- Sections (Introduction, Methods, Results, Discussion, Conclusion)
- Bibliography (natbib)
- Hyperlinks
- Formatação padrão A4, margens 1in

## Markdown → LaTeX

Conversões suportadas:
- **Bold**: `**text**` → `\textbf{text}`
- **Italic**: `*text*` → `\textit{text}`
- **Code**: `` `code` `` → `\texttt{code}`
- **Headers**: `## Title` → `\subsection*{Title}`
- **Links**: `[text](url)` → `\href{url}{text}`
- **Lists**: `- item` → `\item item`

## arXiv Submission

Nota: arXiv requer submissão manual via web interface.
O módulo prepara o arquivo .tex completo, mas a submissão final precisa ser feita manualmente ou via script específico do arXiv.

## Overleaf API

Para usar upload automático no Overleaf:
1. Obtenha API key em: https://www.overleaf.com/user/settings
2. Configure env var: `export OVERLEAF_API_KEY="sua-key"`
3. Execute: `auto_publish("draft.md"; overleaf_api_key=ENV["OVERLEAF_API_KEY"])`

## Exemplo Completo

```julia
# 1. Roda Full Orchestrator
include("FullOrchestrator.jl")
using .BeagleFullOrchestrator
orch = FullOrchestrator("Pergunta de pesquisa...")
run_full_cycle!(orch)  # Gera draft final

# 2. Auto-publish
include("AutoPublish.jl")
using .BeagleAutoPublish
BeagleAutoPublish.auto_publish("paper_final_20251118_120000.md")
```

## Integração

Pode ser integrado no loop infinito do Full Orchestrator:

```julia
# Após cada ciclo, auto-publish
results = run_full_cycle!(orch)
if haskey(results, "draft")
    # Salva draft primeiro
    open("draft_current.md", "w") do f
        write(f, results["draft"])
    end
    
    # Auto-publish
    BeagleAutoPublish.auto_publish("draft_current.md")
end
```

