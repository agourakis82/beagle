// platform-bridge.mjs — the leash. Maps allowlisted Command Deck session kinds to EXACT
// kubectl-exec targets: t560 tmux (via the t560 platform-bridge pod) and the sounio workspace
// zellij (via the workspace pod, as the non-root workspace user). No free-form command ever
// reaches a shell — every argv is fixed here. Pure + unit-tested.

const SOCK = (s) => `/tmp/tmux-1000/${s}`;
const TMUX_LIST_FORMAT = "#{session_name}|#{session_attached}|#{session_activity}|#{window_name}";
/// How many rows of scrollback a "peek" reads. Enough for a state verdict + a quoted question.
export const PEEK_LINES = 25;
/// Record separator for the batched fleet peek. Chosen to not occur in terminal output.
export const PEEK_DELIM = "@@LANE:";
/// Record separator for the batched receipt read.
export const RECEIPT_DELIM = "@@RECEIPT:";
/// Marks the liveness block that the batched peek emits BEFORE the per-lane screens.
export const ALIVE_DELIM = "@@ALIVE:";
/// Marks the loomd block — the FIRST block of the batched peek, before @@ALIVE.
export const LOOMD_DELIM = "@@LOOMD:";
/// O supervisor loomd, dentro do MESMO pod do workspace. Fica em 127.0.0.1 de propósito: ele
/// não tem autenticação nenhuma e o ns beagle não tem NetworkPolicy, então a porta não é
/// exposta ao cluster. O único caminho até ele é este exec, que já é autenticado pelo RBAC
/// do cockpit — carona no transporte que já existe, zero superfície nova.
export const LOOMD_BASE = "http://127.0.0.1:4400";
export const LOOMD_STATE_URL = `${LOOMD_BASE}/v2/state`;
/// Teto de espera do curl. NÃO negociável: este curl roda EM SÉRIE com os 11 capture-pane
/// dentro do `timeout: 20000` do LanePoller. Um loomd travado (não morto) sem teto estouraria
/// o sweep inteiro e envelheceria os 11 vereditos — o loomd derrubaria o board que veio melhorar.
export const LOOMD_TIMEOUT_S = 3;

// The ONLY keystrokes the cockpit may inject into a lane, by tmux key name. A closed set is the
// whole security argument for one-touch approval: a named key is the same `y` he would press, it
// is not a command. Anything a lane needs typed (a real answer to a real question) still requires
// the terminal — see the `input` path on /ws/loom.
export const LANE_KEYS = { enter: "Enter", y: "y", esc: "Escape" };

// pod "@bridge" = resolve the t560 platform-bridge pod at call time; a literal name = that pod.
// The 11 workspace agent lanes are tmux sessions on the workspace pod's OWN uid-owned socket:
// the herd runs them under TMUX_TMPDIR=<home>/.tmux (NOT /tmp/tmux-1000), so they resolve the
// socket via TMUX_TMPDIR and run as the non-root workspace user (`su`-wrapped, like sounio-dev).
export const WORKSPACE_LANES = [
  "claude-1", "claude-2", "claude-3", "codex-1", "codex-2", "codex-3",
  "kimi-cli1", "kimi-cli2", "grok-cli1", "grok-cli2", "repo",
];
const WORKSPACE_LANE = (target) => ({
  type: "tmux", pod: "sounio-workspace-control-0", container: "workspace-ssh",
  user: "openvscode-server", home: "/workspace/.home/openvscode-server",
  tmuxTmpdir: "/workspace/.home/openvscode-server/.tmux", target,
});

export const SESSION_ALLOWLIST = {
  "t560-beagle":     { type: "tmux", pod: "@bridge", socket: "default", target: "beagle" },
  "t560-darwin-ops": { type: "tmux", pod: "@bridge", socket: "default", target: "darwin-ops" },
  "t560-clops":      { type: "tmux", pod: "@bridge", socket: "clops",   target: "clops" },
  "sounio-dev":      { type: "zellij", pod: "sounio-workspace-control-0", container: "workspace-ssh",
                       user: "openvscode-server", home: "/home/openvscode-server", session: "sounio-dev" },
  ...Object.fromEntries(WORKSPACE_LANES.map((l) => [l, WORKSPACE_LANE(l)])),
};

