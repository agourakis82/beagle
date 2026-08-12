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
import { lanesPeekArgv, parseLanesPeek, parseLanesAlive, WORKSPACE_LANES } from "../platform-bridge.mjs";
import { classifyLane, peekLines } from "./laneState.mjs";
import { LoomdView } from "./loomd.mjs";

export class LanePoller {
  constructor({ kubectl, ns, intervalMs = 12000, execFn = execFile, now = () => Date.now() }) {
    this._kubectl = kubectl; this._ns = ns; this._intervalMs = intervalMs;
    this._exec = execFn; this._now = now;
    this._states = new Map();     // lane -> { state, detail, peek, approveKey, observedAt }
    // A segunda fonte, medida no protocolo, que vem de carona NO MESMO exec e portanto no mesmo
    // relógio deste sweep. Ela nunca sobrescreve `_states`: as duas convivem rotuladas.
    this._loomd = new LoomdView({ now });
    this._timer = null;
    this._inFlight = false;
    this._pending = null;
    this.lastError = null;
  }

  /// Latest verdict for a lane, or null if never observed (caller must NOT invent one).
  /// SEMPRE `inferred`: isto aqui é tela raspada, e o rótulo não depende de quem pergunta.
  get(lane) { return this._states.get(lane) || null; }
  all() { return Object.fromEntries(this._states); }

  /// A leitura exata (loomd) da mesma varredura. `loomdTruth()` diz se ela vale — um chamador
  /// que só olhar `loomd(lane)` e achar null não pode concluir "não há lane": pode ser a fonte
  /// que caiu, e essa diferença é o produto desta rodada.
  loomd(lane) { return this._loomd.get(lane); }
  loomdAll() { return this._loomd.lanes; }
  loomdTruth() { return this._loomd.truth(); }

  start() {
    if (this._timer) return;
    this.poll();
    this._timer = setInterval(() => this.poll(), this._intervalMs);
    this._timer?.unref?.();
  }
  stop() { clearInterval(this._timer); this._timer = null; }

  /// Sweep now instead of waiting out the interval. After a one-touch action the card must catch
  /// up in a beat, not in 12s — a board that lags its own button teaches the operator to press
  /// twice. A sweep already in flight is awaited rather than duplicated.
  async refreshNow() { return this.poll(); }

  /// One sweep. Never throws: a failed sweep leaves the previous (now-ageing) verdicts intact.
  poll() {
    if (this._inFlight) return this._pending;   // a slow cluster must not stack execs
    this._inFlight = true;
    this._pending = new Promise((resolve) => {
      this._exec(this._kubectl, lanesPeekArgv(this._ns), { maxBuffer: 4 * 1024 * 1024, timeout: 20000 },
        (err, stdout) => {
          this._inFlight = false;
          if (err && !stdout) { this.lastError = String(err.message || err); return resolve(false); }
          this.lastError = null;
          this.ingest(String(stdout || ""));
          resolve(true);
        });
    });
    return this._pending;
  }

  /// Pure-ish: parse a batched peek and update the verdict table. Exposed for tests.
  ingest(stdout) {
    const screens = parseLanesPeek(stdout);
    // null = this read carried no liveness block (old server, truncated output). Then we know
    // nothing about existence and must not claim a lane is gone.
    const alive = parseLanesAlive(stdout);
    const now = this._now();
    // Mesmo stdout, mesmo `now`: o card exato e o card adivinhado envelhecem pelo mesmo relógio.
    // Só é chamado aqui dentro — `ingest` só roda quando o exec VOLTOU, e um exec que falhou não
    // é medição sobre o loomd (ver o quadro em loomd.mjs).
    this._loomd.ingest(stdout, now);
    for (const lane of WORKSPACE_LANES) {
      const text = screens[lane];
      if (text === undefined) continue;                 // no record at all → keep the old, ageing entry
      const prev = this._states.get(lane);
      const changed = !prev || prev.rawTail !== text;
      const r = classifyLane({
        text,
        // A lane tmux does not list does not exist. Without this, `capture-pane` failing into an
        // empty string reads as "blank screen" → `unknown`, and the board shows cards for lanes
        // that were never created (measured: grok-cli1/2 and codex-3, 2026-08-09).
        alive: alive ? alive.has(lane) : true,
        // Output age is only known across sweeps; unchanged screen = no new output.
        lastOutputAt: changed ? now : (prev?.lastOutputAt ?? now),
        now,
      });
      this._states.set(lane, {
        state: r.state,
        detail: r.detail,
        approveKey: r.approveKey,
        // Whether the lane is sitting at a SHELL (not an agent's input box). Anything that types
        // a command may only aim here — see laneActions.decideIsolate.
        atShell: r.atShell,
        // Declarado pelo classificador, nunca deduzido de prosa pelo cliente.
        ausente: r.ausente === true,
        peek: peekLines(text, 2),
        observedAt: now,
        lastOutputAt: changed ? now : (prev?.lastOutputAt ?? now),
        rawTail: text,
      });
    }
    return this._states;
  }
}
