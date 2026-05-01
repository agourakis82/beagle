import { createHash, randomUUID } from "node:crypto";
import { mkdir, appendFile, writeFile } from "node:fs/promises";
import path from "node:path";

export const MARBLE_MODELS = new Set([
  "marble-1.0-draft",
  "marble-1.0",
  "marble-1.1",
  "marble-1.1-plus",
]);

export const SPATIAL_SCHEMA = "beagle-spatial-control-room-v3.6";
export const SPATIAL_FORGE_SCHEMA = "beagle-spatial-forge-v3.7";

export const SPATIAL_PROVIDER_SLOTS = [
  {
    id: "worldlabs_marble",
    label: "World Labs Marble",
    provider_family: "world",
    artifact_type: "persistent_environment",
    cost_tier: "paid_guarded",
    privacy_tier: "sanitized_external",
    maturity: "primary",
    secret_env: "WORLDLABS_API_KEY",
    models: ["marble-1.0-draft", "marble-1.1", "marble-1.1-plus"],
  },
  {
    id: "hyworld",
    label: "HY-World",
    provider_family: "world",
    artifact_type: "open_world_research",
    cost_tier: "self_hosted_or_lab",
    privacy_tier: "cluster_lab",
    maturity: "research_adapter",
    secret_env: "HYWORLD_ENDPOINT",
    models: ["hy-world-2"],
  },
  {
    id: "hunyuan3d",
    label: "Hunyuan3D",
    provider_family: "asset",
    artifact_type: "mesh_asset",
    cost_tier: "self_hosted_or_external",
    privacy_tier: "sanitized_or_local",
    maturity: "adapter_slot",
    secret_env: "HUNYUAN3D_ENDPOINT",
    models: ["hunyuan3d"],
  },
  {
    id: "trellis",
    label: "TRELLIS",
    provider_family: "asset",
    artifact_type: "structured_3d_asset",
    cost_tier: "self_hosted_or_lab",
    privacy_tier: "cluster_lab",
    maturity: "adapter_slot",
    secret_env: "TRELLIS_ENDPOINT",
    models: ["trellis"],
  },
  {
    id: "meshy",
    label: "Meshy",
    provider_family: "asset",
    artifact_type: "mesh_asset",
    cost_tier: "paid_guarded",
    privacy_tier: "sanitized_external",
    maturity: "adapter_slot",
    secret_env: "MESHY_API_KEY",
    models: ["meshy-text-to-3d"],
  },
  {
    id: "rodin",
    label: "Rodin",
    provider_family: "asset",
    artifact_type: "mesh_asset",
    cost_tier: "paid_guarded",
    privacy_tier: "sanitized_external",
    maturity: "adapter_slot",
    secret_env: "RODIN_API_KEY",
    models: ["rodin"],
  },
  {
    id: "tripo",
    label: "Tripo",
    provider_family: "asset",
    artifact_type: "mesh_asset",
    cost_tier: "paid_guarded",
    privacy_tier: "sanitized_external",
    maturity: "adapter_slot",
    secret_env: "TRIPO_API_KEY",
    models: ["tripo"],
  },
  {
    id: "luma_genie",
    label: "Luma Genie",
    provider_family: "asset",
    artifact_type: "mesh_asset",
    cost_tier: "paid_guarded",
    privacy_tier: "sanitized_external",
    maturity: "scout",
    secret_env: "LUMA_API_KEY",
    models: ["genie"],
  },
];

export function nowIso() {
  return new Date().toISOString();
}

export function sha256(value) {
  return `sha256:${createHash("sha256").update(String(value)).digest("hex")}`;
}

export function normalizeProjectSlug(value = "sounio") {
  const slug = String(value || "sounio")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || "sounio";
}

export function normalizeMarbleModel(value, purpose = "control-room") {
  const requested = String(value || "").trim().toLowerCase();
  if (MARBLE_MODELS.has(requested)) return requested;
  if (purpose === "prompt-iteration") return "marble-1.0-draft";
  return "marble-1.1";
}

export function listSpatialProviderSlots(env = process.env) {
  return SPATIAL_PROVIDER_SLOTS.map((slot) => {
    const configured = !slot.secret_env || Boolean(env[slot.secret_env]);
    return {
      id: slot.id,
      label: slot.label,
      provider_family: slot.provider_family,
      artifact_type: slot.artifact_type,
      cost_tier: slot.cost_tier,
      privacy_tier: slot.privacy_tier,
      maturity: slot.maturity,
      enabled: configured && slot.maturity !== "scout",
      requires_secret: Boolean(slot.secret_env),
      setup_status: configured ? "ready" : "needs_setup",
      models: slot.models,
      notes: providerNotes(slot, configured),
    };
  });
}

