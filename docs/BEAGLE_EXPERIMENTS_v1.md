# BEAGLE Experiments v1.0

## Visão Geral

O BEAGLE Experiments v1.0 é uma infraestrutura completa de experimentação científica para avaliar diferentes condições do exocórtex:

- **Triad vs Single LLM**: Avaliação de ensemble (Triad) vs LLM único
- **HRV-aware vs HRV-blind**: Impacto do contexto fisiológico na síntese
- **Serendipity on/off**: Efeito de injeção de conexões interdisciplinares
- **SpaceWeather-aware vs neutro** (futuro): Influência de clima espacial

Padrão Q1+, estilo HELM/AgentBench: logging completo, separação de condições, reprodutibilidade, métricas claras.

---

## Conceitos Fundamentais

### `experiment_id`

Identificador único de um experimento. Exemplos:
- `triad_vs_single_v1`
- `hrv_aware_vs_blind_v1`
- `serendipity_on_off_v1`

### `condition`

Condição experimental dentro de um experimento. Exemplos:
- `triad`, `single`
- `hrv_aware`, `hrv_blind`
- `serendipity_on`, `serendipity_off`

### `ExperimentRunTag`

Tag experimental que registra um `run_id` como parte de um experimento:

```rust
pub struct ExperimentRunTag {
    pub experiment_id: String,
    pub run_id: String,
    pub condition: String,
    pub timestamp: DateTime<Utc>,
    pub notes: Option<String>,
    
    // Snapshot de config (reprodutibilidade)
    pub triad_enabled: bool,
    pub hrv_aware: bool,
    pub serendipity_enabled: bool,
    pub space_aware: bool,
}
```

---

## Formato de Dados

### `experiments/events.jsonl`

Arquivo JSONL (uma linha por tag) com formato:

```json
{"tag": {"experiment_id": "...", "run_id": "...", "condition": "...", ...}}
```

Localização: `BEAGLE_DATA_DIR/experiments/events.jsonl`

---

## CLIs Disponíveis

### `tag_experiment_run`

Marca um `run_id` existente com tag experimental.

**Uso:**
```bash
tag_experiment_run <experiment_id> <run_id> <condition> [notes...]
```

**Exemplo:**
```bash
tag_experiment_run triad_vs_single_v1 run_abc123 triad "Primeiro run com Triad"
```

**Comportamento:**
- Carrega `BeagleConfig` atual
- Infere flags automaticamente de `run_report.json` (se disponível)
- Cria `ExperimentRunTag` completo com snapshot de config
- Anexa tag em `experiments/events.jsonl`

### `run_experiment_triad_vs_single`

Executa experimento automatizado Triad vs Single LLM.

**Uso:**
```bash
run_experiment_triad_vs_single [--experiment-id ID] [--n-total N] [--question-template TEMPLATE] [--beagle-core-url URL] [--interval-secs SECS]
```

**Exemplo:**
```bash
run_experiment_triad_vs_single \
  --experiment-id triad_vs_single_v1 \
  --n-total 20 \
  --question-template "Paper idea {i}: Explorar aplicações de scaffolds biológicos" \
  --beagle-core-url http://localhost:8080 \
  --interval-secs 5
```

**Comportamento:**
1. Divide `N_TOTAL` runs em duas condições (N/2 cada)
2. Para cada run:
   - Gera pergunta (substitui `{i}` por índice)
   - Chama `/api/pipeline/start` com `with_triad=true` ou `false`
   - Aguarda conclusão via polling de `/api/pipeline/status/:run_id`
   - Cria tag experimental automaticamente
3. Salva todas as tags em `experiments/events.jsonl`

### `run_experiment_hrv_aware_vs_blind`

Executa experimento HRV-aware vs HRV-blind.

**Uso:**
```bash
run_experiment_hrv_aware_vs_blind [--experiment-id ID] [--n-total N] [--question-template TEMPLATE] [--beagle-core-url URL]
```

**Comportamento:**
- Similar ao anterior, mas compara condições `hrv_aware` vs `hrv_blind`
- Requer que pipeline aceite flag `hrv_aware` (implementado em EXP4)

### `run_experiment_serendipity`

Executa experimento Serendipity on/off.

**Uso:**
```bash
run_experiment_serendipity [--experiment-id ID] [--n-total N] [--question-template TEMPLATE] [--beagle-core-url URL]
```

**Comportamento:**
- Controla `BEAGLE_SERENDIPITY` env var entre runs
- Compara condições `serendipity_on` vs `serendipity_off`

### `analyze_experiments`

Analisa resultados de um experimento.

**Uso:**
```bash
analyze_experiments <experiment_id> [--output-format csv|json|terminal] [--output-file PATH]
```

**Exemplo:**
```bash
# Terminal (default)
analyze_experiments triad_vs_single_v1

# CSV
analyze_experiments triad_vs_single_v1 --output-format csv

# JSON
analyze_experiments triad_vs_single_v1 --output-format json --output-file results.json
```

**Métricas Calculadas (por condição):**
- `n_runs`, `n_with_feedback`
- `rating_mean`, `rating_std`, `rating_p50`, `rating_p90`
- `accepted_ratio` (accepted=true / total com feedback)
- Distribuição de severidades (physio/env/space): contagens Normal/Mild/Moderate/Severe
- `stress_index_mean`
- `avg_tokens`, `avg_grok3_calls`, `avg_grok4_calls`

