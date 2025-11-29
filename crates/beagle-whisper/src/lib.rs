//! BEAGLE Whisper - Advanced Audio Processing and Speech Recognition
//!
//! Complete audio processing framework with:
//! - Local voice transcription via whisper.cpp
//! - Multi-backend TTS (Native, Espeak, None)
//! - Advanced audio processing (VAD, diarization, emotion)
//! - Real-time streaming capabilities
//! - Multi-language support
//!
//! Integrates whisper.cpp (local STT) + multiple TTS backends (Native, Espeak, None)
//!
//! # Features
//! - **STT**: 100% local transcription via whisper.cpp
//! - **TTS**: Multi-backend with auto-detection:
//!   - Native TTS (via `tts` crate, behind `native-tts` feature flag)
//!   - Espeak/espeak-ng (command-line, no feature flag needed)
//!   - None (graceful fallback when no TTS available)
//!
//! # Usage
//! ```ignore
//! use beagle_whisper::BeagleWhisper;
//!
//! let whisper = BeagleWhisper::new()?;
//! let text = whisper.transcribe_file("audio.wav").await?;
//! whisper.speak("Hello world").await?;
//! ```

pub mod advanced;
pub mod streaming;

use anyhow::{Context, Result};
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use tokio::task;
use tracing::{error, info, warn};

#[cfg(feature = "native-tts")]
use tts::Tts;

/// Available TTS backends
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TtsBackend {
    /// Native system TTS (via `tts` crate, requires `native-tts` feature)
    Native,
    /// espeak-ng or espeak (command-line, more portable)
    Espeak,
    /// No TTS available (silent mode)
    None,
}

impl std::fmt::Display for TtsBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TtsBackend::Native => write!(f, "Native"),
            TtsBackend::Espeak => write!(f, "Espeak"),
            TtsBackend::None => write!(f, "None"),
        }
    }
}

/// Internal wrapper for different TTS backends
enum TtsEngine {
    #[cfg(feature = "native-tts")]
    Native(Tts),
    Espeak,
    None,
}

/// Local Whisper client (whisper.cpp) with multi-backend TTS
///
/// # Architecture
/// - **STT**: Uses whisper.cpp binary for 100% local transcription
/// - **TTS**: Auto-detects best backend (Native → Espeak → None)
///
/// # Backend Selection
/// 1. Native TTS (if `native-tts` feature enabled and system supports it)
/// 2. espeak-ng (if installed)
/// 3. espeak (if installed, fallback)
/// 4. None (graceful degradation - prints text instead of speaking)
pub struct BeagleWhisper {
    whisper_path: PathBuf,
    model_path: PathBuf,
    language: String,
    threads: usize,
    tts: Arc<Mutex<TtsEngine>>,
    tts_backend: TtsBackend,
}

impl BeagleWhisper {
    /// Creates new BeagleWhisper instance with auto-detected paths and TTS backend
    ///
    /// # Auto-Detection
    /// - Whisper path: `~/whisper.cpp/main`
    /// - Model path: `~/whisper.cpp/models/ggml-large-v3.bin`
    /// - TTS backend: Native → Espeak → None (first available)
    ///
    /// # Errors
    /// Returns error only if auto-detection completely fails.
    /// Logs warnings if whisper.cpp or model not found.
    pub fn new() -> Result<Self> {
        let whisper_path = PathBuf::from(expanduser("~/whisper.cpp/main"));
        let model_path = PathBuf::from(expanduser("~/whisper.cpp/models/ggml-large-v3.bin"));

        // Warn if whisper.cpp not found (but don't fail - allow construction)
        if !whisper_path.exists() {
            warn!("⚠️  whisper.cpp not found at: {:?}", whisper_path);
            warn!("   Install with: git clone https://github.com/ggerganov/whisper.cpp && cd whisper.cpp && make");
        }

        if !model_path.exists() {
            warn!("⚠️  Whisper model not found at: {:?}", model_path);
            warn!("   Download with: cd whisper.cpp && ./models/download-ggml-model.sh large-v3");
        }

        // Auto-detect best TTS backend
        let (tts_engine, tts_backend) = Self::init_tts();

        info!("🎤 BeagleWhisper initialized");
        info!("   Whisper: {:?}", whisper_path);
        info!("   Model: {:?}", model_path);
        info!("   TTS Backend: {}", tts_backend);

        Ok(Self {
            whisper_path,
            model_path,
            language: "pt".to_string(),
            threads: 8,
            tts: Arc::new(Mutex::new(tts_engine)),
            tts_backend,
        })
    }

