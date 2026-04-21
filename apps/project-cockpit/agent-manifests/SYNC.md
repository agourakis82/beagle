# Agent Manifests — Sync Note

Canonical source: `/home/devsounio/beagle/k8s/agent-pods/`

These files are copied here so they can be bundled into the cockpit Docker
image (Docker build context limits — can't COPY from parent of WORKDIR).

**Keep in sync** by running after edits in k8s/agent-pods/:
```
cp k8s/agent-pods/{cockpit-mcp-server.mjs,entrypoint.sh,service.yaml,statefulset.yaml} \
   apps/project-cockpit/agent-manifests/
```

Or automate via the `sync-agent-manifests.sh` script (future).
