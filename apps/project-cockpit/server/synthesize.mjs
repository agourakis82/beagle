// synthesize.mjs — the proactive-synthesis units. SEPARATE from chat (the hard wall):
// nothing here touches or is imported by the chat path. Pure/injected so it is tested
// without the cluster.

export async function gatherSynthesisMaterial({ topic, windowDays = 7 } = {}, deps) {
  const t = typeof topic === "string" ? topic.trim() : "";
  if (t) {
    const [trustedWords, background] = await Promise.all([
      deps.fetchRecentMemories(t, { k: 16, trustedOnly: true }),
      deps.fetchExocortexContext(t, { limit: 8, personal: true }),
    ]);
    return {
      mode: "topic", topic: t,
      trustedWords: Array.isArray(trustedWords) ? trustedWords : [],
      background: typeof background === "string" ? background : "",
    };
  }
  const recent = await deps.fetchRecentTrusted({ windowDays, limit: 20 });
  return {
    mode: "recent", windowDays,
    trustedWords: Array.isArray(recent) ? recent : [],
    background: "",
  };
}

export function buildSynthesisPrompt(material) {
  const words = Array.isArray(material?.trustedWords) ? material.trustedWords : [];
  const wordsBlock = words
    .map((r) => `- ${String(r?.text || "").replace(/\s+/g, " ").trim()}`)
    .filter((l) => l.length > 2)
    .join("\n");
  const background = typeof material?.background === "string" ? material.background.trim() : "";
  const sufficient = wordsBlock.length > 0 || background.length > 0;

  const system = [
    "Você sintetiza o pensamento REGISTRADO de Demetrios (MD+PhD) para ajudá-lo a se articular.",
    "REGRA INEGOCIÁVEL: use SOMENTE o material registrado abaixo. Onde o fio estiver incompleto,",
    "nomeie sob '## Perguntas abertas' — NUNCA invente para preencher. O 'Fundo' é",
    "exploração/hipótese ('você parece explorar…'), nunca afirmado como fato dele.",
    "Registro: elevado, rigoroso, simbólico; trate-o por 'você'.",
    "Escreva markdown com EXATAMENTE estes 5 blocos, nesta ordem e com estes títulos:",
    "## Elevator",
    "## Espinha",
    "## O que você circula / tensões",
    "## Perguntas abertas",
    "## Próximo movimento concreto",
  ].join("\n");

  const scope = material?.mode === "topic"
    ? `sobre "${material.topic}"`
    : `dos últimos ${material?.windowDays ?? 7} dias`;
  const user = sufficient
    ? `Sintetize meu pensamento ${scope}, a partir do meu registro:\n\n` +
      `### Minhas palavras (confiáveis)\n${wordsBlock || "(nenhuma)"}\n\n` +
      `### Fundo (exploração — não é fato meu)\n${background || "(nenhum)"}`
    : "";
  return { system, user, sufficient };
}
