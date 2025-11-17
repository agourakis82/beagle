# HERMES BPSE - Observability Stack

## Visão Geral

Stack completa de observabilidade para monitoramento em tempo real do HERMES BPSE:

- **Prometheus**: Coleta de métricas
- **Grafana**: Dashboards e visualização
- **Loki**: Agregação de logs
- **Promtail**: Coleta de logs do sistema

## Início Rápido

### 1. Iniciar Stack de Observabilidade

```bash
cd /home/maria/beagle/crates/beagle-hermes

# Criar network se não existir
docker network create beagle-network 2>/dev/null || true

# Iniciar stack
docker-compose -f docker-compose.observability.yml up -d
```

### 2. Acessar Dashboards

- **Grafana**: http://localhost:3000
  - Usuário: `admin`
  - Senha: `hermesadmin`

- **Prometheus**: http://localhost:9090

- **Loki**: http://localhost:3100

### 3. Verificar Status

```bash
docker-compose -f docker-compose.observability.yml ps
```

## Métricas Disponíveis

### Manuscripts
- `hermes_manuscripts_total{state}` - Total de manuscripts por estado

### Insights
- `hermes_insights_total{source}` - Total de insights capturados por fonte

### Synthesis
- `hermes_synthesis_total{status}` - Total de jobs de síntese
- `hermes_synthesis_success_total{cluster}` - Sínteses bem-sucedidas

### API
- `hermes_api_latency_seconds{endpoint,method}` - Latência de endpoints

### LLM
- `hermes_llm_calls_total{model,status}` - Chamadas LLM
- `hermes_llm_tokens_total{model,type}` - Tokens consumidos

## Integração no Código

### Inicializar Métricas

```rust
use beagle_hermes::observability;

// No início da aplicação
observability::init_metrics();
```

### Registrar Eventos

```rust
// Insight capturado
observability::record_insight_captured("voice");

// Job de síntese
observability::record_synthesis("success", Some("kec_entropy"));

// Chamada LLM
observability::record_llm_call("claude-sonnet-4.5", "success");

// Tokens consumidos
observability::record_llm_tokens("claude-sonnet-4.5", "input", 1500);

// Latência de API
observability::record_api_latency("/api/insights", "POST", 0.125);
```

### Expor Endpoint de Métricas

```rust
use axum::{routing::get, Router};
use beagle_hermes::observability;

let app = Router::new()
    .route("/metrics", get(observability::metrics_handler));
```

## Dashboards Grafana

### HERMES Overview
- Manuscripts por estado
- Insights capturados (24h)
- Taxa de sucesso de síntese
- Latência de API (p95)
- Chamadas LLM

### Personalização

Edite `observability/grafana/dashboards/hermes_overview.json` para adicionar novos painéis.

## Logs

### Configuração Promtail

O Promtail está configurado para coletar logs de `/var/log/*.log`.

Para logs da aplicação HERMES, configure o tracing para escrever em arquivo:

```rust
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

tracing_subscriber::registry()
    .with(
        tracing_subscriber::fmt::layer()
            .with_writer(std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("/var/log/hermes.log")?)
    )
    .init();
```

## Troubleshooting

### Prometheus não coleta métricas

1. Verifique se o endpoint `/metrics` está acessível
2. Verifique `observability/prometheus/prometheus.yml` para targets corretos
3. Verifique logs: `docker logs hermes-prometheus`

### Grafana não mostra dados

1. Verifique se Prometheus está rodando
2. Verifique datasources em Grafana (Settings → Data Sources)
3. Verifique se as métricas estão sendo expostas: `curl http://localhost:9090/api/v1/query?query=hermes_insights_total`

### Loki não recebe logs

1. Verifique se Promtail está rodando: `docker logs hermes-promtail`
2. Verifique permissões de `/var/log`
3. Verifique configuração em `observability/promtail-config.yml`

## Próximos Passos

- [ ] Configurar alertas no Prometheus
- [ ] Adicionar tracing distribuído (Tempo)
- [ ] Criar dashboards específicos por módulo
- [ ] Configurar retention policies

