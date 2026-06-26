// embed.mjs — Phase B: sovereign bge-m3 embeddings (the Spark/TEI tei-shim).
export function makeEmbed(url, { timeoutMs = 60000, batch = 32 } = {}) {
  return async function embed(texts) {
    const out = [];
    for (let i = 0; i < texts.length; i += batch) {
      const part = texts.slice(i, i + batch);
      const resp = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ inputs: part }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!resp.ok) throw new Error(`embed ${resp.status}: ${(await resp.text()).slice(0, 120)}`);
      const j = await resp.json();
      const vs = Array.isArray(j) && Array.isArray(j[0]) ? j : [j];
      out.push(...vs);
    }
    return out;
  };
}

export default makeEmbed;
