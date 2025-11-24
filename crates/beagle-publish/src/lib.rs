//! BEAGLE Auto-Publish - Publicação automática no arXiv
//! Gera PDF bonito, metadata perfeito, DOI real — 100% automático

mod policy;
pub mod run_log;

use crate::policy::{PublishMode, PublishPolicy};
use crate::run_log::{init_run, save_run_metadata};
use anyhow::{anyhow, Context, Result};
use beagle_config::{beagle_data_dir, safe_mode};
use chrono::Utc;
use reqwest::Client;
use serde_json::json;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tracing::{error, info};

/// Publica paper no arXiv automaticamente (governado por PublishPolicy)
pub async fn publish_to_arxiv(
    title: &str,
    abstract_text: &str,
    markdown_path: &str,
    categories: &str,
) -> Result<String> {
    info!("🚀 Auto-publish pra arXiv iniciado — {}", title);

    let policy = PublishPolicy::from_env();
    let is_safe = safe_mode();
    let mut meta = init_run(
        "beagle-publish",
        policy.label(),
        title,
        "arxiv",
        is_safe || policy.is_dry_run(),
    );

    if is_safe {
        meta.notes = Some("SAFE_MODE ativo: forçando DryRun.".into());
        let meta_path = save_run_metadata(&meta)?;
        let plan_path = write_dry_run_plan(title, abstract_text, markdown_path, categories, None)?;
        info!(
            "SAFE_MODE ativo → dry-run apenas. Plano salvo em {:?} | meta {:?}",
            plan_path, meta_path
        );
        return Ok("dry-run".to_string());
    }

    match policy.mode {
        PublishMode::DryRun => {
            meta.notes = Some("PublishMode=DryRun: só salvando plano.".into());
            let meta_path = save_run_metadata(&meta)?;
            let plan_path =
                write_dry_run_plan(title, abstract_text, markdown_path, categories, None)?;
            info!(
                "Dry-run de publicação: plano em {:?} | meta {:?}",
                plan_path, meta_path
            );
            Ok(format!("dry-run:{}", plan_path.display()))
        }
        PublishMode::ManualConfirm => {
            meta.notes = Some("PublishMode=ManualConfirm: aguardando confirmação humana.".into());
            let meta_path = save_run_metadata(&meta)?;
            let plan_path =
                write_dry_run_plan(title, abstract_text, markdown_path, categories, None)?;

            // Salva arquivo de confirmação pendente
            let confirm_file = plan_path.with_extension("confirm");
            fs::write(&confirm_file, "PENDING_MANUAL_CONFIRMATION")?;
            info!(
                "Plano salvo em {:?}. Para confirmar, delete o arquivo {:?} | meta {:?}",
                plan_path, confirm_file, meta_path
            );

            Err(anyhow!(
                "Publicação requer confirmação manual. Plano salvo em {:?}",
                plan_path
            ))
        }
        PublishMode::FullAuto => {
            meta.notes = Some("Publicação automática autorizada (SAFE_MODE=false).".into());
            let meta_path = save_run_metadata(&meta)?;
            info!(
                "PublishMode=FullAuto: enviando para arXiv. Metadados em {:?}",
                meta_path
            );

            // 1. Gera PDF bonito com pandoc + LaTeX
            let pdf_final =
                generate_pdf(title, abstract_text, markdown_path).context("Falha ao gerar PDF")?;

            // 2. Valida PDF antes de submeter
            validate_pdf(&pdf_final)?;

            // 3. Upload pro arXiv via API
            let doi = upload_to_arxiv(title, abstract_text, &pdf_final, categories)
                .await
                .context("Falha ao submeter para arXiv")?;

            let mut meta_final = meta;
            meta_final.notes = Some(format!("Publicação concluída com DOI {}", doi));
            let _ = save_run_metadata(&meta_final);

            info!("✅ PAPER PUBLICADO NO ARXIV — DOI: {}", doi);
            Ok(doi)
        }
    }
}

fn write_dry_run_plan(
    title: &str,
    abstract_text: &str,
    markdown_path: &str,
    categories: &str,
    score: Option<f64>,
) -> Result<PathBuf> {
    let base_dir = beagle_data_dir();
    std::fs::create_dir_all(&base_dir)?;
    let plan_path = base_dir.join("publish_plan_dryrun.json");
    let payload = json!({
        "mode": "dry-run",
        "safe_mode": safe_mode(),
        "title": title,
        "abstract": abstract_text,
        "markdown_path": markdown_path,
        "categories": categories,
        "score": score,
        "timestamp": Utc::now().to_rfc3339(),
    });
    fs::write(&plan_path, serde_json::to_string_pretty(&payload)?)?;
    Ok(plan_path)
}

/// Gera PDF bonito com pandoc + LaTeX
fn generate_pdf(title: &str, _abstract_text: &str, markdown_path: &str) -> Result<PathBuf> {
    info!("📄 Gerando PDF com pandoc...");

    let pdf_final = PathBuf::from(format!(
        "/tmp/{}_arxiv.pdf",
        title.replace(' ', "_").chars().take(30).collect::<String>()
    ));

    // Converte markdown para PDF diretamente com pandoc
    let output = Command::new("pandoc")
        .args([
            markdown_path,
            "-o",
            pdf_final.to_str().unwrap(),
            "--pdf-engine=xelatex",
            "--template=default",
            "--standalone",
        ])
        .output()
        .context("Falha ao executar pandoc")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        error!("❌ Pandoc falhou: {}", stderr);
        return Err(anyhow!("Pandoc falhou: {}", stderr));
    }

    if !pdf_final.exists() {
        return Err(anyhow!("PDF não foi gerado"));
    }

    info!("✅ PDF gerado: {:?}", pdf_final);
    Ok(pdf_final)
}

