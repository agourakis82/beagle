# Observability SOTA Layer

This directory extends the existing `darwin-observability` stack instead of
creating a second monitoring plane.

## Live design

- `kube-prometheus-stack` already runs in `darwin-platform`
- `node-exporter`, `kube-state-metrics`, `grafana`, `alertmanager`, and
  `prometheus` are already healthy
- This layer adds:
  - NVIDIA GPU telemetry via `dcgm-exporter`
  - Ceph cluster telemetry via `mgr/prometheus`

## Why this path

- one Prometheus, one Grafana, one alerting plane
- less operational drift
- easier dashboarding and recording-rule reuse
- matches the 2026 norm of extending an existing operator-based metrics stack

## Files

- `dcgm-exporter-values.yaml`
  - values for the official NVIDIA `dcgm-exporter` Helm chart
  - scoped to the GPU nodes only
  - emits a `ServiceMonitor` labeled for `darwin-observability`
- `dcgm-counters.production-safe.csv`
  - trimmed counter set for stable cluster-wide scraping
  - intentionally excludes `DCGM_FI_PROF_*` profiling counters that made the
    `r740` exporter scrape stall
- `ceph-mgr-prometheus-servicemonitor.yaml`
  - headless-ish static scrape target for the active Ceph manager metrics
  - labeled for `darwin-observability`
- `darwin-dashboard-gpu-ceph-storage.yaml`
  - Grafana dashboard ConfigMap for GPU, Ceph, and local storage tier signals
- `darwin-dashboard-hpc-control-room.yaml`
  - top-level Grafana control-room for the living stack:
    - observability plane health
    - Sounio workspace habitat and tailnet ingress
    - Slurm control plane
    - GPU and Ceph summary signals
- `darwin-dashboard-sounio-dev-loop.yaml`
  - Grafana dashboard focused on the active Sounio development loop:
    - promoted habitat health
    - tailnet ingress readiness
    - workspace CPU / memory / restart signals
    - rollback workspace visibility
- `darwin-dashboard-slurm-ops.yaml`
  - Grafana dashboard focused on Slurm operational health:
    - controller, accounting, login, REST, workers
    - core pod CPU / memory / restarts
    - GPU utilization while Slurm workloads are live
    - gpuorangefs auto-heal summary:
      - last run success
      - timer age
      - repaired / deferred / failed counts
      - per-node autoheal state timeline
- `darwin-dashboard-sounio-compiler-pipeline.yaml`
  - Grafana dashboard focused on the compiler and test loop inside the promoted
    Sounio workspace:
    - habitat readiness
    - ingress proxy readiness
    - workspace PVC binding
    - compiler/test CPU and memory pressure
    - restart drift on workspace and ingress pods
- `darwin-gpu-ceph-storage-rules.yaml`
  - PrometheusRule bundle for GPU exporter health, Ceph metrics health, quorum,
    and the published `r770` local cache PV
- `darwin-hpc-control-room-rules.yaml`
  - PrometheusRule bundle for observability stack health, Sounio workspace
    availability, tailnet ingress health, Slurm control-plane health, and
    root-filesystem / kubelet disk-pressure guardrails
- `darwin-sounio-slurm-ops-rules.yaml`
  - PrometheusRule bundle for:
    - Sounio habitat restart / CPU / memory pressure
    - Sounio compiler pipeline health:
      - habitat availability
      - ingress degradation
      - workspace PVC binding
      - restart drift
      - CPU throttling
      - workspace memory pressure
    - Slurm REST, login, CPU worker, GPU worker, and control-plane restart drift
    - gpuorangefs auto-heal observability:
      - stale timer / textfile metrics
      - repaired worker notifications
      - deferred repair notifications
      - hard auto-heal failures
- `darwin-alert-sink.yaml`
  - minimal in-cluster webhook receiver used to prove Alertmanager routing
    without introducing an external dependency
- `darwin-alert-routing.yaml`
  - `AlertmanagerConfig` that routes alerts by `notification_tier`:
    - `dev-noise`
    - `real-incident`
- `t560-tailscale-route-metrics.sh`
  - host-local metrics emitter for the `t560` management-LAN/Tailscale route
    health
  - writes Prometheus textfile metrics into `/var/lib/node_exporter/textfile`