    /// Creates BeagleWhisper with custom whisper.cpp and model paths
    ///
    /// TTS backend is still auto-detected.
    pub fn with_paths(
        whisper_path: impl Into<PathBuf>,
        model_path: impl Into<PathBuf>,
    ) -> Result<Self> {
        let (tts_engine, tts_backend) = Self::init_tts();

        let whisper_path = whisper_path.into();
        let model_path = model_path.into();

        info!("🎤 BeagleWhisper initialized with custom paths");
        info!("   Whisper: {:?}", whisper_path);
        info!("   Model: {:?}", model_path);
        info!("   TTS Backend: {}", tts_backend);

        Ok(Self {
            whisper_path,
            model_path,
            language: "pt".to_string(),
            threads: 8,
            tts: Arc::new(Mutex::new(tts_engine)),
            tts_backend,
        })
    }

    /// Initializes TTS with best available backend (auto-detection)
    ///
    /// # Priority Order
    /// 1. Native TTS (if `native-tts` feature enabled and Tts::default() succeeds)
    /// 2. espeak-ng (if command available)
    /// 3. espeak (if command available, fallback)
    /// 4. None (if no TTS found)
    ///
    /// # Returns
    /// Tuple of (TtsEngine, TtsBackend)
    fn init_tts() -> (TtsEngine, TtsBackend) {
        // Try Native TTS first (best quality, requires feature flag)
        #[cfg(feature = "native-tts")]
        {
            match Tts::default() {
                Ok(tts_instance) => {
                    info!("🔊 Native TTS initialized successfully");
                    return (TtsEngine::Native(tts_instance), TtsBackend::Native);
                }
                Err(e) => {
                    warn!("⚠️  Native TTS initialization failed: {}", e);
                    warn!("   Falling back to espeak");
                }
            }
        }

        // Fallback to espeak-ng (more portable, better quality than espeak)
        if Command::new("espeak-ng").arg("--version").output().is_ok() {
            info!("🔊 TTS via espeak-ng available");
            return (TtsEngine::Espeak, TtsBackend::Espeak);
        }

        // Fallback to espeak (older version)
        if Command::new("espeak").arg("--version").output().is_ok() {
            info!("🔊 TTS via espeak available");
            return (TtsEngine::Espeak, TtsBackend::Espeak);
        }

        // No TTS available - graceful degradation
        warn!("⚠️  No TTS backend found");
        warn!("   Install: sudo apt install espeak-ng (Linux)");
        warn!("   or: brew install espeak-ng (macOS)");
        warn!("   Continuing without voice synthesis (text will be printed only)");

        (TtsEngine::None, TtsBackend::None)
    }

    /// Returns the currently active TTS backend
    pub fn tts_backend(&self) -> TtsBackend {
        self.tts_backend
    }

    /// Sets the language for transcription (ISO 639-1 code)
    ///
    /// # Examples
    /// ```ignore
    /// whisper.with_language("en"); // English
    /// whisper.with_language("pt"); // Portuguese
    /// whisper.with_language("es"); // Spanish
    /// ```
    pub fn with_language(mut self, lang: impl Into<String>) -> Self {
        self.language = lang.into();
        self
    }

    /// Sets the number of threads for whisper.cpp processing
    ///
    /// Default: 8 threads
    pub fn with_threads(mut self, threads: usize) -> Self {
        self.threads = threads;
        self
    }

