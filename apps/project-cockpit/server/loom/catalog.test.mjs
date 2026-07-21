import { test } from "node:test";
import assert from "node:assert/strict";
import { catalogKinds, recipeFor } from "./catalog.mjs";

test("catalog has the eight agent kinds plus a raw shell", () => {
  assert.deepEqual(catalogKinds(),
    ["claude", "codex", "cursor", "glm", "kimi", "grok", "opencode", "local", "shell"]);
});

test("recipeFor resolves fixed argv; unknown kind refused", () => {
  const codex = recipeFor("codex");
  assert.ok(Array.isArray(codex.argv) && codex.argv.length > 0);
  assert.equal(recipeFor("codex").argv.includes(";"), false); // no shell metachars smuggled
  assert.equal(recipeFor("evil; rm -rf"), null);
  assert.equal(recipeFor(""), null);
  assert.equal(recipeFor("shell").argv[0], "/bin/bash");
});