// Any allowlisted deck session (name kept isT560Kind for the existing import sites).
export function isT560Kind(kind) {
  return Object.prototype.hasOwnProperty.call(SESSION_ALLOWLIST, kind);
}
export const isDeckKind = isT560Kind;

// zellij runs as a non-root workspace user; wrap in `su` with a clean env. The body is fixed
// (user/home/session come only from the allowlist above — never from request input).
function zellijSu(s, inner) {
  const body = `cd ${s.home}; unset ZELLIJ ZELLIJ_SESSION_NAME; export HOME=${s.home}; exec ${inner}`;
  return ["su", "-s", "/bin/bash", s.user, "-c", body];
}

// Workspace tmux lanes run as the non-root user under their own TMUX_TMPDIR (NOT /tmp/tmux-1000).
// Same `su`-wrap discipline as zellij; the socket is resolved by TMUX_TMPDIR so no `-S` is needed.
// user/home/tmuxTmpdir/target come ONLY from the allowlist — never from request input.
function tmuxSu(s, inner) {
  const body = `export HOME=${s.home}; export TMUX_TMPDIR=${s.tmuxTmpdir}; exec ${inner}`;
  return ["su", "-s", "/bin/bash", s.user, "-c", body];
}

// Returns { pod, container, argv } — the part AFTER `kubectl -n <ns> exec -i[t] <pod> [-c <c>] --`
// — or null if kind/action is not allowlisted. pod may be "@bridge".
// Tab names are injection-safe only if they match this charset (no shell metacharacters);
// the goto-tab param is shell-interpolated inside zellijSu, so anything else is refused.
const SAFE_TAB = /^[A-Za-z0-9._-]{1,64}$/;

export function deckExec(kind, action, param) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s) return null;
  if (s.type === "tmux") {
    // Workspace lanes (s.user set): non-root, own TMUX_TMPDIR, `su`-wrapped, socket via env.
    if (s.user) {
      let inner;
      if (action === "attach") inner = `tmux attach -t ${s.target}`;
      else if (action === "list") inner = `tmux list-sessions -F '${TMUX_LIST_FORMAT}'`;
      else if (action === "kill") inner = `tmux kill-session -t ${s.target}`;
      // Read-only screen read: no attach, no client, so it cannot resize or disturb his lane.
      else if (action === "peek") inner = `tmux capture-pane -p -t ${s.target} -S -${PEEK_LINES}`;
      else return null;
      return { pod: s.pod, container: s.container || null, argv: tmuxSu(s, inner) };
    }
    // @bridge sessions: root on the platform-bridge pod, explicit -S socket, no user wrap.
    let cmd;
    if (action === "attach") cmd = ["tmux", "-S", SOCK(s.socket), "attach", "-t", s.target];
    else if (action === "list") cmd = ["tmux", "-S", SOCK(s.socket), "list-sessions", "-F", TMUX_LIST_FORMAT];
    else if (action === "kill") cmd = ["tmux", "-S", SOCK(s.socket), "kill-session", "-t", s.target];
    else if (action === "peek") cmd = ["tmux", "-S", SOCK(s.socket), "capture-pane", "-p", "-t", s.target, "-S", `-${PEEK_LINES}`];
    else return null;
    return { pod: s.pod, container: null, argv: cmd };
  }
  if (s.type === "zellij") {
    let inner;
    if (action === "attach") inner = `zellij attach ${s.session}`;
    else if (action === "list") inner = "zellij list-sessions";
    else if (action === "kill") inner = `zellij kill-session ${s.session}`;
    else if (action === "tab-next") inner = `zellij -s ${s.session} action go-to-next-tab`;
    else if (action === "tab-prev") inner = `zellij -s ${s.session} action go-to-previous-tab`;
    else if (action === "tabs") inner = `zellij -s ${s.session} action dump-layout`;
    else if (action === "goto-tab") {
      if (!SAFE_TAB.test(String(param || ""))) return null;
      inner = `zellij -s ${s.session} action go-to-tab-name ${param}`;
    }
    else return null;
    return { pod: s.pod, container: s.container || null, argv: zellijSu(s, inner) };
  }
  return null;
}

