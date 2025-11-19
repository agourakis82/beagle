use serde::{Deserialize, Serialize};
use std::process::Command;
use tauri::command;
use tracing::{error, info};

use crate::lsp;
use lsp_types::{CompletionItem, Hover, Location, Position, Url};
use std::collections::HashMap;
use std::path::PathBuf;
use tokio::sync::Mutex as AsyncMutex;

// Gerenciador global de clientes LSP (async-safe)
static LSP_CLIENTS: AsyncMutex<HashMap<String, lsp::LspClient>> = AsyncMutex::new(HashMap::new());

#[derive(Debug, Serialize, Deserialize)]
pub struct ClusterStatus {
    pub nodes: Vec<NodeStatus>,
    pub pods: Vec<PodStatus>,
    pub ready: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct NodeStatus {
    pub name: String,
    pub status: String,
    pub roles: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PodStatus {
    pub name: String,
    pub namespace: String,
    pub status: String,
    pub ready: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SemanticBlame {
    pub line: usize,
    pub commit: String,
    pub author: String,
    pub message: String,
    pub timestamp: String,
    pub concept: Option<String>,
}

/// Processa comando de voz
#[command]
pub async fn voice_command(command: String) -> Result<String, String> {
    info!("Comando de voz recebido: {}", command);

    // Detecta padrões como "BEAGLE, cria seção sobre KEC"
    let cmd_lower = command.to_lowercase();
    
    if cmd_lower.contains("cria seção") || cmd_lower.contains("criar seção") {
        let topic = extract_topic(&command);
        info!("Criando seção sobre: {}", topic);
        return Ok(format!("Seção criada sobre '{}' no Paper Canvas", topic));
    }
    
    if cmd_lower.contains("status cluster") || cmd_lower.contains("status do cluster") {
        let status = get_cluster_status().await;
        return Ok(format!("Status do cluster: {} nodes, {} pods", 
            status.nodes.len(), status.pods.len()));
    }

    Ok(format!("Comando executado: {}", command))
}

/// Extrai tópico de comando de voz
fn extract_topic(command: &str) -> String {
    // Extrai texto após "sobre" ou "de"
    let keywords = ["sobre", "de", "acerca"];
    for keyword in keywords.iter() {
        if let Some(pos) = command.to_lowercase().find(keyword) {
            let start = pos + keyword.len();
            return command[start..].trim().to_string();
        }
    }
    "tópico desconhecido".to_string()
}

/// Sincroniza atualizações Yjs
#[command]
pub async fn yjs_sync(update: Vec<u8>) -> Result<Vec<u8>, String> {
    // TODO: Conectar com servidor Yjs real
    // Por enquanto, apenas ecoa a atualização
    info!("Yjs sync: {} bytes", update.len());
    Ok(update)
}

/// Obtém status do cluster Darwin
#[command]
pub async fn cluster_status() -> Result<ClusterStatus, String> {
    info!("Consultando status do cluster Darwin...");
    
    let status = get_cluster_status().await;
    Ok(status)
}

/// Obtém logs do cluster
#[command]
pub async fn cluster_logs(limit: Option<usize>) -> Result<Vec<String>, String> {
    let limit = limit.unwrap_or(50);
    info!("Buscando {} últimas linhas de log do cluster", limit);
    
    // Tenta kubectl logs
    let output = Command::new("kubectl")
        .args(&["get", "pods", "-A", "-o", "json"])
        .output();
    
    match output {
        Ok(cmd) => {
            if cmd.status.success() {
                let stdout = String::from_utf8_lossy(&cmd.stdout);
                let lines: Vec<String> = stdout
                    .lines()
                    .take(limit)
                    .map(|s| s.to_string())
                    .collect();
                Ok(lines)
            } else {
                let stderr = String::from_utf8_lossy(&cmd.stderr);
                error!("kubectl falhou: {}", stderr);
                Ok(vec![format!("Erro: {}", stderr)])
            }
        }
        Err(e) => {
            error!("Falha ao executar kubectl: {}", e);
            Ok(vec![format!("Erro: kubectl não encontrado: {}", e)])
        }
    }
}

/// Executa comando no cluster
#[command]
pub async fn cluster_exec(command: String) -> Result<String, String> {
    info!("Executando comando no cluster: {}", command);
    
    // Separa comando em partes
    let parts: Vec<&str> = command.split_whitespace().collect();
    if parts.is_empty() {
        return Err("Comando vazio".to_string());
    }
    
    let output = Command::new(&parts[0])
        .args(&parts[1..])
        .output();
    
    match output {
        Ok(cmd) => {
            if cmd.status.success() {
                Ok(String::from_utf8_lossy(&cmd.stdout).to_string())
            } else {
                let stderr = String::from_utf8_lossy(&cmd.stderr);
                Err(format!("Erro: {}", stderr))
            }
        }
        Err(e) => Err(format!("Falha ao executar: {}", e)),
    }
}

/// Git semântico: blame por ideia/conceito
#[command]
pub async fn git_semantic_blame(file_path: String, line: usize) -> Result<SemanticBlame, String> {
    info!("Git semantic blame: {}:{}", file_path, line);
    
    // Executa git blame
    let output = Command::new("git")
        .args(&["blame", "-L", &format!("{},{}", line, line), "-p", &file_path])
        .output();
    
    match output {
        Ok(cmd) => {
            if cmd.status.success() {
                let stdout = String::from_utf8_lossy(&cmd.stdout);
                // Parse git blame -p output
                let blame = parse_git_blame(&stdout, line);
                Ok(blame)
            } else {
                Err("Falha ao executar git blame".to_string())
            }
        }
        Err(e) => Err(format!("Git não encontrado: {}", e)),
    }
}

/// Parse git blame -p output
fn parse_git_blame(output: &str, line: usize) -> SemanticBlame {
    // Parse básico - em produção, usar parser completo
    let mut commit = String::new();
    let mut author = String::new();
    let mut message = String::new();
    let mut timestamp = String::new();
    
    for line_text in output.lines() {
        if line_text.starts_with("author ") {
            author = line_text[7..].trim().to_string();
        } else if line_text.starts_with("committer-time ") {
            timestamp = line_text[15..].trim().to_string();
        } else if line_text.starts_with("summary ") {
            message = line_text[8..].trim().to_string();
        } else if line_text.len() == 40 && line_text.chars().all(|c| c.is_ascii_hexdigit()) {
            commit = line_text.to_string();
        }
    }
    
    SemanticBlame {
        line,
        commit,
        author,
        message,
        timestamp,
        concept: None, // TODO: Extrair conceito semântico
    }
}

/// Obtém status do cluster (helper interno)
async fn get_cluster_status() -> ClusterStatus {
    // Tenta obter nodes
    let nodes_output = Command::new("kubectl")
        .args(&["get", "nodes", "-o", "json"])
        .output();
    
    let mut nodes = Vec::new();
    if let Ok(cmd) = nodes_output {
        if cmd.status.success() {
            let stdout = String::from_utf8_lossy(&cmd.stdout);
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&stdout) {
                if let Some(items) = json.get("items").and_then(|i| i.as_array()) {
                    for item in items {
                        let metadata = item.get("metadata").and_then(|m| m.get("name"));
                        let status = item.get("status").and_then(|s| s.get("conditions"))
                            .and_then(|c| c.as_array())
                            .and_then(|c| c.iter().find(|x| {
                                x.get("type").and_then(|t| t.as_str()) == Some("Ready")
                            }))
                            .and_then(|x| x.get("status").and_then(|s| s.as_str()));
                        
                        let roles = item.get("metadata")
                            .and_then(|m| m.get("labels"))
                            .and_then(|l| l.as_object())
                            .map(|obj| {
                                obj.keys()
                                    .filter(|k| k.starts_with("node-role.kubernetes.io"))
                                    .map(|k| k.split('/').last().unwrap_or(k).to_string())
                                    .collect()
                            })
                            .unwrap_or_default();
                        
                        if let (Some(name), Some(status_str)) = (metadata, status) {
                            nodes.push(NodeStatus {
                                name: name.as_str().unwrap_or("unknown").to_string(),
                                status: status_str.to_string(),
                                roles,
                            });
                        }
                    }
                }
            }
        }
    }
    
    // Tenta obter pods
    let pods_output = Command::new("kubectl")
        .args(&["get", "pods", "-A", "-o", "json"])
        .output();
    
    let mut pods = Vec::new();
    if let Ok(cmd) = pods_output {
        if cmd.status.success() {
            let stdout = String::from_utf8_lossy(&cmd.stdout);
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&stdout) {
                if let Some(items) = json.get("items").and_then(|i| i.as_array()) {
                    for item in items {
                        let metadata = item.get("metadata");
                        let status_obj = item.get("status");
                        
                        let name = metadata
                            .and_then(|m| m.get("name"))
                            .and_then(|n| n.as_str())
                            .unwrap_or("unknown")
                            .to_string();
                        
                        let namespace = metadata
                            .and_then(|m| m.get("namespace"))
                            .and_then(|n| n.as_str())
                            .unwrap_or("default")
                            .to_string();
                        
                        let phase = status_obj
                            .and_then(|s| s.get("phase"))
                            .and_then(|p| p.as_str())
                            .unwrap_or("Unknown")
                            .to_string();
                        
                        let ready = if let Some(containers) = status_obj
                            .and_then(|s| s.get("containerStatuses"))
                            .and_then(|c| c.as_array())
                        {
                            let ready_count = containers.iter()
                                .filter(|c| {
                                    c.get("ready").and_then(|r| r.as_bool()).unwrap_or(false)
                                })
                                .count();
                            format!("{}/{}", ready_count, containers.len())
                        } else {
                            "0/0".to_string()
                        };
                        
                        pods.push(PodStatus {
                            name,
                            namespace,
                            status: phase,
                            ready,
                        });
                    }
                }
            }
        }
    }
    
    let ready = !nodes.is_empty() && nodes.iter().any(|n| n.status == "True");
    
    ClusterStatus { nodes, pods, ready }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LspCompletionRequest {
    pub language: String, // "rust" ou "julia"
    pub uri: String,
    pub line: u32,
    pub character: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LspHoverRequest {
    pub language: String,
    pub uri: String,
    pub line: u32,
    pub character: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LspGotoDefinitionRequest {
    pub language: String,
    pub uri: String,
    pub line: u32,
    pub character: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LspDidOpenRequest {
    pub language: String,
    pub uri: String,
    pub text: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LspDidChangeRequest {
    pub language: String,
    pub uri: String,
    pub version: i32,
    pub text: String,
}

/// Inicia servidor LSP
#[command]
pub async fn lsp_start(language: String, root_path: Option<String>) -> Result<String, String> {
    info!("Iniciando servidor LSP: {}", language);
    
    let server_type = match language.as_str() {
        "rust" => lsp::LanguageServer::RustAnalyzer,
        "julia" => lsp::LanguageServer::JuliaLanguageServer,
        _ => return Err(format!("Linguagem não suportada: {}", language)),
    };
    
    let root = root_path.map(PathBuf::from);
    
    let mut client = lsp::LspClient::new(server_type, root)
        .map_err(|e| format!("Falha ao criar cliente LSP: {}", e))?;
    
    client.start().await
        .map_err(|e| format!("Falha ao iniciar servidor LSP: {}", e))?;
    
    let mut clients = LSP_CLIENTS.lock().await;
    clients.insert(language.clone(), client);
    
    Ok(format!("Servidor LSP iniciado: {}", language))
}

/// Compleção LSP
#[command]
pub async fn lsp_completion(request: LspCompletionRequest) -> Result<Vec<CompletionItem>, String> {
    let uri = Url::parse(&request.uri)
        .map_err(|e| format!("URI inválida: {}", e))?;
    
    let position = Position {
        line: request.line,
        character: request.character,
    };
    
    let mut clients = LSP_CLIENTS.lock().await;
    if let Some(client) = clients.get_mut(&request.language) {
        client.completion(uri, position).await
            .map_err(|e| format!("Falha na completação: {}", e))
    } else {
        Err(format!("Servidor LSP não iniciado: {}", request.language))
    }
}

/// Hover LSP
#[command]
pub async fn lsp_hover(request: LspHoverRequest) -> Result<Option<Hover>, String> {
    let uri = Url::parse(&request.uri)
        .map_err(|e| format!("URI inválida: {}", e))?;
    
    let position = Position {
        line: request.line,
        character: request.character,
    };
    
    let mut clients = LSP_CLIENTS.lock().await;
    if let Some(client) = clients.get_mut(&request.language) {
        client.hover(uri, position).await
            .map_err(|e| format!("Falha no hover: {}", e))
    } else {
        Err(format!("Servidor LSP não iniciado: {}", request.language))
    }
}

/// Goto definition LSP
#[command]
pub async fn lsp_goto_definition(request: LspGotoDefinitionRequest) -> Result<Option<Vec<Location>>, String> {
    let uri = Url::parse(&request.uri)
        .map_err(|e| format!("URI inválida: {}", e))?;
    
    let position = Position {
        line: request.line,
        character: request.character,
    };
    
    let mut clients = LSP_CLIENTS.lock().await;
    if let Some(client) = clients.get_mut(&request.language) {
        client.goto_definition(uri, position).await
            .map_err(|e| format!("Falha no goto_definition: {}", e))
    } else {
        Err(format!("Servidor LSP não iniciado: {}", request.language))
    }
}

/// DidOpen LSP
#[command]
pub async fn lsp_did_open(request: LspDidOpenRequest) -> Result<(), String> {
    let uri = Url::parse(&request.uri)
        .map_err(|e| format!("URI inválida: {}", e))?;
    
    let language_id = match request.language.as_str() {
        "rust" => "rust",
        "julia" => "julia",
        _ => return Err(format!("Linguagem não suportada: {}", request.language)),
    };
    
    let mut clients = LSP_CLIENTS.lock().await;
    if let Some(client) = clients.get_mut(&request.language) {
        client.did_open(uri, request.text, language_id.to_string()).await
            .map_err(|e| format!("Falha no did_open: {}", e))
    } else {
        Err(format!("Servidor LSP não iniciado: {}", request.language))
    }
}

/// DidChange LSP
#[command]
pub async fn lsp_did_change(request: LspDidChangeRequest) -> Result<(), String> {
    let uri = Url::parse(&request.uri)
        .map_err(|e| format!("URI inválida: {}", e))?;
    
    let changes = vec![lsp_types::TextDocumentContentChangeEvent {
        range: None,
        range_length: None,
        text: request.text,
    }];
    
    let mut clients = LSP_CLIENTS.lock().await;
    if let Some(client) = clients.get_mut(&request.language) {
        client.did_change(uri, request.version, changes).await
            .map_err(|e| format!("Falha no did_change: {}", e))
    } else {
        Err(format!("Servidor LSP não iniciado: {}", request.language))
    }
}

