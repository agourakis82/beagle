import { routerChat, assistedImport } from "./contracts.mjs";

const DISTILL_SYS =
  "Você destila uma BIOGRAFIA VIVA curta de Demetrios para um companheiro de IA — quem ele é + o que " +
  "andou fazendo. Saída: 6-10 linhas densas em pt-BR, factual e específica (nomes de projetos, marcos), " +
  "sem encher linguiça. NÃO invente. Inclua trabalho recente concreto.";

export function buildDistillPrompt({ gitLines = [], profileFacts = [], memoryHighlights = [] }) {
  const body = [
    "## Fatos de perfil", ...profileFacts.map((f) => `- ${f}`),
    "## Atividade recente (git)", ...gitLines.slice(0, 40).map((l) => `- ${l}`),
    "## Destaques de memória", ...memoryHighlights.slice(0, 20).map((h) => `- ${h}`),
  ].join("\n");
  return body.slice(0, 7500);
}

export async function generateDigest({ gitLines, profileFacts, memoryHighlights }) {
  const prompt = buildDistillPrompt({ gitLines, profileFacts, memoryHighlights });
  const digest = await routerChat("qwen2.5-14b", DISTILL_SYS, prompt, { temperature: 0.3, max_tokens: 500 });
  // Store as a pinned, retrievable biography doc (text only — beagle-core embeds server-side).
  await assistedImport({
    title: `Biografia viva — ${new Date().toISOString().slice(0, 10)}`,
    sessionId: "biography-digest",
    importScope: "biography_digest",
    confidenceScore: 0.9,
    turns: [{ role: "user", content: digest, timestamp: new Date().toISOString(), metadata: { kind: "biography-digest" } }],
    tags: ["biography-digest", "pinned"],
    metadata: { kind: "biography-digest" },
  });
  return digest;
}
