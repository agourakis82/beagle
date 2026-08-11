//! Cliente ACP — Agent Client Protocol.
//!
//! 🚨 A INVERSÃO IMPORTA: o adaptador (`claude-agent-acp`, Node) é o SERVIDOR; o loomd é o
//! CLIENTE. É o papel que o Zed ocupa, e foi ele que motivou trocar `stream-json` por protocolo
//! aberto: ACP é UMA tradução para N agentes (Codex e Gemini também têm adaptador), enquanto
//! `stream-json` seria o segundo dialeto artesanal deste crate.
//!
//! Enquadramento: ND-JSON, uma mensagem por linha. Não há `Content-Length`.

use crate::event::{AgentEvent, Confidence, Kind};
use crate::trama::Trama;
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{oneshot, Mutex};

const ID_INIT: u64 = 1;
const ID_SESSAO: u64 = 2;
const ID_MODO: u64 = 3;

pub struct AcpLane {
    pub lane: String,
    stdin: Arc<Mutex<Option<tokio::process::ChildStdin>>>,
    /// Aprovações penduradas: id JSON-RPC → quem espera a decisão do operador.
    ///
    /// `Some(true)` permite, `Some(false)` nega, `None` é cancelamento — nunca uma string
    /// livre. Um sentinel de texto (`"allow"` vs. qualquer outra coisa) tem a mesma classe de
    /// defeito que escolher a opção pela posição: um valor futuro fora do vocabulário esperado
    /// vira rejeição silenciosa em vez de erro.
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<Option<bool>>>>>,
    sessao: Arc<Mutex<Option<String>>>,
    proximo_id: Arc<Mutex<u64>>,
    trama: Arc<Trama>,
    modo: String,
    cwd: String,
}

/// Parte um bloco cru em mensagens. Linha vazia é ignorada; linha ilegível é DESCARTADA e não
/// derruba nada — regra já vigente no `codex.rs`, porque o vocabulário cresce e o transporte
/// pode intercalar ruído. Cegueira total é pior que informação parcial.
pub fn linhas_ndjson(bruto: &str) -> Vec<serde_json::Value> {
    bruto
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .filter_map(|l| serde_json::from_str(l).ok())
        .collect()
}

/// As mensagens de abertura, em ordem. **Função pura de propósito**: é o único jeito de assertar
/// que o `session/set_mode` está lá sem subir um Node. Ver o teste da mutação 1.
pub fn mensagens_de_abertura(
    sessao: Option<&str>,
    modo: &str,
    cwd: &str,
) -> Vec<serde_json::Value> {
    // `fs/*` FALSO de propósito: medido no censo que o agente nunca chamou `fs/read_text_file`
    // — ele usa a ferramenta `Read` dele. A capacidade serve a editor com buffer sujo, que não é
    // o nosso caso, e prometer o que não se usa é dívida.
    let mut v = vec![serde_json::json!({
        "jsonrpc": "2.0", "id": ID_INIT, "method": "initialize",
        "params": {
            "protocolVersion": 1,
            "clientCapabilities": {"fs": {"readTextFile": false, "writeTextFile": false}}
        }
    })];
    match sessao {
        Some(sid) => {
            v.push(serde_json::json!({
                "jsonrpc":"2.0","id":ID_SESSAO,"method":"session/load",
                "params":{"sessionId": sid, "cwd": cwd, "mcpServers": []}
            }));
            // Sessão conhecida: o modo já pode ir junto. Sem sessão, ele vai quando a resposta
            // do `session/new` trouxer o id — em `on_message`.
            v.push(serde_json::json!({
                "jsonrpc":"2.0","id":ID_MODO,"method":"session/set_mode",
                "params":{"sessionId": sid, "modeId": modo}
            }));
        }
        None => v.push(serde_json::json!({
            "jsonrpc":"2.0","id":ID_SESSAO,"method":"session/new",
            "params":{"cwd": cwd, "mcpServers": []}
        })),
    }
    v
}

/// Que tipo de mensagem JSON-RPC é esta?
///
/// 🚨 `method` PRIMEIRO. Ids de quem chama e de quem responde são espaços SEPARADOS: o adaptador
/// numera os pedidos dele a partir de 0, então o `id` dele colide com os meus (`ID_SESSAO = 2`).
/// Testar id antes de method fazia o 3º pedido dele (`session/request_permission`, id 2) ser
/// tratado como resposta de sessão e ser ENGOLIDO — o turno pendurava para sempre. Reproduzido
/// duas vezes ao vivo. A regra do protocolo: mensagem COM `method` é pedido ou notificação; SEM
/// `method` e com `id` é resposta.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mensagem {
    /// Tem `method` e `id`: espera resposta minha.
    Pedido,
    /// Sem `method`: é `result`/`error` de um pedido MEU.
    Resposta,
    /// Tem `method`, sem `id`: não espera resposta.
    Notificacao,
}

pub fn classificar(m: &serde_json::Value) -> Mensagem {
    let tem_method = m.get("method").is_some();
    let tem_id = m.get("id").is_some();
    match (tem_method, tem_id) {
        (true, true) => Mensagem::Pedido,
        (true, false) => Mensagem::Notificacao,
        (false, _) => Mensagem::Resposta,
    }
}

