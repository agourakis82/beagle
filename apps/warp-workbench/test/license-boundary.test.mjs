// SPDX-License-Identifier: AGPL-3.0-only

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(new URL("../../../", import.meta.url).pathname);

test("Warp-derived code has an explicit AGPL boundary", () => {
  const readme = fs.readFileSync(path.join(root, "apps/warp-workbench/README.md"), "utf8");
  const license = fs.readFileSync(path.join(root, "apps/warp-workbench/LICENSE"), "utf8");
  const gitmodules = fs.readFileSync(path.join(root, ".gitmodules"), "utf8");

  assert.match(readme, /AGPL boundary/i);
  assert.match(license, /AGPL-3\.0-only/);
  assert.match(gitmodules, /apps\/warp-workbench\/vendor\/warp/);
});

test("Core services do not import the AGPL workbench boundary", () => {
  const guarded = [
    "apps/beagle-monorepo",
    "apps/beagle-memory-engine",
    "beagle-mcp-server",
  ];

  for (const rel of guarded) {
    const dir = path.join(root, rel);
    if (!fs.existsSync(dir)) continue;
    const hits = [];
    const stack = [dir];
    while (stack.length) {
      const current = stack.pop();
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const next = path.join(current, entry.name);
        if (entry.isDirectory()) {
          if (!["node_modules", "target", ".build", "dist"].includes(entry.name)) stack.push(next);
        } else if (/\.(rs|ts|js|mjs|swift|toml|json)$/.test(entry.name)) {
          const text = fs.readFileSync(next, "utf8");
          if (text.includes("apps/warp-workbench") || text.includes("@beagle/warp-workbench")) {
            hits.push(path.relative(root, next));
          }
        }
      }
    }
    assert.deepEqual(hits, [], `${rel} must not import the AGPL boundary`);
  }
});

test("Project Cockpit does not import the AGPL renderer probe", () => {
  const guarded = [
    "apps/project-cockpit",
    "apps/beagle-monorepo",
    "apps/beagle-memory-engine",
    "beagle-mcp-server",
  ];

  for (const rel of guarded) {
    const dir = path.join(root, rel);
    if (!fs.existsSync(dir)) continue;
    const hits = [];
    const stack = [dir];
    while (stack.length) {
      const current = stack.pop();
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const next = path.join(current, entry.name);
        if (entry.isDirectory()) {
          if (!["node_modules", "target", ".build", "dist"].includes(entry.name)) stack.push(next);
        } else if (/\.(rs|ts|js|mjs|swift|toml|json)$/.test(entry.name)) {
          const text = fs.readFileSync(next, "utf8");
          if (text.includes("renderer/warp-metal-probe") || text.includes("warp-metal-probe.mjs")) {
            hits.push(path.relative(root, next));
          }
        }
      }
    }
    assert.deepEqual(hits, [], `${rel} must not import the AGPL renderer probe`);
  }
});