- `darwin-t560-tailscale-route-metrics.service`
  - one-shot systemd unit that runs the host-local route metrics emitter
- `darwin-t560-tailscale-route-metrics.timer`
  - systemd timer that refreshes the route-health metric every minute
- `apply-darwin-node-exporter-textfile-patch.sh`
  - idempotent patch that enables the node-exporter textfile collector against
    `/host/root/var/lib/node_exporter/textfile`
- `install-darwin-t560-tailscale-route-metrics.sh`
  - installs the route metrics script and systemd timer onto `t560`
- `darwin-tailscale-route-rules.yaml`
  - PrometheusRule bundle for the known control-plane regression:
    - `accept-routes=true` on `t560`
    - overlapping `192.168.3.0/24` imported through Tailscale table `52`
    - management-LAN replies no longer returning through `vmbr0`
- `t560-slurmdbd-backend-metrics.sh`
  - metrics emitter for the current live `slurmdbd` backend path on `t560`
  - exports the current `StorageHost`, backend health, rollback readiness,
    backup age, snapshot age, and accounting-read probes
- `t560-sounio-abide-runner-metrics.sh`
  - metrics emitter for the most recent ABIDE campaign submit observed on `t560`
  - exports:
    - last submit age
    - last payload transfer mode
    - last persist mode
    - last run/job identity labels
- `darwin-t560-slurmdbd-backend-metrics.service`
  - one-shot systemd unit that emits the SlurmDBD backend metrics
- `darwin-t560-slurmdbd-backend-metrics.timer`
  - systemd timer that refreshes the backend metrics every two minutes
- `darwin-t560-sounio-abide-runner-metrics.service`
  - one-shot systemd unit that emits the ABIDE runner metrics
- `darwin-t560-sounio-abide-runner-metrics.timer`
  - systemd timer that refreshes the ABIDE runner metrics every two minutes
- `install-darwin-t560-slurmdbd-backend-metrics.sh`
  - installs the SlurmDBD backend metrics script and timer onto `t560`
- `install-darwin-t560-sounio-abide-runner-metrics.sh`
  - installs the ABIDE runner metrics script and timer onto `t560`
- `darwin-slurmdbd-backend-rules.yaml`
  - PrometheusRule bundle for the current SlurmDBD backend path:
    - current backend unhealthy
    - stale logical dumps
    - stale or incomplete migration snapshots
- `darwin-infra-cronjob-rules.yaml`
  - PrometheusRule bundle that watches the cluster's infrastructure CronJobs:
    - a job that exceeded its `backoffLimit` in the last hour (acute, self-clearing)
    - a CronJob with no successful completion for far longer than its period,
      bucketed by cadence: sub-hourly (1h), hourly/6-hourly (8h), daily (26h)
  - added after `slurm-pilot/reaper-keeper` failed every 10 minutes for ~2 days
    with nothing alerting; the reaper daemon it keeps alive was dead the whole
    time on a shared login node
  - the alert `labels.namespace` is the routing namespace (`darwin-platform`),
    as everywhere else here; the resource's real namespace is carried separately
    as `resource_namespace` and is what the descriptions render
  - when you add a new infra CronJob, add it to the matching cadence bucket —
    the buckets are explicit name regexes, not a catch-all
- `apply-darwin-observability-control-plane-patches.sh`
  - idempotent recovery patch that pins the observability stack to the
    `t560-proxmox` control-plane node with the required toleration
  - use this when the compute pool is tainted or unavailable and Grafana /
    Prometheus need a stable home

## GPU worker auto-heal metrics

The `gpuorangefs` worker pool now exports host-local auto-heal metrics through
the node-exporter textfile collector on `t560`:

