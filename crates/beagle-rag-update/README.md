# beagle-rag-update

Utilities for continuous, incremental RAG indexing into Qdrant.

Install (optional):
- `cargo install --locked --path crates/beagle-rag-update --bin darwin-brief --root /usr/local`
- If you omit `--root`, binaries land in `~/.cargo/bin` (fix: `export PATH="$HOME/.cargo/bin:$PATH"`).

## Incremental indexer (git-based)

Build/run:
- `cargo run -p beagle-rag-update --bin darwin-incremental-indexer -- --repo-path /path/to/repo --sync`
- Or index remote repos: `--repo-url https://github.com/org/repo.git --sync`
- Or use a repo targets file (YAML/TOML/JSON): `--repos-file scripts/darwin-repos.example.yaml --sync`
- Or discover public repos via GitHub API: `--github-user agourakis82 --sync`
- Or discover repos for the authenticated user (may include private): `--github-me --sync` (requires `DARWIN_GITHUB_TOKEN`/`GITHUB_TOKEN`/`GH_TOKEN`)
- For private repos with SSH keys: add `--github-clone-ssh`

State is stored in `~/.darwin_index_state.json` by default and uses `git diff --name-status <prev>..HEAD` to re-index only changed files and delete vectors for removed files.

Key env vars:
- `QDRANT_URL` (e.g. `http://10.100.100.4:6333`)
- `EMBEDDING_URL` (e.g. `http://10.100.100.4:8001/v1`)
- `EMBEDDING_MODEL` (e.g. `NV-Embed-v2`)
- `DARWIN_QDRANT_COLLECTION` (default `darwin-repos`)
- `GITHUB_WEBHOOK_SECRET` / `DARWIN_GITHUB_WEBHOOK_SECRET` (for webhook verification)

## Knowledge manager (papers/docs/books)

Index into separate collections:
- `cargo run -p beagle-rag-update --bin darwin-knowledge-manager -- list`
- `cargo run -p beagle-rag-update --bin darwin-knowledge-manager -- scan ~/knowledge`
- `cargo run -p beagle-rag-update --bin darwin-knowledge-manager -- add-paper paper.pdf --title "..." --author "..." --year 2024 --doi "..." --tags tag1 tag2`

PDF extraction uses `pdftotext` (install `poppler-utils`).

Optional ingestion ledger (Postgres):
- Set `DARWIN_LEDGER_DATABASE_URL=postgres://...` to record per-doc hashes/status and skip unchanged documents.
- Use `--force` on the binaries to re-index even if the ledger hash matches.

## Research harvester (literature → darwin-papers)

Fetches paper metadata/abstracts and indexes them into `darwin-papers` (plus saves a Markdown stub for traceability):
- `cargo run -p beagle-rag-update --bin darwin-research-harvester -- --query "HRV cognitive performance" --max-results 10`
- `cargo run -p beagle-rag-update --bin darwin-research-harvester -- --backend pubmed --query "PBPK antidepressants"`

Supported backends:
- `pubmed`, `arxiv`, `openalex`, `crossref`, `europepmc`, `all`

Topic registry (multi-query runs):
- `cargo run -p beagle-rag-update --bin darwin-research-harvester -- --topics-file scripts/darwin-research-topics.yaml`
- Filter: `--topic hrv-cognition --topic rag-security`

## Web harvester (URLs → darwin-docs)

Fetches public web pages, extracts text, writes a Markdown stub, and indexes into `darwin-docs`:
- `cargo run -p beagle-rag-update --bin darwin-web-harvester -- --url https://example.com/doc --allow-host example.com --tag docs`

Extra sources and policy:
- RSS/Atom: `--rss https://example.com/feed.xml`
- Sitemap: `--sitemap https://example.com/sitemap.xml` (also supports `.xml.gz` and sitemap indexes)
- Crawl: `--crawl-depth 1 --max-urls 50` (defaults to same-host; set `--allow-cross-host` to expand)
- Robots: respected by default; disable with `--ignore-robots`
- Optional path filters: `--allow-path-regex '^/docs/'` / `--deny-path-regex '^/blog/'` (or `DARWIN_WEB_ALLOW_PATH_REGEX`, `DARWIN_WEB_DENY_PATH_REGEX`)
- Concurrency/politeness: `--concurrency 8 --per-host-concurrency 2 --host-delay-ms 250` (or `DARWIN_WEB_CONCURRENCY`, `DARWIN_WEB_PER_HOST_CONCURRENCY`, `DARWIN_WEB_HOST_DELAY_MS`)
- Link fanout cap: `--max-links 200` (or `DARWIN_WEB_MAX_LINKS`)

Notes:
- PDF URLs are downloaded and indexed as PDFs (requires `pdftotext` from `poppler-utils`); a Markdown stub is still written for traceability.
- Canonical URLs are honored when present; common tracking query params (e.g. `utm_*`) are stripped for stable doc IDs.

## Eval harness (golden queries)

Runs retrieval checks (top-k) against Qdrant:
- `cargo run -p beagle-rag-update --bin darwin-eval -- --eval-file scripts/darwin-eval.yaml`

Outputs MRR and recall@k (micro + macro). Optional drift gates:
- `DARWIN_EVAL_MIN_MRR`, `DARWIN_EVAL_MAX_MRR_DROP`
- `DARWIN_EVAL_MIN_RECALL`, `DARWIN_EVAL_MAX_RECALL_DROP`

## Brief generator (topic briefs)

Generates Markdown briefs from the current corpus (retrieval + optional LLM synthesis):
- `cargo run -p beagle-rag-update --bin darwin-brief -- --topics-file scripts/darwin-research-topics.yaml`
- Output: `~/knowledge/briefs/<topic>/latest.md`

Notes:
- Set `BEAGLE_ROUTING_POLICY=minimax-grok-deepseek` to prefer MiniMax → Grok → DeepSeek.
- Set `BEAGLE_ROUTING_POLICY=zai-grok-deepseek` to prefer Z.ai → Grok → DeepSeek.
- Use `--no-llm` to emit a retrieval report without calling an LLM.
- Use `--strict-citations` / `DARWIN_BRIEF_STRICT_CITATIONS=true` to fail on out-of-range citations like `[99]`.
