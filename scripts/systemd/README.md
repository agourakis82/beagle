# DARWIN systemd (continuous RAG + ResearchOps)

1) Install binaries (recommended for systemd: `/usr/local/bin`):
- Quick path: `sudo bash scripts/systemd/install-darwin-bins.sh --root /usr/local`
- Manual (from repo root): `sudo cargo install --locked --path ./crates/beagle-rag-update --bin darwin-incremental-indexer --root /usr/local`
- Manual (from anywhere): `sudo cargo install --locked --path /path/to/beagle/crates/beagle-rag-update --bin darwin-incremental-indexer --root /usr/local`

If you install without `--root`, binaries go to `~/.cargo/bin` (fix: `export PATH="$HOME/.cargo/bin:$PATH"` or call the full path).

Tip: systemd services in this folder run `bash scripts/systemd/darwin-run.sh ...` to locate binaries via `DARWIN_BIN_DIR`, `PATH`, and common fallback paths (including `~/.cargo/bin`).

2) Create `/etc/darwin-indexer.env` (example):
```bash
QDRANT_URL=http://10.100.100.4:6333
EMBEDDING_URL=http://10.100.100.4:8001/v1
EMBEDDING_MODEL=NV-Embed-v2
DARWIN_LEDGER_DATABASE_URL=postgres://user:pass@host:5432/beagle
DARWIN_QDRANT_COLLECTION=darwin-repos
DARWIN_REPOS_DIR=/home/<user>/repos
DARWIN_INDEX_STATE_FILE=/home/<user>/.darwin_index_state.json
DARWIN_INDEX_ARGS="--repo-path /home/<user>/beagle"
# Optional repo registry:
# DARWIN_REPOS_FILE=/home/<user>/beagle/scripts/darwin-repos.example.yaml
# Optional GitHub discovery (public repos):
# DARWIN_GITHUB_USER=agourakis82
# DARWIN_GITHUB_ORG=darwin-cluster
# DARWIN_GITHUB_ME=true
# DARWIN_GITHUB_INCLUDE_FORKS=false
# DARWIN_GITHUB_CLONE_SSH=true
# DARWIN_GITHUB_API_BASE=https://api.github.com
# DARWIN_GITHUB_TOKEN=...  # or GITHUB_TOKEN / GH_TOKEN
DARWIN_INDEX_ERROR_WEBHOOK_URL=https://your.webhook/endpoint
```

Create `/etc/darwin-harvester.env` (example):
```bash
QDRANT_URL=http://10.100.100.4:6333
EMBEDDING_URL=http://10.100.100.4:8001/v1
EMBEDDING_MODEL=NV-Embed-v2
DARWIN_LEDGER_DATABASE_URL=postgres://user:pass@host:5432/beagle
BEAGLE_QDRANT_COLLECTIONS=darwin-repos,darwin-papers,darwin-docs,darwin-books
# Recommended: topic registry runs (multiple queries/backends/tags)
DARWIN_HARVEST_TOPICS_FILE=/home/<user>/beagle/scripts/darwin-research-topics.yaml
DARWIN_HARVEST_ARGS="--topics-file ${DARWIN_HARVEST_TOPICS_FILE} --backend all"

# Or ad-hoc CLI queries:
# DARWIN_HARVEST_ARGS="--backend all --max-results 10 --query \"HRV cognitive performance\" --query \"PBPK antidepressants\""
```

Create `/etc/darwin-web.env` (example):
```bash
QDRANT_URL=http://10.100.100.4:6333
EMBEDDING_URL=http://10.100.100.4:8001/v1
EMBEDDING_MODEL=NV-Embed-v2
DARWIN_WEB_HARVEST_ARGS="--sources-file /home/<user>/beagle/scripts/darwin-web-sources.example.yaml --max-urls 50 --crawl-depth 0"
# Or use: /home/<user>/beagle/scripts/darwin-web-sources.sota.yaml
```