- source service:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/systemd/slurm-pilot-gpuorangefs-autoheal.service`
- source timer:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/systemd/slurm-pilot-gpuorangefs-autoheal.timer`
- source script:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/70-autoheal-gpuorangefs-pool.sh`
- textfile output:
  - `/var/lib/node_exporter/textfile/slurm_gpuorangefs_autoheal.prom`

Key metrics:

- `darwin_slurm_gpuorangefs_autoheal_last_run_success`
- `darwin_slurm_gpuorangefs_autoheal_last_run_unixtime`
- `darwin_slurm_gpuorangefs_autoheal_last_run_duration_seconds`
- `darwin_slurm_gpuorangefs_autoheal_admitted_nodes`
- `darwin_slurm_gpuorangefs_autoheal_healthy_nodes`
- `darwin_slurm_gpuorangefs_autoheal_quarantined_nodes`
- `darwin_slurm_gpuorangefs_autoheal_repaired_nodes`
- `darwin_slurm_gpuorangefs_autoheal_deferred_nodes`
- `darwin_slurm_gpuorangefs_autoheal_failed_nodes`
- `darwin_slurm_gpuorangefs_worker_state_code{node=...,status=...}`

The most recent ABIDE campaign submit is also exported via:

- `darwin_sounio_abide_runner_metrics_last_emit_unixtime`
- `darwin_sounio_abide_runner_last_submit_unixtime`
- `darwin_sounio_abide_runner_last_submit_age_seconds`
- `darwin_sounio_abide_runner_last_payload_transfer_mode_code`
  - `1 = embedded`
  - `2 = sbcast`
- `darwin_sounio_abide_runner_last_persist_mode_code`
  - `1 = orangefs`
  - `2 = worker_local`
- `darwin_sounio_abide_runner_last_submit_info{...}`
- `darwin_sounio_abide_runner_last_manifest_info{...}`

Prometheus now alerts separately when:

- the ABIDE runner metrics timer goes stale
- the last observed ABIDE campaign submit used `worker_local` fallback

Interpretation:

- “just checking” means:
  - `last_run_success = 1`
  - `healthy_nodes == admitted_nodes`
  - `repaired_nodes = 0`
  - `deferred_nodes = 0`
  - `failed_nodes = 0`
- “actually repaired” means `repaired_nodes > 0`
- “wanted to repair but waited” means `deferred_nodes > 0`
- “automation failed” means `failed_nodes > 0` or `last_run_success = 0`

## Apply

From a host with cluster-admin kubeconfig and Helm:

```bash
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

helm upgrade --install darwin-dcgm-exporter \
  gpu-helm-charts/dcgm-exporter \
  --namespace darwin-observability-system \
  --create-namespace \
  -f dcgm-exporter-values.yaml \
  --kubeconfig /etc/kubernetes/admin.conf

