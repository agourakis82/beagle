// mount.mjs — build the real session factory + expose a self-contained mount helper.
//
// Self-contained by design: index.mjs does not have KUBECTL/AGENT_NAMESPACE/bridgePodName
// in scope (those live in agent-routes.mjs / platform-routes.mjs), so this module defines
// its own copies, mirroring the existing pattern in platform-routes.mjs (lines 7-14).
import { execFileSync } from "node:child_process";
import { Broker } from "./broker.mjs";
import { OwnedPtySession } from "./ownedSession.mjs";
import { AdaptedSession } from "./adaptedSession.mjs";
import { recipeFor } from "./catalog.mjs";
import { isT560Kind, zellijCleanupArgv } from "../platform-bridge.mjs";

const KUBECTL = process.env.PROJECT_COCKPIT_KUBECTL || "/usr/local/bin/kubectl";
const NS = process.env.PROJECT_COCKPIT_AGENT_NAMESPACE || "beagle";

// Resolve the t560 platform-bridge pod synchronously (AdaptedSession calls podResolver
// inline, not async), mirroring agent-routes.mjs's bridgePodName but via execFileSync.
function syncBridgePodResolver() {
  const out = execFileSync(KUBECTL, ["-n", NS, "get", "pod",
    "-l", "app=platform-bridge", "-o", "jsonpath={.items[0].metadata.name}"], { encoding: "utf8" });
  if (!out.trim()) throw new Error("platform-bridge pod not found");
  return out.trim();
}

export function makeSessionFactory({ kubectl, ns, podResolver }) {
  return (sid, kind) => {
    if (isT560Kind(kind)) return new AdaptedSession(sid, kind, { kubectl, ns, podResolver });
    const recipe = recipeFor(kind);
    if (!recipe) throw new Error(`unknown kind: ${kind}`);
    return new OwnedPtySession(sid, kind, recipe);
  };
}

// mountLoom() is self-contained: no args needed from index.mjs. Builds the real
// kubectl/ns/podResolver internally and returns a Broker singleton wired to
// handleConnection(ws) by the caller.
// His existing attachable sessions (Command Deck adapters): 3 t560 tmux sessions + the
// sounio workspace zellij. Seeded lazily — each attaches on first subscribe.
const SEED_SESSIONS = [
  { kind: "t560-beagle",     title: "beagle" },
  { kind: "t560-darwin-ops", title: "darwin-ops" },
  { kind: "t560-clops",      title: "clops" },
  { kind: "sounio-dev",      title: "sounio-dev" },
];

export function mountLoom() {
  const podResolver = syncBridgePodResolver;
  const sessionFactory = makeSessionFactory({ kubectl: KUBECTL, ns: NS, podResolver });
  const broker = new Broker({ sessionFactory });
  for (const { kind, title } of SEED_SESSIONS) {
    broker.addLazySeed(kind, kind, () => new AdaptedSession(kind, kind, { kubectl: KUBECTL, ns: NS, podResolver }), { title });
  }
  // Startup hygiene: clear broker zellij attaches orphaned by a previous pod (rollout leaks).
  for (const { kind } of SEED_SESSIONS) {
    const cargv = zellijCleanupArgv(kind, NS);
    if (cargv) { try { execFileSync(KUBECTL, cargv, { stdio: "ignore", timeout: 8000 }); } catch { /* best effort */ } }
  }
  broker.startStatePump();
  return broker;
}
