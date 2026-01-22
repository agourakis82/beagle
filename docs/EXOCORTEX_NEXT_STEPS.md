# BEAGLE Exocortex — Next Priorities (Dev-Canon)

## P0 — Make the loop run end-to-end (today)

1. **Infrastructure online**
   - Qdrant reachable (`QDRANT_URL`)
   - Embedding server reachable (`EMBEDDING_URL`, `EMBEDDING_MODEL`)
2. **Darwin binaries discoverable**
   - Install to `/usr/local/bin` or set `DARWIN_BIN_DIR` / `PATH`
   - Quick helper: `source scripts/activate_darwin.sh`
3. **Nightly loop smoke test**
   - Run `beagle_darwin_nightly_workflow_minimax` or `beagle_darwin_nightly_workflow_zai`
   - Confirm artifacts via `beagle_get_darwin_job_artifacts` (job log + summary)
4. **Systemd automation**
   - `sudo bash scripts/systemd/install-darwin-timers.sh --user <user> --write-env-examples --enable`
   - Edit `/etc/darwin-*.env` with real URLs/keys and webhook notifications

## P1 — Improve corpus quality (this week)

1. **Repo coverage**
   - Add more `--repo-path` / `--repo-url` targets and confirm delete semantics (removed files → removed chunks).
2. **Knowledge base**
   - Create `~/knowledge/{papers,docs,books}` and ingest via `darwin-knowledge-manager`.
3. **Deep web harvesting policy**
   - Configure allow/deny host + path regexes; keep `robots.txt` enabled by default.
4. **Briefing discipline**
   - Curate `scripts/darwin-research-topics.yaml` (enabled topics, tags, queries).

## P2 — Reliability + evaluation gates (next)

1. **Eval coverage**
   - Expand `scripts/darwin-eval.yaml` with golden queries tied to your actual projects.
2. **Drift monitoring**
   - Use `--min-mrr` / `--max-mrr-drop` and alert via `DARWIN_NIGHTLY_ERROR_WEBHOOK_URL`.
3. **Service hardening**
   - Implemented: `scripts/systemd/beagle-core.service`, `scripts/systemd/beagle-mcp.service`
   - Install: `sudo bash scripts/systemd/install-beagle-services.sh --user <user> --write-env-examples --enable`
