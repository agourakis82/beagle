# B16.1 - Known Limits

- this phase proves a second real workstream, not full portfolio orchestration
- the second workstream stays inside the same repo and same promoted
  `beagle-darwin-hpc-general-noninfra` scope
- the runtime still has one configured default cutover workstream; the second
  line is seeded through a bounded pilot-time workstream identity override
- this phase does not reopen bridge, result/object plane, ingress, edge, HA or
  topology
- the phase does not broaden to arbitrary user-defined workstreams yet
- local host `cargo` exists, but the stronger compile proof remains the live
  container build path because the host MSRV still trails the repo lockfile

In other words, B16.1 is the minimal generalization step from one canonical
workstream to two real workstreams under the same Beagle-native model.
