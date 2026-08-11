//! O laço que mantém um filho vivo. Não sabe o que o filho fala — por isso serve ao codex
//! (JSON-RPC do app-server) e ao ACP (ND-JSON) sem virar abstração vazada.

use crate::event::{AgentEvent, Confidence, Kind};
use crate::trama::Trama;
use std::sync::Arc;

pub fn proximo_backoff(atual_ms: u64) -> u64 {
    (atual_ms * 2).min(15_000)
}

/// Ciclo mais curto que isto, mesmo terminando com sucesso, não é saudável — é um filho que
/// nasceu e morreu sem fazer nada (um adaptador que imprime `--help` e sai com status 0, por
/// exemplo). Ver `ciclo_e_saudavel`.
const CICLO_MINIMO_SAUDAVEL_MS: u128 = 2_000;

/// 🚨 ACHADO 6: um `Ok(())` sozinho não prova vivacidade — só prova que o processo terminou sem
/// erro, o que também é verdade para um filho que nasce e morre na hora. Função separada para
/// ser testável sem depender de tempo real de execução do `supervisionar`.
fn ciclo_e_saudavel(sucesso: bool, duracao: std::time::Duration) -> bool {
    sucesso && duracao.as_millis() >= CICLO_MINIMO_SAUDAVEL_MS
}

pub fn supervisionar<F, Fut>(lane: String, trama: Arc<Trama>, rodar: F)
where
    F: Fn() -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = std::io::Result<()>> + Send,
{
    tokio::spawn(async move {
        let mut backoff_ms = 500u64;
        loop {
            let inicio = std::time::Instant::now();
            let resultado = rodar().await;
            let duracao = inicio.elapsed();
            match resultado {
                Ok(()) if ciclo_e_saudavel(true, duracao) => {
                    // Subida boa zera o castigo: uma lane que ficou horas de pé e caiu uma vez
                    // merece voltar em meio segundo, não no teto herdado de falhas antigas.
                    backoff_ms = 500;
                }
                Ok(()) => {
                    // Sucesso rápido demais: sem isto, um adaptador que sobe e sai na hora com
                    // status 0 reiniciava a cada 500ms para sempre — Ok zerava o backoff e cada
                    // volta gravava um SessionEnded, ~2 eventos/s, sem que o board dissesse
                    // `error` nenhuma vez. Trata como falha: nem reseta o backoff, nem deixa o
                    // ciclo passar em silêncio.
                    trama.append(
                        AgentEvent::new(&lane, Kind::Error, Confidence::Exact).detail(format!(
                            "filho saiu com sucesso em {duracao:?}, curto demais para ser \
                             saudavel — tratado como falha"
                        )),
                    );
                }
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
                Err(std::io::Error::other("caiu de proposito"))
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

    // ─── Achado 6: sucesso imediato demais e um laco quente sem sinal ────────────────────────

    /// Um adaptador que imprime help e sai com sucesso na hora — o cenário concreto do achado —
    /// tem de contar como falha e aparecer na trama. Sem isto ele reinicia a cada 500ms para
    /// sempre (`Ok` zera o backoff), gravando ~2 `SessionEnded`/s, e o board nunca diz `error`.
    #[tokio::test]
    async fn ciclo_curto_com_sucesso_conta_como_falha_e_aparece_na_trama() {
        let dir = std::env::temp_dir().join(format!("loomd-sup6-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));

        supervisionar("rapido".into(), t.clone(), move || async move {
            // Sucesso IMEDIATO: nenhum trabalho de verdade, como um binário errado que só
            // imprime `--help` e sai com status 0.
            Ok(())
        });

        tokio::time::sleep(std::time::Duration::from_millis(700)).await;

        let erros: Vec<_> = t
            .since(0, Some("rapido"))
            .into_iter()
            .filter(|e| e.kind == Kind::Error)
            .collect();
        assert!(
            !erros.is_empty(),
            "um ciclo saudavel nao pode durar menos que o minimo — a trama tem de dizer Error, \
             nao ficar muda"
        );
        std::fs::remove_dir_all(&dir).ok();
    }
}
