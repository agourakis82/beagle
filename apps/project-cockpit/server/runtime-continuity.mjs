function cleanString(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value).trim();
  return "";
}

function nonNegativeInteger(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.floor(number) : 0;
}

function pick(sources, keys) {
  for (const source of sources) {
    if (!source || typeof source !== "object") continue;
    for (const key of keys) {
      if (source[key] !== undefined && source[key] !== null && source[key] !== "") {
        return source[key];
      }
    }
  }
  return null;
}

function trueOnly(value) {
  return value === true;
}

const TRANSITION_LABELS = Object.freeze({
  initial: "Initial generation",
  "clean-respawn": "Clean respawn",
  "pod-resurrected": "Pod resurrection",
});

export function normalizeRuntimeContinuity(block = {}) {
  const provenance = block?.provenance && typeof block.provenance === "object"
    ? block.provenance
    : {};
  const authorityStatus = block?.authorityStatus || block?.authority_status || {};
  // runtimeContinuity is derived display state, never an authority source. Recompute it
  // from raw block evidence so an upstream cannot launder a forged green receipt.
  const sources = [block, provenance, authorityStatus];

  const runtimeAuthority = cleanString(pick(sources, ["runtimeAuthority", "runtime_authority"]));
  const supervisorRuntime = cleanString(pick(sources, ["supervisorRuntime", "supervisor_runtime", "runtime"]));
  const supervisorProtocol = cleanString(pick(sources, ["supervisorProtocol", "supervisor_protocol", "protocol"]));
  const loomInstanceId = cleanString(pick(sources, ["loomInstanceId", "loom_instance_id"]));
  const generationFingerprint = cleanString(pick(sources, ["generationFingerprint", "generation_fingerprint"]));
  const semanticJournalHead = cleanString(pick(sources, ["semanticJournalHead", "semantic_journal_head"]));
  const guardianJournalHead = cleanString(pick(sources, ["guardianJournalHead", "guardian_journal_head"]));
  const generationLineageHead = cleanString(pick(sources, ["generationLineageHead", "generation_lineage_head"]));
  const predecessorInstanceId = cleanString(pick(sources, ["predecessorInstanceId", "predecessor_instance_id"]));
  const predecessorSemanticJournalHead = cleanString(pick(sources, [
    "predecessorSemanticJournalHead",
    "predecessor_semantic_journal_head",
  ]));
  const predecessorGuardianJournalHead = cleanString(pick(sources, [
    "predecessorGuardianJournalHead",
    "predecessor_guardian_journal_head",
  ]));
  const journalVerified = trueOnly(pick(sources, ["journalVerified", "journal_verified"]));
  const lineageVerified = trueOnly(pick(sources, ["lineageVerified", "lineage_verified"]));
  const generationTransition = cleanString(pick(sources, [
    "generationTransition",
    "generation_transition",
  ]));
  const generationTransitionCount = nonNegativeInteger(pick(sources, [
    "generationTransitionCount",
    "generation_transition_count",
  ]));
  const podResurrectionCount = nonNegativeInteger(pick(sources, [
    "podResurrectionCount",
    "pod_resurrection_count",
  ]));
  const kernelRecoveryCount = nonNegativeInteger(pick(sources, [
    "kernelRecoveryCount",
    "kernel_recovery_count",
  ]));

  const hasRuntimeEvidence = Boolean(
    runtimeAuthority || supervisorRuntime || loomInstanceId || generationFingerprint || generationTransition
  );
  const knownTransition = Object.hasOwn(TRANSITION_LABELS, generationTransition);
  const successorTransition = generationTransition === "clean-respawn" || generationTransition === "pod-resurrected";
  const successorReceiptComplete = !successorTransition || Boolean(
    generationLineageHead &&
    predecessorInstanceId &&
    predecessorSemanticJournalHead &&
    predecessorGuardianJournalHead
  );
  const countsConsistent = (
    generationTransition === "initial" &&
    generationTransitionCount === 0 &&
    podResurrectionCount === 0
  ) || (
    generationTransition === "clean-respawn" &&
    generationTransitionCount >= 1 &&
    podResurrectionCount < generationTransitionCount
  ) || (
    generationTransition === "pod-resurrected" &&
    generationTransitionCount >= 1 &&
    podResurrectionCount >= 1 &&
    podResurrectionCount <= generationTransitionCount
  );
  const verified = Boolean(
    hasRuntimeEvidence &&
    runtimeAuthority === "loom" &&
    loomInstanceId &&
    generationFingerprint &&
    journalVerified &&
    semanticJournalHead &&
    guardianJournalHead &&
    lineageVerified &&
    knownTransition &&
    successorReceiptComplete &&
    countsConsistent
  );

  let status = "unattributed";
  if (hasRuntimeEvidence && runtimeAuthority !== "loom") status = "foreign-runtime";
  if (hasRuntimeEvidence && runtimeAuthority === "loom") status = "proof-incomplete";
  if (verified && generationTransition === "initial") status = "verified-initial-generation";
  if (verified && generationTransition === "clean-respawn") status = "verified-clean-respawn";
  if (verified && generationTransition === "pod-resurrected") status = "verified-pod-resurrection";

  return {
    status,
    verified,
    hasRuntimeEvidence,
    transitionLabel: TRANSITION_LABELS[generationTransition] || "Unknown transition",
    runtimeAuthority: runtimeAuthority || null,
    supervisorRuntime: supervisorRuntime || null,
    supervisorProtocol: supervisorProtocol || null,
    loomInstanceId: loomInstanceId || null,
    generationFingerprint: generationFingerprint || null,
    journalVerified,
    semanticJournalHead: semanticJournalHead || null,
    guardianJournalHead: guardianJournalHead || null,
    kernelRecoveryCount,
    lineageVerified,
    generationLineageHead: generationLineageHead || null,
    generationTransition: generationTransition || null,
    generationTransitionCount,
    podResurrectionCount,
    predecessorInstanceId: predecessorInstanceId || null,
    predecessorSemanticJournalHead: predecessorSemanticJournalHead || null,
    predecessorGuardianJournalHead: predecessorGuardianJournalHead || null,
  };
}

export function attachRuntimeContinuity(payload = {}) {
  if (!payload || typeof payload !== "object" || !Array.isArray(payload.blocks)) return payload;
  return {
    ...payload,
    blocks: payload.blocks.map((block) => ({
      ...block,
      runtimeContinuity: normalizeRuntimeContinuity(block),
    })),
  };
}