    /// Transcribes audio file to text using whisper.cpp
    ///
    /// # Arguments
    /// * `audio_path` - Path to audio file (WAV, MP3, etc.)
    ///
    /// # Returns
    /// Transcribed text (cleaned, without timestamps)
    ///
    /// # Errors
    /// Returns error if:
    /// - whisper.cpp binary not found or not executable
    /// - Audio file not found or invalid format
    /// - whisper.cpp process fails
    pub async fn transcribe_file(&self, audio_path: &str) -> Result<String> {
        info!("🎤 Transcribing file: {}", audio_path);

        let output = Command::new(&self.whisper_path)
            .args([
                "-m",
                self.model_path.to_str().unwrap(),
                "-f",
                audio_path,
                "-l",
                &self.language,
                "-t",
                &self.threads.to_string(),
                "--no-print-progress",
                "--print-colors",
                "false",
            ])
            .output()
            .context("Failed to execute whisper.cpp")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("❌ Whisper failed: {}", stderr);
            return Err(anyhow::anyhow!("Whisper failed: {}", stderr));
        }

        // Extract transcription text (filter out timestamps and progress lines)
        let transcription = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| {
                // Keep only actual transcription lines (skip metadata)
                !line.contains("[")
                    && !line.contains("whisper")
                    && !line.trim().is_empty()
                    && !line.contains("-->")
            })
            .collect::<Vec<_>>()
            .join(" ");

        info!("✅ Transcription: {} chars", transcription.len());
        Ok(transcription.trim().to_string())
    }

    /// Synthesizes text to speech using the active TTS backend
    ///
    /// # Behavior by Backend
    /// - **Native**: Uses system TTS (best quality, async)
    /// - **Espeak**: Uses espeak-ng/espeak command-line (good quality, sync)
    /// - **None**: Logs text to console (no audio output)
    ///
    /// # Arguments
    /// * `text` - Text to speak
    ///
    /// # Errors
    /// Returns error only if TTS backend explicitly fails.
    /// Backend=None never errors (prints instead).
    pub async fn speak(&self, text: &str) -> Result<()> {
        let tts = self.tts.clone();
        let text = text.to_string();
        let language = self.language.clone();

        // Execute TTS in separate thread to avoid blocking
        task::spawn_blocking(move || {
            let mut tts_guard = futures::executor::block_on(async { tts.lock().await });

            match &mut *tts_guard {
                #[cfg(feature = "native-tts")]
                TtsEngine::Native(tts_instance) => match tts_instance.speak(&text, false) {
                    Ok(_) => {
                        info!("🔊 TTS Native: Speaking {} chars", text.len());
                        Ok(())
                    }
                    Err(e) => {
                        warn!("⚠️  TTS Native error: {}", e);
                        Err(anyhow::anyhow!("TTS Native error: {}", e))
                    }
                },
                TtsEngine::Espeak => {
                    // Use espeak-ng or espeak via command-line
                    let espeak_cmd = if Command::new("espeak-ng").arg("--version").output().is_ok()
                    {
                        "espeak-ng"
                    } else {
                        "espeak"
                    };

                    let output = Command::new(espeak_cmd)
                        .args(&[
                            "-v",
                            &format!("{}+f3", language), // female voice, pitch 3
                            "-s",
                            "150", // speed 150 wpm
                            &text,
                        ])
                        .output();

                    match output {
                        Ok(result) if result.status.success() => {
                            info!("🔊 TTS Espeak: Speaking {} chars", text.len());
                            Ok(())
                        }
                        Ok(result) => {
                            let stderr = String::from_utf8_lossy(&result.stderr);
                            warn!("⚠️  TTS Espeak error: {}", stderr);
                            Err(anyhow::anyhow!("TTS Espeak error: {}", stderr))
                        }
                        Err(e) => {
                            warn!("⚠️  TTS Espeak command failed: {}", e);
                            Err(anyhow::anyhow!("TTS Espeak command failed: {}", e))
                        }
                    }
                }
                TtsEngine::None => {
                    // Graceful degradation - print instead of speak
                    info!("🔊 TTS disabled - printing text instead:");
                    info!("   {}", text);
                    Ok(())
                }
            }
        })
        .await
        .context("Failed to execute TTS task")?
    }

    /// Starts real-time transcription from microphone (live mode)
    ///
    /// # Returns
    /// Receiver channel that yields transcribed text segments as they're recognized
    ///
    /// # Usage
    /// ```ignore
    /// let mut rx = whisper.start_live_transcription()?;
    /// while let Some(text) = rx.recv().await {
    ///     println!("Heard: {}", text);
    /// }
    /// ```
    ///
    /// # Notes
    /// - Filters out short/empty transcriptions (< 5 chars)
    /// - Runs whisper.cpp in streaming mode (`--print-realtime`)
    /// - Spawns background task - channel closes when task ends
    pub fn start_live_transcription(&self) -> Result<mpsc::Receiver<String>> {
        info!("🎤 Starting real-time transcription...");

        let (tx, rx) = mpsc::channel(32);
        let whisper_path = self.whisper_path.clone();
        let model_path = self.model_path.clone();
        let language = self.language.clone();
        let threads = self.threads;

        task::spawn_blocking(move || {
            let mut child = match Command::new(&whisper_path)
                .args([
                    "-m",
                    model_path.to_str().unwrap(),
                    "-l",
                    &language,
                    "--print-realtime",
                    "-t",
                    &threads.to_string(),
                    "-f",
                    "-", // Read from stdin (microphone)
                ])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
            {
                Ok(c) => c,
                Err(e) => {
                    error!("❌ Failed to start Whisper: {}", e);
                    return;
                }
            };

            let mut stdout = match child.stdout.take() {
                Some(s) => s,
                None => {
                    error!("❌ Failed to get Whisper stdout");
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

                            // Extract transcription (format: [HH:MM:SS.mmm --> HH:MM:SS.mmm] text)
                            if line.contains("]") && line.len() > 10 {
                                if let Some(transcription) = line.split("]").nth(1) {
                                    let text = transcription.trim().to_string();

                                    // Filter very short or empty transcriptions
                                    if text.len() > 5
                                        && !text.chars().all(|c| c.is_whitespace() || c == '-')
                                    {
                                        info!("🎤 Whisper: {}", text);

                                        // Send to channel (non-blocking)
                                        if tx.try_send(text).is_err() {
                                            warn!("⚠️  Transcription channel full, dropping");
                                        }
                                    }
                                }
                            }

                            buffer.clear();
                        } else if !c.is_control() {
                            buffer.push(c);
                        }
                    }
                    Err(e) => {
                        error!("❌ Error reading Whisper stdout: {}", e);
                        break;
                    }
                }
            }

            // Cleanup
            let _ = child.wait();
        });

        Ok(rx)
    }
}

