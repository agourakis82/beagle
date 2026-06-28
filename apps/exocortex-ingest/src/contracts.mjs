// Thin clients for the LIVE deployed contracts — see docs/exocortex/CONTRACTS.md (Task 0).
// beagle-core embeds server-side: we send TEXT, never vectors.
const ROUTER = process.env.LLM_ROUTER_URL || "http://router.llm-router.svc.cluster.local:4000";
const BEAGLE = process.env.BEAGLE_INTERNAL_URL || "http://beagle-core.beagle.svc.cluster.local:8080";
const OP_TOKEN = process.env.BEAGLE_OPERATOR_API_TOKEN || "";

function beagleHeaders() {
  return {
    "content-type": "application/json",
    accept: "application/json",
    "X-Beagle-Consumer": "beagle-operator",
    Authorization: `Bearer ${OP_TOKEN}`,
  };
}

// POST /api/exocortex/v1/memory/assisted-import — canonical ingest path.
// turns: [{ role, content, timestamp, metadata }]
export async function assistedImport({
  title,
  turns,
  tags = [],
  metadata = {},
  sessionId,
  importScope = "biographical_corpus",
  privacyClass = "sensitive",
  sourcePlatform = "exocortex-ingest",
  sourceSurface = "disk-corpus",
  projectRef = "exocortex",
  confidenceScore = 0.8,
}) {
  const body = {
    source_platform: sourcePlatform,
    source_surface: sourceSurface,
    import_scope: importScope,
    session_id: sessionId,
    project_ref: projectRef,
    privacy_class: privacyClass,
    title,
    confidence_score: confidenceScore,
    create_chronoself_commit: false,
    turns,
    tags,
    metadata: { restricted_leak_check: "passed", remembered_from: "exocortex-ingest", ...metadata },
  };
  const r = await fetch(`${BEAGLE}/api/exocortex/v1/memory/assisted-import`, {
    method: "POST",
    headers: beagleHeaders(),
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`assistedImport ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return r.json();
}

// POST /api/memory/query — POST on the deployed pod (not GET). Returns { summary, highlights:[{snippet,date,...}] }.
export async function memoryQuery(query, k = 5) {
  const r = await fetch(`${BEAGLE}/api/memory/query`, {
    method: "POST",
    headers: beagleHeaders(),
    body: JSON.stringify({ query, k }),
  });
  if (!r.ok) throw new Error(`memoryQuery ${r.status}`);
  return r.json();
}

// POST /v1/chat/completions (LiteLLM router, on-cluster self-hosted models).
export async function routerChat(model, system, user, { temperature = 0.4, max_tokens = 700 } = {}) {
  const r = await fetch(`${ROUTER}/v1/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json", Authorization: "Bearer noauth" },
    body: JSON.stringify({
      model, temperature, max_tokens,
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
    }),
  });
  if (!r.ok) throw new Error(`routerChat ${r.status}`);
  return (await r.json()).choices[0].message.content.trim();
}
