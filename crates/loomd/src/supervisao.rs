//! O laço que mantém um filho vivo. Não sabe o que o filho fala — por isso serve ao codex
//! (JSON-RPC do app-server) e ao ACP (ND-JSON) sem virar abstração vazada.

use crate::event::{AgentEvent, Confidence, Kind};
use crate::trama::Trama;
use std::sync::Arc;

pub fn proximo_backoff(atual_ms: u64) -> u64 {
    (atual_ms * 2).min(15_000)
}

pub fn supervisionar<F, Fut>(lane: String, trama: Arc<Trama>, rodar: F)
where
    F: Fn() -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = std::io::Result<()>> + Send,
{
    tokio::spawn(async move {
        let mut backoff_ms = 500u64;
        loop {
            match rodar().await {
                // Subida boa zera o castigo: uma lane que ficou horas de pé e caiu uma vez
                // merece voltar em meio segundo, não no teto herdado de falhas antigas.
                Ok(()) => backoff_ms = 500,
                Err(e) => {
                    trama.append(
                        AgentEvent::new(&lane, Kind::Error, Confidence::Exact)
                            .detail(format!("filho caiu: {e}")),
                    );
                }
            }
            tokio::time::sleep(std::time::Duration::from_millis(backoff_ms)).await;
            backoff_ms = proximo_backoff(backoff_ms);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_dobra_e_para_no_teto() {
        assert_eq!(proximo_backoff(500), 1_000);
        assert_eq!(proximo_backoff(8_000), 15_000);
        assert_eq!(proximo_backoff(15_000), 15_000);
    }

    #[tokio::test]
    async fn falha_do_filho_vira_evento_e_o_laco_continua() {
        let dir = std::env::temp_dir().join(format!("loomd-sup-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let n = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let n2 = n.clone();

        supervisionar("teste".into(), t.clone(), move || {
            let n = n2.clone();
            async move {
                n.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                Err(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    "caiu de proposito",
                ))
            }
        });

        tokio::time::sleep(std::time::Duration::from_millis(1_600)).await;

        // Reentrou pelo menos uma vez depois da primeira falha: o laço não desiste.
        assert!(n.load(std::sync::atomic::Ordering::SeqCst) >= 2);
        let erros: Vec<_> = t
            .since(0, Some("teste"))
            .into_iter()
            .filter(|e| e.kind == Kind::Error)
            .collect();
        assert!(
            !erros.is_empty(),
            "a falha do filho tem de aparecer na trama"
        );
        assert!(erros[0]
            .detail
            .as_deref()
            .unwrap()
            .contains("caiu de proposito"));
        std::fs::remove_dir_all(&dir).ok();
    }
}
