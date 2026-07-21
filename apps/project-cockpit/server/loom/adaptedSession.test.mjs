import { test } from "node:test";
import assert from "node:assert/strict";
import { adaptedAttachArgv } from "./adaptedSession.mjs";

test("adapted attach builds an exact kubectl argv from the deck allowlist, refuses unknown", () => {
  const argv = adaptedAttachArgv("t560-beagle", "/usr/local/bin/kubectl", "beagle", () => "bridge-pod");
  assert.deepEqual(argv,
    ["-n", "beagle", "exec", "-it", "bridge-pod", "--", "tmux", "-S", "/tmp/tmux-1000/default", "attach", "-t", "beagle"]);
  assert.equal(adaptedAttachArgv("evil", "/k", "beagle", () => "p"), null);
});
