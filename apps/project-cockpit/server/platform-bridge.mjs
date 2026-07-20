// platform-bridge.mjs — the leash. Maps allowlisted t560 session kinds to EXACT tmux argv
// against the bridge pod. No free-form command ever reaches tmux. Pure + unit-tested.
export const SESSION_ALLOWLIST = {
  "t560-beagle":     { socket: "default", target: "beagle" },
  "t560-darwin-ops": { socket: "default", target: "darwin-ops" },
  "t560-clops":      { socket: "clops",   target: "clops" },
};
const SOCK = (s) => `/tmp/tmux-1000/${s}`;
const TMUX_LIST_FORMAT = "#{session_name}|#{session_attached}|#{session_activity}|#{window_name}";

export function isT560Kind(kind) {
  return Object.prototype.hasOwnProperty.call(SESSION_ALLOWLIST, kind);
}
export function tmuxAttachArgv(kind) {
  const s = SESSION_ALLOWLIST[kind];
  return s ? ["-S", SOCK(s.socket), "attach", "-t", s.target] : null;
}
export function tmuxControlArgv(kind, verb) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s) return null;
  if (verb === "kill") return ["-S", SOCK(s.socket), "kill-session", "-t", s.target];
  if (verb === "list") return ["-S", SOCK(s.socket), "list-sessions", "-F", TMUX_LIST_FORMAT];
  return null;
}
/** raw = { <kind>: "<name>|<attached>|<activity_epoch>|<window>" }. now = epoch seconds. */
export function buildSessionList(raw, now) {
  const out = [];
  for (const [kind, line] of Object.entries(raw || {})) {
    if (typeof line !== "string" || !line.trim()) continue;
    const [name, attached, activity, window] = line.trim().split("|");
    out.push({
      kind, name,
      attached: attached === "1",
      idleSeconds: Math.max(0, Math.round((Number(now) || 0) - (Number(activity) || 0))),
      window: window || "",
    });
  }
  return out;
}
