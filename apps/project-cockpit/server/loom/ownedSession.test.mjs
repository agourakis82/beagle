import { test } from "node:test";
import assert from "node:assert/strict";
import { OwnedPtySession } from "./ownedSession.mjs";
import { recipeFor } from "./catalog.mjs";

test("owned session runs a recipe, streams output to the ring, then exits", async () => {
  // Use the shell recipe to run a trivial deterministic command.
  const s = new OwnedPtySession("t1", "shell", recipeFor("shell"));
  let out = "";
  s.onData((d) => { out += d; });
  const exited = new Promise((res) => s.onExit(res));
  s.write("echo loom-ok; exit\n");
  await exited;
  assert.match(out, /loom-ok/);
  assert.match(s.snapshot(), /loom-ok/);
  assert.equal(s.meta.alive, false);
  assert.equal(s.meta.source, "owned");
});
