# B26.7 GO / NO-GO

## GO when

- `sounio-workspace` is healthy in the `beagle` namespace
- Beagle resolves the Sounio habitat by `workstream_id`
- `launch_managed_workspace_session.sh --workstream sounio-lang-main --client cursor` succeeds
- `/workspace/sounio/.git` exists
- `git remote get-url origin` points to `https://github.com/sounio-lang/sounio.git`
- `bin/souc --version` succeeds
- restart preserves the same workstream/workspace/session identity
- cluster is green
- Slurm is green

## NO-GO when

- the workspace resolves to the Beagle habitat instead of Sounio
- the workspace root is a snapshot without `.git`
- managed attach cannot install or resume
- the repo cannot run `bin/souc --version`
- restart changes identity or breaks attach