/// A resposta de `session/new`/`session/load` deve disparar `set_mode`?
///
/// 🚨 SÓ quando a sessão era DESCONHECIDA. No caminho de sessão conhecida o `set_mode` já foi
/// enfileirado estaticamente por `mensagens_de_abertura` (ali existe `sessionId` para usar), e
/// disparar de novo mandaria duas requisições com o mesmo id JSON-RPC.
pub fn deve_fixar_modo_na_resposta(sessao_previa: Option<&str>) -> bool {
    sessao_previa.is_none()
}

impl AcpLane {
    pub fn spawn(lane: &str, bin: &str, cwd: &str, modo: &str, trama: Arc<Trama>) -> Arc<Self> {
        // A sessão vem da TRAMA na subida fria, igual ao codex: o daemon é descartável, a
        // sessão não. `session/load` é capacidade anunciada (`loadSession: true`), então
        // retomar é chamada de protocolo e não heurística.
        let s0 = trama.session_of(lane);
        if let Some(s) = &s0 {
            eprintln!("[loomd] lane {lane}: sessao ACP anotada na trama, vou carregar: {s}");
        }
        let me = Arc::new(Self {
            lane: lane.to_string(),
            stdin: Arc::new(Mutex::new(None)),
            pending: Arc::new(Mutex::new(HashMap::new())),
            sessao: Arc::new(Mutex::new(s0)),
            proximo_id: Arc::new(Mutex::new(10)),
            trama: trama.clone(),
            modo: modo.to_string(),
            cwd: cwd.to_string(),
        });
        let (b, c) = (bin.to_string(), cwd.to_string());
        let this = me.clone();
        crate::supervisao::supervisionar(lane.to_string(), trama, move || {
            let (this, b, c) = (this.clone(), b.clone(), c.clone());
            async move { this.run_once(&b, &c).await }
        });
        me
    }

    pub async fn session_id(&self) -> Option<String> {
        self.sessao.lock().await.clone()
    }

    /// 🚨 ACHADO 4 (crítico): a versão anterior não devolvia nada — com `stdin == None` (o
    /// daemon acabou de subir, ou está no meio de um backoff de respawn de até 15s) o payload
    /// caía no chão em silêncio, e todo chamador seguia como se tivesse falado. Propagar aqui é
    /// o único jeito de `prompt`/`interrupt`/`answer` saberem que não afirmaram um fato falso.
    async fn enviar(&self, v: serde_json::Value) -> Result<(), String> {
        let mut g = self.stdin.lock().await;
        let Some(si) = g.as_mut() else {
            return Err("adaptador ACP sem stdin (ainda nao subiu ou ja caiu)".to_string());
        };
        si.write_all(format!("{v}\n").as_bytes())
            .await
            .map_err(|e| format!("falha ao escrever no adaptador ACP: {e}"))?;
        si.flush()
            .await
            .map_err(|e| format!("falha ao dar flush no adaptador ACP: {e}"))?;
        Ok(())
    }

    /// 🚨 O CRITICAL DA REVISÃO: `spawn()` também pode falhar antes de qualquer leitura. Nesse
    /// caminho a limpeza roda aqui, explicitamente — o `?` original saía de `run_once` sem
    /// passar pelo ponto único de limpeza, e o `supervisao.rs` só registra `Kind::Error` e
    /// respawna, deixando o mapa `pending` intacto de um ciclo anterior.
    async fn run_once(&self, bin: &str, cwd: &str) -> std::io::Result<()> {
        let mut child = match tokio::process::Command::new(bin)
            .current_dir(cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                self.cancelar_pendentes("adaptador ACP nao subiu").await;
                return Err(e);
            }
        };
        let out = child.stdout.take().expect("stdout pipe");
        *self.stdin.lock().await = child.stdin.take();

        // O handshake vem da função PURA — é ela que o teste da mutação 1 asserta. Montar as
        // mensagens aqui dentro tornaria o `set_mode` inassertável sem subir um Node.
        let sid0 = self.sessao.lock().await.clone();
        for m in mensagens_de_abertura(sid0.as_deref(), &self.modo, cwd) {
            // Melhor esforço: o handshake é best-effort igual sempre foi — se o stdin cair no
            // meio dele, a leitura seguinte falha e o supervisor reconecta.
            let _ = self.enviar(m).await;
        }

