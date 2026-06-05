#!/usr/bin/env node

import { spawn } from "node:child_process";
import { appendFile, mkdir, open, rm } from "node:fs/promises";
import path from "node:path";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
const fullProviders = process.env.PROVIDERS || "claude,codex,cursor";

function safeSlug(slug) {
  return String(slug || "default").replace(/[^a-zA-Z0-9._-]+/g, "-");
}

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

function commandLabel(command, args = []) {
  return [command, ...args].join(" ");
}

function run(command, args = [], { env = {}, timeoutMs = 300_000 } = {}) {
  return new Promise((resolve, reject) => {
    const startedAt = Date.now();
    const child = spawn(command, args, {
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(Object.assign(new Error(`timeout after ${timeoutMs}ms: ${commandLabel(command, args)}`), {
        detail: { stdout, stderr, durationMs: Date.now() - startedAt }
      }));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      stdout += text;
      process.stdout.write(text);
    });
    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      stderr += text;
      process.stderr.write(text);
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      const durationMs = Date.now() - startedAt;
      if (code === 0) {
        resolve({ command: commandLabel(command, args), durationMs, stdout, stderr });
      } else {
        reject(Object.assign(new Error(`command exited ${code}: ${commandLabel(command, args)}`), {
          detail: { code, stdout, stderr, durationMs }
        }));
      }
    });
  });
}

async function withLock(fn) {
  const lockDir = path.join(DATA_DIR, "locks");
  await mkdir(lockDir, { recursive: true });
  const lockPath = path.join(lockDir, `multimodel-full-${projectSlug}.lock`);
  let handle;
  try {
    handle = await open(lockPath, "wx");
    await handle.writeFile(JSON.stringify({
      projectSlug,
      pid: process.pid,
      startedAt: new Date().toISOString()
    }));
  } catch (error) {
    if (error.code === "EEXIST") {
      throw new Error(`another multimodel full verification is already running for ${projectSlug}: ${lockPath}`);
    }
    throw error;
  }
  try {
    return await fn();
  } finally {
    await handle?.close().catch(() => {});
    await rm(lockPath, { force: true }).catch(() => {});
  }
}

