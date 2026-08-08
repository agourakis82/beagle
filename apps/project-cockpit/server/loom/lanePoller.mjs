// lanePoller.mjs — the Frota's truth source. One read-only kubectl exec on a timer peeks EVERY
// workspace lane, classifies each screen, and publishes {state, detail, peek, observedAt}.
//
// Why poll instead of deriving from the attached stream: a card must be honest about lanes you
// are NOT watching. Deriving state only from attached sessions would paint every unwatched lane
// "idle" — a lie by omission, and the operator would stop trusting the board. Peeking is
// read-only (capture-pane), so it never attaches a client and never resizes his real panes.
//
// Every entry carries `observedAt` so the UI can mark it stale instead of asserting a fresh
// truth it does not have (platform invariant: observed/remembered/declared/stale).
import { execFile } from "node:child_process";
import { lanesPeekArgv, parseLanesPeek, WORKSPACE_LANES } from "../platform-bridge.mjs";
import { classifyLane, peekLines } from "./laneState.mjs";

export class LanePoller {
  constructor({ kubectl, ns, intervalMs = 12000, execFn = execFile, now = () => Date.now() }) {
    this._kubectl = kubectl; this._ns = ns; this._intervalMs = intervalMs;
    this._exec = execFn; this._now = now;
    this._states = new Map();     // lane -> { state, detail, peek, approveKey, observedAt }
    this._timer = null;
    this._inFlight = false;
    this.lastError = null;
  }

  /// Latest verdict for a lane, or null if never observed (caller must NOT invent one).
  get(lane) { return this._states.get(lane) || null; }
  all() { return Object.fromEntries(this._states); }

  start() {
    if (this._timer) return;
    this.poll();
    this._timer = setInterval(() => this.poll(), this._intervalMs);
    this._timer?.unref?.();
  }
  stop() { clearInterval(this._timer); this._timer = null; }

  /// One sweep. Never throws: a failed sweep leaves the previous (now-ageing) verdicts intact.
  poll() {
    if (this._inFlight) return;          // a slow cluster must not stack execs
    this._inFlight = true;
    return new Promise((resolve) => {
      this._exec(this._kubectl, lanesPeekArgv(this._ns), { maxBuffer: 4 * 1024 * 1024, timeout: 20000 },
        (err, stdout) => {
          this._inFlight = false;
          if (err && !stdout) { this.lastError = String(err.message || err); return resolve(false); }
          this.lastError = null;
          this.ingest(String(stdout || ""));
          resolve(true);
        });
    });
  }

  /// Pure-ish: parse a batched peek and update the verdict table. Exposed for tests.
  ingest(stdout) {
    const screens = parseLanesPeek(stdout);
    const now = this._now();
    for (const lane of WORKSPACE_LANES) {
      const text = screens[lane];
      if (text === undefined) continue;                 // lane absent → keep the old, ageing entry
      const prev = this._states.get(lane);
      const changed = !prev || prev.rawTail !== text;
      const r = classifyLane({
        text,
        // Output age is only known across sweeps; unchanged screen = no new output.
        lastOutputAt: changed ? now : (prev?.lastOutputAt ?? now),
        now,
      });
      this._states.set(lane, {
        state: r.state,
        detail: r.detail,
        approveKey: r.approveKey,
        peek: peekLines(text, 2),
        observedAt: now,
        lastOutputAt: changed ? now : (prev?.lastOutputAt ?? now),
        rawTail: text,
      });
    }
    return this._states;
  }
}