impl Default for BeagleWhisper {
    fn default() -> Self {
        Self::new().unwrap_or_else(|_| {
            // Fallback with default paths even if they don't exist
            let (tts_engine, tts_backend) = Self::init_tts();
            Self {
                whisper_path: PathBuf::from("whisper.cpp/main"),
                model_path: PathBuf::from("whisper.cpp/models/ggml-large-v3.bin"),
                language: "pt".to_string(),
                threads: 8,
                tts: Arc::new(Mutex::new(tts_engine)),
                tts_backend,
            }
        })
    }
}

/// Helper to expand ~ in paths
fn expanduser(path: &str) -> PathBuf {
    if path.starts_with("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(&path[2..]);
        }
    }
    PathBuf::from(path)
}

/// Complete voice assistant with callback pattern for LLM processing
///
/// # Architecture
/// - **Pure STT + TTS**: BeagleWhisper handles voice I/O only
/// - **Callback-based LLM**: You provide any async function to process text
/// - **No hardcoded dependencies**: Works with Grok, Claude, local LLMs, anything
///
/// # Usage Examples
///
/// ## With custom LLM
/// ```ignore
/// let assistant = BeagleVoiceAssistant::new()?;
/// assistant.start_assistant_loop(|text| async move {
///     my_llm_client.complete(&text).await.unwrap_or_default()
/// }).await?;
/// ```
///
/// ## With smart router
/// ```ignore
/// let assistant = BeagleVoiceAssistant::new()?;
/// assistant.start_with_smart_router().await?;
/// ```
pub struct BeagleVoiceAssistant {
    whisper: BeagleWhisper,
}