**Saída Terminal:**
```
📊 Experimento: triad_vs_single_v1
   Total de runs: 20

Condition triad:
  runs: 10 (feedback: 8)
  rating mean: 8.20 (std 0.70)
  rating p50: 8.00
  rating p90: 9.00
  accepted: 7/8 (87.5%)
  physio_severity: Normal:5 Moderate:3 Severe:0
  stress_index_mean: 0.450
  avg_tokens: 1250.0
  avg_grok3_calls: 5.2
  avg_grok4_calls: 0.0

Condition single:
  runs: 10 (feedback: 8)
  rating mean: 6.70 (std 1.10)
  rating p50: 7.00
  rating p90: 8.00
  accepted: 4/8 (50.0%)
  physio_severity: Normal:5 Moderate:3 Severe:0
  stress_index_mean: 0.480
  avg_tokens: 980.0
  avg_grok3_calls: 4.8
  avg_grok4_calls: 0.0
```

---

## Exemplos Concretos

### Como Rodar um Experimento Triad vs Single com N=20

1. **Certifique-se de que o core_server está rodando:**
   ```bash
   cargo run --bin core_server --package beagle-monorepo
   ```

2. **Execute o experimento:**
   ```bash
   cargo run --bin run_experiment_triad_vs_single --package beagle-experiments -- \
     --experiment-id triad_vs_single_v1 \
     --n-total 20 \
     --question-template "Paper idea {i}: Explorar aplicações de scaffolds biológicos em medicina regenerativa"
   ```

3. **Aguarde conclusão** (pode levar vários minutos, dependendo da latência do pipeline).

4. **Registre feedback humano** (opcional):
   ```bash
   tag_run run_abc123 1 8 "Excelente draft"
   tag_run run_xyz789 0 5 "Precisa melhorar clareza"
   ```

5. **Analise resultados:**
   ```bash
   cargo run --bin analyze_experiments --package beagle-experiments -- \
     triad_vs_single_v1 \
     --output-format csv
   ```

### Como Analisar Resultados

```bash
# Ver resumo no terminal
analyze_experiments triad_vs_single_v1

# Exportar CSV para análise externa (Julia, Python, R)
analyze_experiments triad_vs_single_v1 --output-format csv

# Exportar JSON
analyze_experiments triad_vs_single_v1 --output-format json
```

O CSV/JSON será salvo em `BEAGLE_DATA_DIR/experiments/<experiment_id>_summary.{csv|json}`.

### Interpretação de Métricas

- **rating_mean**: Média de ratings (0-10). Maior é melhor.
- **accepted_ratio**: Proporção de runs aceitos. Maior é melhor.
- **physio_severity**: Distribuição de severidades fisiológicas (do Observer 2.0). Pode indicar se condições experimentais afetam estado fisiológico ou vice-versa.
- **avg_tokens**: Média de tokens usados. Útil para análise de custo/eficiência.
- **avg_grok4_calls**: Média de chamadas ao Grok 4 Heavy. Indica uso de tier mais caro.

---

## Integração com Pipeline

O pipeline aceita flags experimentais via HTTP:

**POST `/api/pipeline/start`**
```json
{
  "question": "Pergunta científica...",
  "with_triad": true,
  "hrv_aware": true,
  "experiment_id": "triad_vs_single_v1"
}
```

Flags:
- `hrv_aware` (opcional, default: `true`): Se `false`, usa `UserContext::default()` (contexto neutro)
- `with_triad` (opcional, default: `false`): Se `true`, executa Triad após pipeline
- `experiment_id` (opcional): ID do experimento para rastreamento

---

## Notas Importantes

1. **Camada de Avaliação Científica**: Este módulo é para avaliação científica do BEAGLE, não para usuário final.

2. **Reprodutibilidade**: Tags incluem snapshot de config no momento do run, permitindo reprodutibilidade parcial (thresholds Observer, flags Serendipity, etc.).

3. **Limitações**:
   - Thresholds Observer podem mudar entre runs (configurável, mas não versionado per-run)
   - LLM responses variam (stochasticidade), então múltiplos runs são necessários
   - Feedback humano requer tempo (análise pode ser feita incrementalmente)

4. **Padrão SOTA**: Este desenho é compatível com frameworks de avaliação como HELM (múltiplas dimensões) e AgentBench (cenários estruturados), focando em logging completo e separação de condições.

---

## Próximos Passos

Para chegar em N≈1000 eventos até março 2026:

1. Rodar experimentos automatizados periodicamente (cronjobs, scripts Julia)
2. Coletar feedback humano incrementalmente (CLI `tag_run`)
3. Analisar resultados periodicamente (`analyze_experiments`)
4. Ajustar condições/hipóteses baseado em métricas
5. Exportar dados para análise fina (Julia, Python, R)

---

## Referências

- **HELM**: [CRFM HELM Documentation](https://crfm-helm.readthedocs.io/)
- **AgentBench**: Evaluation frameworks for LLM-as-Agent
- **BEAGLE Observer 2.0**: Ver `docs/BEAGLE_OBSERVER_v2_0.md`
- **BEAGLE Core v0.3**: Ver `docs/BEAGLE_CORE_v0_3.md`

