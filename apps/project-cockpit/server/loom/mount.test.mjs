// mount.test.mjs — TDD for the real session factory + mountLoom wiring.
import { test } from "node:test";
import assert from "node:assert/strict";
import { makeSessionFactory } from "./mount.mjs";

test("makeSessionFactory builds owned sessions for catalog kinds", () => {
  const factory = makeSessionFactory({ kubectl: "/k", ns: "beagle", podResolver: () => "p" });
  const s = factory("shell-1", "shell");
  assert.equal(s.meta.source, "owned");
  s.kill();
});

test("makeSessionFactory builds adapted sessions for allowlisted t560-* kinds", () => {
  const factory = makeSessionFactory({
    kubectl: "/bin/true",
    ns: "beagle",
    podResolver: () => "bridge-pod",
  });
  const s = factory("t560-1", "t560-beagle");
  assert.equal(s.meta.source, "adapted");
  s.kill();
});

test("makeSessionFactory throws on unknown catalog kind", () => {
  const factory = makeSessionFactory({ kubectl: "/k", ns: "beagle", podResolver: () => "p" });
  assert.throws(() => factory("x-1", "not-a-real-kind"), /unknown kind/);
});
