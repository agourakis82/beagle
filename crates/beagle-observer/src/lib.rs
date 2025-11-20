//! Universal Observer v0.2 + v0.3 - "Ativa Tudo"
//!
//! Captura completa de:
//! - File changes (papers, notes, thoughts)
//! - Clipboard (a cada 3s)
//! - Screenshots (a cada 30s)
//! - Input activity (teclado/mouse)
//! - Browser history (Chrome + Firefox)
//! - HealthKit data (v0.3 - macOS/iOS)

use chrono::Utc;
use notify::{EventKind, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::time;
use uuid::Uuid;
use tracing::{info, warn, error};
use serde::{Deserialize, Serialize};
use axum::{routing::post, Router, Json};
use serde_json::Value;
use std::sync::Arc;
mod broadcast;
use broadcast::ObservationBroadcast;

#[derive(Serialize, Clone, Debug)]
pub struct Observation {
    pub id: String,
    pub timestamp: String,
    pub source: String,
    pub path: Option<String>,
    pub content_preview: String,
    pub metadata: serde_json::Value,
}

#[derive(Deserialize)]
struct BrowserEntry {
    url: String,
    title: Option<String>,
    visit_time: Option<String>,
}

pub struct UniversalObserver {
    broadcast: Arc<ObservationBroadcast>,
    observations_tx: Arc<mpsc::UnboundedSender<Observation>>,
    data_dir: PathBuf,
}

impl UniversalObserver {
    pub fn new() -> anyhow::Result<Self> {
        let broadcast = Arc::new(ObservationBroadcast::new());
        let (tx, mut rx) = mpsc::unbounded_channel();
        let broadcast_clone = broadcast.clone();
        
        // Task que repassa todas as observações para o broadcast
        tokio::spawn(async move {
            while let Some(obs) = rx.recv().await {
                broadcast_clone.broadcast(obs).await;
            }
        });
        
        let cfg = beagle_config::load();
        let data_dir = PathBuf::from(&cfg.storage.data_dir);
        
        // Cria diretórios necessários
        std::fs::create_dir_all(&data_dir.join("screenshots"))?;
        std::fs::create_dir_all(&data_dir.join("observations"))?;
        
        Ok(Self {
            broadcast,
            observations_tx: Arc::new(tx),
            data_dir,
        })
    }

    /// Retorna um receiver para observações
    pub async fn subscribe(&self) -> mpsc::UnboundedReceiver<Observation> {
        self.broadcast.subscribe().await
    }

    pub async fn start_full_surveillance(&self) -> anyhow::Result<()> {
        let tx = self.observations_tx.clone();
        let data_dir = self.data_dir.clone();

        // 1. File watcher (papers, notes, thoughts)
        let tx1 = tx.clone();
        let data_dir1 = data_dir.clone();
        tokio::spawn(async move {
            let mut watcher = match notify::recommended_watcher(move |res: Result<notify::Event, notify::Error>| {
                if let Ok(event) = res {
                    if matches!(event.kind, EventKind::Create(_) | EventKind::Modify(_)) {
                        for path in event.paths {
                            let content = std::fs::read_to_string(&path)
                                .unwrap_or_default();
                            let preview = content
                                .chars()
                                .take(280)
                                .collect::<String>();
                            
                            let _ = tx1.send(Observation {
                                id: Uuid::new_v4().to_string(),
                                timestamp: Utc::now().to_rfc3339(),
                                source: "file_change".to_string(),
                                path: Some(path.to_string_lossy().to_string()),
                                content_preview: preview,
                                metadata: serde_json::json!({
                                    "kind": format!("{:?}", event.kind)
                                }),
                            });
                        }
                    }
                }
            }) {
                Ok(w) => w,
                Err(e) => {
                    error!("Falha ao criar file watcher: {}", e);
                    return;
                }
            };

            for p in &["thoughts", "papers/drafts", "notes"] {
                let path = data_dir1.join(p);
                if path.exists() {
                    if let Err(e) = watcher.watch(&path, RecursiveMode::Recursive) {
                        warn!("Falha ao observar {}: {}", path.display(), e);
                    } else {
                        info!("Observando: {}", path.display());
                    }
                }
            }

            std::future::pending::<()>().await;
        });

        // 2. Clipboard watcher (a cada 3s)
        let tx2 = tx.clone();
        tokio::spawn(async move {
            let mut last = String::new();
            loop {
                #[cfg(target_os = "macos")]
                {
                    if let Ok(clip) = get_clipboard_macos() {
                        if clip != last && !clip.trim().is_empty() && clip.len() < 5000 {
                            let _ = tx2.send(Observation {
                                id: Uuid::new_v4().to_string(),
                                timestamp: Utc::now().to_rfc3339(),
                                source: "clipboard".to_string(),
                                path: None,
                                content_preview: clip.clone(),
                                metadata: serde_json::json!({ "length": clip.len() }),
                            });
                            last = clip;
                        }
                    }
                }
                #[cfg(target_os = "linux")]
                {
                    if let Ok(clip) = get_clipboard_linux() {
                        if clip != last && !clip.trim().is_empty() && clip.len() < 5000 {
                            let _ = tx2.send(Observation {
                                id: Uuid::new_v4().to_string(),
                                timestamp: Utc::now().to_rfc3339(),
                                source: "clipboard".to_string(),
                                path: None,
                                content_preview: clip.clone(),
                                metadata: serde_json::json!({ "length": clip.len() }),
                            });
                            last = clip;
                        }
                    }
                }
                #[cfg(target_os = "windows")]
                {
                    if let Ok(clip) = get_clipboard_windows() {
                        if clip != last && !clip.trim().is_empty() && clip.len() < 5000 {
                            let _ = tx2.send(Observation {
                                id: Uuid::new_v4().to_string(),
                                timestamp: Utc::now().to_rfc3339(),
                                source: "clipboard".to_string(),
                                path: None,
                                content_preview: clip.clone(),
                                metadata: serde_json::json!({ "length": clip.len() }),
                            });
                            last = clip;
                        }
                    }
                }
                time::sleep(Duration::from_secs(3)).await;
            }
        });

        // 3. Screenshot a cada 30s
        let tx3 = tx.clone();
        let screenshot_dir = data_dir.join("screenshots");
        tokio::spawn(async move {
            let mut interval = time::interval(Duration::from_secs(30));
            loop {
                interval.tick().await;
                let filename = format!("{}.png", Utc::now().format("%Y%m%d_%H%M%S"));
                let path = screenshot_dir.join(&filename);
                
                if capture_screenshot(&path).is_ok() {
                    let _ = tx3.send(Observation {
                        id: Uuid::new_v4().to_string(),
                        timestamp: Utc::now().to_rfc3339(),
                        source: "screenshot".to_string(),
                        path: Some(path.to_string_lossy().to_string()),
                        content_preview: String::new(),
                        metadata: serde_json::json!({ "filename": filename }),
                    });
                }
            }
        });

        // 4. Input activity (teclado/mouse) - detecta se está ativo
        let tx4 = tx.clone();
        tokio::spawn(async move {
            let mut last_activity = Instant::now();
            loop {
                let has_activity = check_input_activity();
                if has_activity {
                    if last_activity.elapsed() > Duration::from_secs(60) {
                        let _ = tx4.send(Observation {
                            id: Uuid::new_v4().to_string(),
                            timestamp: Utc::now().to_rfc3339(),
                            source: "input_activity".to_string(),
                            path: None,
                            content_preview: "Usuário ativo".to_string(),
                            metadata: serde_json::json!({}),
                        });
                    }
                    last_activity = Instant::now();
                }
                time::sleep(Duration::from_millis(500)).await;
            }
        });

        // 5. Browser history (Chrome + Firefox) - a cada 5 min
        let tx5 = tx.clone();
        tokio::spawn(async move {
            let mut interval = time::interval(Duration::from_secs(300));
            loop {
                interval.tick().await;
                if let Ok(history) = Self::scrape_browser_history() {
                    for entry in history.iter().take(10) {
                        let _ = tx5.send(Observation {
                            id: Uuid::new_v4().to_string(),
                            timestamp: Utc::now().to_rfc3339(),
                            source: "browser_history".to_string(),
                            path: None,
                            content_preview: entry.title.clone().unwrap_or_else(|| entry.url.clone()),
                            metadata: serde_json::json!({
                                "url": entry.url,
                                "visit_time": entry.visit_time
                            }),
                        });
                    }
                }
            }
        });

        // 6. HealthKit bridge (v0.3) - localhost:8081
        let tx6 = tx.clone();
        tokio::spawn(async move {
            let app = Router::new()
                .route("/health", post(move |Json(payload): Json<Value>| {
                    let tx = tx6.clone();
                    async move {
                        let hrv = payload.get("hrv_sdnn").and_then(|v| v.as_f64()).unwrap_or(0.0);
                        let hr = payload.get("hr").and_then(|v| v.as_f64()).unwrap_or(0.0);
                        let spo2 = payload.get("spo2").and_then(|v| v.as_f64()).unwrap_or(0.0);
                        
                        let _ = tx.send(Observation {
                            id: Uuid::new_v4().to_string(),
                            timestamp: Utc::now().to_rfc3339(),
                            source: "healthkit".to_string(),
                            path: None,
                            content_preview: format!("HRV: {:.1}ms, HR: {:.0}bpm, SpO2: {:.0}%", hrv, hr, spo2),
                            metadata: payload,
                        });
                        "ok"
                    }
                }));

            info!("HealthKit bridge ativo em http://localhost:8081/health");
            
            let listener = tokio::net::TcpListener::bind("0.0.0.0:8081")
                .await
                .expect("Falha ao bind na porta 8081");
            
            axum::serve(listener, app)
                .await
                .expect("Falha ao iniciar servidor HealthKit");
        });

        info!("Universal Observer v0.2 + v0.3 ATIVA TUDO – surveillance total iniciada");
        Ok(())
    }

    pub fn scrape_browser_history() -> anyhow::Result<Vec<BrowserEntry>> {
        // Chrome (Linux/macOS)
        let home = std::env::var("HOME")?;
        let chrome_paths = [
            format!("{}/.config/google-chrome/Default/History", home),
            format!("{}/Library/Application Support/Google/Chrome/Default/History", home),
        ];

        for path in &chrome_paths {
            if Path::new(path).exists() {
                if let Ok(output) = std::process::Command::new("sqlite3")
                    .arg(path)
                    .arg("SELECT url, title, datetime(last_visit_time/1000000-11644473600, 'unixepoch') FROM urls ORDER BY last_visit_time DESC LIMIT 10")
                    .output()
                {
                    let text = String::from_utf8_lossy(&output.stdout);
                    let mut entries = Vec::new();
                    for line in text.lines() {
                        let parts: Vec<&str> = line.split('|').collect();
                        if parts.len() >= 2 {
                            entries.push(BrowserEntry {
                                url: parts[0].to_string(),
                                title: Some(parts[1].to_string()),
                                visit_time: parts.get(2).map(|s| s.to_string()),
                            });
                        }
                    }
                    if !entries.is_empty() {
                        return Ok(entries);
                    }
                }
            }
        }

        // Firefox (Linux/macOS)
        let firefox_pattern = format!("{}/.mozilla/firefox/*/places.sqlite", home);
        if let Ok(output) = std::process::Command::new("sh")
            .arg("-c")
            .arg(format!("find {} -name places.sqlite 2>/dev/null | head -1", firefox_pattern.replace("/*/", "/")))
            .output()
        {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() && Path::new(&path).exists() {
                if let Ok(output) = std::process::Command::new("sqlite3")
                    .arg(&path)
                    .arg("SELECT url, title, datetime(last_visit_date/1000000, 'unixepoch') FROM moz_places ORDER BY last_visit_date DESC LIMIT 10")
                    .output()
                {
                    let text = String::from_utf8_lossy(&output.stdout);
                    let mut entries = Vec::new();
                    for line in text.lines() {
                        let parts: Vec<&str> = line.split('|').collect();
                        if parts.len() >= 2 {
                            entries.push(BrowserEntry {
                                url: parts[0].to_string(),
                                title: Some(parts[1].to_string()),
                                visit_time: parts.get(2).map(|s| s.to_string()),
                            });
                        }
                    }
                    if !entries.is_empty() {
                        return Ok(entries);
                    }
                }
            }
        }

        Ok(Vec::new())
    }

    pub async fn physiological_state_analysis(&self, observations: &[Observation]) -> anyhow::Result<String> {
        let health_obs: Vec<&Observation> = observations
            .iter()
            .filter(|o| o.source == "healthkit")
            .rev()
            .take(10)
            .collect();

        if health_obs.is_empty() {
            return Ok("Nenhum dado de HealthKit disponível ainda.".to_string());
        }

        let prompt = format!(
            "Você é o metacognitor fisiológico do Demetrios.\n\
            Aqui estão os últimos {} pontos de HealthKit (HRV, frequência cardíaca, SpO2, minutos mindful).\n\n\
            Dados:\n{}\n\n\
            Diagnóstico brutal em 5 linhas:\n\
            1. Estado cognitivo atual (flow / stress / burnout)\n\
            2. Qualidade do sono recente\n\
            3. Nível real de mindfulness vs intenção\n\
            4. Recomendação fisiológica imediata (respiração 4-7-8, caminhada, cochilo, etc.)\n\
            5. Impacto previsto na produtividade científica hoje\n\nResposta:",
            health_obs.len(),
            serde_json::to_string_pretty(&health_obs)?
        );

        let router = beagle_llm::BeagleRouter;
        router.complete(&prompt).await
    }
}

// Clipboard functions
#[cfg(target_os = "macos")]
pub fn get_clipboard_macos() -> anyhow::Result<String> {
    use std::process::Command;
    let output = Command::new("pbpaste").output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(target_os = "linux")]
pub fn get_clipboard_linux() -> anyhow::Result<String> {
    use std::process::Command;
    // Tenta xclip primeiro
    if let Ok(output) = Command::new("xclip").arg("-selection").arg("clipboard").arg("-o").output() {
        if output.status.success() {
            return Ok(String::from_utf8_lossy(&output.stdout).to_string());
        }
    }
    // Fallback para xsel
    let output = Command::new("xsel").arg("--clipboard").arg("--output").output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(target_os = "windows")]
fn get_clipboard_windows() -> anyhow::Result<String> {
    // Windows clipboard via PowerShell
    use std::process::Command;
    let output = Command::new("powershell")
        .arg("-Command")
        .arg("Get-Clipboard")
        .output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

// Screenshot functions
fn capture_screenshot(path: &Path) -> anyhow::Result<()> {
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        Command::new("screencapture")
            .arg("-x")
            .arg(path)
            .output()?;
        Ok(())
    }
    
    #[cfg(target_os = "linux")]
    {
        use std::process::Command;
        // Tenta gnome-screenshot primeiro
        if Command::new("gnome-screenshot")
            .arg("-f")
            .arg(path)
            .output()
            .is_ok() {
            return Ok(());
        }
        // Fallback para scrot
        Command::new("scrot")
            .arg(path)
            .output()?;
        Ok(())
    }
    
    #[cfg(target_os = "windows")]
    {
        // Windows screenshot via PowerShell
        use std::process::Command;
        let script = format!(
            "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height; $graphics = [System.Drawing.Graphics]::FromImage($bmp); $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size); $bmp.Save('{}'); $graphics.Dispose(); $bmp.Dispose()",
            path.display()
        );
        Command::new("powershell")
            .arg("-Command")
            .arg(&script)
            .output()?;
        Ok(())
    }
    
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        Err(anyhow::anyhow!("Screenshot não suportado nesta plataforma"))
    }
}

// Input activity detection
fn check_input_activity() -> bool {
    #[cfg(target_os = "macos")]
    {
        // macOS: verifica se há processos de input ativos
        use std::process::Command;
        if let Ok(output) = Command::new("ps")
            .arg("aux")
            .output()
        {
            let text = String::from_utf8_lossy(&output.stdout);
            // Verifica se há atividade de teclado/mouse (simplificado)
            return text.contains("WindowServer") || text.contains("loginwindow");
        }
    }
    
    #[cfg(target_os = "linux")]
    {
        // Linux: verifica eventos de input
        use std::process::Command;
        if let Ok(output) = Command::new("xset")
            .arg("q")
            .output()
        {
            return output.status.success();
        }
    }
    
    #[cfg(target_os = "windows")]
    {
        // Windows: sempre retorna true (simplificado)
        return true;
    }
    
    false
}
