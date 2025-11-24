//! BEAGLE Observability - OpenTelemetry Integration
//!
//! Configuração de tracing com OpenTelemetry para exportação de métricas
//! e traces para sistemas externos (Jaeger, Prometheus, etc.)

use anyhow::Result;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};

#[cfg(feature = "otel")]
use opentelemetry::global;
#[cfg(feature = "otel")]
use opentelemetry_sdk::{runtime, trace::TracerProvider, Resource};
#[cfg(feature = "otel")]
use tracing_opentelemetry::OpenTelemetryLayer;

/// Inicializa observabilidade com tracing estruturado
///
/// Configura:
/// - Tracing com spans e eventos
/// - Exportação JSON estruturada (se RUST_LOG_JSON=1)
/// - OpenTelemetry (se feature "otel" habilitada e OTLP_ENDPOINT configurado)
pub fn init_observability() -> Result<()> {
    let filter = EnvFilter::from_default_env().add_directive("beagle=info".parse().unwrap());

    // Se RUST_LOG_JSON=1, usa formato JSON estruturado
    let use_json = std::env::var("RUST_LOG_JSON")
        .map(|v| v == "1" || v.to_lowercase() == "true")
        .unwrap_or(false);

    #[cfg(feature = "otel")]
    {
        // Configura OpenTelemetry se feature habilitada
        let resource = Resource::new(vec![
            opentelemetry::KeyValue::new("service.name", "beagle"),
            opentelemetry::KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
        ]);

        let otlp_endpoint = std::env::var("OTLP_ENDPOINT").ok();

        let tracer_provider = if let Some(endpoint) = otlp_endpoint {
            let exporter = opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(endpoint);

            TracerProvider::builder()
                .with_batch_exporter(exporter, runtime::Tokio)
                .with_resource(resource)
                .build()
        } else {
            TracerProvider::builder()
                .with_simple_exporter(
                    opentelemetry_sdk::export::trace::stdout::StdoutExporter::default(),
                )
                .with_resource(resource)
                .build()
        };

        global::set_tracer_provider(tracer_provider);
        let otel_layer = OpenTelemetryLayer::new(global::tracer("beagle"));

        if use_json {
            Registry::default()
                .with(filter)
                .with(otel_layer)
                .with(fmt::layer().json())
                .init();
        } else {
            Registry::default()
                .with(filter)
                .with(otel_layer)
                .with(fmt::layer().with_target(false))
                .init();
        }

        tracing::info!(
            "Observabilidade inicializada (OTLP: {}, JSON: {})",
            otlp_endpoint.is_some(),
            use_json
        );
    }

    #[cfg(not(feature = "otel"))]
    {
        // Sem OpenTelemetry, apenas tracing básico
        if use_json {
            Registry::default()
                .with(filter)
                .with(fmt::layer().json())
                .init();
        } else {
            Registry::default()
                .with(filter)
                .with(fmt::layer().with_target(false))
                .init();
        }

        tracing::info!("Observabilidade inicializada (JSON: {})", use_json);
    }

    Ok(())
}

/// Shutdown observability (chamar no final da aplicação)
pub fn shutdown_observability() {
    tracing::info!("Shutting down observability");
    #[cfg(feature = "otel")]
    {
        global::shutdown_tracer_provider();
    }
}
