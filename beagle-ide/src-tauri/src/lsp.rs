//! Language Server Protocol (LSP) Client para Rust e Julia
//! Gerencia comunicação com rust-analyzer e Julia LanguageServer

use anyhow::{Context, Result};
use lsp_types::{
    ClientCapabilities, CompletionItem, CompletionOptions, CompletionParams, DidChangeTextDocumentParams,
    DidOpenTextDocumentParams, DocumentSymbolParams, GotoDefinitionParams, HoverParams, InitializeParams,
    Position, ServerCapabilities, TextDocumentContentChangeEvent, TextDocumentIdentifier,
    TextDocumentItem, TextDocumentPositionParams, Url,
};
use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command as AsyncCommand;
use tokio_stream::wrappers::LinesStream;
use tokio_stream::StreamExt;
use tracing::{error, info, warn};

#[derive(Debug, Clone)]
pub enum LanguageServer {
    RustAnalyzer,
    JuliaLanguageServer,
}

#[derive(Debug)]
pub struct LspClient {
    language: LanguageServer,
    child: Option<Child>,
    root_uri: Option<Url>,
    capabilities: Option<ServerCapabilities>,
    next_request_id: u64,
}

impl LspClient {
    /// Cria novo cliente LSP
    pub fn new(language: LanguageServer, root_path: Option<PathBuf>) -> Result<Self> {
        let root_uri = root_path
            .as_ref()
            .map(|p| Url::from_file_path(p).unwrap());

        Ok(Self {
            language,
            child: None,
            root_uri,
            capabilities: None,
            next_request_id: 1,
        })
    }

    /// Inicia servidor LSP
    pub async fn start(&mut self) -> Result<()> {
        info!("Iniciando servidor LSP: {:?}", self.language);

        let (command, args) = match self.language {
            LanguageServer::RustAnalyzer => {
                // Tenta encontrar rust-analyzer no PATH ou via cargo
                let rust_analyzer = find_rust_analyzer().await?;
                (rust_analyzer, vec![])
            }
            LanguageServer::JuliaLanguageServer => {
                // Julia LanguageServer via julia
                let julia = find_julia().await?;
                (
                    julia,
                    vec![
                        "-e".to_string(),
                        "using LanguageServer; runserver()".to_string(),
                    ],
                )
            }
        };

        let mut child = AsyncCommand::new(&command)
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .with_context(|| format!("Falha ao iniciar servidor LSP: {:?}", self.language))?;

        info!("Servidor LSP iniciado: {:?}", self.language);

        // Initialize
        self.initialize().await?;

        // Converter para std::process::Child se necessário
        // Por enquanto, mantemos AsyncCommand
        self.child = Some(
            Command::new(&command)
                .args(&args)
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .with_context(|| format!("Falha ao iniciar servidor LSP (sync): {:?}", self.language))?,
        );

        Ok(())
    }

    /// Initialize LSP connection
    async fn initialize(&mut self) -> Result<()> {
        let params = InitializeParams {
            process_id: Some(std::process::id()),
            root_path: self.root_uri.as_ref().and_then(|u| u.to_file_path().ok()),
            root_uri: self.root_uri.clone(),
            initialization_options: None,
            capabilities: ClientCapabilities::default(),
            trace: None,
            workspace_folders: None,
            client_info: Some(lsp_types::ClientInfo {
                name: "BEAGLE IDE".to_string(),
                version: Some("0.1.0".to_string()),
            }),
            locale: None,
        };

        let request = lsp_types::request::Initialize::METHOD.to_string();
        let _response = self.send_request(request, params).await?;

        // Parse capabilities from response
        // Por enquanto, assumimos capacidades padrão
        self.capabilities = Some(ServerCapabilities::default());

        Ok(())
    }