ceph mgr module enable prometheus
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f ceph-mgr-prometheus-servicemonitor.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-dashboard-gpu-ceph-storage.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-dashboard-hpc-control-room.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-dashboard-sounio-dev-loop.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-dashboard-slurm-ops.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-dashboard-sounio-compiler-pipeline.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-gpu-ceph-storage-rules.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-hpc-control-room-rules.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-sounio-slurm-ops-rules.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-alert-sink.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-alert-routing.yaml
bash apply-darwin-node-exporter-textfile-patch.sh
bash install-darwin-t560-tailscale-route-metrics.sh
bash install-darwin-t560-slurmdbd-backend-metrics.sh
bash install-darwin-t560-sounio-abide-runner-metrics.sh
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-tailscale-route-rules.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-slurmdbd-backend-rules.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f darwin-infra-cronjob-rules.yaml
```

If the main observability stack is stuck because every worker node is tainted or
NotReady, recover it onto `t560-proxmox` first:

```bash
bash apply-darwin-observability-control-plane-patches.sh
```

## Quick verification

Run the bundled read-only verifier first:

```bash
bash verify-darwin-hpc-observability.sh
```

Useful knobs:

- `KUBECONFIG_PATH=/path/to/admin.conf`
  - override the kubeconfig path used by the verifier
- `DCGM_MIN_TARGETS=3`
  - tune the minimum healthy `darwin-dcgm-exporter` targets expected by the verifier

The script checks:

- required namespaces
- rule bundles and alert routing
- Grafana dashboard ConfigMaps
- `dcgm-exporter` and Ceph `mgr/prometheus` ServiceMonitors
- promoted Sounio habitat readiness
- Prometheus target health for:
  - `darwin-dcgm-exporter`
  - `ceph-mgr-prometheus`

## Verify

Prometheus targets:

```bash
curl -fsS http://10.96.77.172:9090/api/v1/targets | jq -r '.data.activeTargets[] | [.labels.job,.health,.scrapeUrl] | @tsv'
```

Expected new jobs:

- `darwin-dcgm-exporter`
- `ceph-mgr-prometheus`

Grafana dashboard ConfigMaps:

```bash
kubectl --kubeconfig /etc/kubernetes/admin.conf get cm -n darwin-platform -l grafana_dashboard=1 | grep gpu-ceph-storage
```

Prometheus rules:

```bash
kubectl --kubeconfig /etc/kubernetes/admin.conf get prometheusrule -n darwin-platform darwin-gpu-ceph-storage-rules
kubectl --kubeconfig /etc/kubernetes/admin.conf get prometheusrule -n darwin-platform darwin-hpc-control-room-rules
kubectl --kubeconfig /etc/kubernetes/admin.conf get prometheusrule -n darwin-platform darwin-sounio-slurm-ops-rules
kubectl --kubeconfig /etc/kubernetes/admin.conf get prometheusrule -n darwin-platform darwin-tailscale-route-rules
kubectl --kubeconfig /etc/kubernetes/admin.conf get prometheusrule -n darwin-platform darwin-slurmdbd-backend-rules
kubectl --kubeconfig /etc/kubernetes/admin.conf get alertmanagerconfig -n darwin-platform darwin-alert-routing
kubectl --kubeconfig /etc/kubernetes/admin.conf get deploy -n darwin-platform darwin-alert-sink
```

The new control-room dashboard ConfigMap should also appear:

```bash
kubectl --kubeconfig /etc/kubernetes/admin.conf get cm -n darwin-platform darwin-dashboard-hpc-control-room
kubectl --kubeconfig /etc/kubernetes/admin.conf get cm -n darwin-platform darwin-dashboard-sounio-dev-loop
kubectl --kubeconfig /etc/kubernetes/admin.conf get cm -n darwin-platform darwin-dashboard-slurm-ops
kubectl --kubeconfig /etc/kubernetes/admin.conf get cm -n darwin-platform darwin-dashboard-sounio-compiler-pipeline
```

The bundled verifier wraps the checks above into a single health pass and is the
recommended first operator step before digging into individual objects.

## Common failure signatures

- `DarwinDcgmExporterTargetsMissing`
  - Run `bash verify-darwin-hpc-observability.sh`
  - Then inspect:
    - `kubectl --kubeconfig /etc/kubernetes/admin.conf -n darwin-observability-system get pods -l app.kubernetes.io/name=dcgm-exporter -o wide`
    - `kubectl --kubeconfig /etc/kubernetes/admin.conf -n darwin-observability-system get servicemonitor darwin-dcgm-exporter -o yaml`
  - If pods are scrapeable but unstable, re-check the reduced counter set in `dcgm-counters.production-safe.csv`

- `CephMgrPrometheusDown`
  - The most common cause is the active Ceph manager moving away from the
    statically published endpoint
  - Re-check:
    - `ceph mgr services`
    - `kubectl --kubeconfig /etc/kubernetes/admin.conf -n darwin-observability-system get endpoints ceph-mgr-prometheus -o yaml`
  - Update `ceph-mgr-prometheus-servicemonitor.yaml` if the active manager IP changed

- `DarwinSounioWorkspaceHabitatUnavailable`
  - Re-check the promoted workspace first:
    - `kubectl --kubeconfig /etc/kubernetes/admin.conf -n beagle get statefulset,pods,pvc | grep sounio-workspace-habitat`
  - Then inspect the ingress side:
    - `kubectl --kubeconfig /etc/kubernetes/admin.conf -n tailscale get pods | grep sounio-workspace-ingress`

- `DarwinT560ManagementRouteNotViaVmbr0` or `DarwinT560ManagementSubnetImportedViaTailscale`
  - This is the known control-plane regression path on `t560`
  - Re-check:
    - `systemctl status darwin-t560-tailscale-route-metrics.timer`
    - `journalctl -u darwin-t560-tailscale-route-metrics.service --since '30 min ago'`
    - host routing / Tailscale `accept-routes` state on `t560`

## Notes

- The Ceph `mgr/prometheus` endpoint is tied to the active manager. In the
  current cluster that is `t560-proxmox` on `10.100.100.2:9283`.
- If the active manager moves, update the static `Endpoints` object or replace
  it later with a more dynamic discovery mechanism.
- In this cluster, the `darwin-observability-system` namespace needs a larger
  `ResourceQuota`/`LimitRange` than the March defaults to fit `dcgm-exporter`
  on all three GPU nodes.
- The official `dcgm-exporter` chart works here with:
  - `runtimeClassName: nvidia`
  - `hostPID: true`
  - memory limit raised back to `512Mi`
- We also disable the built-in Kubernetes pod mapper (`DCGM_EXPORTER_KUBERNETES=false`)
  after the Helm deploy because the exporter cannot read
  `/var/lib/kubelet/pod-resources/kubelet.sock` in this cluster and otherwise
  returns HTTP `500` on `/metrics`.
- The production-safe counter set from `dcgm-counters.production-safe.csv`
  should be loaded into `exporter-metrics-config-map` before restarting the
  DaemonSet; this keeps the `r740` target from timing out on heavy profiling
  counters.
- That tradeoff still gives us the important SOTA signals now:
  - GPU-level telemetry in Prometheus/Grafana
  - Ceph telemetry in the same stack
  - one unified monitoring plane before deeper storage surgery
- The `Darwin GPU Ceph Storage` dashboard is designed as the first operator view
  for this phase:
  - Ceph health and manager scrape status
  - GPU scrape health and utilization
  - Ceph capacity signals
  - readiness of the new local cache tier on `r770`
  - readiness of the premium local NVMe tier on `r740`
- The `Darwin HPC Control Room` dashboard is the higher-level operator view for
  daily work:
  - Prometheus / Grafana / Alertmanager / operator / kube-state-metrics health
  - Sounio promoted habitat and tailnet ingress health
  - Slurm controller and accounting health
  - GPU utilization and memory trends
  - Ceph capacity pressure
- The `Darwin Sounio Dev Loop` dashboard is the development workspace view:
  - promoted habitat readiness
  - tailnet ingress readiness
  - CPU and memory shape of the current and rollback workspaces
  - restart drift that would disrupt editing sessions
- The `Darwin Slurm Ops` dashboard is the batch plane view:
  - control-plane readiness
  - worker readiness
  - control-plane CPU and memory pressure
  - restart drift and GPU pressure during live workloads
- The `Darwin Sounio Compiler Pipeline` dashboard is the language loop view:
  - promoted habitat readiness
  - ingress proxy readiness
  - PVC binding for the workspace
  - CPU and memory shape of compiler/test execution inside the live workspace
  - restart drift that would interrupt the compiler loop
- Publishing Grafana through the shared Tailscale ingress consumes one
  Tailscale-backed `LoadBalancer`/`NodePort` service in `darwin-platform`, so
  the namespace quota now allows `services.loadbalancers=1` and
  `services.nodeports=1`. The reapplicable manifest lives in:
  - `/home/devsounio/beagle/k8s/tailscale-operator/darwin-platform-quota-grafana-tailnet.yaml`
- The live node-agnostic Grafana endpoint is:
  - `http://darwin-grafana.tail21cbc4.ts.net`
