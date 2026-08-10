// appserver-raw.mjs — o CENSO do protocolo, sem normalizar nada.
//
// Por que existe: `appserver-probe.mjs` traduz o que já conhece e DESCARTA o resto (`NORMALIZE`
// sem entrada → nada). Isso serve para provar o arco, e é péssimo para responder à pergunta que
// decide o desenho da tela: **o `codex app-server` emite delta de texto?** Se emitir, a Sessão
// mostra a resposta chegando; se não, mostra por turno e não finge streaming.
//
// Aqui nada é filtrado: todo método que chega é contado, com o PRIMEIRO exemplo guardado inteiro
// e o caminho dos campos registrado. O veredito sai no fim, em uma tabela.
//
//   CODEX_HOME=/workspace/.probe/codex-home PROBE_CWD=/workspace/.probe/ws \
//     node appserver-raw.mjs
//
// Aprovação: responde SIM automaticamente, porque sem aprovar não se chega ao diff — e é um
// diretório de laboratório, criado para isto.
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";

const CODEX = process.env.CODEX_BIN || "codex";
const CWD = process.env.PROBE_CWD || "/tmp/probe-ws";
const OUT = process.env.PROBE_OUT || "/tmp/appserver-censo.json";
const PROMPT =
  process.env.PROBE_PROMPT ||
  "Escreva um arquivo alvo.txt com exatamente a linha `oi` e depois me explique em duas frases o que você fez.";
const BUDGET_MS = Number(process.env.PROBE_BUDGET_MS || 180000);

const child = spawn(CODEX, ["app-server", "--listen", "stdio://"], {
  stdio: ["pipe", "pipe", "pipe"],
  env: { ...process.env },
});

let nextId = 1;
const pending = new Map();
const send = (method, params) => {
  const id = nextId++;
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((res, rej) => pending.set(id, { res, rej }));
};
const reply = (id, result) =>
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");

// ─── O censo ────────────────────────────────────────────────────────────────────────────────
/** método → { n, primeiro exemplo inteiro, união dos caminhos de campo vistos } */
const censo = new Map();
/** Caminhos achatados: `turn.diff` em vez de um objeto aninhado, para a tabela caber na tela. */
function caminhos(v, prefixo = "", saida = new Set(), prof = 0) {
  if (prof > 4 || v === null || typeof v !== "object") return saida;
  for (const [k, val] of Object.entries(v)) {
    const p = prefixo ? `${prefixo}.${k}` : k;
    saida.add(p);
    if (val && typeof val === "object" && !Array.isArray(val)) caminhos(val, p, saida, prof + 1);
  }
  return saida;
}
function registrar(method, params, tipo) {
  let e = censo.get(method);
  if (!e) {
    e = { method, tipo, n: 0, exemplo: params, campos: new Set() };
    censo.set(method, e);
  }
  e.n += 1;
  for (const c of caminhos(params)) e.campos.add(c);
}

// Um delta é qualquer coisa que entregue PEDAÇO de texto. Não confio no nome do método: procuro
// a forma. `text_delta`, `partial_json`, `.delta`, `chunk` — e o nome, também.
const PISTAS_DELTA = /delta|partial|chunk|stream/i;
function cheiraDelta(method, params) {
  if (PISTAS_DELTA.test(method)) return true;
  const flat = JSON.stringify(params ?? {});
  return /"(delta|partial_json|chunk)"\s*:/.test(flat);
}
const suspeitosDeDelta = new Set();

