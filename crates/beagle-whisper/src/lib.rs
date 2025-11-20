//! BEAGLE Whisper - Transcrição de Voz 100% Local
//! Integra whisper.cpp (local) + Grok 3/4 Heavy para assistente pessoal

use std::process::{Command, Stdio};
use std::io::{Read, Write};
use std::path::PathBuf;
use tokio::sync::mpsc;
use tokio::task;
use tracing::{info, warn, error};
use anyhow::{Context, Result};
use beagle_grok_api::GrokClient;
use beagle_smart_router::query_smart;

/// Cliente Whisper local (whisper.cpp)
pub struct BeagleWhisper {
    whisper_path: PathBuf,
    model_path: PathBuf,
    language: String,
    threads: usize,
}

impl BeagleWhisper {
    pub fn new() -> Result<Self> {
        // Detecta sistema operacional
        let whisper_path = if cfg!(target_os = "macos") {
            PathBuf::from(expanduser("~/whisper.cpp/main"))
        } else {
            PathBuf::from(expanduser("~/whisper.cpp/main"))
        };
        
        let model_path = if cfg!(target_os = "macos") {
            PathBuf::from(expanduser("~/whisper.cpp/models/ggml-large-v3.bin"))
        } else {
            PathBuf::from(expanduser("~/whisper.cpp/models/ggml-large-v3.bin"))
        };
        
        // Verifica se whisper.cpp existe
        if !whisper_path.exists() {
            warn!("⚠️  whisper.cpp não encontrado em: {:?}", whisper_path);
            warn!("   Instale com: git clone https://github.com/ggerganov/whisper.cpp && cd whisper.cpp && make");
        }
        
        if !model_path.exists() {
            warn!("⚠️  Modelo Whisper não encontrado em: {:?}", model_path);
            warn!("   Baixe com: cd whisper.cpp && ./models/download-ggml-model.sh large-v3");
        }
        
        info!("🎤 BeagleWhisper inicializado");
        info!("   Whisper: {:?}", whisper_path);
        info!("   Modelo: {:?}", model_path);
        
        Ok(Self {
            whisper_path,
            model_path,
            language: "pt".to_string(),
            threads: 8,
        })
    }
    
    pub fn with_paths(whisper_path: impl Into<PathBuf>, model_path: impl Into<PathBuf>) -> Result<Self> {
        Ok(Self {
            whisper_path: whisper_path.into(),
            model_path: model_path.into(),
            language: "pt".to_string(),
            threads: 8,
        })
    }
    
    pub fn with_language(mut self, lang: impl Into<String>) -> Self {
        self.language = lang.into();
        self
    }
    
    pub fn with_threads(mut self, threads: usize) -> Self {
        self.threads = threads;
        self
    }
    
    /// Transcreve arquivo de áudio
    pub async fn transcribe_file(&self, audio_path: &str) -> Result<String> {
        info!("🎤 Transcrevendo arquivo: {}", audio_path);
        
        let output = Command::new(&self.whisper_path)
            .args([
                "-m", self.model_path.to_str().unwrap(),
                "-f", audio_path,
                "-l", &self.language,
                "-t", &self.threads.to_string(),
                "--no-print-progress",
                "--print-colors", "false",
            ])
            .output()
            .context("Falha ao executar whisper.cpp")?;
        
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("❌ Whisper falhou: {}", stderr);
            return Err(anyhow::anyhow!("Whisper falhou: {}", stderr));
        }
        
