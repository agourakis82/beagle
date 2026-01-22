# Dev-Canon Runbook (Core + MCP + Darwin ResearchOps)

## 1) Install `darwin-*` binaries

Recommended (works with systemd + Core Darwin jobs):

```bash
sudo bash scripts/systemd/install-darwin-bins.sh --root /usr/local
```

If you install without `--root`, binaries land in `~/.cargo/bin`:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
# or (for Core jobs + systemd scripts)
export DARWIN_BIN_DIR="$HOME/.cargo/bin"
```

Quick helper (adds common bin dirs to `PATH` and sets `BEAGLE_WORKSPACE_ROOT`):

```bash
source scripts/activate_darwin.sh
```

Optional: install systemd timers (indexer 6h, research 12h, web 12h, knowledge daily, nightly 03:00):

```bash
sudo bash scripts/systemd/install-darwin-timers.sh --user root --workspace /root/beagle --write-env-examples --enable
```

Security note: `/etc/darwin-*.env` and `/etc/beagle-*.env` may contain API keys; keep them `0600` (the installer writes them with restrictive perms).

## 2) Core host environment (keep keys out of repo)

Minimum for Darwin:

```bash
export BEAGLE_WORKSPACE_ROOT=/root/beagle
export BEAGLE_DATA_DIR=/root/beagle-data
export BEAGLE_PROFILE=lab
export BEAGLE_SAFE_MODE=true

export QDRANT_URL=http://localhost:6333
export EMBEDDING_URL=http://localhost:8001/v1
export EMBEDDING_MODEL=NV-Embed-v2

# Recommended: query all Darwin collections (Exocortex + brief)
export BEAGLE_QDRANT_COLLECTIONS=darwin-repos,darwin-papers,darwin-docs,darwin-books
# Or: single collection
# export BEAGLE_QDRANT_COLLECTION=darwin-repos
```

Provider policy (pick one):

- MiniMax-first:
  - `export BEAGLE_ROUTING_POLICY=minimax-grok-deepseek`
  - `export MINIMAX_API_KEY=...`
  - (optional) `export MINIMAX_API_BASE=https://api.minimax.io/anthropic/v1`
- Z.ai-first:
  - `export BEAGLE_ROUTING_POLICY=zai-grok-deepseek`
  - `export ZAI_API_KEY=...`
  - (optional) `export ZAI_API_BASE=https://open.bigmodel.cn/api/paas/v4`
  - (optional) `export ZAI_MODEL=GLM-4.7`

Fallbacks:
- `export XAI_API_KEY=...` (Grok)
- `export DEEPSEEK_API_KEY=...` (math tier)
Premium (optional): if configured, critical/phd tasks can route to subscriptions:
- `export ANTHROPIC_API_KEY=...` (Claude Direct)
- Install `claude` CLI for `ClaudeCli` routing (no key)
- `export GITHUB_TOKEN=...` / `GH_TOKEN=...` (Copilot)
- `export CURSOR_API_KEY=...` (Cursor)

## 3) Knowledge base (local PDFs/docs/books)

PDF indexing uses `pdftotext`:

```bash
sudo apt-get update
sudo apt-get install -y poppler-utils
```

Create directories:

```bash
bash scripts/setup_knowledge_dirs.sh /root/knowledge
```

## 4) Start BEAGLE Core

```bash
cargo run -p beagle-monorepo --bin core_server --release
```

Or install and run as systemd (recommended for always-on):

```bash
sudo bash scripts/systemd/install-beagle-services.sh --user root --workspace /root/beagle --write-env-examples --enable
```

## 5) Start MCP server

```bash
cd beagle-mcp-server
cp .env.example .env  # set BEAGLE_CORE_URL=http://localhost:8080
npm install
npm run build
npm start
```

## 6) Trigger nightly ResearchOps via MCP

Use either `beagle_darwin_nightly_workflow_minimax` or `beagle_darwin_nightly_workflow_zai`.
Example args (no secrets):

```json
{
  "harvest_args": "--topics-file scripts/darwin-research-topics.yaml --backend all",
  "web_harvest_args": "--rss https://example.com/feed.xml --crawl-depth 1 --max-urls 200 --tag sota",
  "brief_args": "--topics-file scripts/darwin-research-topics.yaml --delta-days 7",
  "eval_args": "--eval-file scripts/darwin-eval.yaml --k 10 --max-mrr-drop 0.05",
  "env": { "DARWIN_BIN_DIR": "/root/.cargo/bin" }
}
```

Follow up with `beagle_get_darwin_job_status` and `beagle_get_darwin_job_artifacts`.

## 6.1) Trigger incremental indexing via MCP (repos)

Use `beagle_darwin_indexer` to run the git-based incremental indexer on the Core host.

Examples:

- Index a local repo:
  `{ "repo_path": ["/root/beagle"], "sync": true }`
- Index all public repos from a GitHub user:
  `{ "github_user": ["agourakis82"], "sync": true }`
- Index repos for the authenticated GitHub user (may include private; requires token on host):
  `{ "github_me": true, "github_clone_ssh": true, "sync": true }`
- Index via repo registry:
  `{ "repos_file": ["scripts/darwin-repos.example.yaml"], "sync": true }`

## 6.2) GitHub push webhook (optional)

- Configure `GITHUB_WEBHOOK_SECRET` (or `DARWIN_GITHUB_WEBHOOK_SECRET`) on the BEAGLE Core host.
- For private repos, set `DARWIN_GITHUB_WEBHOOK_CLONE_SSH=true` to prefer `ssh_url` when cloning.

## 7) HRV + TTS (optional quick check)

- Update HRV: `beagle_observer_update_physio` (`hrv_ms`, optional `heart_rate_bpm`)
- Speak: `beagle_voice_tts` (`text`, optional `language`, `use_hrv_rate=true`)
