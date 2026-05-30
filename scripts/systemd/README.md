# DARWIN Indexer systemd

1) Install binaries:
- `cargo install --path /home/demetrios/beagle/crates/beagle-rag-update --bin darwin-incremental-indexer`
- `cargo install --path /home/demetrios/beagle/crates/beagle-rag-update --bin darwin-research-harvester`
- (optional) `cargo install --path /home/demetrios/beagle/crates/beagle-rag-update --bin darwin-web-harvester`

2) Create `/etc/darwin-indexer.env` (example):
```bash
QDRANT_URL=http://10.100.100.4:6333
EMBEDDING_URL=http://10.100.100.4:8001/v1
EMBEDDING_MODEL=NV-Embed-v2
DARWIN_LEDGER_DATABASE_URL=postgres://user:pass@host:5432/beagle
DARWIN_QDRANT_COLLECTION=darwin-repos
DARWIN_REPOS_DIR=/home/demetrios/repos
DARWIN_INDEX_STATE_FILE=/home/demetrios/.darwin_index_state.json
DARWIN_INDEX_ARGS="--repo-path /home/demetrios/beagle"
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
DARWIN_HARVEST_TOPICS_FILE=/home/demetrios/beagle/scripts/darwin-research-topics.yaml
DARWIN_HARVEST_ARGS="--topics-file ${DARWIN_HARVEST_TOPICS_FILE} --backend all"

# Or ad-hoc CLI queries:
# DARWIN_HARVEST_ARGS="--backend all --max-results 10 --query \"HRV cognitive performance\" --query \"PBPK antidepressants\""
```

3) Install and enable the timer:
- `sudo cp scripts/systemd/darwin-indexer.* /etc/systemd/system/`
- `sudo cp scripts/systemd/darwin-research-harvester.* /etc/systemd/system/`
- `sudo systemctl daemon-reload`
- `sudo systemctl enable --now darwin-indexer.timer`
- `sudo systemctl enable --now darwin-research-harvester.timer`