const steps = [
  {
    name: "subscription setup",
    command: "npm",
    args: ["run", "verify:multimodel:subscription-setup"],
    timeoutMs: 60_000
  },
  {
    name: "subscription client doctor",
    command: "npm",
    args: ["run", "verify:multimodel:subscription-doctor"],
    timeoutMs: 60_000
  },
  {
    name: "subscription client bringup",
    command: "npm",
    args: ["run", "verify:multimodel:subscription-bringup"],
    timeoutMs: 60_000
  },
  {
    name: "subscription connect plan",
    command: "npm",
    args: ["run", "verify:multimodel:subscription-connect-plan"],
    timeoutMs: 90_000
  },
  {
    name: "subscription live drill",
    command: "npm",
    args: ["run", "verify:multimodel:subscription-live-drill"],
    timeoutMs: 90_000
  },
  {
    name: "subscription drill CLI",
    command: "npm",
    args: ["run", "verify:workbench:subscription-drill-cli"],
    timeoutMs: 60_000
  },
  {
    name: "subscription probe guard",
    command: "npm",
    args: ["run", "verify:multimodel:subscription-probe-guard"],
    timeoutMs: 60_000
  },
  {
    name: "public endpoint doctor",
    command: "npm",
    args: ["run", "verify:multimodel:public-base"],
    timeoutMs: 60_000
  },
  {
    name: "public endpoint candidates",
    command: "npm",
    args: ["run", "verify:multimodel:public-endpoint-candidates"],
    timeoutMs: 60_000
  },
  {
    name: "Tailscale Funnel guard",
    command: "npm",
    args: ["run", "verify:multimodel:tailscale-funnel-guard"],
    timeoutMs: 60_000
  },
  {
    name: "Tailscale Funnel path guard",
    command: "npm",
    args: ["run", "verify:multimodel:tailscale-funnel-path-guard"],
    timeoutMs: 60_000
  },
  {
    name: "Kimi bridge guard",
    command: "npm",
    args: ["run", "verify:multimodel:kimi-bridge-guard"],
    timeoutMs: 60_000
  },
  {
    name: "HTTP MCP auth",
    command: "npm",
    args: ["run", "verify:workbench:http-mcp-auth"],
    timeoutMs: 60_000
  },
  {
    name: "remote MCP transport",
    command: "npm",
    args: ["run", "verify:workbench:remote-mcp-transport"],
    timeoutMs: 60_000
  },
  {
    name: "MCP client kit generate",
    command: "npm",
    args: ["run", "generate:workbench:mcp-client-kit"],
    timeoutMs: 60_000
  },
  {
    name: "MCP client kit install",
    command: "npm",
    args: ["run", "copy:workbench:mcp-client-kit"],
    timeoutMs: 60_000
  },
  {
    name: "MCP client install",
    command: "npm",
    args: ["run", "verify:workbench:mcp-client-install"],
    timeoutMs: 90_000
  },
  {
    name: "MCP client kit",
    command: "npm",
    args: ["run", "verify:workbench:mcp-client-kit"],
    timeoutMs: 90_000
  },
  {
    name: "MCP contract",
    command: "npm",
    args: ["run", "verify:workbench:mcp-contract"],
    timeoutMs: 120_000
  },
  {
    name: "MCP stdio",
    command: "npm",
    args: ["run", "verify:workbench:mcp-stdio"],
    timeoutMs: 120_000
  },
  {
    name: "MCP realtime",
    command: "npm",
    args: ["run", "verify:multimodel:mcp-realtime"],
    timeoutMs: 120_000
  },
  {
    name: "UI send real chat",
    command: "npm",
    args: ["run", "verify:multimodel:ui-send"],
    env: {
      PROVIDERS: process.env.UI_SEND_PROVIDERS || "claude,codex,cursor",
      VERIFY_MULTIMODEL_TIMEOUT_MS: process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || "220000"
    },
    timeoutMs: 240_000
  },
  {
    name: "substantial real chat",
    command: "npm",
    args: ["run", "verify:multimodel:real-chat"],
    env: {
      PROVIDERS: process.env.REAL_CHAT_PROVIDERS || "claude,codex,cursor",
      VERIFY_MULTIMODEL_TIMEOUT_MS: process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || "300000"
    },
    timeoutMs: 330_000
  },
  {
    name: "UI context across live providers",
    command: "npm",
    args: ["run", "verify:multimodel:ui-context"],
    env: {
      PROVIDERS: fullProviders,
      VERIFY_MULTIMODEL_TIMEOUT_MS: process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || "260000"
    },
    timeoutMs: 300_000
  },
  {
    name: "turn evidence",
    command: "npm",
    args: ["run", "verify:multimodel:turn-evidence"],
    env: {
      PROVIDERS: fullProviders
    },
    timeoutMs: 60_000
  },
  {
    name: "UI MCP cancel",
    command: "npm",
    args: ["run", "verify:multimodel:ui-mcp-cancel"],
    timeoutMs: 150_000
  },
  {
    name: "UI subscription reply drill",
    command: "npm",
    args: ["run", "verify:multimodel:ui-subscription-drill"],
    timeoutMs: 120_000
  },
  {
    name: "desktop CLI provider",
    command: "npm",
    args: ["run", "verify:multimodel:desktop-cli-provider"],
    timeoutMs: 150_000
  },
  {
    name: "local live room",
    command: "npm",
    args: ["run", "verify:multimodel:live-room"],
    env: {
      VERIFY_MULTIMODEL_TIMEOUT_MS: process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || "300000"
    },
    timeoutMs: 330_000
  },
  {
    name: "UI stop",
    command: "npm",
    args: ["run", "verify:multimodel:ui-stop"],
    timeoutMs: 150_000
  },
  {
    name: "health",
    command: "npm",
    args: ["run", "verify:multimodel:health"],
    timeoutMs: 60_000
  }
];

try {
  const result = await withLock(async () => {
    const completed = [];
    for (const step of steps) {
      console.log(`\n[full] ${step.name}`);
      const output = await run(step.command, step.args, {
        env: { PROJECT_SLUG: projectSlug, ...(step.env || {}) },
        timeoutMs: step.timeoutMs
      });
      completed.push({
        name: step.name,
        command: output.command,
        durationMs: output.durationMs
      });
    }
    return {
      ok: true,
      schema: "beagle.multimodel-full-verification.v1",
      kind: "full",
      projectSlug,
      providers: fullProviders.split(",").map((item) => item.trim()).filter(Boolean),
      steps: completed,
      verifiedAt: new Date().toISOString(),
      truthMode: "observed-serial-full-multimodel-verification"
    };
  });
  await appendVerificationRecord(projectSlug, result);
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    projectSlug,
    error: error.message,
    detail: error.detail || null,
    truthMode: "verification-failed"
  }, null, 2));
  process.exit(1);
}
