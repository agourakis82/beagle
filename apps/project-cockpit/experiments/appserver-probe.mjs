// appserver-probe.mjs — o passo 1: supervisão ESTRUTURADA de uma lane, sem TTY e sem regex.
//
// Fala JSON-RPC com `codex app-server` por stdio e normaliza o que chega no esquema único
// (AgentEvent). Nada aqui parseia tela: `waitingOnApproval` é enum tipado do protocolo, e o
// diff vem pronto em `turn/diff/updated`.
//
// Todo evento sai marcado `exact` — veio do protocolo. Quando existir a lane de compatibilidade
// por PTY, aquela sai `inferred`, e nenhuma ação destrutiva dispara nela.
import { spawn } from "node:child_process";

const CODEX = process.env.CODEX_BIN || "codex";
const CWD = process.env.PROBE_CWD || "/tmp/probe-ws";
const PROMPT = process.env.PROBE_PROMPT || "rode `ls -la` neste diretorio e me diga quantos arquivos ha";
const BUDGET_MS = Number(process.env.PROBE_BUDGET_MS || 120000);

const EXTRA = (process.env.PROBE_CODEX_ARGS || "").split(" ").filter(Boolean);
const child = spawn(CODEX, ["app-server", ...EXTRA, "--listen", "stdio://"], {
  stdio: ["pipe", "pipe", "pipe"],
  env: { ...process.env },
});

let nextId = 1;
const pending = new Map();
function send(method, params) {
  const id = nextId++;
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((res, rej) => pending.set(id, { res, rej }));
}
function reply(id, result) {
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

// ─── O esquema único. Copiado da forma da Linear: estado DERIVADO das atividades. ─────────
const events = [];
function emit(kind, payload, confidence = "exact") {
  const e = { ts: Date.now(), kind, confidence, ...payload };
  events.push(e);
  const tag = confidence === "exact" ? "◆" : "◇";
  const s = JSON.stringify(payload);
  console.log(`${tag} ${kind.padEnd(26)} ${kind === "error" ? s : s.slice(0, 150)}`);
}

const NORMALIZE = {
  "thread/started":        (p) => ["session_started", { threadId: p.threadId }],
  "thread/status/changed": (p) => {
    const s = p.status || {};
    const flags = s.activeFlags || [];
    // ISTO é o ponto do exercício: o estado "travado esperando você" é um enum do protocolo,
    // não `strings.Contains(line, "───────")`.
    if (flags.includes("waitingOnApproval")) return ["awaiting_approval", { threadId: p.threadId }];
    if (flags.includes("waitingOnUserInput")) return ["awaiting_input", { threadId: p.threadId }];
    return [s.type === "idle" ? "idle" : "status", { status: s.type, flags }];
  },
  "turn/started":     (p) => ["turn_started", { turnId: p.turnId }],
  "turn/completed":   (p) => ["turn_ended", { turnId: p.turnId }],
  "turn/diff/updated":(p) => ["diff_proposed", { turnId: p.turnId, lines: String(p.diff || "").split("\n").length }],
  "item/started":     (p) => ["item_started", { type: p.item?.type ?? p.item?.item_type }],
  "item/completed":   (p) => ["item_completed", { type: p.item?.type ?? p.item?.item_type }],
  "error":            (p) => ["error", { message: String(p.message || JSON.stringify(p)) }],
};

// Requisições que o AGENTE faz a NÓS — aprovação é RPC, não tecla.
//
// ⚠️ MEDIDO NA MARRA: cada família tem o SEU enum, e o valor errado é aceito em silêncio pelo
// transporte e ignorado pelo agente. `{decision:"approved"}` num fileChange NÃO edita nada —
// o enum ali é `accept`. Só peguei porque conferi o ARQUIVO, não o log. Um "aprovado" que não
// aprova é exatamente a mentira que este sistema existe para não contar.
const APPROVALS = {
  "item/fileChange/requestApproval":       { decision: "accept" },        // accept|acceptForSession|decline|cancel
  "item/commandExecution/requestApproval": { decision: "accept" },        // idem
  "execCommandApproval":                   { decision: "approved" },      // ReviewDecision, enum DIFERENTE
  "applyPatchApproval":                    { decision: "approved" },      // ReviewDecision
};

let approvalsSeen = 0;
let buf = "";
child.stdout.on("data", (chunk) => {
  buf += chunk.toString();
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let m;
    try { m = JSON.parse(line); } catch { console.log("RAW:", line.slice(0, 120)); continue; }

    if (m.id !== undefined && (m.result !== undefined || m.error !== undefined) && pending.has(m.id)) {
      const { res, rej } = pending.get(m.id); pending.delete(m.id);
      m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result);
      continue;
    }
    if (m.method && m.id !== undefined) {          // ServerRequest — o agente perguntando
      const verdict = APPROVALS[m.method];
      if (verdict) {
        approvalsSeen++;
        const p = m.params || {};
        emit("awaiting_approval", {
          via: m.method,
          command: p.command ?? p.parsedCmd ?? p.itemId ?? null,
          reason: p.reason ?? null,
        });
        // Respondemos com um VEREDITO. É o que substitui `tmux send-keys y`.
        reply(m.id, verdict);
        emit("approval_answered", { via: m.method, ...verdict });
      } else {
        reply(m.id, {});
      }
      continue;
    }
    if (m.method) {                                 // ServerNotification
      const n = NORMALIZE[m.method];
      if (n) { const [kind, payload] = n(m.params || {}); emit(kind, payload); }
    }
  }
});
child.stderr.on("data", (d) => process.stderr.write("[codex] " + d));

const done = new Promise((r) => setTimeout(r, BUDGET_MS));

(async () => {
  await send("initialize", {
    clientInfo: { name: "loom-probe", title: "Loom probe", version: "0.0.1" },
  });
  console.log("— initialize ok");

  const list = await send("thread/list", {}).catch((e) => ({ error: String(e).slice(0, 120) }));
  const threads = list?.threads ?? list?.items ?? [];
  console.log(`— thread/list: ${Array.isArray(threads) ? threads.length : "?"} thread(s) conhecidas`);

  const t = await send("thread/start", { cwd: CWD });
  const threadId = t?.threadId ?? t?.thread?.id;
  console.log(`— thread/start: ${threadId}`);

  await send("turn/start", {
    threadId,
    input: [{ type: "text", text: PROMPT }],
  }).catch((e) => console.log("turn/start erro:", String(e).slice(0, 200)));

  await done;
  console.log("\n════ RESUMO ════");
  const byKind = {};
  for (const e of events) byKind[e.kind] = (byKind[e.kind] || 0) + 1;
  console.log(JSON.stringify(byKind, null, 1));
  console.log(`aprovações recebidas como RPC tipado: ${approvalsSeen}`);
  console.log(`eventos 'exact': ${events.filter((e) => e.confidence === "exact").length} / ${events.length}`);
  child.kill();
  process.exit(0);
})();