impl BeagleVoiceAssistant {
    /// Creates new voice assistant with auto-detected BeagleWhisper
    pub fn new() -> Result<Self> {
        let whisper = BeagleWhisper::new()?;
        info!("🎤 BeagleVoiceAssistant initialized");
        Ok(Self { whisper })
    }

    /// Returns reference to internal BeagleWhisper for direct access
    pub fn whisper(&self) -> &BeagleWhisper {
        &self.whisper
    }

    /// Starts assistant loop with custom callback for text processing
    ///
    /// # Arguments
    /// * `process_fn` - Async function that takes transcribed text and returns LLM response
    ///
    /// # Callback Pattern
    /// The callback should:
    /// - Take `String` (transcribed user input)
    /// - Return `Future<Output = String>` (LLM response)
    /// - Handle errors internally (return error message as String)
    ///
    /// # Examples
    ///
    /// ## With Grok
    /// ```ignore
    /// use beagle_smart_router::query_smart;
    ///
    /// assistant.start_assistant_loop(|text| async move {
    ///     query_smart(&text, 80000).await
    /// }).await?;
    /// ```
    ///
    /// ## With any LLM client
    /// ```ignore
    /// let my_client = MyLlmClient::new();
    /// assistant.start_assistant_loop(move |text| {
    ///     let client = my_client.clone();
    ///     async move {
    ///         client.complete(&text).await.unwrap_or_else(|e| format!("Error: {}", e))
    ///     }
    /// }).await?;
    /// ```
    ///
    /// # Behavior
    /// 1. Starts live transcription (microphone input)
    /// 2. For each transcribed segment:
    ///    - Calls `process_fn` with text
    ///    - Prints user input and LLM response
    ///    - Speaks response via TTS (if available)
    /// 3. Continues until Ctrl+C or channel closes
    pub async fn start_assistant_loop<F, Fut>(&self, process_fn: F) -> Result<()>
    where
        F: Fn(String) -> Fut,
        Fut: std::future::Future<Output = String>,
    {
        info!("🚀 Starting voice assistant loop...");
        info!("   Speak near microphone. Press Ctrl+C to stop.");

        let mut receiver = self.whisper.start_live_transcription()?;

        loop {
            tokio::select! {
                transcription = receiver.recv() => {
                    if let Some(text) = transcription {
                        info!("🎤 Received transcription: {}", text);

                        // Process text with provided callback
                        let response = process_fn(text.clone()).await;

                        info!("🤖 BEAGLE: {}", response);
                        println!("\n🎤 You: {}", text);
                        println!("🤖 BEAGLE: {}\n", response);

                        // Synthesize response (TTS)
                        if let Err(e) = self.whisper.speak(&response).await {
                            warn!("⚠️  Failed to speak response: {}", e);
                            // Continue even if TTS fails - response already printed
                        }
                    } else {
                        warn!("⚠️  Transcription channel closed");
                        break;
                    }
                }
            }
        }

        Ok(())
    }

    /// Helper to use with beagle-smart-router (convenience method)
    ///
    /// # Requires
    /// - `beagle-smart-router` crate in dependencies
    /// - `query_smart` function available
    ///
    /// # Equivalent to
    /// ```ignore
    /// assistant.start_assistant_loop(|text| async move {
    ///     query_smart(&text, 80000).await
    /// }).await
    /// ```
    pub async fn start_with_smart_router(&self) -> Result<()> {
        use beagle_smart_router::query_smart;

        self.start_assistant_loop(|text| async move { query_smart(&text, 80000).await })
            .await
    }

