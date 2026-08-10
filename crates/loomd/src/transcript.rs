//! Observa uma lane TUI lendo o transcript que o Claude Code JÁ escreve.
//!
//! 🚨 O CAMINHO TEM PEGADINHA, e ela quase derrubou o desenho: cada lane tem HOME próprio. Não é
//! `~/.claude/projects/`, é `.agents/<lane>/.claude/projects/<cwd-slug>/<sessao>.jsonl`. O
//! diretório compartilhado estava parado há quatro dias enquanto as lanes escreviam milhares de
//! linhas nos delas.
//!
//! Read-only por decisão: as 3 lanes estão trabalhando com `defaultMode: auto` e o TUI intacto.
//! Isto substitui os hooks — que continuam no código para o dia em que for preciso INTERCEPTAR;
//! para OBSERVAR, o arquivo já está lá, com fidelidade total em vez de só onde o hook dispara.

use crate::trama::Trama;
use std::sync::Arc;

pub struct TranscriptTail;

/// A sessão corrente é o `.jsonl` de mtime mais novo. Sessão nova = arquivo novo, então isto
/// também é a detecção de rotação.
pub fn arquivo_mais_novo(dir: &std::path::Path) -> Option<std::path::PathBuf> {
    let mut melhor: Option<(std::time::SystemTime, std::path::PathBuf)> = None;
    for e in std::fs::read_dir(dir).ok()? {
        let p = e.ok()?.path();
        if p.extension().and_then(|x| x.to_str()) != Some("jsonl") {
            continue;
        }
        let mt = p.metadata().ok()?.modified().ok()?;
        if melhor.as_ref().map_or(true, |(m, _)| mt > *m) {
            melhor = Some((mt, p));
        }
    }
    melhor.map(|(_, p)| p)
}

/// Truncamento: se o offset guardado passou do fim do arquivo, o arquivo encolheu e o offset é
/// lixo — recomeça do zero. Arquivo pede esta guarda; socket não.
pub fn offset_seguro(offset: u64, tamanho: u64) -> u64 {
    if offset > tamanho {
        0
    } else {
        offset
    }
}

impl TranscriptTail {
    /// `base` é o diretório de projetos da lane, por exemplo
    /// `/workspace/.home/openvscode-server/.agents/claude-2/.claude/projects/-workspace-sounio`.
    pub fn spawn(lane: &str, base: &str, trama: Arc<Trama>) -> Arc<Self> {
        let (l, b) = (lane.to_string(), base.to_string());
        tokio::spawn(async move {
            let dir = std::path::PathBuf::from(&b);
            let mut atual: Option<std::path::PathBuf> = None;
            let mut offset: u64 = 0;
            loop {
                if let Some(f) = arquivo_mais_novo(&dir) {
                    // Rotação: sessão nova é arquivo novo, e o offset do anterior não vale nele.
                    if atual.as_ref() != Some(&f) {
                        atual = Some(f.clone());
                        offset = 0;
                    }
                    let tam = std::fs::metadata(&f).map(|m| m.len()).unwrap_or(0);
                    offset = offset_seguro(offset, tam);
                    if tam > offset {
                        if let Ok(bytes) = ler_de(&f, offset) {
                            offset = tam;
                            for linha in String::from_utf8_lossy(&bytes).lines() {
                                let Ok(v) = serde_json::from_str::<serde_json::Value>(linha) else {
                                    continue;
                                };
                                if let Some(e) = crate::event::from_transcript_line(&l, &v) {
                                    trama.append(e);
                                }
                            }
                        }
                    }
                }
                tokio::time::sleep(std::time::Duration::from_millis(1_500)).await;
            }
        });
        Arc::new(Self)
    }
}

fn ler_de(p: &std::path::Path, offset: u64) -> std::io::Result<Vec<u8>> {
    use std::io::{Read, Seek, SeekFrom};
    let mut f = std::fs::File::open(p)?;
    f.seek(SeekFrom::Start(offset))?;
    let mut v = Vec::new();
    f.read_to_end(&mut v)?;
    Ok(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offset_maior_que_o_arquivo_recomeca_do_zero() {
        assert_eq!(offset_seguro(500, 900), 500, "offset valido e respeitado");
        assert_eq!(offset_seguro(900, 900), 900, "fim exato nao e truncamento");
        assert_eq!(
            offset_seguro(1_000, 900),
            0,
            "arquivo encolheu: offset e lixo"
        );
    }

    #[test]
    fn escolhe_o_jsonl_de_mtime_mais_novo() {
        let dir = std::env::temp_dir().join(format!("loomd-tt-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("velha.jsonl"), "{}\n").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1_100));
        std::fs::write(dir.join("nova.jsonl"), "{}\n").unwrap();
        std::fs::write(dir.join("ruido.txt"), "nao e transcript").unwrap();

        let f = arquivo_mais_novo(&dir).expect("tem de achar um");
        assert_eq!(f.file_name().unwrap(), "nova.jsonl");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn diretorio_sem_transcript_devolve_nada() {
        let dir = std::env::temp_dir().join(format!("loomd-tt-vazio-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert!(arquivo_mais_novo(&dir).is_none());
        std::fs::remove_dir_all(&dir).ok();
    }
}
