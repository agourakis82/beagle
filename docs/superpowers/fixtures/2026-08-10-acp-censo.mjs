// CENSO CRU DO ACP.
//
// Cliente ND-JSON escrito à mão de propósito: o SDK esconderia justamente o que eu quero medir.
// No codex esse mesmo exercício mostrou que 70 de 107 eventos eram delta que eu descartava.
//
// Grava TODA linha nas duas direções em censo.jsonl e no fim conta por método/variante.

import { spawn } from "node:child_process";
import { appendFileSync, writeFileSync, readFileSync } from "node:fs";

const LOG = new URL("./censo.jsonl", import.meta.url).pathname;
writeFileSync(LOG, "");

const CWD = process.argv[2];
const PEDIDO = process.argv[3];

const ag = spawn("./node_modules/.bin/claude-agent-acp", [], {
  stdio: ["pipe", "pipe", "pipe"],
  env: { ...process.env },
});

let stderr = "";
ag.stderr.on("data", (b) => { stderr += b.toString(); });

const registrar = (dir, msg) =>
  appendFileSync(LOG, JSON.stringify({ t: Date.now(), dir, msg }) + "\n");

let proximoId = 1;
const pendentes = new Map();

function enviar(obj) {
  registrar("→", obj);
  ag.stdin.write(JSON.stringify(obj) + "\n");
}

function pedir(method, params) {
  const id = proximoId++;
  return new Promise((res, rej) => {
    pendentes.set(id, { res, rej });
    enviar({ jsonrpc: "2.0", id, method, params });
  });
}

const responder = (id, result) => enviar({ jsonrpc: "2.0", id, result });

// ---- as respostas do CLIENTE aos pedidos do agente -------------------------
// Auto-aprovar, que é a política que ele escolheu para as lanes. Escolho a opção
// pelo `kind` declarado, nunca por posição na lista.
function atenderPedidoDoAgente(m) {
  const { id, method, params } = m;
  if (method === "session/request_permission") {
    const ops = params?.options ?? [];
    const escolhida =
      ops.find((o) => o.kind === "allow_always") ??
      ops.find((o) => o.kind === "allow_once") ??
      ops[0];
    responder(id, { outcome: { outcome: "selected", optionId: escolhida?.optionId } });
    return;
  }
  if (method === "fs/read_text_file") {
    try {
      const txt = readFileSync(params.path, "utf8");
      responder(id, { content: txt });
    } catch (e) {
      enviar({ jsonrpc: "2.0", id, error: { code: -32000, message: String(e) } });
    }
    return;
  }
  if (method === "fs/write_text_file") {
    try {
      writeFileSync(params.path, params.content);
      responder(id, {});
    } catch (e) {
      enviar({ jsonrpc: "2.0", id, error: { code: -32000, message: String(e) } });
    }
    return;
  }
  // Qualquer outro pedido: responder vazio e REGISTRAR que apareceu — um método que
  // eu não previ é exatamente o achado que o censo existe para produzir.
  responder(id, {});
}

// ---- laço de leitura ------------------------------------------------------
let buf = "";
ag.stdout.on("data", (b) => {
  buf += b.toString();
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const linha = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!linha) continue;
    let m;
    try { m = JSON.parse(linha); } catch { registrar("←?", linha); continue; }
    registrar("←", m);

    if (m.id !== undefined && m.method) { atenderPedidoDoAgente(m); continue; }
    if (m.id !== undefined) {
      const p = pendentes.get(m.id);
      pendentes.delete(m.id);
      if (!p) continue;
      m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result);
    }
  }
});

// ---- o roteiro ------------------------------------------------------------
const morte = setTimeout(() => { console.error("ESTOUROU O TEMPO"); fim(1); }, 300_000);

function fim(cod) {
  clearTimeout(morte);
  if (stderr.trim()) console.error("--- stderr do agente ---\n" + stderr.trim().slice(0, 2000));
  try { ag.kill("SIGTERM"); } catch {}
  process.exit(cod);
}

try {
  const init = await pedir("initialize", {
    protocolVersion: 1,
    clientCapabilities: {
      fs: { readTextFile: true, writeTextFile: true },
      terminal: true,
    },
  });
  console.log("initialize  →", JSON.stringify(init).slice(0, 400));

  const sess = await pedir("session/new", { cwd: CWD, mcpServers: [] });
  console.log("session/new →", JSON.stringify(sess).slice(0, 300));

  // 🚨 O adaptador nasce em `bypassPermissions` — medido na rodada 1. Sem trocar o modo,
  // `session/request_permission` NUNCA dispara e a tela de aprovação fica sem fonte.
  const modo = process.env.ACP_MODO;
  if (modo) {
    await pedir("session/set_mode", { sessionId: sess.sessionId, modeId: modo });
    console.log("modo        →", modo);
  }

  const r = await pedir("session/prompt", {
    sessionId: sess.sessionId,
    prompt: [{ type: "text", text: PEDIDO }],
  });
  console.log("prompt      →", JSON.stringify(r));
  fim(0);
} catch (e) {
  console.error("FALHOU:", e.message);
  fim(1);
}
