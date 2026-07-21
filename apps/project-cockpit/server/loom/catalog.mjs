// catalog.mjs — the allowlist of agent launch recipes. The leash: only these spawn.
// Each recipe is fixed argv + env; no request input is ever interpolated in.
const NODE_BIN = process.env.LOOM_NODE_BIN || "node";
const CATALOG = {
  claude:   { argv: ["claude"],                       resumeArgv: ["claude", "--continue"] },
  codex:    { argv: [NODE_BIN, "codex"],              resumeArgv: [NODE_BIN, "codex", "resume", "--last"] },
  cursor:   { argv: ["cursor-agent"],                 resumeArgv: null },
  glm:      { argv: ["glm"],                          resumeArgv: null },
  kimi:     { argv: ["kimi"],                         resumeArgv: null },
  grok:     { argv: ["grok"],                         resumeArgv: null },
  opencode: { argv: ["opencode"],                     resumeArgv: null },
  local:    { argv: ["beagle-local-agent"],           resumeArgv: null },
  shell:    { argv: ["/bin/bash", "-l"],              resumeArgv: null },
};
export function catalogKinds() { return Object.keys(CATALOG); }
export function recipeFor(kind) {
  if (!Object.prototype.hasOwnProperty.call(CATALOG, kind)) return null;
  const r = CATALOG[kind];
  return { argv: r.argv, resumeArgv: r.resumeArgv, env: {}, home: null, cwd: null };
}
