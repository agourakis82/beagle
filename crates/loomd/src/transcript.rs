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

/// Onde o cursor `(arquivo, offset)` desta lane fica gravado: ao lado do próprio diário.
///
/// 🚨 POR QUE NÃO A TRAMA: a trama guarda FATOS semânticos (sessão, turno, aprovação) — é por
/// isso que o `codex.rs` relê `session_of` dela sem precisar de arquivo novo, e um sid de sessão
/// é ele mesmo um fato do diário. Um offset de bytes não é um fato: é contabilidade de
/// transporte deste tailer, e boa parte das linhas do transcript NUNCA produz evento (filtradas
/// por `from_transcript_line`), então não há fato correspondente na trama onde pendurar o
/// progresso — teria de alargar o `Kind`/`AgentEvent` compartilhado por toda a plataforma só
/// para um dado que mais ninguém lê. Um sidecar pequeno, específico deste tailer, é o corte mais
/// estreito.
fn caminho_cursor(trama_path: &std::path::Path, lane: &str) -> std::path::PathBuf {
    trama_path
        .parent()
        .map(std::path::Path::to_path_buf)
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join(format!("{lane}.transcript-cursor.json"))
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Cursor {
    arquivo: String,
    offset: u64,
}

fn ler_cursor(p: &std::path::Path) -> Option<Cursor> {
    let s = std::fs::read_to_string(p).ok()?;
    serde_json::from_str(&s).ok()
}

fn salvar_cursor(p: &std::path::Path, arquivo: &std::path::Path, offset: u64) {
    let c = Cursor {
        arquivo: arquivo.to_string_lossy().into_owned(),
        offset,
    };
    if let Ok(s) = serde_json::to_string(&c) {
        let _ = std::fs::write(p, s);
    }
}

/// Uma varredura: acha o arquivo corrente, lê o que cresceu desde `offset`, publica os eventos
/// e persiste o cursor. Extraído de `spawn` para ser testável sem subir uma task tokio — é a
/// mesma disciplina do `mensagens_de_abertura` em `acp.rs`.
fn varrer_uma_vez(
    dir: &std::path::Path,
    lane: &str,
    trama: &Trama,
    atual: &mut Option<std::path::PathBuf>,
    offset: &mut u64,
    cursor_path: &std::path::Path,
) {
    let Some(f) = arquivo_mais_novo(dir) else {
        return;
    };
    // Rotação: sessão nova é arquivo novo, e o offset do anterior não vale nele.
    if atual.as_ref() != Some(&f) {
        *atual = Some(f.clone());
        *offset = 0;
    }
    let tam = std::fs::metadata(&f).map(|m| m.len()).unwrap_or(0);
    *offset = offset_seguro(*offset, tam);
    if tam > *offset {
        if let Ok(bytes) = ler_de(&f, *offset) {
            *offset = tam;
            for linha in String::from_utf8_lossy(&bytes).lines() {
                let Ok(v) = serde_json::from_str::<serde_json::Value>(linha) else {
                    continue;
                };
                if let Some(e) = crate::event::from_transcript_line(lane, &v) {
                    trama.append(e);
                }
            }
            salvar_cursor(cursor_path, &f, *offset);
        }
    }
}

impl TranscriptTail {
    /// `base` é o diretório de projetos da lane, por exemplo
    /// `/workspace/.home/openvscode-server/.agents/claude-2/.claude/projects/-workspace-sounio`.
    pub fn spawn(lane: &str, base: &str, trama: Arc<Trama>) -> Arc<Self> {
        let (l, b) = (lane.to_string(), base.to_string());
        let cursor_path = caminho_cursor(trama.path(), &l);
        tokio::spawn(async move {
            let dir = std::path::PathBuf::from(&b);
            // 🚨 A SUBIDA FRIA (achado 1): sem isto o offset nasce 0 em RAM a cada reinício do
            // daemon, e o mesmo `.jsonl` — que continua sendo o de mtime mais novo — é relido do
            // byte 0, republicando tudo com seq novo. Medido ao vivo: `claude-1` com 1137
            // eventos, três reinícios = a conversa quatro vezes na trama.
            let cursor0 = ler_cursor(&cursor_path);
            let mut atual: Option<std::path::PathBuf> = cursor0
                .as_ref()
                .map(|c| std::path::PathBuf::from(&c.arquivo));
            let mut offset: u64 = cursor0.as_ref().map(|c| c.offset).unwrap_or(0);
            loop {
                varrer_uma_vez(&dir, &l, &trama, &mut atual, &mut offset, &cursor_path);
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

    // ─── Achado 1: reinicio do daemon nao pode reingerir o transcript inteiro ────────────────

    fn linha_prompt(texto: &str) -> String {
        format!(
            "{}\n",
            serde_json::json!({"type": "last-prompt", "prompt": texto})
        )
    }

    #[test]
    fn reinicio_retoma_do_cursor_persistido_em_vez_de_reingerir_tudo() {
        use crate::trama::Trama;
        use std::sync::Arc;

        let raiz = std::env::temp_dir().join(format!("loomd-tt-cursor-{}", std::process::id()));
        let base = raiz.join("projeto");
        std::fs::create_dir_all(&base).unwrap();
        std::fs::write(
            base.join("sessao.jsonl"),
            format!("{}{}", linha_prompt("um"), linha_prompt("dois")),
        )
        .unwrap();

        // Diretório SEPARADO do transcript: `trama.jsonl` também tem extensão `.jsonl`, e se
        // vivesse no mesmo diretório da lane ela mesma seria escolhida por `arquivo_mais_novo`.
        let trama_path = raiz.join("loomd").join("trama.jsonl");
        let trama = Arc::new(Trama::open(&trama_path));
        let cursor_path = caminho_cursor(trama.path(), "claude-1");

        // Primeira "subida": varre o arquivo inteiro.
        let mut atual: Option<std::path::PathBuf> = None;
        let mut offset: u64 = 0;
        varrer_uma_vez(
            &base,
            "claude-1",
            &trama,
            &mut atual,
            &mut offset,
            &cursor_path,
        );
        assert_eq!(
            trama.since(0, Some("claude-1")).len(),
            2,
            "a primeira varredura tem de ver as duas linhas"
        );

        // "Reinicio do daemon": processo novo, estado em RAM nasce do zero — só o cursor em
        // disco sobrevive. Um processo novo lê o cursor e retoma a varredura a partir dele.
        let cursor0 = ler_cursor(&cursor_path).expect("o cursor tem de ter sido persistido");
        let mut atual2: Option<std::path::PathBuf> =
            Some(std::path::PathBuf::from(&cursor0.arquivo));
        let mut offset2: u64 = cursor0.offset;
        varrer_uma_vez(
            &base,
            "claude-1",
            &trama,
            &mut atual2,
            &mut offset2,
            &cursor_path,
        );

        assert_eq!(
            trama.since(0, Some("claude-1")).len(),
            2,
            "o reinicio nao pode republicar o que ja foi visto"
        );
        std::fs::remove_dir_all(&raiz).ok();
    }
}