// Kill leaked broker-owned zellij attach clients for a session, WITHOUT touching his real
// clients (e.g. the Mac via Termius). Discriminator: broker attaches are children of a
// `su -s /bin/bash <user>` process; his direct clients are children of sshd. Killing the
// cockpit-side kubectl-exec does NOT reliably kill the remote attach (it orphans), so this
// parent-based cleanup is the reliable detach. Session/user come only from the allowlist.
export function zellijCleanupArgv(kind, ns) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s || s.type !== "zellij") return null;
  const script =
    `for z in $(pgrep -x -f "zellij attach ${s.session}" 2>/dev/null); do ` +
    `pp=$(ps -o ppid= -p "$z" 2>/dev/null | tr -d " "); ` +
    `pc=$(ps -o args= -p "$pp" 2>/dev/null); ` +
    `case "$pc" in *"su -s /bin/bash ${s.user}"*) kill -9 "$z" "$pp" 2>/dev/null;; esac; done`;
  return ["-n", ns, "exec", s.pod, "-c", s.container, "--", "sh", "-c", script];
}

// ONE kubectl exec that read-only-peeks EVERY workspace lane, delimited per lane. This is what
// lets the Frota show a TRUE state for all 11 lanes without attaching to any of them (attaching
// 11 clients would resize his real panes). The lane list is the allowlist constant — never
// request input — so the interpolated loop carries no injection surface. Read-only by
// construction: capture-pane cannot write to a pane.
// The same exec also reports which sessions actually EXIST. Without it a lane that was never
// created reads identically to one whose screen is blank — `capture-pane` sends "can't find pane"
// to stderr, which is discarded, so the peek comes back empty and the classifier says `unknown`
// ("advertised but never observed"). That painted cards for three lanes that do not exist.
export function lanesPeekArgv(ns) {
  const lane0 = SESSION_ALLOWLIST[WORKSPACE_LANES[0]];
  // O bloco do loomd vem PRIMEIRO e no MESMO exec: mesmo pod, mesmo container, mesmo relógio,
  // zero RBAC novo. O `echo` final é carga útil, não enfeite — a resposta do axum não termina
  // em newline, e sem ele o `@@ALIVE:` gruda no fim do JSON: o JSON não parseia (loomd lido
  // como caído) E o bloco de liveness some (as 11 lanes passariam a ser assumidas vivas).
  const loomd = `echo "${LOOMD_DELIM}"; curl -fsS --max-time ${LOOMD_TIMEOUT_S} ${LOOMD_STATE_URL} 2>/dev/null; echo`;
  const alive = `echo "${ALIVE_DELIM}"; tmux ls -F "#{session_name}" 2>/dev/null`;
  const script = [loomd, alive]
    .concat(WORKSPACE_LANES.map(
      (l) => `echo "${PEEK_DELIM}${l}"; tmux capture-pane -p -t ${l} -S -${PEEK_LINES} 2>/dev/null`))
    .join("; ");
  const inner = `sh -c '${script}'`;
  return ["-n", ns, "exec", "-i", lane0.pod, "-c", lane0.container, "--", ...tmuxSu(lane0, inner)];
}

// The set of lanes tmux actually has, read from the leading @@ALIVE: block. Returns null — NOT an
// empty set — when the block is absent, so a caller can tell "no lanes" apart from "did not ask".
// Guessing "nothing is alive" from a truncated read would wipe the whole board.
export function parseLanesAlive(stdout) {
  const lines = String(stdout || "").split("\n");
  const start = lines.findIndex((l) => l.startsWith(ALIVE_DELIM));
  if (start < 0) return null;
  const alive = new Set();
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith(PEEK_DELIM) || line.startsWith(ALIVE_DELIM)) break;
    const name = line.trim();
    if (WORKSPACE_LANES.includes(name)) alive.add(name);
  }
  return alive;
}

// O exec PERGUNTOU ao loomd? Isso é diferente de o loomd ter respondido. Sem esta distinção,
// um cockpit velho (script sem o bloco) e um loomd morto ficam indistinguíveis, e o board diria
// "fonte exata caiu" quando na verdade ninguém perguntou.
export function hasLoomdBlock(stdout) {
  return String(stdout || "").split("\n").some((l) => l.startsWith(LOOMD_DELIM));
}