export function findProviderSlot(id = "worldlabs_marble") {
  const normalized = String(id || "worldlabs_marble").trim().toLowerCase();
  return SPATIAL_PROVIDER_SLOTS.find((slot) => slot.id === normalized) || SPATIAL_PROVIDER_SLOTS[0];
}

export function buildGenerationDraft(input = {}, env = process.env) {
  const projectSlug = normalizeProjectSlug(input.project_slug);
  const provider = findProviderSlot(input.provider_slot);
  const purpose = String(input.purpose || "spatial-desk").trim() || "spatial-desk";
  const prompt = sanitizePrompt(input.sanitized_prompt || input.prompt_summary);
  const configured = !provider.secret_env || Boolean(env[provider.secret_env]);
  const approved = Boolean(input.approved);
  return {
    id: `spatial-draft:${sha256(`${projectSlug}|${provider.id}|${purpose}|${prompt}`)}`,
    schema_version: SPATIAL_FORGE_SCHEMA,
    project_slug: projectSlug,
    provider_slot: provider.id,
    provider_label: provider.label,
    purpose,
    status: configured ? (approved ? "approved_ready" : "needs_approval") : "needs_setup",
    prompt_hash: sha256(prompt),
    sanitized_prompt_summary: prompt.slice(0, 500),
    approved,
    cost_tier: provider.cost_tier,
    privacy_tier: provider.privacy_tier,
    artifact_type: provider.artifact_type,
    budget_policy:
      provider.cost_tier === "paid_guarded"
        ? "paid external generation requires explicit approval metadata"
        : "draft can remain local/cluster-lab until promoted",
    provenance: {
      source: "world-console",
      schema_version: SPATIAL_FORGE_SCHEMA,
      sanitized_prompt_only: true,
      private_memory_excluded: true,
    },
  };
}

export function sanitizePrompt(prompt) {
  const text = String(prompt || "").trim().replace(/\s+/g, " ");
  if (!text) {
    throw Object.assign(new Error("sanitized_prompt is required"), { statusCode: 400 });
  }
  if (text.length > 4000) {
    throw Object.assign(new Error("sanitized_prompt must stay under 4000 characters"), {
      statusCode: 400,
    });
  }
  const lower = text.toLowerCase();
  const blocked = [
    "client_secret",
    "refresh_token",
    "private key",
    "-----begin",
    "bearer ",
    "api_key",
    "password:",
    "passwd",
    "restricted:",
    "raw log",
    "token=",
    "sk-",
    "ghp_",
  ];
  if (blocked.some((needle) => lower.includes(needle))) {
    throw Object.assign(new Error("prompt appears to contain secret or restricted material"), {
      statusCode: 422,
    });
  }
  return text;
}

export function buildGeneratePayload(input = {}) {
  const provider = findProviderSlot(input.provider_slot);
  if (provider.id !== "worldlabs_marble") {
    throw Object.assign(new Error(`${provider.id} is draft-only in v3.7`), { statusCode: 501 });
  }
  const projectSlug = normalizeProjectSlug(input.project_slug);
  const purpose = String(input.purpose || "control-room").trim() || "control-room";
  const prompt = sanitizePrompt(input.sanitized_prompt || input.prompt_summary);
  const model = normalizeMarbleModel(input.model, purpose);
  const displayName = String(input.display_name || `${projectSlug} Spatial Control Room`).slice(0, 64);
  if (!input.approved) {
    throw Object.assign(new Error("Marble generation requires approved=true"), { statusCode: 403 });
  }
  return {
    projectSlug,
    purpose,
    prompt,
    promptHash: sha256(prompt),
    model,
    request: {
      world_prompt: {
        disable_recaption: true,
        text_prompt: prompt,
      },
      display_name: displayName,
      model,
      permission: input.permission || { access: "private" },
      tags: [...new Set([...(input.tags || []), "beagle", "sounio", "spatial-control-room"])],
    },
  };
}

function providerNotes(slot, configured) {
  const notes = [
    "Artifacts are derived; canonical memory remains JSONL/Merkle/Chronoself in Beagle.",
    "Prompts must be sanitized summaries without raw private memory, logs, or secrets.",
  ];
  if (!configured) notes.push(`Configure ${slot.secret_env} to enable this provider slot.`);
  if (slot.cost_tier === "paid_guarded") notes.push("Paid generation requires explicit approved=true.");
  return notes;
}

