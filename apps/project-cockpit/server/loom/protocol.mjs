// protocol.mjs — the fixed client<->broker message set. The swap boundary.
// "unknown" = advertised but never observed. It exists so a card can say "I don't know yet"
// instead of defaulting to a comfortable-looking "idle" it has not earned.
export const STATES = ["running", "idle", "waiting", "stuck", "exited", "unknown"];
export const CLIENT_TYPES = new Set(["hello", "list", "subscribe", "unsubscribe", "input", "resize", "create", "kill", "reset"]);
export const SERVER_TYPES = new Set(["sessions", "scrollback", "data", "state", "exit", "error"]);

export function decodeClient(str) {
  let m;
  try { m = JSON.parse(str); } catch { return null; }
  if (!m || typeof m !== "object" || !CLIENT_TYPES.has(m.t)) return null;
  return m;
}
export function encodeServer(msg) {
  if (!msg || !SERVER_TYPES.has(msg.t)) throw new Error(`bad server msg: ${msg && msg.t}`);
  return JSON.stringify(msg);
}