// O payload do `@@LOOMD:` — o /v2/state do supervisor, cru. Devolve `null`, NUNCA objeto vazio,
// quando o bloco falta, vem vazio ou não parseia: quem chama precisa distinguir "o loomd está
// calado" de "o loomd disse que não supervisiona lane nenhuma". Tratar as duas como iguais é
// exatamente como uma fonte morta viraria "tudo inferred" em silêncio.
export function parseLoomdState(stdout) {
  const lines = String(stdout || "").split("\n");
  const start = lines.findIndex((l) => l.startsWith(LOOMD_DELIM));
  if (start < 0) return null;
  const buf = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith(PEEK_DELIM) || line.startsWith(ALIVE_DELIM) || line.startsWith(LOOMD_DELIM)) break;
    buf.push(line);
  }
  const raw = buf.join("\n").trim();
  if (!raw) return null;                       // curl falhou (-f) ou o loomd não está de pé
  let j;
  try { j = JSON.parse(raw); } catch { return null; }
  // Um 200 com corpo que não é o contrato é tão inútil quanto silêncio — e mais perigoso, porque
  // parece resposta. `lanes` precisa ser array; qualquer outra coisa é "calado".
  if (!j || typeof j !== "object" || !Array.isArray(j.lanes)) return null;
  return j;
}

// ─── ONE-TOUCH ACTIONS: send-keys, not attach ────────────────────────────────────────────
// `tmux send-keys` delivers a keystroke WITHOUT becoming a client, so answering a prompt from
// the Mac does not resize his panes (tmux sizes a window to its smallest attached client).
// Both builders take the lane from the allowlist and the key from LANE_KEYS — no request text
// is ever interpolated, which is what keeps this on the read-only side of the leash's spirit.

/// Where `sounio-lane-worktrees` puts a lane's private tree. Derived from the lane NAME only.
export const LANE_WT_ROOT = "/workspace/.wt";

export function laneSendKeyArgv(ns, lane, key) {
  const s = SESSION_ALLOWLIST[lane];
  if (!s || !s.user || !WORKSPACE_LANES.includes(lane)) return null;
  if (!Object.prototype.hasOwnProperty.call(LANE_KEYS, key)) return null;
  const inner = `tmux send-keys -t ${s.target} ${LANE_KEYS[key]}`;
  return ["-n", ns, "exec", "-i", s.pod, "-c", s.container, "--", ...tmuxSu(s, inner)];
}

// Move a lane into its own worktree. This types a `cd` at the lane's shell — it is only sound for
// a lane at rest, which the caller enforces; typing into a running agent would go into its prompt.
export function laneIsolateArgv(ns, lane) {
  const s = SESSION_ALLOWLIST[lane];
  if (!s || !s.user || !WORKSPACE_LANES.includes(lane)) return null;
  const inner = `tmux send-keys -t ${s.target} "cd ${LANE_WT_ROOT}/${s.target}" Enter`;
  return ["-n", ns, "exec", "-i", s.pod, "-c", s.container, "--", ...tmuxSu(s, inner)];
}

// Does the lane's worktree exist yet? `laneIsolateArgv` would otherwise type a `cd` into a
// directory that is not there and leave the lane exactly where it was, silently.
export function laneWorktreeCheckArgv(ns, lane) {
  const s = SESSION_ALLOWLIST[lane];
  if (!s || !s.user || !WORKSPACE_LANES.includes(lane)) return null;
  const inner = `sh -c "test -d ${LANE_WT_ROOT}/${s.target} && echo yes || echo no"`;
  return ["-n", ns, "exec", "-i", s.pod, "-c", s.container, "--", ...tmuxSu(s, inner)];
}

// ─── APROVAR A LANE DO LOOMD: RPC, não tecla ─────────────────────────────────────────────
// A lane servida pelo loomd não tem tecla para receber (`fuseFleet` zera o `approveKey` porque
// não existe pane onde apertar): ela responde por `POST /v2/lanes/:lane/approve`. O transporte é
// o MESMO da leitura — `kubectl exec` no pod do workspace, curl para 127.0.0.1 — justamente
// para não abrir superfície nova: o loomd não tem autenticação nenhuma e continua sem porta
// exposta ao cluster. O que autentica esta chamada é o RBAC do cockpit sobre o exec.