export function normalizeWorld(world = {}, context = {}) {
  const assets = world.assets || {};
  const splats = assets.splats || {};
  const mesh = assets.mesh || {};
  const imagery = assets.imagery || {};
  return {
    schema_version: SPATIAL_SCHEMA,
    project_slug: context.projectSlug || normalizeProjectSlug(world.project_slug),
    operation_id: context.operationId || world.operation_id || null,
    world_id: world.world_id || context.worldId || `mock-world-${randomUUID()}`,
    display_name: world.display_name || context.displayName || "Sounio Spatial Control Room",
    status: context.status || "ready",
    model: world.model || context.model || "marble-1.1",
    permission: normalizePermission(world.permission),
    world_marble_url: world.world_marble_url || null,
    prompt_hash: context.promptHash || sha256(JSON.stringify(world.world_prompt || {})),
    prompt_summary: context.promptSummary || "",
    assets: {
      pano_url: imagery.pano_url || assets.pano_url || null,
      collider_mesh_url: mesh.collider_mesh_url || assets.collider_mesh_url || null,
      hq_mesh_urls: compactArray([mesh.hq_mesh_url, ...(mesh.hq_mesh_urls || [])]),
      spz_urls: splats.spz_urls || splats || {},
      ply_urls: splats.ply_urls || {},
      coordinate_system: "opencv:+x-left,+y-down,+z-forward",
      coordinate_transform: "opencv_to_opengl:scale_yz_minus_one",
      asset_root: context.assetRoot || null,
      degraded_reason: null,
    },
    tags: [...new Set([...(world.tags || []), "marble", `project:${context.projectSlug || "sounio"}`])],
    provenance: {
      source: "world-console",
      sanitized_prompt_only: true,
      worldlabs_operation_id: context.operationId || world.operation_id || null,
      derived_artifact: true,
    },
  };
}

export function normalizePermission(permission) {
  if (!permission) return "private";
  if (typeof permission === "string") return permission.toLowerCase() === "public" ? "public" : "private";
  const access = String(permission.access || permission.visibility || "private").toLowerCase();
  return access === "public" ? "public" : "private";
}

export async function appendJsonl(rootDir, fileName, value) {
  await mkdir(rootDir, { recursive: true });
  await appendFile(path.join(rootDir, fileName), `${JSON.stringify(value)}\n`, "utf8");
}

export async function cacheManifest(rootDir, world) {
  const worldDir = path.join(rootDir, world.world_id);
  await mkdir(worldDir, { recursive: true });
  const manifestPath = path.join(worldDir, "asset-manifest.json");
  await writeFile(manifestPath, JSON.stringify(world, null, 2), "utf8");
  return manifestPath;
}

export async function generateWorld({ client, input, rootDir }) {
  const built = buildGeneratePayload(input);
  const operation = await client.generateWorld(built.request);
  const record = {
    id: `operation:${operation.operation_id || randomUUID()}`,
    created_at: nowIso(),
    project_slug: built.projectSlug,
    purpose: built.purpose,
    operation_id: operation.operation_id,
    model: built.model,
    prompt_hash: built.promptHash,
    prompt_summary: built.prompt,
    status: operation.done ? "ready" : "running",
    provenance: { source: "world-console", sanitized_prompt_only: true },
  };
  await appendJsonl(rootDir, "marble_operations.jsonl", record);
  return { operation: record, world: operation.response ? normalizeWorld(operation.response, built) : null };
}

export async function pollOperation({ client, operationId, context = {}, rootDir }) {
  const operation = await client.getOperation(operationId);
  const world = operation.response ? normalizeWorld(operation.response, { ...context, operationId }) : null;
  if (world) {
    await cacheManifest(rootDir, world);
    await appendJsonl(rootDir, "spatial_worlds.jsonl", world);
  }
  return { operation, world };
}

export async function getWorld({ client, worldId, context = {}, rootDir }) {
  const world = normalizeWorld(await client.getWorld(worldId), { ...context, worldId });
  await cacheManifest(rootDir, world);
  await appendJsonl(rootDir, "spatial_worlds.jsonl", world);
  return world;
}

export function createWorldLabsClient({ apiKey, baseUrl = "https://api.worldlabs.ai/marble/v1", fetchImpl = fetch }) {
  if (!apiKey) {
    throw Object.assign(new Error("WORLDLABS_API_KEY is not configured"), { statusCode: 503 });
  }
  async function request(method, endpoint, body) {
    const response = await fetchImpl(`${baseUrl}${endpoint}`, {
      method,
      headers: {
        "content-type": "application/json",
        "WLT-Api-Key": apiKey,
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await response.text();
    const parsed = text ? JSON.parse(text) : {};
    if (!response.ok) {
      throw Object.assign(new Error(parsed?.detail || `worldlabs_http_${response.status}`), {
        statusCode: response.status,
      });
    }
    return parsed;
  }
  return {
    generateWorld: (payload) => request("POST", "/worlds:generate", payload),
    getOperation: (operationId) => request("GET", `/operations/${encodeURIComponent(operationId)}`),
    getWorld: (worldId) => request("GET", `/worlds/${encodeURIComponent(worldId)}`),
  };
}

function compactArray(values) {
  return values.filter((value) => typeof value === "string" && value.trim().length > 0);
}
