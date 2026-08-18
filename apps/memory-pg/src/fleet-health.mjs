// fleet-health.mjs — o alarme que faltava para a frota de modelos.
//
// A extração passou a rodar contra um modelo carregado na CPU e ninguém soube; antes disso,
// ficou apontada para um grupo que o roteador não conseguia servir e o erro virava um retry
// silencioso. Em ambos os casos havia um alarme por perto, e nenhum vigiava a coisa certa.
//
// ⚠️ O QUE ESTE ALARME NÃO FAZ: não vigia "deployment em zero réplicas". O zero é
// DELIBERADO — a config do roteador diz `RTX 8000 scale-to-0; só 1 ativo por vez via
// rtx8000-switch.sh`, porque os modelos científicos dividem a mesma GPU física. Um alarme que
// tocasse em cada zero tocaria o tempo todo, e alarme que toca à toa é silenciado. É assim
// que alarmes morrem.
//
// O que ele vigia é a única pergunta que importa: **os modelos de que o sistema DEPENDE
// respondem agora?** Não a réplica, não o pod, não a GPU — a resposta. Provar o canal ponta a
// ponta é a mesma disciplina do alarme de extração parada, e foi ela que pegou o cabeçalho
// fora de latin-1 que teria deixado aquele alarme mudo.

/** Latin-1 puro: cabeçalho HTTP é ByteString e um travessão derruba o `fetch` ANTES de publicar. */
function asciiSeguro(s) {
  return String(s).replace(/[^\x20-\xFF]/g, "?");
}

/**
 * Pergunta ao roteador se um modelo responde, com o menor pedido possível.
 *
 * Um `/v1/models` não serve: ele lista o que está CONFIGURADO, não o que está vivo — foi
 * exatamente assim que `r1-distill-70b` apareceu na lista enquanto o backend estava fora.
 * Só uma completação de verdade prova o caminho.
 *
 * @returns {Promise<{model:string, ok:boolean, ms:number, erro:string|null}>}
 */
export async function provaModelo(model, { routerUrl, fetchImpl = fetch, timeoutMs = 120000 } = {}) {
  const t0 = Date.now();
  try {
    const r = await fetchImpl(`${routerUrl.replace(/\/+$/, "")}/v1/chat/completions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        model, temperature: 0, max_tokens: 1,
        messages: [{ role: "user", content: "ok" }],
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const ms = Date.now() - t0;
    if (!r.ok) {
      const t = await r.text();
      return { model, ok: false, ms, erro: `HTTP ${r.status}: ${t.slice(0, 160)}` };
    }
    return { model, ok: true, ms, erro: null };
  } catch (e) {
    return { model, ok: false, ms: Date.now() - t0, erro: String(e?.message ?? e).slice(0, 160) };
  }
}

/**
 * Saúde da frota: os modelos DECLARADOS COMO DEPENDÊNCIA respondem?
 *
 * A lista vem de fora (env), não de uma varredura do cluster. É uma declaração explícita de
 * "disto eu dependo" — o que torna a ausência de um modelo uma decisão visível em vez de um
 * desaparecimento silencioso.
 *
 * `lentoMs` existe porque estar vivo não basta: um modelo servido pela CPU responde, e
 * responde tão devagar que todo timeout real estoura. Foi assim que o `coder:32b` gastou
 * 4min28s para dois tokens sem nada acusar.
 */
export async function fleetHealth({ modelos, routerUrl, fetchImpl = fetch, lentoMs = 30000, timeoutMs = 120000 } = {}) {
  // Cada dependência carrega o PRÓPRIO endereço (`modelo@url`), com `routerUrl` de padrão.
  // As duas faixas do desenho vivem em endpoints diferentes — o modelo de volume no Ollama do
  // Spark, o r1 atrás do roteador — e um alarme com um único endereço vigiaria metade da
  // frota achando que vigia a frota inteira.
  const alvos = (modelos || []).map((m) => {
    const s = String(m).trim();
    const i = s.indexOf("@");
    return i < 0 ? { model: s, url: routerUrl } : { model: s.slice(0, i), url: s.slice(i + 1) };
  }).filter((a) => a.model && a.url);
  if (!alvos.length) return { ok: true, motivo: null, resultados: [], declarados: 0 };

  const resultados = [];
  for (const a of alvos) {
    resultados.push(await provaModelo(a.model, { routerUrl: a.url, fetchImpl, timeoutMs }));
  }

  const mortos = resultados.filter((r) => !r.ok);
  const lentos = resultados.filter((r) => r.ok && r.ms >= lentoMs);

  let motivo = null;
  if (mortos.length) {
    motivo = `${mortos.length}/${alvos.length} modelo(s) de que dependemos nao respondem: ` +
      mortos.map((r) => `${r.model} (${r.erro})`).join("; ");
  } else if (lentos.length) {
    // Lento e alarme de verdade, nao curiosidade: um modelo na CPU responde e inutiliza o
    // pipeline igual, so que sem erro nenhum para investigar depois.
    motivo = `${lentos.length}/${alvos.length} modelo(s) vivos mas LENTOS demais: ` +
      lentos.map((r) => `${r.model} ${(r.ms / 1000).toFixed(0)}s para 1 token`).join("; ");
  }
  return { ok: motivo === null, motivo, resultados, declarados: alvos.length };
}

/** Publica no ntfy. Cabeçalhos em latin-1 puro — ver o comentário no topo. */
export async function avisarFrota(motivo, env = process.env, fetchImpl = fetch) {
  const topic = env.NTFY_TOPIC;
  if (!topic) return false;
  const base = env.NTFY_URL || "http://ntfy.beagle.svc.cluster.local";
  const auth = "Basic " + Buffer.from(`${env.NTFY_USER ?? ""}:${env.NTFY_PASSWORD ?? ""}`).toString("base64");
  try {
    const r = await fetchImpl(`${base}/${topic}`, {
      method: "POST",
      headers: {
        authorization: auth,
        Title: asciiSeguro("Beagle: frota de modelos degradada"),
        Priority: "high",
        Tags: "warning",
      },
      body: asciiSeguro(motivo),
      signal: AbortSignal.timeout(15000),
    });
    return r.ok;
  } catch {
    return false;
  }
}

export default { provaModelo, fleetHealth, avisarFrota };