/// Marcador do código HTTP que o `-w` do curl escreve DEPOIS do corpo.
/// Sem ele um 409 do loomd ("essa lane não está esperando aprovação") chegaria como corpo com
/// exit 0 do curl e viraria "aprovei" — a mentira exata que esta rodada existe para impedir.
/// Não usamos `curl -f` porque `-f` come o corpo do erro, que é justamente o MOTIVO da recusa.
export const LOOMD_HTTP_DELIM = "@@HTTP:";

/// Charset de nome de lane que pode ser interpolado numa URL dentro de `sh -c`.
/// Segunda tranca, não a primeira: o chamador já só aceita lanes que o loomd DECLAROU na última
/// leitura. Esta aqui garante que, mesmo que o próprio loomd passe a declarar um nome hostil
/// (o nome vem de `LOOMD_CODEX_LANES` no pod, não daqui), nada com metacaractere de shell ou com
/// `/` e `.` — que dariam travessia de caminho no router do axum — chegue a ser montado.
const SAFE_LOOMD_LANE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;

export function loomdApproveArgv(ns, lane, allow) {
  if (!SAFE_LOOMD_LANE.test(String(lane || ""))) return null;
  const spec = SESSION_ALLOWLIST[WORKSPACE_LANES[0]];
  // O corpo é uma das DUAS constantes literais abaixo — nada de texto de request vira JSON aqui.
  const payload = allow === false ? '{"allow":false}' : '{"allow":true}';
  const inner =
    `curl -sS --max-time ${LOOMD_TIMEOUT_S} -X POST -H "Content-Type: application/json"` +
    ` -d '${payload}' -w "\\n${LOOMD_HTTP_DELIM}%{http_code}"` +
    ` ${LOOMD_BASE}/v2/lanes/${lane}/approve`;
  return ["-n", ns, "exec", "-i", spec.pod, "-c", spec.container, "--", ...tmuxSu(spec, inner)];
}

/// { code, body } do stdout do exec acima. `code: null` = o curl não chegou a ter resposta HTTP
/// (loomd fora do ar, exec falhou, timeout) — e isso NÃO pode ser tratado como sucesso.
export function parseLoomdHttp(stdout) {
  const lines = String(stdout || "").split("\n");
  // De trás para frente de propósito: o corpo do loomd é JSON livre e poderia conter o marcador;
  // a linha que o `-w` escreveu é sempre a última.
  let idx = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (lines[i].startsWith(LOOMD_HTTP_DELIM)) { idx = i; break; }
  }
  if (idx < 0) return { code: null, body: String(stdout || "").trim() };
  const code = Number(lines[idx].slice(LOOMD_HTTP_DELIM.length).trim());
  return {
    code: Number.isInteger(code) && code >= 100 ? code : null,
    body: lines.slice(0, idx).join("\n").trim(),
  };
}

/// O `error` que o loomd manda no corpo (`{"ok":false,"error":"..."}`), ou null. O motivo dele é
/// melhor que qualquer texto nosso: ele sabe se a lane não é supervisionada ou se não há pendência.
export function loomdErrorOf(body) {
  try {
    const j = JSON.parse(String(body || ""));
    return j && typeof j.error === "string" && j.error ? j.error : null;
  } catch { return null; }
}

// Split the batched peek stdout into { lane: screenText }. Unknown labels are dropped.
export function parseLanesPeek(stdout) {
  const out = {};
  let cur = null, buf = [];
  for (const line of String(stdout || "").split("\n")) {
    if (line.startsWith(PEEK_DELIM)) {
      if (cur) out[cur] = buf.join("\n");
      const name = line.slice(PEEK_DELIM.length).trim();
      cur = WORKSPACE_LANES.includes(name) ? name : null;
      buf = [];
    } else if (cur) {
      buf.push(line);
    }
  }
  if (cur) out[cur] = buf.join("\n");
  return out;
}