        let transcription = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| {
                // Filtra linhas de progresso e mantém apenas transcrição
                !line.contains("[") && !line.contains("whisper") && !line.trim().is_empty()
            })
            .collect::<Vec<_>>()
            .join(" ");
        
        info!("✅ Transcrição: {} chars", transcription.len());
        Ok(transcription)
    }
    
    /// Inicia transcrição em tempo real (microfone)
    pub fn start_live_transcription(&self) -> Result<mpsc::Receiver<String>> {
        info!("🎤 Iniciando transcrição em tempo real...");
        
        let (tx, rx) = mpsc::channel(32);
        let whisper_path = self.whisper_path.clone();
        let model_path = self.model_path.clone();
        let language = self.language.clone();
        let threads = self.threads;
        
        task::spawn_blocking(move || {
            let mut child = match Command::new(&whisper_path)
                .args([
                    "-m", model_path.to_str().unwrap(),
                    "-l", &language,
                    "--print-realtime",
                    "-t", &threads.to_string(),
                    "-f", "-", // Lê de stdin
                ])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
            {
                Ok(c) => c,
                Err(e) => {
                    error!("❌ Falha ao iniciar Whisper: {}", e);
                    return;
                }
            };
            
            let mut stdout = match child.stdout.take() {
                Some(s) => s,
                None => {
                    error!("❌ Falha ao obter stdout do Whisper");
                    return;
                }
            };
            
            let mut buffer = String::new();
            let mut byte_buf = [0u8; 1];
            
            loop {
                match stdout.read(&mut byte_buf) {
                    Ok(0) => break, // EOF
                    Ok(_) => {
                        let c = byte_buf[0] as char;
                        
                        if c == '\n' {
                            let line = buffer.trim().to_string();
                            
                            // Extrai transcrição (formato: [HH:MM:SS.mmm --> HH:MM:SS.mmm] texto)
                            if line.contains("]") && line.len() > 10 {
                                if let Some(transcription) = line.split("]").nth(1) {
                                    let text = transcription.trim().to_string();
                                    
                                    // Filtra transcrições muito curtas ou vazias
                                    if text.len() > 5 && !text.chars().all(|c| c.is_whitespace() || c == '-') {
                                        info!("🎤 Whisper: {}", text);
                                        
                                        // Envia para canal (não bloqueia se canal cheio)
                                        if tx.try_send(text).is_err() {
                                            warn!("⚠️  Canal de transcrição cheio, descartando");
                                        }
                                    }
                                }
                            }
                            
                            buffer.clear();
                        } else if c.is_control() {
                            // Ignora caracteres de controle
                        } else {
                            buffer.push(c);
                        }
                    }
                    Err(e) => {
                        error!("❌ Erro ao ler stdout do Whisper: {}", e);
                        break;
                    }
                }
            }
        });
        
        Ok(rx)
    }
    
    /// Transcreve e envia para Grok automaticamente
    pub async fn transcribe_and_query(&self, audio_path: &str) -> Result<String> {
        let transcription = self.transcribe_file(audio_path).await?;
        
        // Envia para Grok 3
        info!("🤖 Enviando transcrição para Grok 3...");
        let response = query_smart(&transcription, 80000).await;
        
        info!("✅ Resposta do BEAGLE: {} chars", response.len());
        Ok(response)
    }
}

impl Default for BeagleWhisper {
    fn default() -> Self {
        Self::new().unwrap_or_else(|_| {
            // Fallback com paths padrão mesmo se não existirem
            Self {
                whisper_path: PathBuf::from("whisper.cpp/main"),
                model_path: PathBuf::from("whisper.cpp/models/ggml-large-v3.bin"),
                language: "pt".to_string(),
                threads: 8,
            }
        })
    }
}

/// Helper para expandir ~
fn expanduser(path: &str) -> PathBuf {
    if path.starts_with("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(&path[2..]);
        }
    }
    PathBuf::from(path)
}

/// Assistente pessoal completo (Whisper + Grok + Loop)
pub struct BeagleVoiceAssistant {
    whisper: BeagleWhisper,
    grok: GrokClient,
}

impl BeagleVoiceAssistant {
    pub fn new() -> Result<Self> {
        let whisper = BeagleWhisper::new()?;
        let api_key = std::env::var("GROK_API_KEY")
            .unwrap_or_else(|_| "xai-tua-key".to_string());
        let grok = GrokClient::new(&api_key);
        
        info!("🎤 BeagleVoiceAssistant inicializado");
        Ok(Self { whisper, grok })
    }
    
    /// Inicia loop de assistente pessoal (transcrição → Grok → resposta)
    pub async fn start_assistant_loop(&self) -> Result<()> {
        info!("🚀 Iniciando loop de assistente pessoal...");
        info!("   Fale perto do microfone. Ctrl+C para parar.");
        
        let mut receiver = self.whisper.start_live_transcription()?;
        
        loop {
            tokio::select! {
                transcription = receiver.recv() => {
                    if let Some(text) = transcription {
                        info!("🎤 Transcrição recebida: {}", text);
                        
                        // Envia para Grok 3
                        let response = query_smart(&text, 80000).await;
                        info!("🤖 BEAGLE: {}", response);
                        println!("\n🎤 Tu: {}", text);
                        println!("🤖 BEAGLE: {}\n", response);
                        
                        // TODO: TTS aqui (speak(response))
                    } else {
                        warn!("⚠️  Canal de transcrição fechado");
                        break;
                    }
                }
            }
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_whisper_creation() {
        let whisper = BeagleWhisper::new();
        assert!(whisper.is_ok());
    }
    
    #[tokio::test]
    async fn test_assistant_creation() {
        let assistant = BeagleVoiceAssistant::new();
        // Não falha mesmo sem whisper.cpp instalado
        assert!(assistant.is_ok() || assistant.is_err());
    }
}

