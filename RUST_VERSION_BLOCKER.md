# Rust Version Blocker

## Issue

The Beagle codebase (post-darwin-hpc-governance merge) requires **Rust 1.86+** to compile.

Current system Rust: **1.85.0** (built from source tarball, system-wide in /usr/bin)

## Root Cause

Transitive dependencies have high MSRV requirements:
- `home` 0.5.12 (from `gcp_auth`) → requires 1.88
- `icu_*` 2.2.0 (from unicode/i18n crates) → require 1.86
- `time` 0.3.47 → requires 1.88

These are pulled in by essential crates (`gcp_auth`, `chrono`, etc.) that cannot be easily downgraded without cascading changes.

## Dependency Chain Example

```
beagle-llm 
  └── gcp_auth 0.10.0
      └── home 0.5.12 (requires rustc 1.88)
```

## Solutions

### Option A: Update System Rust (Recommended)
```bash
# On t560-proxmox (requires system admin access)
cd /tmp
wget https://static.rust-lang.org/dist/rust-1.86.0-x86_64-unknown-linux-gnu.tar.gz
tar xzf rust-1.86.0-x86_64-unknown-linux-gnu.tar.gz
cd rust-1.86.0-x86_64-unknown-linux-gnu
./install.sh --prefix=/usr

# Verify
rustc --version  # should show 1.86.0+
cargo test --all
```

### Option B: Use Remote Workspace (Immediate)
The K8s workspace at `/workspace/sounio` has newer Rust and can be used for:
```bash
# SSH into K8s workspace
ssh -i ~/.ssh/id_ed25519 -p 2222 openvscode-server@sounio-workspace-ssh.tail21cbc4.ts.net

# Or use browser
http://sounio-workspace.tail21cbc4.ts.net:8080
```

Alternatively, Beagle has a K8s workspace (TBD if active):
```bash
# If beagle-workspace exists
kubectl -n beagle exec -it deployment/beagle-workspace -- bash
cd /workspace/beagle
cargo test --all
```

### Option C: Pin Dependencies (Not Recommended)
Manually downgrading transitive deps:
- Requires changing `gcp_auth` usage or alternative auth
- `icu` is pulled by `chrono` — would need to audit all date handling
- High risk of cascading breakage; not attempted here

## Status

**Blocker**: ✋ System Rust too old  
**Impact**: `cargo test --all` fails at compile stage  
**Workaround**: Use K8s workspace for testing  
**Fix**: Update system Rust to 1.86.0 (requires system admin)

## Next Steps

1. **Immediate**: Use K8s workspace for testing (if available)
2. **Short-term**: Raise with system admin to update `/usr/bin/rustc`
3. **CI/CD**: Ensure GitHub Actions use Rust 1.86+ for validation

---

**Created**: 2026-04-15  
**Merge commit**: 55e826b (Beagle feat/darwin-hpc-governance merged to main)  
**Unresolved**: Rust version upgrade needed on t560-proxmox
