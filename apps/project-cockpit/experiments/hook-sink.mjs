// hook-sink.mjs — o passo 2: receber estado de uma sessão de agente que NÓS NÃO LANÇAMOS.
//
// O app-server do codex exige ser dono do processo. Os hooks HTTP do Claude Code não: são
// CONFIGURAÇÃO. O CLI liga de volta para cá a cada transição, sem PTY, sem relançar a lane.
// É o que fecha a outra metade da frota.
//
// Normaliza para o MESMO esquema do consumidor do codex (AgentEvent), para provar que a camada
// que importa é a de normalização — sete grafias de "esperando humano" viram uma.
import { createServer } from "node:http";

const PORT = Number(process.env.SINK_PORT || 4399);
const events = [];

// A tabela de tradução. É literalmente o produto desta fase: cada fornecedor escreve
// "aguardando humano" do seu jeito, e o supervisor precisa de UM vocabulário.
function normalize(h) {
  const ev = h.hook_event_name || h.hookEventName || "?";
  const base = { session: (h.session_id || "").slice(0, 8), cwd: h.cwd };
  switch (ev) {
    case "SessionStart":      return { kind: "session_started", ...base, source: h.source };
    case "SessionEnd":        return { kind: "session_ended", ...base, reason: h.reason };
    case "UserPromptSubmit":  return { kind: "turn_started", ...base };
    case "PreToolUse":        return { kind: "tool_call", ...base, tool: h.tool_name };
    case "PostToolUse":       return { kind: "tool_result", ...base, tool: h.tool_name };
    case "PermissionRequest": return { kind: "awaiting_approval", ...base, tool: h.tool_name };
    case "PermissionDenied":  return { kind: "approval_denied", ...base, tool: h.tool_name };
    case "Stop":              return { kind: "turn_ended", ...base };
    case "SubagentStop":      return { kind: "subagent_ended", ...base };
    case "Notification": {
      // `agent_needs_input` / `permission_prompt` são a mesma verdade que o
      // `waitingOnApproval` do codex. Uma tabela, um vocabulário.
      const t = h.notification_type;
      if (t === "permission_prompt" || t === "agent_needs_input")
        return { kind: "awaiting_approval", ...base, notification_type: t };
      if (t === "idle_prompt")     return { kind: "idle", ...base };
      if (t === "agent_completed") return { kind: "turn_ended", ...base };
      return { kind: "notification", ...base, notification_type: t };
    }
    default:
      // Desconhecido é INFORMAÇÃO, nunca falha: o vocabulário cresce a cada versão.
      return { kind: "unknown", ...base, raw_event: ev };
  }
}

createServer((req, res) => {
  if (req.method !== "POST") { res.writeHead(405).end(); return; }
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    let h = {};
    try { h = JSON.parse(body); } catch { /* corpo ilegível: registrar cru, não fingir */ }
    const auth = req.headers.authorization ? "com-bearer" : "SEM-BEARER";
    const e = { ts: Date.now(), confidence: "exact", auth, ...normalize(h) };
    events.push(e);
    console.log(`◆ ${String(e.kind).padEnd(18)} ${auth.padEnd(11)} ${JSON.stringify(
      Object.fromEntries(Object.entries(e).filter(([k]) => !["ts","kind","confidence","auth"].includes(k)))
    ).slice(0, 130)}`);
    // Resposta vazia = "não interfira". Bloquear/permitir tem forma própria e não é o que
    // este teste mede; aqui o ponto é só provar que o estado CHEGA.
    res.writeHead(200, { "content-type": "application/json" }).end("{}");
  });
}).listen(PORT, "127.0.0.1", () => console.log(`— sink ouvindo em http://127.0.0.1:${PORT}`));

process.on("SIGTERM", () => {
  const by = {};
  for (const e of events) by[e.kind] = (by[e.kind] || 0) + 1;
  console.log("\n════ RESUMO ════\n" + JSON.stringify(by, null, 1));
  console.log(`total ${events.length} · todos 'exact' · sem bearer: ${events.filter(e=>e.auth==="SEM-BEARER").length}`);
  process.exit(0);
});
