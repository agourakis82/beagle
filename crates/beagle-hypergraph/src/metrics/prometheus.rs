//! Exportador de métricas baseado no ecossistema Prometheus.
//!
//! Este módulo provê uma fachada de alto nível para coletar e expor métricas
//! operacionais do hipergrafo Beagle, viabilizando integração com Prometheus,
//! Grafana e demais plataformas de observabilidade compatíveis com o formato
//! [OpenMetrics](https://openmetrics.io/).

#![allow(dead_code)]

use std::time::Duration;

use prometheus::{Counter, Encoder, Histogram, HistogramOpts, Opts, Registry, TextEncoder};
use thiserror::Error;

/// Erros possíveis durante a gestão de métricas Prometheus.
#[derive(Debug, Error)]
pub enum MetricsError {
    /// Erro originado na criação ou registro de coletores Prometheus.
    #[error("falha Prometheus: {0}")]
    Prometheus(#[from] prometheus::Error),
    /// Falha na serialização das métricas para texto.
    #[error("erro de codificação Prometheus: {0}")]
    Encoding(#[from] std::io::Error),
    /// Falha na conversão do buffer de bytes para `String` UTF-8.
    #[error("erro UTF-8 ao serializar métricas: {0}")]
    Utf8(#[from] std::string::FromUtf8Error),
}

/// Conjunto básico de métricas operacionais expostas pelo hipergrafo.
pub struct Metrics {
    registry: Registry,
    /// Contador cumulativo de nós persistidos.
    pub nodes_created: Counter,
    /// Contador cumulativo de consultas atendidas.
    pub queries_executed: Counter,
    /// Histograma de latência de consultas em segundos.
    pub query_duration: Histogram,
}

impl Metrics {
    /// Instancia as métricas padrão e as registra no `Registry` informado.
    pub fn new(registry: &Registry) -> Result<Self, MetricsError> {
        let nodes_created = Counter::with_opts(Opts::new(
            "beagle_nodes_created_total",
            "Total acumulado de nós criados no hipergrafo",
        ))?;
        registry.register(Box::new(nodes_created.clone()))?;

        let queries_executed = Counter::with_opts(Opts::new(
            "beagle_queries_executed_total",
            "Total acumulado de consultas executadas",
        ))?;
        registry.register(Box::new(queries_executed.clone()))?;

        let query_duration_opts = HistogramOpts::new(
            "beagle_query_duration_seconds",
            "Distribuição de latência das consultas ao hipergrafo",
        )
        .buckets(vec![
            0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0,
        ]);
        let query_duration = Histogram::with_opts(query_duration_opts)?;
        registry.register(Box::new(query_duration.clone()))?;

        Ok(Self {
            registry: registry.clone(),
            nodes_created,
            queries_executed,
            query_duration,
        })
    }

    /// Referência ao `Registry` interno (útil para integrações externas).
    pub fn registry(&self) -> &Registry {
        &self.registry
    }

    /// Incrementa o contador de nós criados.
    pub fn inc_nodes_created(&self) {
        self.nodes_created.inc();
    }

    /// Acrescenta quantidade arbitrária de nós criados (batch).
    pub fn add_nodes_created(&self, count: u64) {
        if count > 0 {
            self.nodes_created.inc_by(count as f64);
        }
    }

    /// Observa estatísticas de uma consulta concluída.
    pub fn observe_query(&self, duration: Duration) {
        self.queries_executed.inc();
        self.query_duration.observe(duration.as_secs_f64());
    }

    /// Serializa as métricas atualmente registradas no formato de texto Prometheus.
    pub fn gather(&self) -> Result<String, MetricsError> {
        let encoder = TextEncoder::new();
        let metric_families = self.registry.gather();
        let mut buffer = Vec::new();
        encoder.encode(&metric_families, &mut buffer)?;
        Ok(String::from_utf8(buffer)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn metrics_are_registered_and_serialized() {
        let registry = Registry::new();
        let metrics = Metrics::new(&registry).expect("registro de métricas deve funcionar");

        metrics.inc_nodes_created();
        metrics.add_nodes_created(2);
        metrics.observe_query(Duration::from_millis(42));

        let output = metrics.gather().expect("serialização deve gerar texto");
        assert!(
            output.contains("beagle_nodes_created_total"),
            "texto deve conter contador de nós"
        );
        assert!(
            output.contains("beagle_queries_executed_total"),
            "texto deve conter contador de consultas"
        );
        assert!(
            output.contains("beagle_query_duration_seconds_bucket"),
            "histograma deve ser exportado no formato Prometheus"
        );
    }
}
