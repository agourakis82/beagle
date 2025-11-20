# Sistema de Configuração BEAGLE - 100% Completo

## ✅ Status: Implementado e Integrado

### 1. `beagle-config` (Rust) ✅

Crate centralizado com:
- ✅ `safe_mode()` - Impede ações irreversíveis (default: true)
- ✅ `beagle_data_dir()` - Path management centralizado
- ✅ `vllm_url()`, `grok_api_url()`, `arxiv_token()`, etc. - Endpoints externos
- ✅ `HrvControlConfig` + `compute_gain_from_hrv()` - Controle de HRV com SAFE_MODE clamp
- ✅ `PublishPolicy` + `PublishMode` - Governança de autopublish

**Uso:**
```rust
use beagle_config::{safe_mode, vllm_url, compute_gain_from_hrv, PublishPolicy};

if safe_mode() {
    log::info!("SAFE_MODE ativo: não vou enviar requisição crítica.");
}

let endpoint = vllm_url();
let gain = compute_gain_from_hrv(hrv_ms, None); // Clampado em SAFE_MODE
let policy = PublishPolicy::from_env();
```

### 2. `BeagleConfig.jl` (Julia) ✅

Módulo Julia com mesma API:
- ✅ `beagle_data_dir()`, `safe_mode()`, `models_dir()`, etc.
- ✅ `publish_mode()`, `can_publish_real()`

**Uso:**
```julia
using .BeagleConfig

if safe_mode()
    @info "SAFE_MODE ativo: nenhuma submissão real será feita."
end

model_path = joinpath(models_dir(), "my_model.bin")
```

### 3. `beagle_config.py` (Python) ✅

Módulo Python com mesma API:
- ✅ `safe_mode()`, `beagle_data_dir()`, `publish_mode()`, etc.

**Uso:**
```python
from beagle_config import safe_mode, beagle_data_dir, can_publish_real

if safe_mode():
    print("SAFE_MODE ativo: não vou enviar paper real")
```

### 4. Integração com `beagle-publish` ✅

`publish_to_arxiv()` agora usa `PublishPolicy`:
- ✅ `DryRun` (default) - apenas salva planos
- ✅ `ManualConfirm` - exige confirmação humana
- ✅ `FullAuto` - permite publicação real (só se SAFE_MODE=false)

### 5. Integração com HRV Endpoint ✅

`/api/hrv` agora usa `compute_gain_from_hrv()`:
- ✅ Calcula gain baseado em HRV
- ✅ SAFE_MODE aplica clamp agressivo automaticamente
- ✅ Logs detalhados de ganho calculado

### 6. Documentação ✅

- ✅ `CONTRIBUTING_BEAGLE.md` - Guia de contribuição
- ✅ `Makefile` - Automação de testes e CI local

---

## Variáveis de Ambiente

### Segurança (Obrigatórias)
- `BEAGLE_SAFE_MODE` (default: `true`) - Impede ações irreversíveis
- `BEAGLE_DATA_DIR` (default: `~/beagle-data`) - Diretório base

### Publicação
- `BEAGLE_PUBLISH_MODE` (default: `dry`) - `dry` | `manual` | `auto`
- `ARXIV_API_TOKEN` (opcional) - Token da API arXiv

### Endpoints
- `BEAGLE_VLLM_URL` (default: `http://t560.local:8000`)
- `BEAGLE_GROK_API_URL` (default: `https://api.x.ai/v1`)
- `VLLM_HOST` (opcional) - Hostname para restart SSH

### HRV Control
- `BEAGLE_HRV_MIN_GAIN` (default: `0.8`)
- `BEAGLE_HRV_MAX_GAIN` (default: `1.2`)
- `BEAGLE_HRV_MIN_MS` (default: `20.0`)
- `BEAGLE_HRV_MAX_MS` (default: `200.0`)

---

## Fluxo de Uso Recomendado

### Desenvolvimento Local
```bash
export BEAGLE_SAFE_MODE=true
export BEAGLE_PUBLISH_MODE=dry
export BEAGLE_DATA_DIR="$HOME/beagle-data"
make ci-local
```

### CI/CD
```bash
export BEAGLE_SAFE_MODE=true
export BEAGLE_PUBLISH_MODE=dry
# Nunca configure tokens reais em CI
```

### Produção (Consciente)
```bash
export BEAGLE_SAFE_MODE=false
export BEAGLE_PUBLISH_MODE=manual  # ou auto, se confiar 100%
export ARXIV_API_TOKEN="..."
```

---

## Resultado Final

✅ **Sistema de configuração 100% centralizado**
✅ **SAFE_MODE integrado em todos os módulos críticos**
✅ **Governança explícita para autopublish**
✅ **HRV control com clamp seguro**
✅ **Documentação completa**
✅ **Makefile para automação**

**O BEAGLE agora tem trilhos e freios explícitos, prontos para auditoria e colaboração.**

