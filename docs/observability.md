## Stack de Observabilidade Beagle

### Componentes Principais
- **Prometheus**: coleta métricas expostas em `/metrics` pelo `beagle-server` e pelo `jaeger`.
- **Grafana**: consome a fonte de dados Prometheus e publica o dashboard `Beagle Observability`.
- **Jaeger**: agrega e disponibiliza *distributed traces* (coletor OTLP habilitado).

### Provisionamento Local (Docker Compose)
1. **Executar infraestrutura core**  
   ```
   docker compose up -d
   ```
2. **Subir observabilidade**  
   ```
   docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
   ```
   - Prometheus: `http://localhost:9090`
   - Grafana: `http://localhost:3001` (admin/admin)
   - Jaeger UI: `http://localhost:16686`
3. **Importar dashboard**  
   O arquivo `observability/grafana/dashboards/dashboard.json` é provisionado automaticamente; alterações podem ser feitas pela UI (persistem via *allowUiUpdates*).

### Deploy em Kubernetes
- Manifestos em `k8s/monitoring/prometheus.yaml` criam namespace `monitoring`, RBAC mínimo e `Deployment` do Prometheus com descoberta automática de `beagle-server` (label `app=beagle-server`).
- Recomenda-se aplicar com `kubectl apply -f k8s/monitoring/prometheus.yaml`.
- Grafana e Jaeger podem ser instalados via Helm Charts oficiais ou replicando a topologia do Docker Compose.

### Fluxo de Validação
1. **Métricas**: Prometheus deve responder em `/-/healthy`; verifique que o *target* `beagle-server` está `UP` e que o endpoint `/metrics` retorna contadores em tempo real.
2. **Grafana**: Dashboard deve exibir:
   - `Throughput (req/s)` usando `sum(rate(http_requests_total[5m]))`.
   - `Latência de Consulta (P50/P95)` derivada de `beagle_query_duration_seconds_bucket`.
   - `Taxa de Erros 5xx` baseada em `http_requests_total{status=~"5.."}`.
   - Tabela com distribuição de métodos/status.
3. **Traces**: Configure o *SDK* OpenTelemetry do serviço para enviar para `http://localhost:4317`. Valide no Jaeger UI que os *spans* estão presentes e correlacionados com as métricas.

### Observabilidade Cruzada
- *Latency ↔ Traces*: use a combinação de `histogram_quantile` e spans Jaeger para drivar RCA de regressões.
- *Throughput ↔ Errors*: spikes em `http_requests_total` com status 5xx devem ser investigados com logs e traces correlatos.
- *Dashboards*: exporte snapshots para compliance (ABNT NBR 15906) quando necessário.

### Métricas Multimodais (Semana 5)
- **Latência de fusão** (`beagle_multimodal_fuse_latency_seconds`): histograma com *buckets* de micro a sub-segundos, alinhado às metas de regressão de performance.
- **Fusões malsucedidas** (`beagle_multimodal_fuse_failures_total`): contador para compor *error budget* de 99,9% uptime, segmentável por `strategy`.
- **Modalidades ausentes** (`beagle_multimodal_missing_modalities`): *gauge* atualizado por operação para auditar cobertura de fontes.
- **Norma pós-fusão** (`beagle_multimodal_fused_norm`): garante estabilidade do espaço vetorial; monitorar desvios >2% como alerta amarelo.
- **Tracing**: cada chamada `FusionLayer::fuse` emite span `beagle.multimodal.fuse` com campos `strategy`, `modalities_present` e `latency_ms`.
- **Logging estruturado**: logger `slog` emite eventos `fusion_success`/`fusion_failure` com dados para correlação com Prometheus e Jaeger.

