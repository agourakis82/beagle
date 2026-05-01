import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import {
  buildGenerationDraft,
  cacheManifest,
  createWorldLabsClient,
  generateWorld,
  getWorld,
  listSpatialProviderSlots,
  pollOperation,
} from "./world-console-core.mjs";

const port = Number(process.env.WORLD_CONSOLE_PORT || process.env.PORT || 8096);
const host = process.env.WORLD_CONSOLE_HOST || "0.0.0.0";
const rootDir = process.env.BEAGLE_SPATIAL_WORLD_DIR || "/orangefs/beagle-spatial-worlds";
const mockMode = process.env.WORLD_CONSOLE_MOCK === "true";

const client = mockMode
  ? mockClient()
  : process.env.WORLDLABS_API_KEY
    ? createWorldLabsClient({
        apiKey: process.env.WORLDLABS_API_KEY,
        baseUrl: process.env.WORLDLABS_BASE_URL,
      })
    : unconfiguredClient();

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    if (req.method === "GET" && url.pathname === "/health") {
      return json(res, 200, { status: "ok", service: "world-console", mock: mockMode });
    }
    if (req.method === "GET" && url.pathname === "/ready") {
      return json(res, 200, {
        status: "ready",
        worldlabs_configured: mockMode || Boolean(process.env.WORLDLABS_API_KEY),
        asset_root: rootDir,
      });
    }
    if (req.method === "GET" && url.pathname === "/v1/providers") {
      return json(res, 200, {
        schema_version: "beagle-spatial-forge-v3.7",
        providers: listSpatialProviderSlots(process.env),
      });
    }
    if (req.method === "POST" && url.pathname === "/v1/generation/drafts") {
      const body = await readJson(req);
      return json(res, 200, buildGenerationDraft(body, process.env));
    }
    if (req.method === "POST" && url.pathname === "/v1/worlds/marble") {
      const body = await readJson(req);
      return json(res, 200, await generateWorld({ client, input: body, rootDir }));
    }
    const operationMatch = url.pathname.match(/^\/v1\/operations\/([^/]+)$/);
    if (req.method === "GET" && operationMatch) {
      return json(
        res,
        200,
        await pollOperation({ client, operationId: decodeURIComponent(operationMatch[1]), rootDir }),
      );
    }
    const worldAssetsMatch = url.pathname.match(/^\/v1\/worlds\/([^/]+)\/assets$/);
    if (req.method === "GET" && worldAssetsMatch) {
      const manifest = await loadOrFetchWorld(decodeURIComponent(worldAssetsMatch[1]));
      return json(res, 200, manifest.assets);
    }
    const worldMatch = url.pathname.match(/^\/v1\/worlds\/([^/]+)$/);
    if (req.method === "GET" && worldMatch) {
      return json(res, 200, await loadOrFetchWorld(decodeURIComponent(worldMatch[1])));
    }
    return json(res, 404, { error: "not_found" });
  } catch (error) {
    return json(res, Number(error?.statusCode || 500), {
      error: error?.message || "world_console_request_failed",
    });
  }
});

server.listen(port, host, () => {
  console.log(`world-console listening on ${host}:${port}`);
});

async function loadOrFetchWorld(worldId) {
  const manifestPath = path.join(rootDir, worldId, "asset-manifest.json");
  try {
    return JSON.parse(await readFile(manifestPath, "utf8"));
  } catch {
    return getWorld({ client, worldId, rootDir });
  }
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const text = Buffer.concat(chunks).toString("utf8");
  return text ? JSON.parse(text) : {};
}

function json(res, status, value) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(value));
}

function mockClient() {
  return {
    async generateWorld(payload) {
      return {
        done: false,
        operation_id: "op-mock-sounio-control-room",
        created_at: new Date().toISOString(),
        response: null,
        metadata: { model: payload.model },
      };
    },
    async getOperation(operationId) {
      return {
        done: true,
        operation_id: operationId,
        response: mockWorld("world-mock-sounio-control-room"),
      };
    },
    async getWorld(worldId) {
      return mockWorld(worldId);
    },
  };
}

function unconfiguredClient() {
  const fail = async () => {
    throw Object.assign(new Error("WORLDLABS_API_KEY is not configured"), { statusCode: 503 });
  };
  return {
    generateWorld: fail,
    getOperation: fail,
    getWorld: fail,
  };
}

function mockWorld(worldId) {
  return {
    world_id: worldId,
    display_name: "Sounio Control Room",
    model: "marble-1.1",
    world_marble_url: `https://marble.worldlabs.ai/worlds/${worldId}`,
    permission: { access: "private" },
    tags: ["beagle", "sounio", "spatial-control-room"],
    assets: {
      imagery: { pano_url: `https://assets.example/${worldId}/pano.png` },
      mesh: { collider_mesh_url: `https://assets.example/${worldId}/collider.glb` },
      splats: {
        spz_urls: {
          low_res: `https://assets.example/${worldId}/splats-low.spz`,
          full: `https://assets.example/${worldId}/splats.spz`,
        },
      },
    },
  };
}
