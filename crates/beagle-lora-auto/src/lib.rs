//! BEAGLE LoRA Auto – parametrizado por ambiente
//! Construído para rodar o treinamento via Python e reiniciar o vLLM remotamente.

use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

/// Configuração carregada de variáveis de ambiente.
#[derive(Debug, Clone)]
pub struct LoraConfig {
    pub beagle_root: String,
    pub script_path: String,
    pub lora_host: String,
    pub vllm_host: String,
    pub model_name: String,
}

impl LoraConfig {
    /// Cria configuração a partir de variáveis de ambiente.
    /// 
    /// **Variáveis obrigatórias:**
    /// - `BEAGLE_ROOT`: Diretório raiz do BEAGLE
    /// - `BEAGLE_LORA_SCRIPT`: Caminho para script de treinamento
    /// - `VLLM_HOST`: Hostname para restart do vLLM (opcional se `VLLM_RESTART_SKIP=true`)
    /// 
    /// **Variáveis opcionais:**
    /// - `BEAGLE_LORA_MODEL`: Nome do modelo (default: unsloth/Llama-3.2-8B-Instruct-bnb-4bit)
    /// - `VLLM_RESTART_SKIP`: Se `true`, não tenta restart do vLLM
    pub fn from_env() -> Result<Self, String> {
        let beagle_root = env::var("BEAGLE_ROOT")
            .map_err(|_| "BEAGLE_ROOT não definido. Defina a variável de ambiente BEAGLE_ROOT com o diretório raiz do BEAGLE.")?;
        
        let script_path = env::var("BEAGLE_LORA_SCRIPT")
            .unwrap_or_else(|_| format!("{}/scripts/train_lora_unsloth.py", beagle_root));
        
        let vllm_host = env::var("VLLM_HOST").ok();
        
        let model_name = env::var("BEAGLE_LORA_MODEL")
            .unwrap_or_else(|_| "unsloth/Llama-3.2-8B-Instruct-bnb-4bit".to_string());
        
        Ok(Self {
            beagle_root,
            script_path,
            lora_host: vllm_host.clone().unwrap_or_default(),
            vllm_host: vllm_host.unwrap_or_default(),
            model_name,
        })
    }
}

impl Default for LoraConfig {
    fn default() -> Self {
        // Tenta carregar de env, mas não falha se não estiver definido
        // (para compatibilidade com testes)
        Self::from_env().unwrap_or_else(|_| Self {
            beagle_root: String::new(),
            script_path: String::new(),
            lora_host: String::new(),
            vllm_host: String::new(),
            model_name: "unsloth/Llama-3.2-8B-Instruct-bnb-4bit".to_string(),
        })
    }
}

/// Executa o script Python de LoRA e reinicia o vLLM.
pub fn train_lora(bad_draft: &str, good_draft: &str, output_dir: &str) -> Result<String, String> {
    let config = LoraConfig::from_env()
        .map_err(|e| format!("Configuração inválida: {}", e))?;

    if let Some(parent) = Path::new(output_dir).parent() {
        if let Err(err) = fs::create_dir_all(parent) {
            return Err(format!("Não foi possível criar pasta de saída: {err}"));
        }
    }

    let script_path = Path::new(&config.script_path);
    if !script_path.exists() {
        return Err(format!("Script não encontrado: {}", config.script_path));
    }

    // Salva drafts em arquivos temporários para o script Python.
    let tmp_dir = env::temp_dir().join("beagle_lora_auto");
    if let Err(err) = fs::create_dir_all(&tmp_dir) {
        return Err(format!("Falha ao preparar diretório temporário: {err}"));
    }
    let bad_path = tmp_dir.join("bad_draft.txt");
    let good_path = tmp_dir.join("good_draft.txt");

    if let Err(err) = fs::write(&bad_path, bad_draft) {
        return Err(format!("Falha ao salvar bad draft: {err}"));
    }
    if let Err(err) = fs::write(&good_path, good_draft) {
        return Err(format!("Falha ao salvar good draft: {err}"));
    }

    let output = Command::new("python3")
        .arg(script_path)
        .env("BAD_DRAFT", &bad_path)
        .env("GOOD_DRAFT", &good_path)
        .env("OUTPUT_DIR", output_dir)
        .env("MODEL_NAME", &config.model_name)
        .output()
        .map_err(|e| format!("Falha ao executar script: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(format!(
            "Script falhou (status {}): {stderr}\nstdout: {stdout}",
            output.status
        ));
    }

    // Restart vLLM (opcional - pode ser skipado com VLLM_RESTART_SKIP=true)
    if env::var("VLLM_RESTART_SKIP").unwrap_or_else(|_| "false".to_string()) != "true" {
        if config.vllm_host.is_empty() {
            return Err("VLLM_HOST não definido e VLLM_RESTART_SKIP não está true. Defina VLLM_HOST ou VLLM_RESTART_SKIP=true.".to_string());
        }
        
        let vllm_restart_cmd = env::var("VLLM_RESTART_CMD")
            .unwrap_or_else(|_| format!("cd {} && docker-compose restart vllm", config.beagle_root));
        
        let ssh_status = Command::new("ssh")
            .arg(&config.vllm_host)
            .arg(&vllm_restart_cmd)
            .status()
            .map_err(|e| format!("SSH falhou: {e}"))?;

        if !ssh_status.success() {
            return Err("Restart vLLM falhou".to_string());
        }
    }

    Ok("LoRA treinado e vLLM reiniciado".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fails_when_script_missing() {
        // Garante que não executamos nada se o script não existir.
        std::env::set_var(
            "BEAGLE_LORA_SCRIPT",
            "/tmp/nao_existe/train_lora_unsloth.py",
        );
        let result = train_lora("bad", "good", "/tmp/lora_out");
        assert!(result.is_err());
        std::env::remove_var("BEAGLE_LORA_SCRIPT");
    }
}
