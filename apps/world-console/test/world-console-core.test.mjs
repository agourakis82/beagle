import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  buildGenerationDraft,
  buildGeneratePayload,
  generateWorld,
  listSpatialProviderSlots,
  normalizeWorld,
  pollOperation,
  sanitizePrompt,
} from "../src/world-console-core.mjs";

test("sanitized prompts reject secrets and build private Marble payloads", () => {
  assert.throws(() => sanitizePrompt("client_secret: nope"), /secret/);
  const built = buildGeneratePayload({
    project_slug: "Sounio",
    sanitized_prompt: "Sounio control room with agent lanes and evidence panels.",
    approved: true,
    tags: ["control-room"],
  });
  assert.equal(built.projectSlug, "sounio");
  assert.equal(built.model, "marble-1.1");
  assert.equal(built.request.permission.access, "private");
  assert.match(built.promptHash, /^sha256:/);
});

test("spatial forge exposes provider slots and guarded drafts", () => {
  const slots = listSpatialProviderSlots({ WORLDLABS_API_KEY: "configured" });
  assert.ok(slots.some((slot) => slot.id === "worldlabs_marble" && slot.setup_status === "ready"));
  assert.ok(slots.some((slot) => slot.id === "meshy" && slot.setup_status === "needs_setup"));
  const draft = buildGenerationDraft(
    {
      project_slug: "Beagle",
      provider_slot: "meshy",
      sanitized_prompt: "A compact symbolic object for the Spatial Desk.",
      purpose: "desk-instrument",
    },
    {},
  );
  assert.equal(draft.project_slug, "beagle");
  assert.equal(draft.provider_slot, "meshy");
  assert.equal(draft.status, "needs_setup");
  assert.equal(draft.approved, false);
  assert.match(draft.prompt_hash, /^sha256:/);
});

test("mock generate and poll creates normalized asset manifest", async () => {
  const rootDir = await mkdtemp(path.join(tmpdir(), "beagle-world-console-"));
  const client = {
    async generateWorld() {
      return { done: false, operation_id: "op-1", response: null };
    },
    async getOperation() {
      return {
        done: true,
        operation_id: "op-1",
        response: {
          world_id: "world-1",
          display_name: "Sounio Control Room",
          model: "marble-1.1",
          permission: { access: "private" },
          assets: {
            imagery: { pano_url: "https://assets.example/pano.png" },
            mesh: { collider_mesh_url: "https://assets.example/collider.glb" },
            splats: { spz_urls: { low_res: "https://assets.example/low.spz" } },
          },
        },
      };
    },
  };
  const generation = await generateWorld({
    client,
    rootDir,
    input: {
      project_slug: "sounio",
      sanitized_prompt: "Sanitized control room.",
      approved: true,
    },
  });
  assert.equal(generation.operation.operation_id, "op-1");
  const polled = await pollOperation({ client, operationId: "op-1", rootDir });
  assert.equal(polled.world.world_id, "world-1");
  assert.equal(polled.world.permission, "private");
  assert.equal(polled.world.assets.spz_urls.low_res, "https://assets.example/low.spz");
  assert.equal(polled.world.assets.coordinate_transform, "opencv_to_opengl:scale_yz_minus_one");
});

test("normalizeWorld extracts pano, collider, and splats", () => {
  const world = normalizeWorld({
    world_id: "world-2",
    assets: {
      imagery: { pano_url: "pano.png" },
      mesh: { collider_mesh_url: "collider.glb" },
      splats: { spz_urls: { full: "splats.spz" } },
    },
  }, { projectSlug: "sounio", promptSummary: "summary" });
  assert.equal(world.assets.pano_url, "pano.png");
  assert.equal(world.assets.collider_mesh_url, "collider.glb");
  assert.equal(world.assets.spz_urls.full, "splats.spz");
});
