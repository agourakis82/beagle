import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyPath, signalWeight } from "../src/walk.mjs";

test("excludes junk dirs", () => {
  assert.equal(classifyPath("a/node_modules/x.js"), "exclude");
  assert.equal(classifyPath("a/target/x.rs"), "exclude");
  assert.equal(classifyPath("a/.git/objects/ab"), "exclude");
  assert.equal(classifyPath("a/.cache/x"), "exclude");
});
test("includes high-signal content", () => {
  assert.equal(classifyPath("projects/notes.md"), "include");
  assert.equal(classifyPath("papers/hsn.tex"), "include");
  assert.equal(classifyPath("a/thoughts.txt"), "include");
});
test("prose-only mode keeps writing + shell history, drops source code", () => {
  const opt = { proseOnly: true };
  assert.equal(classifyPath("papers/hsn.tex", opt), "include");
  assert.equal(classifyPath("notes/diary.md", opt), "include");
  assert.equal(classifyPath("x/.bash_history", opt), "include");
  assert.equal(classifyPath("self-hosted/lexer/main.sio", opt), "exclude");
  assert.equal(classifyPath("src/lib.rs", opt), "exclude");
});

test("biographical signal weighting ranks writing above generated docs", () => {
  assert.ok(signalWeight("research/hsn.tex") > signalWeight("crate/README.md"));
  assert.ok(signalWeight("journal/2026.md") > signalWeight("node_modules/pkg/README.md"));
  assert.ok(signalWeight("src/lib.rs") < signalWeight("notes/diary.md"));
});