        let r = self.ciclo_de_leitura(out).await;
        let _ = child.wait().await;
        r
    }

    /// O laço de leitura, genérico no leitor para que o caminho de ERRO seja testável. Um `?`
    /// solto aqui dentro sairia de `run_once` antes da limpeza — foi o defeito reportado na
    /// revisão.
    async fn ler_ate_o_fim<R: tokio::io::AsyncRead + Unpin>(&self, out: R) -> std::io::Result<()> {
        let mut lines = BufReader::new(out).lines();
        while let Some(line) = lines.next_line().await? {
            if line.trim().is_empty() {
                continue;
            }
            if std::env::var("LOOMD_DEBUG").is_ok() {
                eprintln!("[acp rx] {}", &line.chars().take(220).collect::<String>());
            }
            let Ok(m) = serde_json::from_str::<serde_json::Value>(&line) else {
                continue;
            };
            self.on_message(m).await;
        }
        Ok(())
    }

    /// Ponto ÚNICO de saída do ciclo de leitura: fim normal OU erro de I/O, a limpeza roda
    /// sempre. Genérico no leitor (via `ler_ate_o_fim`) para que o caminho de erro seja coberto
    /// por teste sem subir um Node — ver `erro_de_leitura_tambem_libera_as_pendencias`.
    async fn ciclo_de_leitura<R: tokio::io::AsyncRead + Unpin>(
        &self,
        out: R,
    ) -> std::io::Result<()> {
        let r = self.ler_ate_o_fim(out).await;
        *self.stdin.lock().await = None;
        self.cancelar_pendentes("adaptador ACP encerrou").await;
        self.trama.append(
            AgentEvent::new(&self.lane, Kind::SessionEnded, Confidence::Exact)
                .detail("adaptador ACP encerrou"),
        );
        r
    }

    async fn on_message(&self, m: serde_json::Value) {
        // 🚨 `classificar` primeiro: sem isto, o 3º `session/request_permission` do adaptador
        // (id 2, espaço dele) colide com `ID_SESSAO` (id 2, meu espaço) e é engolido aqui como
        // se fosse resposta de sessão. Só uma mensagem SEM `method` pode ser resposta minha.
        if classificar(&m) == Mensagem::Resposta
            && m.get("id").and_then(|x| x.as_u64()) == Some(ID_SESSAO)
        {
            // Resposta ao `session/new` / `session/load`: guarda a sessão e FIXA O MODO — mas
            // só quando a sessão era desconhecida. Ver `deve_fixar_modo_na_resposta`.
            if let Some(sid) = m.pointer("/result/sessionId").and_then(|x| x.as_str()) {
                let previa = self.sessao.lock().await.clone();
                *self.sessao.lock().await = Some(sid.to_string());
                let mut e = AgentEvent::new(&self.lane, Kind::SessionStarted, Confidence::Exact)
                    .detail(format!("sessao ACP {sid}"));
                e.session = Some(sid.to_string());
                self.trama.append(e);
                // Só no caminho de sessão NOVA: no de retomada o `set_mode` já foi no handshake,
                // e repetir mandaria id JSON-RPC duplicado.
                if deve_fixar_modo_na_resposta(previa.as_deref()) {
                    self.fixar_modo(sid).await;
                }
            }
            return;
        }
        // 🚨 O ACP só emite `agent_message_chunk`: NUNCA uma variante de mensagem completa.
        // A resposta de `session/prompt` é quem fecha o turno, e traz `stopReason` — é o único
        // outro ponto em que a fala acumulada tem de ser descarregada, ou a última resposta do
        // turno (a que não foi seguida por outra ferramenta) nunca chega na trama.
        if classificar(&m) == Mensagem::Resposta {
            if m.pointer("/result/stopReason").is_some() {
                self.descarregar_fala().await;
            }
            return;
        }
        let metodo = m.get("method").and_then(|x| x.as_str()).unwrap_or("");
        if classificar(&m) == Mensagem::Pedido && metodo == "session/request_permission" {
            let rpc_id = m["id"].clone();
            // `rpc_id.to_string()` num id JSON *string* devolve `"\"abc\""` — as aspas
            // vazariam para a tela. `as_str()` despe a sintaxe; ids numéricos (sem `as_str`)
            // continuam pelo `to_string()` de fallback.
            let id = rpc_id
                .as_str()
                .map(str::to_string)
                .unwrap_or_else(|| rpc_id.to_string());
            let params = m["params"].clone();

            let (tx, rx) = oneshot::channel::<Option<bool>>();
            self.pending.lock().await.insert(id.clone(), tx);

            let mut e = crate::event::from_acp_permission(&self.lane, &id, &params);
            e.session = self.sessao.lock().await.clone();
            self.trama.append(e);

            // A resposta espera o operador em outra task: bloquear aqui pararia a leitura do
            // stdout, e com ela toda a observação da lane. O turno fica parado — que é o
            // comportamento correto, e a tela mostra "esperando você", não "travado".
            //
            // 🚨 ACHADO 4: a trama só é atualizada AQUI, depois da tentativa de escrita de
            // verdade — nunca em `answer()`, que só resolve o canal e não sabe se a entrega vai
            // dar certo. Sem stdin (ou com o adaptador já caído), o registro é `Kind::Error`
            // dizendo que a resposta não pôde ser entregue — nunca "permitida"/"negada" para uma
            // entrega que não aconteceu.
            let stdin = self.stdin.clone();
            let trama = self.trama.clone();
            let (lane, id_evento) = (self.lane.clone(), id.clone());
            tokio::spawn(async move {
                // `Err` (o `Sender` foi derrubado) e `Ok(None)` (cancelamento explícito) são o
                // mesmo caso: ninguém vai responder por este pedido.
                let Ok(Some(allow)) = rx.await else {
                    return;
                };
                let opt = crate::event::acp_option_id(&params, allow);
                let resp = serde_json::json!({
                    "jsonrpc":"2.0","id":rpc_id,
                    "result":{"outcome":{"outcome":"selected","optionId":opt}}
                });
                let mut g = stdin.lock().await;
                let entregue = match g.as_mut() {
                    Some(si) => si
                        .write_all(format!("{resp}\n").as_bytes())
                        .await
                        .and(Ok(()))
                        .and(si.flush().await)
                        .is_ok(),
                    None => false,
                };
                drop(g);
                trama.append(if entregue {
                    AgentEvent::new(&lane, Kind::ApprovalAnswered, Confidence::Exact).detail(
                        format!(
                            "aprovacao {id_evento}: {}",
                            if allow { "permitida" } else { "negada" }
                        ),
                    )
                } else {
                    AgentEvent::new(&lane, Kind::Error, Confidence::Exact).detail(format!(
                        "aprovacao {id_evento}: resposta nao pode ser entregue ao adaptador \
                         (sem stdin ou falha de escrita)"
                    ))
                });
            });
            return;
        }
        let _ = self.traduzir(&m).await;
    }

    /// 🚨 SEM ISTO A TABELA DE APROVAÇÃO É CÓDIGO MORTO.
    ///
    /// Medido: `session/new` devolve `currentModeId: "bypassPermissions"`, e nesse modo o
    /// `session/request_permission` NÃO DISPARA UMA VEZ — o próprio SDK avisa no stderr que
    /// `canUseTool` fica sombreado. Escrito por dedução, a tela de aprovação ficaria vazia e a
    /// conclusão seria "o ACP não emite permissão".
    async fn fixar_modo(&self, sid: &str) {
        // Best-effort igual sempre foi: se falhar aqui, o próximo handshake (reconexão) manda de
        // novo — não há fato novo sendo gravado na trama neste caminho.
        let _ = self
            .enviar(serde_json::json!({
                "jsonrpc":"2.0","id":ID_MODO,"method":"session/set_mode",
                "params":{"sessionId": sid, "modeId": self.modo}
            }))
            .await;
    }

    /// Publica a fala acumulada como um `AgentMessage` inteiro, e limpa o buffer — numa só
    /// operação (`Trama::tomar_delta`), para nunca ficar no meio do caminho entre "publicado" e
    /// "descartado". `None` quando o buffer estava vazio: não inventa evento sem texto.
    ///
    /// 🚨 MEDIDO ao vivo (Task 8): o adaptador emite SOMENTE `agent_message_chunk` — nunca uma
    /// variante de mensagem completa. O desenho anterior tratava o chunk como delta esperando um
    /// evento completo que não existe, e a trama nunca via o que o agente disse. Chamada em DOIS
    /// pontos: quando um `tool_call` chega (a fala antes da ferramenta é um enunciado completo) e
    /// quando o turno termina (a resposta de `session/prompt`, que traz `stopReason` — a ÚNICA
    /// fala que não é seguida de outra ferramenta e por isso não teria outro gatilho).
    async fn descarregar_fala(&self) {
        if let Some(t) = self.trama.tomar_delta(&self.lane) {
            let mut e =
                AgentEvent::new(&self.lane, Kind::AgentMessage, Confidence::Exact).with_text(t);
            e.session = self.sessao.lock().await.clone();
            self.trama.append(e);
        }
    }

    async fn traduzir(&self, m: &serde_json::Value) -> Option<()> {
        if m.get("method").and_then(|x| x.as_str()) != Some("session/update") {
            return None;
        }
        let u = m.pointer("/params/update")?;
        let variante = u
            .get("sessionUpdate")
            .and_then(|x| x.as_str())
            .unwrap_or("");
        if variante == "agent_message_chunk" {
            if let Some(t) = u.pointer("/content/text").and_then(|x| x.as_str()) {
                self.trama.acumular_delta(&self.lane, t);
            }
            return Some(());
        }
        // 🚨 ACHADO 5: pensamento e fala não podem dividir o mesmo buffer. Nenhuma fixture ao
        // vivo tinha `agent_thought_chunk` (código latente, tratado mas nunca exercitado), mas
        // se o thinking for ligado num turno, misturar os dois faria o raciocínio interno entrar
        // em `text` como se fosse o que o agente de fato disse — e `resumir` poderia citá-lo no
        // card. ESCOLHA: descartar, não um buffer separado — o `codex.rs` já trata `reasoning`
        // do mesmo jeito (`from_codex_notification` devolve `None` para o item inteiro), e hoje
        // não há nenhuma superfície na tela para mostrar "pensamento" separado de "fala"; um
        // buffer paralelo guardaria um estado que ninguém lê.
        if variante == "agent_thought_chunk" {
            return Some(());
        }
        // A fala anterior à ferramenta é um enunciado completo: DESCARREGA, nunca descarta —
        // ver `descarregar_fala`.
        if variante == "tool_call" {
            self.descarregar_fala().await;
        }
        if let Some(mut e) = crate::event::from_acp_update(&self.lane, u) {
            e.session = self.sessao.lock().await.clone();
            self.trama.append(e);
        }
        Some(())
    }

    /// Construtor só de teste: sem filho, sem stdio. O vazamento se prova no mapa de
    /// pendências, e subir um Node de verdade tornaria o teste lento e flaky sem provar mais.
    #[cfg(test)]
    pub(crate) fn nua_para_teste(
        lane: &str,
        trama: Arc<Trama>,
        modo: &str,
        sessao: Option<&str>,
    ) -> Arc<Self> {
        Arc::new(Self {
            lane: lane.to_string(),
            stdin: Arc::new(Mutex::new(None)),
            pending: Arc::new(Mutex::new(HashMap::new())),
            sessao: Arc::new(Mutex::new(sessao.map(str::to_string))),
            proximo_id: Arc::new(Mutex::new(10)),
            trama,
            modo: modo.to_string(),
            cwd: "/tmp".into(),
        })
    }

    /// Só de teste: pluga um stdin de verdade (de um subprocesso real) numa lane `nua_para_teste`
    /// — para testes que precisam verificar o que acontece numa ENTREGA bem-sucedida, sem
    /// precisar subir o adaptador ACP de verdade.
    #[cfg(test)]
    pub(crate) async fn plugar_stdin_para_teste(&self, si: tokio::process::ChildStdin) {
        *self.stdin.lock().await = Some(si);
    }

    /// Toda aprovação pendurada é resolvida como CANCELADA antes do respawn.
    ///
    /// Sem isto, a morte do filho deixa botões na tela que não respondem a ninguém — o único
    /// ponto deste desenho em que a falha produz UI mentirosa em vez de UI ausente.
    ///
    /// O guard de `pending` é solto ANTES de enviar e de escrever na trama: os métodos da
    /// `Trama` são síncronos e não haveria deadlock segurando o lock por cima, mas não há
    /// motivo para segurar um lock `tokio` por cima de I/O quando um `Vec` intermediário resolve.
    async fn cancelar_pendentes(&self, motivo: &str) {
        let itens: Vec<(String, oneshot::Sender<Option<bool>>)> = {
            let mut g = self.pending.lock().await;
            g.drain().collect()
        };
        for (id, tx) in itens {
            let _ = tx.send(None);
            self.trama.append(
                AgentEvent::new(&self.lane, Kind::ApprovalAnswered, Confidence::Exact)
                    .detail(format!("aprovacao {id} cancelada: {motivo}")),
            );
        }
    }

    async fn novo_id(&self) -> u64 {
        let mut g = self.proximo_id.lock().await;
        *g += 1;
        *g
    }

    pub async fn prompt(&self, text: &str) -> Result<(), String> {
        let sid = self
            .sessao
            .lock()
            .await
            .clone()
            .ok_or("sessao ACP ainda nao aberta")?;
        let id = self.novo_id().await;
        // 🚨 ACHADO 4: `enviar` agora PROPAGA se não havia stdin — e o `?` aqui garante que a
        // trama só afirma "o operador falou" (`Kind::UserPrompt`, `Confidence::Exact`) DEPOIS de
        // a escrita de fato acontecer. Cenário medido: o daemon sobe e o operador manda um
        // prompt em menos de um segundo, ou durante um respawn (backoff até 15s) — antes desta
        // correção o diário registrava o prompt como entregue mesmo caindo no chão.
        self.enviar(serde_json::json!({
            "jsonrpc":"2.0","id":id,"method":"session/prompt",
            "params":{"sessionId": sid, "prompt":[{"type":"text","text": text}]}
        }))
        .await?;
        let mut e =
            AgentEvent::new(&self.lane, Kind::UserPrompt, Confidence::Exact).with_text(text);
        e.session = Some(sid);
        self.trama.append(e);
        Ok(())
    }

    pub async fn interrupt(&self) -> Result<(), String> {
        let sid = self
            .sessao
            .lock()
            .await
            .clone()
            .ok_or("sessao ACP ainda nao aberta")?;
        // Propagado: sem isto a rota `/interrupt` respondia 202 mesmo quando o cancelamento
        // nunca saiu do daemon — nenhum turno de fato recebia o pedido.
        self.enviar(serde_json::json!({
            "jsonrpc":"2.0","method":"session/cancel","params":{"sessionId": sid}
        }))
        .await?;
        Ok(())
    }

    /// O que o ACP tem no lugar do `turn/steer` do codex: `promptQueueing: true`. O prompt vai
    /// para a FILA, não redireciona o turno em curso. Mesmo canal do `prompt` de propósito —
    /// dois caminhos para a mesma ação divergem.
    pub async fn enfileirar(&self, text: &str) -> Result<(), String> {
        self.prompt(text).await
    }

    /// 🚨 ACHADO 4: NÃO grava mais o fato "aprovacao X: permitida/negada" aqui. Antes desta
    /// correção o evento ia para a trama imediatamente após `tx.send`, mas a ENTREGA de fato ao
    /// adaptador acontece numa task separada (a que espera `rx` em `on_message`) — se o stdin
    /// tivesse caído entre o pedido e a resposta, o diário afirmaria uma entrega que nunca
    /// aconteceu. Agora só o canal é resolvido aqui; quem escreve o fato na trama é a task de
    /// entrega, depois de tentar de verdade.
    pub async fn answer(&self, approval_id: &str, allow: bool) -> Result<(), String> {
        let tx = self
            .pending
            .lock()
            .await
            .remove(approval_id)
            .ok_or_else(|| format!("aprovacao {approval_id} nao esta pendente"))?;
        tx.send(Some(allow))
            .map_err(|_| format!("aprovacao {approval_id}: ninguem esta esperando a resposta"))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ndjson_parte_por_linha_e_ignora_ruido() {
        let bruto = "{\"a\":1}\n\n nao e json \n{\"b\":2}\n";
        let v = linhas_ndjson(bruto);
        assert_eq!(
            v.len(),
            2,
            "duas mensagens legiveis, o ruido nao conta e nao mata"
        );
        assert_eq!(v[0]["a"], 1);
        assert_eq!(v[1]["b"], 2);
    }

    #[test]
    fn ndjson_vazio_nao_produz_nada() {
        assert!(linhas_ndjson("").is_empty());
        assert!(linhas_ndjson("\n\n\n").is_empty());
    }

    /// 🚨 A MUTAÇÃO 1 DO SPEC, fechada por teste unitário e não só pela prova ao vivo.
    ///
    /// O adaptador nasce em `bypassPermissions`; nesse modo `session/request_permission` não
    /// dispara nenhuma vez. Se alguém remover o `set_mode`, TODA a tabela de aprovação vira
    /// código morto e a única evidência seria uma tela vazia — que se lê como "o ACP não pede
    /// permissão". O handshake é função PURA justamente para que isso seja assertável.
    #[test]
    fn o_handshake_manda_set_mode_e_ele_e_o_ultimo() {
        let ms = mensagens_de_abertura(Some("sess-1"), "default", "/workspace/.wt/claude-4");
        let metodos: Vec<&str> = ms
            .iter()
            .map(|m| m["method"].as_str().unwrap_or(""))
            .collect();
        assert_eq!(
            metodos,
            vec!["initialize", "session/load", "session/set_mode"]
        );
        let sm = ms.last().unwrap();
        assert_eq!(sm["params"]["modeId"], "default");
        assert_eq!(sm["params"]["sessionId"], "sess-1");
    }

    #[test]
    fn sem_sessao_conhecida_o_handshake_abre_uma_nova() {
        let ms = mensagens_de_abertura(None, "auto", "/workspace/.wt/claude-4");
        let metodos: Vec<&str> = ms
            .iter()
            .map(|m| m["method"].as_str().unwrap_or(""))
            .collect();
        // Sem sessão ainda não há `sessionId` para o `set_mode`: ele vai quando a resposta
        // do `session/new` chegar. Duas mensagens aqui, e a segunda é `session/new`.
        assert_eq!(metodos, vec!["initialize", "session/new"]);
        assert_eq!(ms[1]["params"]["cwd"], "/workspace/.wt/claude-4");
    }

    #[test]
    fn set_mode_na_resposta_so_quando_a_sessao_era_nova() {
        assert!(
            deve_fixar_modo_na_resposta(None),
            "sessao nova: o handshake nao mandou"
        );
        assert!(
            !deve_fixar_modo_na_resposta(Some("sess-1")),
            "retomada: ja foi no handshake"
        );
    }

    #[test]
    fn fs_e_declarado_falso_porque_o_agente_nunca_chama() {
        let ms = mensagens_de_abertura(None, "default", "/tmp");
        let caps = &ms[0]["params"]["clientCapabilities"]["fs"];
        assert_eq!(caps["readTextFile"], false);
        assert_eq!(caps["writeTextFile"], false);
    }

    /// O VAZAMENTO. É o único ponto deste desenho em que a falha produz UI MENTIROSA em vez de
    /// UI ausente: um botão na tela do Mission Control que não responde a ninguém, para sempre.
    #[tokio::test]
    async fn morte_do_filho_resolve_toda_aprovacao_pendente() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", None);

        let (tx, mut rx) = oneshot::channel::<Option<bool>>();
        lane.pending.lock().await.insert("77".into(), tx);

        lane.cancelar_pendentes("adaptador morreu").await;

        assert!(
            lane.pending.lock().await.is_empty(),
            "nenhuma pendencia pode sobrar"
        );
        assert!(
            rx.try_recv().is_ok(),
            "quem esperava a decisao tem de ser liberado"
        );
        let resp: Vec<_> = t
            .since(0, Some("claude-4"))
            .into_iter()
            .filter(|e| e.kind == Kind::ApprovalAnswered)
            .collect();
        assert_eq!(
            resp.len(),
            1,
            "a trama tem de registrar que a pendencia MORREU"
        );
        assert!(resp[0]
            .detail
            .as_deref()
            .unwrap()
            .contains("adaptador morreu"));
        std::fs::remove_dir_all(&dir).ok();
    }

    /// Leitor que devolve erro de I/O na primeira leitura — sem escrever uma linha sequer.
    /// Simula a queda do adaptador NO MEIO da leitura, o caminho que o `?` solto em
    /// `run_once` costumava escapar sem passar pela limpeza.
    #[derive(Default)]
    struct LeitorQueCai;

    impl tokio::io::AsyncRead for LeitorQueCai {
        fn poll_read(
            self: std::pin::Pin<&mut Self>,
            _cx: &mut std::task::Context<'_>,
            _buf: &mut tokio::io::ReadBuf<'_>,
        ) -> std::task::Poll<std::io::Result<()>> {
            std::task::Poll::Ready(Err(std::io::Error::other("queda simulada")))
        }
    }

    /// 🚨 O CRITICAL DA REVISÃO: `ler_ate_o_fim` propaga o erro com `?` — e se `ciclo_de_leitura`
    /// não tivesse um ponto único de saída, esse `?` sairia de `run_once` ANTES da limpeza,
    /// deixando `pending` intacto para o próximo `spawn` do supervisor. O adaptador novo
    /// escreveria a resposta com um `rpc_id` que ele nunca emitiu, e a trama registraria
    /// "aprovacao X: permitida" — a UI mentirosa.
    #[tokio::test]
    async fn erro_de_leitura_tambem_libera_as_pendencias() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-err-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", None);

        let (tx, mut rx) = oneshot::channel::<Option<bool>>();
        lane.pending.lock().await.insert("99".into(), tx);

        let r = lane.ciclo_de_leitura(LeitorQueCai).await;

        assert!(
            r.is_err(),
            "o erro de leitura tem de propagar — e o supervisor quem decide respawnar"
        );
        assert!(
            lane.pending.lock().await.is_empty(),
            "a queda NO MEIO da leitura tambem tem de limpar — nao so o fim normal"
        );
        assert!(
            rx.try_recv().is_ok(),
            "quem esperava a decisao tem de ser liberado mesmo no caminho de erro"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    // ─── Defeito 1: colisão de id JSON-RPC engolindo pedido de permissão ────────────────────

    #[test]
    fn classificar_confere_method_antes_de_id() {
        // Pedido: tem `method` E `id` — o adaptador manda isto para `session/request_permission`.
        assert_eq!(
            classificar(&serde_json::json!({
                "id": 2, "method": "session/request_permission", "params": {}
            })),
            Mensagem::Pedido
        );
        // Resposta: SEM `method`, com `id` — é o `result` de um pedido MEU.
        assert_eq!(
            classificar(&serde_json::json!({"id": 2, "result": {"sessionId": "s"}})),
            Mensagem::Resposta
        );
        // Notificação: tem `method`, sem `id`.
        assert_eq!(
            classificar(&serde_json::json!({"method": "session/update", "params": {}})),
            Mensagem::Notificacao
        );
    }

    /// 🚨 O CRITICAL: `ID_SESSAO = 2` é do MEU espaço de ids; o adaptador numera os pedidos DELE
    /// a partir de 0, independente. No 3º `session/request_permission` (id 2 no espaço dele),
    /// testar id antes de method engolia a mensagem como se fosse resposta de `session/new` — o
    /// pedido nunca era publicado, ninguém respondia, o turno pendurava para sempre.
    #[tokio::test]
    async fn pedido_de_permissao_com_id_colidindo_nao_e_engolido() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-colisao-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        // Mesmo id que `ID_SESSAO`, mas é um PEDIDO do adaptador — tem `method`.
        let msg = serde_json::json!({
            "jsonrpc": "2.0",
            "id": ID_SESSAO,
            "method": "session/request_permission",
            "params": {
                "sessionId": "sess-1",
                "toolCall": {"toolCallId": "toolu_1", "kind": "execute"},
                "options": [{"optionId": "allow", "kind": "allow_once"}]
            }
        });
        lane.on_message(msg).await;

        assert!(
            lane.pending.lock().await.contains_key("2"),
            "o pedido tem que ficar pendente — engolido silenciosamente é o defeito"
        );
        let pendentes: Vec<_> = t
            .since(0, Some("claude-4"))
            .into_iter()
            .filter(|e| e.kind == Kind::AwaitingApproval)
            .collect();
        assert_eq!(
            pendentes.len(),
            1,
            "a trama tem de publicar o pedido, nao descarta-lo"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    // ─── Defeito 2: a fala do agente nunca chegava na trama ─────────────────────────────────

    fn chunk_de_fala(texto: &str) -> serde_json::Value {
        serde_json::json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "agent_message_chunk",
                    "content": {"type": "text", "text": texto}
                }
            }
        })
    }

    /// 🚨 MEDIDO AO VIVO (Task 8): o adaptador emite SOMENTE `agent_message_chunk`, nunca uma
    /// variante de mensagem completa. O desenho anterior chamava `limpar_delta` quando um
    /// `tool_call` chegava — a fala que veio ANTES da ferramenta era DESCARTADA, não publicada.
    #[tokio::test]
    async fn tres_chunks_e_um_tool_call_publicam_uma_fala_e_depois_a_ferramenta() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-fala-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        for pedaco in ["Vou", " ler", " o arquivo"] {
            lane.traduzir(&chunk_de_fala(pedaco)).await;
        }
        let tool_call = serde_json::json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "tool_call",
                    "toolCallId": "t1",
                    "title": "Read medidas.txt",
                    "kind": "read"
                }
            }
        });
        lane.traduzir(&tool_call).await;

        let eventos = t.since(0, Some("claude-4"));
        let falas: Vec<_> = eventos
            .iter()
            .filter(|e| e.kind == Kind::AgentMessage)
            .collect();
        assert_eq!(
            falas.len(),
            1,
            "tres chunks tem de virar UMA fala, nao tres nem zero"
        );
        assert_eq!(
            falas[0].text.as_deref(),
            Some("Vou ler o arquivo"),
            "os pedacos tem de chegar concatenados NA ORDEM"
        );
        let ferramentas: Vec<_> = eventos
            .iter()
            .filter(|e| e.kind == Kind::ToolCall)
            .collect();
        assert_eq!(ferramentas.len(), 1);
        assert!(
            falas[0].seq < ferramentas[0].seq,
            "a fala tem de aparecer ANTES da ferramenta que a seguiu"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    /// A resposta de `session/prompt` traz `stopReason` — é o unico outro gatilho que existe
    /// para a fala que TERMINA o turno sem ser seguida de outra ferramenta.
    #[tokio::test]
    async fn fim_de_turno_descarrega_a_fala_pendente_e_esvazia_o_buffer() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-fim-fala-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        for pedaco in ["Pronto", ", terminei"] {
            lane.traduzir(&chunk_de_fala(pedaco)).await;
        }
        let fim = serde_json::json!({"id": 11, "result": {"stopReason": "end_turn"}});
        lane.on_message(fim).await;

        let falas: Vec<_> = t
            .since(0, Some("claude-4"))
            .into_iter()
            .filter(|e| e.kind == Kind::AgentMessage)
            .collect();
        assert_eq!(falas.len(), 1);
        assert_eq!(falas[0].text.as_deref(), Some("Pronto, terminei"));
        let st = t
            .state()
            .into_iter()
            .find(|l| l.lane == "claude-4")
            .unwrap();
        assert!(
            st.streaming_text.is_none(),
            "o buffer tem de esvaziar depois do descarregamento"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    /// Fim de turno sem chunk nenhum não pode inventar um `AgentMessage` vazio.
    #[tokio::test]
    async fn fim_de_turno_sem_fala_nao_inventa_agent_message() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-fim-vazio-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        let fim = serde_json::json!({"id": 11, "result": {"stopReason": "end_turn"}});
        lane.on_message(fim).await;

        let falas = t
            .since(0, Some("claude-4"))
            .into_iter()
            .filter(|e| e.kind == Kind::AgentMessage)
            .count();
        assert_eq!(falas, 0, "sem chunk nao ha fala para descarregar");
        std::fs::remove_dir_all(&dir).ok();
    }

    // ─── Achado 4: escrita perdida em silêncio, com rota e trama reportando sucesso ─────────

    /// O cenário concreto do achado: o daemon subiu (ou está em backoff de respawn) e o
    /// operador manda um prompt ANTES de qualquer processo existir. `nua_para_teste` é
    /// exatamente isso — `stdin == None`, sem filho nenhum.
    #[tokio::test]
    async fn prompt_sem_stdin_propaga_erro_e_nao_afirma_que_o_operador_falou() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-p4-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        let r = lane.prompt("ola, tudo bem?").await;

        assert!(
            r.is_err(),
            "sem stdin o prompt tem de FALHAR, nunca fingir que foi entregue"
        );
        let falas: Vec<_> = t
            .since(0, Some("claude-4"))
            .into_iter()
            .filter(|e| e.kind == Kind::UserPrompt)
            .collect();
        assert!(
            falas.is_empty(),
            "a trama nao pode dizer que o operador falou se a escrita nunca aconteceu"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn interrupt_sem_stdin_propaga_erro() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-i4-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        assert!(
            lane.interrupt().await.is_err(),
            "sem stdin, 202 seria mentira: nao ha turno nenhum recebendo o cancelamento"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    /// O correlato para `answer`: o canal aceita a decisão do operador (o `oneshot::send`
    /// sempre pode suceder), mas a ENTREGA de fato ao adaptador acontece numa task separada,
    /// depois. Gravar "aprovacao X: permitida" na hora de `answer` é afirmar uma entrega que
    /// ainda nem foi tentada. A trama só pode dizer o que a task de entrega de fato conseguiu.
    #[tokio::test]
    async fn resposta_de_aprovacao_sem_stdin_nao_afirma_entrega_que_nao_aconteceu() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-a4-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        let pedido = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 5,
            "method": "session/request_permission",
            "params": {
                "sessionId": "sess-1",
                "toolCall": {"toolCallId": "toolu_1", "kind": "execute"},
                "options": [{"optionId": "allow", "kind": "allow_once"}]
            }
        });
        lane.on_message(pedido).await;

        let r = lane.answer("5", true).await;
        assert!(
            r.is_ok(),
            "o canal aceitou a decisao — isto so diz que alguem vai TENTAR entregar"
        );

        // Dá tempo para a task de entrega (que roda sem stdin, e por isso falha) terminar.
        for _ in 0..40 {
            if !t.since(0, Some("claude-4")).is_empty()
                && t.since(0, Some("claude-4"))
                    .iter()
                    .any(|e| e.kind == Kind::Error || e.kind == Kind::ApprovalAnswered)
            {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        }

        let eventos = t.since(0, Some("claude-4"));
        assert!(
            !eventos.iter().any(|e| e.kind == Kind::ApprovalAnswered),
            "sem stdin a resposta NUNCA foi entregue ao adaptador — a trama nao pode dizer \
             'permitida'"
        );
        assert!(
            eventos
                .iter()
                .any(|e| e.kind == Kind::Error && e.detail.as_deref().unwrap_or("").contains("5")),
            "a falha de entrega tem de aparecer na trama, nao silêncio: {:?}",
            eventos.iter().map(|e| e.kind).collect::<Vec<_>>()
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    // ─── Achado 5: pensamento nao pode colar na fala ─────────────────────────────────────────

    fn chunk_de_pensamento(texto: &str) -> serde_json::Value {
        serde_json::json!({
            "method": "session/update",
            "params": {
                "update": {
                    "sessionUpdate": "agent_thought_chunk",
                    "content": {"type": "text", "text": texto}
                }
            }
        })
    }

    /// Nenhuma das fixtures ao vivo tinha `agent_thought_chunk` — é código LATENTE, tratado mas
    /// nunca exercitado de verdade. Num turno com thinking ligado, o desenho anterior acumulava
    /// pensamento e fala no MESMO buffer, e `descarregar_fala` publicava tudo junto como
    /// `Kind::AgentMessage` — o raciocínio interno entraria no card como se fosse o que o agente
    /// de fato disse.
    #[tokio::test]
    async fn pensamento_nunca_entra_no_texto_da_fala() {
        let dir = std::env::temp_dir().join(format!("loomd-acp-pensamento-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = AcpLane::nua_para_teste("claude-4", t.clone(), "default", Some("sess-1"));

        lane.traduzir(&chunk_de_pensamento("Deixa eu pensar nisso"))
            .await;
        lane.traduzir(&chunk_de_fala("Vou ler o arquivo")).await;
        let fim = serde_json::json!({"id": 11, "result": {"stopReason": "end_turn"}});
        lane.on_message(fim).await;

        let falas: Vec<_> = t
            .since(0, Some("claude-4"))
            .into_iter()
            .filter(|e| e.kind == Kind::AgentMessage)
            .collect();
        assert_eq!(falas.len(), 1, "so a fala vira AgentMessage");
        assert_eq!(
            falas[0].text.as_deref(),
            Some("Vou ler o arquivo"),
            "o pensamento nao pode aparecer colado na frente da fala"
        );
        std::fs::remove_dir_all(&dir).ok();
    }
}