- The intended operator landing page in Grafana is `Darwin HPC Control Room`,
  with `Darwin Sounio Dev Loop`, `Darwin Slurm Ops`, and
  `Darwin Sounio Compiler Pipeline` starred for the admin user so the daily
  views stay one click away.
- Alert routing for this layer is intentionally split by the custom label
  `notification_tier`:
  - `dev-noise` is for high-signal development friction that should stay out of
    the true incident path
  - `real-incident` is for outages or hard failures in the living workspace /
    Slurm plane
- The current proof receiver is `darwin-alert-sink`, which is enough to verify
  end-to-end Alertmanager routing inside the cluster before wiring a real
  destination such as email, Slack, or PagerDuty.
- There is intentionally no external notification credential committed in this
  repo or loaded in `darwin-platform` today. Until a real email / Slack /
  PagerDuty destination is provided, `darwin-alert-sink` remains the verified
  proof target for both `dev-noise` and `real-incident`.
- The `t560` route-health alerting path is intentionally anchored in
  node-exporter textfile metrics because Prometheus cannot inspect local
  `tailscale debug prefs` state by itself:
  - host script emits metrics every minute
  - node-exporter scrapes the textfile on `t560`
  - `darwin-tailscale-route-rules.yaml` alerts if the old overlapping-route
    failure mode returns
- Because `AlertmanagerConfig` objects in this stack match by namespace, the
  custom alerts in this directory carry a static `namespace=darwin-platform`
  label on purpose.