// ─── OFICINA: read-only dev-status queries on the workspace repo ─────────────────────────
// Fixed, named, read-only queries — the ONLY dev commands the cockpit may run. No build, no
// test, no gate: those cost ~61GiB of RAM and minutes, so the Oficina READS receipts and CI
// verdicts instead of producing them. Each entry is a literal command string; nothing is ever
// interpolated from a request.
export const WORKSPACE_QUERIES = {
  // "Is it green?" — open PRs with their full check rollup.
  "pr-list": `gh pr list --state open --limit 20 --json number,title,headRefName,isDraft,updatedAt,url,statusCheckRollup`,
  // "Is main green?" — the latest CI run on the default branch.
  "main-ci": `gh run list --branch main --limit 8 --json databaseId,name,status,conclusion,createdAt,url,headSha`,
  // "Where am I?" — branch, then sha/time/subject, then dirty count: one line each.
  // NOTE: no single quotes anywhere. These strings are interpolated INSIDE `sh -c '...'`, so a
  // nested quote silently truncates the command (it mangled this very query in production).
  "git-head": `git rev-parse --abbrev-ref HEAD; git log -1 --format=%H%x09%ct%x09%s; git status --porcelain | wc -l`,
  // "Quem está onde?" — every lane's actual working directory, to detect the shared-tree hazard
  // (measured: all 10 lanes sit in /workspace/sounio on one branch with ~53 dirty files).
  // DOUBLE quotes are mandatory here: unquoted, tmux's "|" would become a shell pipe and "#"
  // would start a comment. (Double quotes are safe inside the outer `sh -c '…'`; single ones
  // are not — see the git-head incident above.)
  "lane-cwds": `tmux list-panes -a -F "#{session_name}|#{pane_current_path}|#{pane_current_command}"`,
  // "O que a linguagem PROVOU?" — the newest experiment/gate receipts. Sounio writes a versioned
  // JSON receipt per proven claim (schema/status/metrics/novel_claims/generated_at), so the
  // workbench reads EVIDENCE instead of a pass/fail dot. Newest first, bounded.
  "receipts": `for f in $(find artifacts -name "*.v1.json" -newermt "-60 days" -printf "%T@\t%p\n" 2>/dev/null | sort -rn | head -14 | cut -f2); do echo "@@RECEIPT:$f"; head -c 4000 "$f"; echo; done`,
  // The branch of each distinct tree a lane sits in: "<path>\t<branch>" per line.
  "tree-branches": `for d in $(tmux list-panes -a -F "#{pane_current_path}" | sort -u); do printf "%s\t%s\n" "$d" "$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"; done`,
};

export function workspaceQueryArgv(ns, name) {
  const cmd = Object.prototype.hasOwnProperty.call(WORKSPACE_QUERIES, name) ? WORKSPACE_QUERIES[name] : null;
  if (!cmd) return null;
  const lane0 = SESSION_ALLOWLIST[WORKSPACE_LANES[0]];
  const inner = `sh -c 'cd /workspace/sounio && ${cmd}'`;
  return ["-n", ns, "exec", "-i", lane0.pod, "-c", lane0.container, "--", ...tmuxSu(lane0, inner)];
}

// Full kubectl argv given a resolved pod name (caller resolves "@bridge" → real pod).
export function kubectlArgv(ns, pod, spec, interactive) {
  const c = spec.container ? ["-c", spec.container] : [];
  return ["-n", ns, "exec", interactive ? "-it" : "-i", pod, ...c, "--", ...spec.argv];
}

// Parse a kind's "list" stdout into one metadata-only session entry (or null if absent).
export function parseDeckSession(kind, stdout, now) {
  const s = SESSION_ALLOWLIST[kind];
  if (!s) return null;
  if (s.type === "tmux") {
    const line = String(stdout || "").split("\n").find((l) => l.startsWith(s.target + "|"));
    if (!line) return null;
    const [name, attached, activity, window] = line.trim().split("|");
    return {
      kind, name,
      attached: attached === "1",
      idleSeconds: Math.max(0, Math.round((Number(now) || 0) - (Number(activity) || 0))),
      window: window || "",
    };
  }
  if (s.type === "zellij") {
    // Output carries ANSI + e.g. "sounio-dev [Created 4days ...] (current)".
    const plain = String(stdout || "").replace(/\[[0-9;?]*[A-Za-z]/g, "");
    const line = plain.split("\n").find((l) => l.includes(s.session));
    if (!line) return null;
    return { kind, name: s.session, attached: /current/i.test(line), idleSeconds: 0, window: "zellij" };
  }
  return null;
}