Create `/etc/darwin-nightly.env` (example):
```bash
# Toggle steps
DARWIN_NIGHTLY_RUN_INDEXER=0
DARWIN_NIGHTLY_RUN_RESEARCH=1
DARWIN_NIGHTLY_RUN_WEB=0
DARWIN_NIGHTLY_RUN_BRIEF=1
DARWIN_NIGHTLY_RUN_EVAL=1

# Optional: override where darwin-* binaries live (default: /usr/local/bin)
# DARWIN_BIN_DIR=/home/<user>/.cargo/bin

# Briefs (optional, runs darwin-brief)
DARWIN_BRIEF_ARGS="--topics-file /home/<user>/beagle/scripts/darwin-research-topics.yaml --delta-days 7"

# Eval config (uses scripts/darwin-eval.yaml by default)
DARWIN_EVAL_FILE=/home/<user>/beagle/scripts/darwin-eval.yaml
DARWIN_EVAL_ARGS="--eval-file ${DARWIN_EVAL_FILE} --k 10 --max-mrr-drop 0.05"

# Optional: web harvesting inputs
# DARWIN_WEB_HARVEST_ARGS="--rss https://example.com/feed.xml --crawl-depth 1 --max-urls 50 --tag sota"

# Notifications (optional)
DARWIN_NIGHTLY_ERROR_WEBHOOK_URL=https://your.webhook/endpoint
DARWIN_NIGHTLY_SUCCESS_WEBHOOK_URL=https://your.webhook/endpoint
```

Create `/etc/darwin-knowledge.env` (example):
```bash
BEAGLE_WORKSPACE_ROOT=/home/<user>/beagle
DARWIN_BIN_DIR=/usr/local/bin

QDRANT_URL=http://10.100.100.4:6333
EMBEDDING_URL=http://10.100.100.4:8001/v1
EMBEDDING_MODEL=NV-Embed-v2

# Base directory with papers/, docs/, books/
DARWIN_KNOWLEDGE_ARGS="scan /home/<user>/knowledge"
```

3) Install and enable timers:
- `sudo cp scripts/systemd/darwin-indexer.* /etc/systemd/system/`
- `sudo cp scripts/systemd/darwin-research-harvester.* /etc/systemd/system/`
- `sudo cp scripts/systemd/darwin-web-harvester.* /etc/systemd/system/`
- `sudo cp scripts/systemd/darwin-knowledge-manager.* /etc/systemd/system/`
- `sudo cp scripts/systemd/darwin-nightly.* /etc/systemd/system/`
- `sudo systemctl daemon-reload`
- `sudo systemctl enable --now darwin-indexer.timer`
- `sudo systemctl enable --now darwin-research-harvester.timer`
- `sudo systemctl enable --now darwin-web-harvester.timer`
- `sudo systemctl enable --now darwin-knowledge-manager.timer`
- `sudo systemctl enable --now darwin-nightly.timer`

Or use the installer (recommended):
```bash
sudo bash scripts/systemd/install-darwin-timers.sh --user <user> --workspace /path/to/beagle --write-env-examples --enable
```

Security note:
- The installer writes `/etc/darwin-*.env` with mode `0600` by default (these files may contain API keys).

4) Debug:
- `journalctl -u darwin-indexer.service -n 200 --no-pager`
- `journalctl -u darwin-research-harvester.service -n 200 --no-pager`
- `journalctl -u darwin-web-harvester.service -n 200 --no-pager`
- `journalctl -u darwin-knowledge-manager.service -n 200 --no-pager`
- `journalctl -u darwin-nightly.service -n 200 --no-pager`

## BEAGLE Core + MCP (optional)

To run the Core HTTP API and MCP server under systemd:

```bash
sudo bash scripts/systemd/install-beagle-services.sh --user <user> --workspace /path/to/beagle --write-env-examples --enable
```

Prereqs:
- Core binary installed (recommended): `cargo install --path apps/beagle-monorepo --bin core_server --locked --root /usr/local`
- MCP built: `cd beagle-mcp-server && npm install && npm run build`

## Expose MCP publicly (Cloudflare Tunnel)

To use BEAGLE MCP from **claude.ai** (remote MCP connector), you can expose the local MCP HTTP port via Cloudflare Tunnel.

Quick start (ephemeral URL):

```bash
sudo cp scripts/systemd/cloudflared-beagle.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-beagle.service
sudo journalctl -u cloudflared-beagle.service --no-pager -n 200 | rg -o 'https://[a-z0-9-]+\\.trycloudflare\\.com' | tail -n 1
```

Runbook: `docs/MCP_EXTERNAL_ACCESS.md`
