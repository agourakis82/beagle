const { proxyActivities } = require("@temporalio/workflow");

const activities = proxyActivities({
  startToCloseTimeout: "2 minutes",
  retry: {
    maximumAttempts: 3,
    nonRetryableErrorTypes: ["restricted_content", "unsupported_claim"],
  },
});

async function BeagleSelfWritingPaperRun(input) {
  const paperRun = await activities.loadPaperRun({ paper_run_id: input.paper_run_id });
  const contextPack = await activities.compileContext({
    paper_run_id: input.paper_run_id,
    task: "self-writing-systems-paper",
    query: `Continue PaperRun ${paperRun.title} with provenance and claim guards.`,
  });
  const artifacts = await activities.loadArtifacts({ paper_run_id: input.paper_run_id });
  await activities.recordEffectiveness({
    paper_run_id: input.paper_run_id,
    temporal_workflow_id: paperRun.temporal_workflow_id,
    context_pack_id: contextPack.id || paperRun.context_pack_id,
    query: paperRun.title,
    step_id: "paperrun_temporal_smoke",
    success: true,
    outcome: "temporal_runner_smoke_completed",
  });
  return {
    paper_run_id: input.paper_run_id,
    status: "completed_smoke",
    context_pack_id: contextPack.id || paperRun.context_pack_id,
    artifact_count: Array.isArray(artifacts.artifact_refs) ? artifacts.artifact_refs.length : 0,
  };
}

module.exports = { BeagleSelfWritingPaperRun };