let buf = "";
child.stdout.on("data", (d) => {
  buf += d.toString();
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let m;
    try {
      m = JSON.parse(line);
    } catch {
      continue;
    }

    if (m.id !== undefined && m.method === undefined) {
      const p = pending.get(m.id);
      if (p) {
        pending.delete(m.id);
        m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result);
      }
      continue;
    }

    if (m.method && m.id !== undefined) {
      // ServerRequest — o agente perguntando. Registra e aprova.
      registrar(m.method, m.params, "request");
      const campos = JSON.stringify(m.params ?? {}).slice(0, 200);
      console.log(`? ${m.method}  ${campos}`);
      // Cada família tem seu enum — é a armadilha nº1 do README do loomd.
      const val = m.method.startsWith("item/") ? "accept" : "approved";
      reply(m.id, { decision: val });
      continue;
    }

    if (m.method) {
      registrar(m.method, m.params, "notification");
      if (cheiraDelta(m.method, m.params)) suspeitosDeDelta.add(m.method);
    }
  }
});
child.stderr.on("data", (d) => process.stderr.write(`[codex] ${d}`));

function veredito() {
  const linhas = [...censo.values()].sort((a, b) => b.n - a.n);
  console.log("\n╭─ CENSO DO PROTOCOLO ─────────────────────────────────────────────────────────");
  console.log(`│ ${String("n").padStart(4)}  ${"tipo".padEnd(12)} método`);
  for (const e of linhas) {
    console.log(`│ ${String(e.n).padStart(4)}  ${e.tipo.padEnd(12)} ${e.method}`);
  }
  console.log("╰──────────────────────────────────────────────────────────────────────────────");

  console.log("\n▸ DELTA DE TEXTO?");
  if (suspeitosDeDelta.size === 0) {
    console.log("  NÃO — nenhum método com forma de delta em toda a sessão.");
    console.log("  Consequência: a Sessão mostra a resposta POR TURNO. Não simular streaming.");
  } else {
    console.log(`  SIM — ${[...suspeitosDeDelta].join(", ")}`);
    for (const nome of suspeitosDeDelta) {
      console.log(`\n  exemplo de ${nome}:`);
      console.log("  " + JSON.stringify(censo.get(nome).exemplo, null, 2).split("\n").join("\n  "));
    }
  }

  const temTexto = [...censo.values()].filter((e) =>
    [...e.campos].some((c) => /(^|\.)(text|message|content)(\.|$)/.test(c)));
  console.log("\n▸ ONDE MORA O TEXTO DO AGENTE");
  for (const e of temTexto) {
    const cs = [...e.campos].filter((c) => /(^|\.)(text|message|content)(\.|$)/.test(c));
    console.log(`  ${e.method}: ${cs.join(", ")}`);
  }

  const diff = [...censo.values()].filter((e) => [...e.campos].some((c) => /diff|patch/i.test(c)));
  console.log("\n▸ DIFF");
  console.log(diff.length ? diff.map((e) => `  ${e.method}: ${[...e.campos].filter((c) => /diff|patch/i.test(c)).join(", ")}`).join("\n") : "  (nenhum)");

  writeFileSync(OUT, JSON.stringify(
    [...censo.values()].map((e) => ({ ...e, campos: [...e.campos] })), null, 2));
  console.log(`\ncenso completo em ${OUT}`);
}

(async () => {
  const morte = setTimeout(() => {
    console.log("\n[orçamento estourado]");
    veredito();
    child.kill("SIGKILL");
    process.exit(0);
  }, BUDGET_MS);

  try {
    await send("initialize", {
      clientInfo: { name: "appserver-raw", title: "censo", version: "0.1.0" },
    });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "initialized" }) + "\n");
    const th = await send("thread/start", { cwd: CWD });
    const threadId = th?.thread?.id ?? th?.threadId ?? th?.id;
    console.log(`thread=${threadId} cwd=${CWD}`);
    await send("turn/start", {
      threadId,
      input: [{ type: "text", text: PROMPT }],
    });
  } catch (e) {
    console.error("falhou:", e.message);
  }

  // Deixa o turno correr; o veredito sai no fim do orçamento ou quando o turno completar.
  const fim = setInterval(() => {
    if (censo.has("turn/completed")) {
      clearInterval(fim);
      clearTimeout(morte);
      setTimeout(() => {
        veredito();
        child.kill("SIGKILL");
        process.exit(0);
      }, 1500);
    }
  }, 500);
})();