/// Valida PDF antes de submeter
fn validate_pdf(pdf_path: &PathBuf) -> Result<()> {
    info!("🔍 Validando PDF...");

    // Verifica se arquivo existe
    if !pdf_path.exists() {
        return Err(anyhow!("PDF não existe: {:?}", pdf_path));
    }

    // Verifica tamanho (arXiv tem limite de 10MB)
    let metadata = fs::metadata(pdf_path)?;
    let size_mb = metadata.len() as f64 / 1_000_000.0;

    if size_mb > 10.0 {
        return Err(anyhow!("PDF muito grande: {:.2}MB (limite: 10MB)", size_mb));
    }

    info!("✅ PDF validado: {:.2}MB", size_mb);
    Ok(())
}

/// Upload pro arXiv via API
async fn upload_to_arxiv(
    title: &str,
    abstract_text: &str,
    pdf_path: &PathBuf,
    categories: &str,
) -> Result<String> {
    info!("📤 Submetendo para arXiv...");

    let auth_token = std::env::var("ARXIV_API_TOKEN")
        .context("ARXIV_API_TOKEN não configurado. Configure em arxiv.org → settings → API")?;

    let client = Client::new();

    // Metadata do paper
    let metadata = json!({
        "title": title,
        "authors": ["Demetrios Chiuratto Agourakis"],
        "abstract": abstract_text,
        "categories": categories.split_whitespace().collect::<Vec<_>>(),
        "license": "http://arxiv.org/licenses/nonexclusive-distrib/1.0/",
        "comments": "Generated automatically by BEAGLE SINGULARITY"
    });

    // Cria form multipart
    let pdf_bytes = fs::read(pdf_path).context("Falha ao ler PDF")?;

    let file_name = pdf_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("paper.pdf")
        .to_string();

    let form = reqwest::multipart::Form::new()
        .text("metadata", metadata.to_string())
        .part(
            "file",
            reqwest::multipart::Part::bytes(pdf_bytes)
                .file_name(file_name)
                .mime_str("application/pdf")
                .context("Falha ao criar part multipart")?,
        );

    // Submete
    let resp = client
        .post("https://arxiv.org/api/submit")
        .header("Authorization", format!("Bearer {}", auth_token))
        .multipart(form)
        .send()
        .await
        .context("Falha ao enviar requisição para arXiv")?;

    let status = resp.status();
    let text = resp
        .text()
        .await
        .context("Falha ao ler resposta do arXiv")?;

    info!("📥 arXiv resposta (status {}): {}", status, text);

    // Extrai DOI se sucesso
    if status.is_success() && text.contains("success") {
        // Extrai arXiv ID da resposta
        let arxiv_id = if let Some(start) = text.find("arxiv:") {
            let rest = &text[start + 6..];
            rest.split_whitespace().next().unwrap_or("unknown")
        } else if let Some(start) = text.find("arXiv:") {
            let rest = &text[start + 6..];
            rest.split_whitespace().next().unwrap_or("unknown")
        } else {
            "unknown"
        };

        let doi = format!("10.48550/arXiv.{}", arxiv_id);
        info!("✅ PAPER PUBLICADO NO ARXIV — DOI: {}", doi);
        Ok(doi)
    } else {
        Err(anyhow!("arXiv rejeitou (status {}): {}", status, text))
    }
}

/// Publica paper automaticamente quando score > 98
pub async fn auto_publish_if_ready(
    title: &str,
    abstract_text: &str,
    markdown_path: &str,
    score: f64,
) -> Result<Option<String>> {
    if score < 98.0 {
        info!("ℹ️  Score {} < 98.0, não publicando ainda", score);
        return Ok(None);
    }

    let policy = PublishPolicy::from_env();
    info!(
        "🎯 Score {} >= 98.0, iniciando fluxo de publicação (mode={}, SAFE_MODE={})",
        score,
        policy.label(),
        safe_mode()
    );
    let categories = "cs.AI q-bio.NC physics.bio-ph";

    let doi = publish_to_arxiv(title, abstract_text, markdown_path, categories).await?;

    if safe_mode() || policy.is_dry_run() || doi.starts_with("dry-run") {
        info!("Publicação está em modo dry-run/SAFE_MODE; nenhum post externo será realizado.");
        return Ok(None);
    }

    // Auto-posta no Twitter também
    if let Ok(twitter_ids) = beagle_twitter::auto_post_if_ready(
        title,
        abstract_text,
        &format!(
            "https://arxiv.org/abs/{}",
            doi.trim_start_matches("10.48550/arXiv.")
        ),
        score,
    )
    .await
    {
        if twitter_ids.is_some() {
            info!("✅ Thread bilíngue postada no Twitter");
        }
    }

    Ok(Some(doi))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore = "Requires ARXIV_API_TOKEN and pandoc"]
    async fn test_publish_to_arxiv() {
        // Teste manual - requer setup real
        let result = publish_to_arxiv(
            "Test Paper",
            "This is a test abstract",
            "/tmp/test.md",
            "cs.AI",
        )
        .await;

        // Não asserta sucesso pois requer setup real
        println!("Result: {:?}", result);
    }
}
