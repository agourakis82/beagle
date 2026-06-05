# beagle-rag-update

Utilities for continuous, incremental RAG indexing into Qdrant.

## Incremental indexer (git-based)

Build/run:
- `cargo run -p beagle-rag-update --bin darwin-incremental-indexer -- --repo-path /path/to/repo --sync`
- Or index remote repos: `--repo-url https://github.com/org/repo.git --sync`

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
- Sitemap: `--sitemap https://example.com/sitemap.xml`
- Crawl: `--crawl-depth 1 --max-urls 50` (defaults to same-host; set `--allow-cross-host` to expand)
- Robots: respected by default; disable with `--ignore-robots`

## Eval harness (golden queries)

Runs retrieval checks (top-k) against Qdrant:
- `cargo run -p beagle-rag-update --bin darwin-eval -- --eval-file scripts/darwin-eval.yaml`
