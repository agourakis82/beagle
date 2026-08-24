import { test } from "node:test";
import assert from "node:assert/strict";
import { attachRuntimeContinuity, normalizeRuntimeContinuity } from "./runtime-continuity.mjs";

function resurrectedProvenance(overrides = {}) {
  return {
    runtime_authority: "loom",
    supervisor_runtime: "sounio-loom-2026.08.24.4",
    supervisor_protocol: "beagle-pty-supervisor-v1",
    loom_instance_id: "loom-generation-current",
    generation_fingerprint: "sha256:generation-current",
    journal_verified: true,
    semantic_journal_head: "sha256:semantic-current",
    guardian_journal_head: "sha256:guardian-current",
    kernel_recovery_count: 2,
    lineage_verified: true,
    generation_lineage_head: "sha256:lineage-current",
    generation_transition: "pod-resurrected",
    generation_transition_count: 1,
    pod_resurrection_count: 1,
    predecessor_instance_id: "loom-generation-predecessor",
    predecessor_semantic_journal_head: "sha256:semantic-predecessor",
    predecessor_guardian_journal_head: "sha256:guardian-predecessor",
    ...overrides,
  };
}

test("verified Pod resurrection exposes a complete operator receipt", () => {
  const continuity = normalizeRuntimeContinuity({ provenance: resurrectedProvenance() });
  assert.equal(continuity.status, "verified-pod-resurrection");
  assert.equal(continuity.verified, true);
  assert.equal(continuity.transitionLabel, "Pod resurrection");
  assert.equal(continuity.predecessorInstanceId, "loom-generation-predecessor");
  assert.equal(continuity.podResurrectionCount, 1);
  assert.equal(continuity.kernelRecoveryCount, 2);
});

test("sabotage control: claimed lineage without predecessor receipts stays unverified", () => {
  const continuity = normalizeRuntimeContinuity({
    provenance: resurrectedProvenance({
      predecessor_semantic_journal_head: null,
      predecessor_guardian_journal_head: null,
    }),
  });
  assert.equal(continuity.status, "proof-incomplete");
  assert.equal(continuity.verified, false);
  assert.equal(continuity.lineageVerified, true, "the upstream claim is retained, not laundered");
});

test("sabotage control: a forged derived receipt is discarded", () => {
  const continuity = normalizeRuntimeContinuity({
    id: "legacy-block",
    provenance: {},
    runtimeContinuity: {
      status: "verified-pod-resurrection",
      verified: true,
      runtimeAuthority: "loom",
      journalVerified: true,
      lineageVerified: true,
    },
  });
  assert.equal(continuity.status, "unattributed");
  assert.equal(continuity.verified, false);
  assert.equal(continuity.hasRuntimeEvidence, false);
});

test("sabotage control: Pod transition with zero resurrection count stays unverified", () => {
  const continuity = normalizeRuntimeContinuity({
    provenance: resurrectedProvenance({ pod_resurrection_count: 0 }),
  });
  assert.equal(continuity.status, "proof-incomplete");
  assert.equal(continuity.verified, false);
});

test("initial Loom generation can verify without a predecessor or lineage head", () => {
  const continuity = normalizeRuntimeContinuity({
    runtimeAuthority: "loom",
    supervisorRuntime: "sounio-loom-2026.08.24.4",
    loomInstanceId: "loom-generation-initial",
    generationFingerprint: "sha256:generation-initial",
    journalVerified: true,
    semanticJournalHead: "sha256:semantic-initial",
    guardianJournalHead: "sha256:guardian-initial",
    lineageVerified: true,
    generationTransition: "initial",
  });
  assert.equal(continuity.status, "verified-initial-generation");
  assert.equal(continuity.verified, true);
  assert.equal(continuity.generationLineageHead, null);
});

test("legacy blocks are explicitly unattributed rather than inferred as continuous", () => {
  const continuity = normalizeRuntimeContinuity({ id: "legacy-block", provenance: {} });
  assert.equal(continuity.status, "unattributed");
  assert.equal(continuity.verified, false);
  assert.equal(continuity.hasRuntimeEvidence, false);
});

test("proxy payload enrichment is immutable and idempotent", () => {
  const payload = { blocks: [{ id: "block-1", provenance: resurrectedProvenance() }] };
  const once = attachRuntimeContinuity(payload);
  const twice = attachRuntimeContinuity(once);
  assert.notEqual(once, payload);
  assert.equal(payload.blocks[0].runtimeContinuity, undefined);
  assert.deepEqual(twice, once);
});
