# Beagle MVP-0: Sounio Workday Daily Driver

This is the first daily-driver rollout slice. It is intentionally smaller than
the full spatial/paper/MemoryArena roadmap:

- cluster-canonical Beagle memory on `beagle-data`;
- Sounio workspace replay/block state on workspace PVC only;
- Project Cockpit as gateway, with `workspace-agent` as Workbench authority;
- Sounio Six agent lanes in the Apple Workbench;
- GraphRAG++ recovery of remembered work blocks.

## Build images

All build jobs default to `main` so the cluster builds the exact code promoted
by the release merge. They publish the same versioned MVP tag:

```bash
kubectl apply -f k8s/beagle/build-job.yaml
kubectl apply -f k8s/beagle/mcp-build-job.yaml
kubectl apply -f k8s/beagle-memory-lab/build-job.yaml
kubectl apply -f k8s/workspace-platform/workspace-agent-build-job.yaml
kubectl apply -f k8s/project-cockpit/build-job.yaml
```

Expected tag: `sounio-workday-mvp-c63a309`.

## Roll out

```bash
kubectl apply -k k8s/beagle
kubectl apply -k k8s/project-cockpit
kubectl apply -k k8s/beagle-memory-lab
kubectl apply -k k8s/sounio-workspace-habitat
```

`project-cockpit` must run with:

```text
PROJECT_COCKPIT_WORKBENCH_AUTHORITY=workspace-agent
```

## Smoke

```bash
COCKPIT_URL=http://project-cockpit.beagle.svc.cluster.local \
BEAGLE_CORE_URL=http://beagle-core.beagle.svc.cluster.local:8080 \
scripts/sounio-workday-mvp-smoke
```

The MVP passes when a real Sounio work block can be remembered and recovered
through GraphRAG++ with provenance, while secret-like content is blocked.