    /// Helper to use with Grok API directly (convenience method)
    ///
    /// # Environment
    /// Requires `GROK_API_KEY` or `XAI_API_KEY` environment variable
    ///
    /// # Equivalent to
    /// ```ignore
    /// let api_key = std::env::var("GROK_API_KEY").unwrap();
    /// assistant.start_assistant_loop(move |text| {
    ///     let key = api_key.clone();
    ///     async move {
    ///         let grok = GrokClient::new(&key);
    ///         grok.complete(&text, 4096).await.unwrap_or_else(|e| format!("Error: {}", e))
    ///     }
    /// }).await
    /// ```
    pub async fn start_with_grok(&self) -> Result<()> {
        use beagle_grok_api::GrokClient;

        let api_key = std::env::var("GROK_API_KEY")
            .or_else(|_| std::env::var("XAI_API_KEY"))
            .unwrap_or_else(|_| {
                warn!("⚠️  GROK_API_KEY not set, using placeholder");
                "xai-placeholder".to_string()
            });

        self.start_assistant_loop(move |text| {
            let key = api_key.clone();
            async move {
                let grok = GrokClient::new(&key);
                grok.chat(&text, None)
                    .await
                    .unwrap_or_else(|e| format!("Error: {}", e))
            }
        })
        .await
    }
}

impl Default for BeagleVoiceAssistant {
    fn default() -> Self {
        Self::new().unwrap_or_else(|_| Self {
            whisper: BeagleWhisper::default(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_whisper_creation() {
        let whisper = BeagleWhisper::new();
        // Should succeed even without whisper.cpp installed (warns but doesn't fail)
        assert!(whisper.is_ok());
    }

    #[tokio::test]
    async fn test_whisper_with_paths() {
        let whisper = BeagleWhisper::with_paths("/tmp/whisper", "/tmp/model.bin");
        assert!(whisper.is_ok());
    }

    #[tokio::test]
    async fn test_whisper_language() {
        let whisper = BeagleWhisper::new()
            .unwrap()
            .with_language("en")
            .with_threads(4);
        assert_eq!(whisper.language, "en");
        assert_eq!(whisper.threads, 4);
    }

    #[tokio::test]
    async fn test_tts_backend_detection() {
        let whisper = BeagleWhisper::new().unwrap();
        let backend = whisper.tts_backend();
        // Should be one of the valid backends
        assert!(matches!(
            backend,
            TtsBackend::Native | TtsBackend::Espeak | TtsBackend::None
        ));
    }

    #[tokio::test]
    async fn test_tts_backend_display() {
        assert_eq!(TtsBackend::Native.to_string(), "Native");
        assert_eq!(TtsBackend::Espeak.to_string(), "Espeak");
        assert_eq!(TtsBackend::None.to_string(), "None");
    }

    #[tokio::test]
    async fn test_speak_no_panic() {
        let whisper = BeagleWhisper::new().unwrap();
        // Should not panic even if TTS unavailable
        let result = whisper.speak("Test message").await;
        // Result depends on TTS availability - either Ok or Err, but no panic
        let _: Result<()> = result;
    }

    #[tokio::test]
    async fn test_assistant_creation() {
        let assistant = BeagleVoiceAssistant::new();
        // Should succeed even without whisper.cpp installed
        assert!(assistant.is_ok());
    }

    #[tokio::test]
    async fn test_assistant_whisper_access() {
        let assistant = BeagleVoiceAssistant::new().unwrap();
        let _whisper = assistant.whisper();
        // Should be able to access internal whisper
    }

    #[test]
    fn test_expanduser() {
        std::env::set_var("HOME", "/home/test");
        let path = expanduser("~/documents");
        assert_eq!(path, PathBuf::from("/home/test/documents"));

        let path = expanduser("/absolute/path");
        assert_eq!(path, PathBuf::from("/absolute/path"));
    }
}
