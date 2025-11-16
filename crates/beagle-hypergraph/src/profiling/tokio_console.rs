#![allow(dead_code)]

use std::{future::Future, sync::OnceLock};

static TOKIO_CONSOLE_INIT: OnceLock<()> = OnceLock::new();

/// Inicializa o [`tokio-console`](https://github.com/tokio-rs/console) para inspeção de tarefas assíncronas.
///
/// A chamada configura o `subscriber` global do `tracing`, habilitando métricas de latência,
/// detecção de bloqueios (`blocking`) e telemetria em tempo real via CLI `tokio-console`.
///
/// # Panics
/// Poderá entrar em *panic* se uma outra camada `tracing` global já tiver sido instalada
/// antes desta função ser invocada. Em cenários de aplicações compostas, garanta que o `tokio-console`
/// seja configurado antes de outros `subscribers`.
pub fn init() {
    TOKIO_CONSOLE_INIT.get_or_init(|| {
        console_subscriber::init();
    });
}

/// Executa uma aplicação assíncrona com instrumentação do `tokio-console`.
///
/// Este *helper* recebe um *closure* que produz o `Future` principal da aplicação, garantindo
/// que a instrumentação esteja habilitada antes da execução.
///
/// # Example
/// ```no_run
/// use beagle_hypergraph::profiling::tokio_console;
/// use tokio::time::{sleep, Duration};
///
/// async fn run_app() {
///     sleep(Duration::from_secs(1)).await;
/// }
///
/// #[tokio::main]
/// async fn main() {
///     tokio_console::run_with_console(run_app).await;
/// }
/// ```
pub async fn run_with_console<F, Fut>(factory: F) -> Fut::Output
where
    F: FnOnce() -> Fut,
    Fut: Future,
{
    init();
    factory().await
}