    /// Envia request LSP
    async fn send_request(&mut self, method: String, params: Value) -> Result<Value> {
        let id = self.next_request_id;
        self.next_request_id += 1;

        let request = serde_json::json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        });

        // Enviar via stdin do child process
        // Por enquanto, retornamos mock
        info!("LSP request: {} (id: {})", method, id);
        Ok(serde_json::json!({}))
    }

    /// Abre documento no servidor LSP
    pub async fn did_open(&mut self, uri: Url, text: String, language_id: String) -> Result<()> {
        let params = DidOpenTextDocumentParams {
            text_document: TextDocumentItem {
                uri,
                language_id,
                version: 0,
                text,
            },
        };

        self.send_notification("textDocument/didOpen", params).await?;
        Ok(())
    }

    /// Atualiza documento no servidor LSP
    pub async fn did_change(
        &mut self,
        uri: Url,
        version: i32,
        changes: Vec<TextDocumentContentChangeEvent>,
    ) -> Result<()> {
        let params = DidChangeTextDocumentParams {
            text_document: TextDocumentIdentifier {
                uri,
            },
            version,
            content_changes: changes,
        };

        self.send_notification("textDocument/didChange", params).await?;
        Ok(())
    }

    /// Envia notificação LSP
    async fn send_notification(&mut self, method: &str, params: impl serde::Serialize) -> Result<()> {
        let notification = serde_json::json!({
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        });

        info!("LSP notification: {}", method);
        Ok(())
    }

    /// Compleção no posição especificada
    pub async fn completion(&mut self, uri: Url, position: Position) -> Result<Vec<CompletionItem>> {
        let params = CompletionParams {
            text_document_position: TextDocumentPositionParams {
                text_document: TextDocumentIdentifier { uri },
                position,
            },
            work_done_progress_params: Default::default(),
            partial_result_params: Default::default(),
            context: None,
        };

        // Mock por enquanto - implementar comunicação real
        info!("LSP completion request: {:?}", position);
        Ok(vec![])
    }

    /// Hover no posição especificada
    pub async fn hover(&mut self, uri: Url, position: Position) -> Result<Option<lsp_types::Hover>> {
        let params = HoverParams {
            text_document_position_params: TextDocumentPositionParams {
                text_document: TextDocumentIdentifier { uri },
                position,
            },
            work_done_progress_params: Default::default(),
        };

        info!("LSP hover request: {:?}", position);
        Ok(None)
    }

    /// Goto definition
    pub async fn goto_definition(&mut self, uri: Url, position: Position) -> Result<Option<Vec<lsp_types::Location>>> {
        let params = GotoDefinitionParams {
            text_document_position_params: TextDocumentPositionParams {
                text_document: TextDocumentIdentifier { uri },
                position,
            },
            work_done_progress_params: Default::default(),
            partial_result_params: Default::default(),
        };

        info!("LSP goto_definition request: {:?}", position);
        Ok(None)
    }

    /// Document symbols
    pub async fn document_symbols(&mut self, uri: Url) -> Result<Vec<lsp_types::DocumentSymbol>> {
        let params = DocumentSymbolParams {
            text_document: TextDocumentIdentifier { uri },
            work_done_progress_params: Default::default(),
            partial_result_params: Default::default(),
        };

        info!("LSP document_symbols request");
        Ok(vec![])
    }

    /// Para servidor LSP
    pub fn stop(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            info!("Servidor LSP parado: {:?}", self.language);
        }
    }
}

impl Drop for LspClient {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Encontra rust-analyzer no PATH ou via cargo
async fn find_rust_analyzer() -> Result<String> {
    // Tenta diretamente no PATH
    if which::which("rust-analyzer").is_ok() {
        return Ok("rust-analyzer".to_string());
    }

    // Tenta via cargo
    let output = Command::new("cargo")
        .args(&["install", "--list"])
        .output();

    if let Ok(cmd) = output {
        let stdout = String::from_utf8_lossy(&cmd.stdout);
        if stdout.contains("rust-analyzer") {
            // Encontra path no output
            for line in stdout.lines() {
                if line.contains("rust-analyzer") {
                    // Extrai path
                    if let Some(path) = line.split_whitespace().nth(1) {
                        return Ok(path.to_string());
                    }
                }
            }
        }
    }

    // Fallback: tenta diretório comum
    if let Some(home) = std::env::var_os("HOME") {
        let path = PathBuf::from(home)
            .join(".cargo")
            .join("bin")
            .join("rust-analyzer");
        if path.exists() {
            return Ok(path.to_string_lossy().to_string());
        }
    }

    Err(anyhow::anyhow!("rust-analyzer não encontrado. Instale com: cargo install rust-analyzer"))
}

/// Encontra Julia no PATH
async fn find_julia() -> Result<String> {
    if let Ok(path) = which::which("julia") {
        return Ok(path.to_string_lossy().to_string());
    }

    Err(anyhow::anyhow!("Julia não encontrado. Instale Julia de https://julialang.org"))
}

