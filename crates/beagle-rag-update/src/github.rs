use anyhow::{Context, Result};
use reqwest::header::{HeaderMap, HeaderValue};
use serde::Deserialize;

#[derive(Debug, Clone)]
pub struct GitHubClient {
    client: reqwest::Client,
    api_base: String,
    token: Option<String>,
}

impl GitHubClient {
    pub fn new(api_base: impl Into<String>, token: Option<String>) -> Result<Self> {
        let client = reqwest::Client::builder()
            .user_agent("beagle-rag-update/0.10")
            .build()
            .context("failed to build GitHub HTTP client")?;
        Ok(Self {
            client,
            api_base: api_base.into().trim_end_matches('/').to_string(),
            token,
        })
    }

    pub fn token_from_env() -> Option<String> {
        std::env::var("DARWIN_GITHUB_TOKEN")
            .ok()
            .or_else(|| std::env::var("GITHUB_TOKEN").ok())
            .or_else(|| std::env::var("GH_TOKEN").ok())
    }

    pub async fn list_user_repos(&self, user: &str, include_forks: bool) -> Result<Vec<GitHubRepo>> {
        let url = format!("{}/users/{}/repos", self.api_base, user);
        self.list_repos(&url, include_forks).await
    }

    pub async fn list_org_repos(&self, org: &str, include_forks: bool) -> Result<Vec<GitHubRepo>> {
        let url = format!("{}/orgs/{}/repos", self.api_base, org);
        self.list_repos(&url, include_forks).await
    }

    /// List repos for the authenticated user (`GET /user/repos`).
    ///
    /// This can include private repos depending on token scopes.
    pub async fn list_authenticated_user_repos(
        &self,
        include_forks: bool,
    ) -> Result<Vec<GitHubRepo>> {
        let Some(_) = &self.token else {
            anyhow::bail!("GitHub token required for /user/repos (set DARWIN_GITHUB_TOKEN/GITHUB_TOKEN/GH_TOKEN)");
        };
        let url = format!("{}/user/repos", self.api_base);
        self.list_repos(&url, include_forks).await
    }

    async fn list_repos(&self, url: &str, include_forks: bool) -> Result<Vec<GitHubRepo>> {
        let mut all = Vec::new();
        let mut page: u32 = 1;

        loop {
            let mut headers = HeaderMap::new();
            headers.insert(
                "accept",
                HeaderValue::from_static("application/vnd.github+json"),
            );
            if let Some(token) = &self.token {
                let v = HeaderValue::from_str(&format!("Bearer {}", token))
                    .context("failed to build GitHub Authorization header")?;
                headers.insert("authorization", v);
            }

            let resp = self
                .client
                .get(url)
                .headers(headers)
                .query(&{
                    let mut q = vec![
                        ("per_page", "100".to_string()),
                        ("page", page.to_string()),
                        ("sort", "pushed".to_string()),
                        ("direction", "desc".to_string()),
                    ];
                    if url.ends_with("/user/repos") {
                        // Helps /user/repos include private repos (best-effort; ignored if unsupported).
                        q.push(("visibility", "all".to_string()));
                    }
                    q
                })
                .send()
                .await
                .with_context(|| format!("GitHub API request failed: {url}"))?;

            let status = resp.status();
            if !status.is_success() {
                let body = resp.text().await.unwrap_or_default();
                anyhow::bail!("GitHub API error {} for {}: {}", status, url, body);
            }

            let batch: Vec<GitHubRepo> = resp
                .json()
                .await
                .with_context(|| format!("failed to parse GitHub JSON response from {url}"))?;

            if batch.is_empty() {
                break;
            }

            for repo in batch {
                if !include_forks && repo.fork {
                    continue;
                }
                if repo.archived || repo.disabled {
                    continue;
                }
                all.push(repo);
            }

            page += 1;
            // Safety: avoid infinite loops if the API behaves unexpectedly.
            if page > 200 {
                break;
            }
        }

        Ok(all)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct GitHubRepo {
    pub name: String,
    pub full_name: Option<String>,
    pub clone_url: Option<String>,
    pub ssh_url: Option<String>,
    #[serde(default)]
    pub fork: bool,
    #[serde(default)]
    pub archived: bool,
    #[serde(default)]
    pub disabled: bool,
}
