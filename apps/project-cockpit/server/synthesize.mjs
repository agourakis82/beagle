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
