use crate::indexer::RepoTarget;
use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Deserialize)]
pub struct RepoTargetsFile {
    #[serde(default)]
    pub repos: Vec<RepoTargetSpec>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum RepoTargetSpec {
    String(String),
    Map(RepoTargetMap),
}

#[derive(Debug, Clone, Deserialize)]
pub struct RepoTargetMap {
    pub name: Option<String>,
    pub path: Option<String>,
    pub url: Option<String>,
}

pub fn load_repo_targets_file(path: &Path, default_repos_dir: &Path) -> Result<Vec<RepoTarget>> {
    let cfg = config::Config::builder()
        .add_source(config::File::from(path.to_path_buf()))
        .build()
        .with_context(|| format!("failed to load repo targets file: {}", path.display()))?;
    let parsed: RepoTargetsFile = cfg
        .try_deserialize()
        .with_context(|| format!("failed to parse repo targets file: {}", path.display()))?;
    parsed
        .repos
        .into_iter()
        .enumerate()
        .map(|(idx, spec)| spec.into_repo_target(default_repos_dir).with_context(|| {
            format!(
                "invalid repo target at index {} in {}",
                idx,
                path.display()
            )
        }))
        .collect()
}

impl RepoTargetSpec {
    fn into_repo_target(self, default_repos_dir: &Path) -> Result<RepoTarget> {
        match self {
            RepoTargetSpec::String(s) => {
                let s = s.trim().to_string();
                if s.is_empty() {
                    anyhow::bail!("empty repo spec string");
                }
                if looks_like_url(&s) {
                    let name = derive_name_from_url(&s)?;
                    Ok(RepoTarget {
                        name,
                        path: default_repos_dir.join(derive_dir_from_url(&s)?),
                        url: Some(s),
                    })
                } else {
                    let path = expand_tilde(&s);
                    let name = path
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("repo")
                        .to_string();
                    Ok(RepoTarget {
                        name,
                        path,
                        url: None,
                    })
                }
            }
            RepoTargetSpec::Map(m) => m.into_repo_target(default_repos_dir),
        }
    }
}

impl RepoTargetMap {
    fn into_repo_target(self, default_repos_dir: &Path) -> Result<RepoTarget> {
        let url = self.url.map(|u| u.trim().to_string()).filter(|u| !u.is_empty());
        let path = self
            .path
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .map(|p| expand_tilde(&p));

        let name = if let Some(name) = self.name.clone().filter(|n| !n.trim().is_empty()) {
            name.trim().to_string()
        } else if let Some(path) = &path {
            path.file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("repo")
                .to_string()
        } else if let Some(url) = &url {
            derive_name_from_url(url)?
        } else {
            anyhow::bail!("repo target must include at least one of: name, path, url");
        };

        let resolved_path = if let Some(path) = path {
            path
        } else if let Some(url) = &url {
            default_repos_dir.join(derive_dir_from_url(url)?)
        } else {
            anyhow::bail!("repo target missing path and url");
        };

        Ok(RepoTarget {
            name,
            path: resolved_path,
            url,
        })
    }
}

fn expand_tilde(s: &str) -> PathBuf {
    if let Some(rest) = s.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(s)
}

fn looks_like_url(s: &str) -> bool {
    let s = s.trim();
    s.starts_with("http://") || s.starts_with("https://") || s.starts_with("git@")
}

fn derive_name_from_url(url: &str) -> Result<String> {
    // https://github.com/org/repo.git -> repo
    // git@github.com:org/repo.git -> repo
    let trimmed = url.trim_end_matches('/');
    let last = trimmed
        .split('/')
        .last()
        .or_else(|| trimmed.split(':').last())
        .unwrap_or("");
    let name = last.trim_end_matches(".git").trim();
    if name.is_empty() {
        anyhow::bail!("could not derive repo name from url: {url}");
    }
    Ok(name.to_string())
}

fn derive_dir_from_url(url: &str) -> Result<String> {
    // We keep the legacy directory scheme: repos_dir/<repo-name>.
    // This matches previous index state + doc_id conventions.
    derive_name_from_url(url)
}

