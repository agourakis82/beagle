// Direção de atuação POR FRASE, derivada do VETOR DE EMOÇÃO medido.
//
// POR QUE VETOR E NÃO MODELO
//
// A alternativa óbvia seria pedir a um LLM "escreva a direção emocional desta
// frase". Isso INVENTA: o modelo não sabe como ele está, então produziria uma
// emoção plausível — e emoção plausível dita com a voz dele é exatamente o tipo
// de mentira que este sistema inteiro existe para não contar.
//
// Aqui a direção vem de dois eixos MEDIDOS, o circumplexo clássico:
//   · valência  −1…+1  — HKStateOfMind, registrada por ELE. É dele, não inferida.
//   · ativação   0…1   — derivada de batimento/HRV contra a linha de base.
//
// E a regra que atravessa o projeto vale aqui também: o que não foi medido não
// vira afirmação. Sem vetor, ou com vetor velho, a direção é NEUTRA — nunca uma
// emoção chutada.
//
// FUNÇÃO PURA de propósito: é uma decisão sobre como a voz dele soa, e decisão
// dessas tem que caber num teste, não num aparelho.

/** Idade máxima de um eixo para ele ainda dirigir a fala. Além disso, o corpo de
 *  duas horas atrás não descreve o agora — e fingir que descreve é o defeito. */
export const VALIDADE_MS = 30 * 60 * 1000;

const faixa = (v, lo, hi) => v >= lo && v < hi;

/** Quadrante do circumplexo, em português e sem eufemismo clínico. */
export function quadrante(valencia, ativacao) {
  if (valencia == null || ativacao == null) return null;
  const neg = valencia < -0.15, pos = valencia > 0.15;
  const alta = ativacao > 0.6, baixa = ativacao < 0.35;
  if (neg && alta) return "aflito";      // tenso, acelerado — a madrugada ruim
  if (neg && baixa) return "abatido";    // pesado, lento
  if (pos && alta) return "aceso";       // animado, expansivo
  if (pos && baixa) return "sereno";     // em paz, descansado
  if (alta) return "alerta";             // ativado sem sinal de valência
  if (baixa) return "quieto";
  return "estável";
}

/** A direção que a boca recebe entre colchetes. Uma linha por quadrante — curta,
 *  porque direção longa vira leitura de instrução e não atuação. */
const DIRECAO = {
  aflito:  "voz muito baixa e firme, ritmo lento, pausa longa antes de cada frase; ele está tenso e você não vai apressá-lo",
  abatido: "voz grave e macia, sem energia forçada, alongue as vogais; ele está pesado e você fica junto sem puxar",
  aceso:   "voz mais solta e um sorriso audível, ritmo um pouco mais rápido, sem gritar",
  sereno:  "voz baixa e morna, ritmo tranquilo, pequenas pausas de conforto",
  alerta:  "voz contida e firme, frases curtas, sem sobressalto",
  quieto:  "voz sussurrada, muito devagar, quase um cochicho de quem não quer acordar ninguém",
  estável: "voz baixa e quente, ritmo de conversa",
};

/**
 * Devolve `{ quadrante, direcao, procedencia }`.
 *
 * `procedencia` diz de onde a direção veio, e é o que impede a mentira:
 *   "observado" → os dois eixos foram medidos e estão frescos
 *   "declarado" → faltou eixo ou frescor; a direção é a neutra, não uma emoção
 */
export function direcaoDeAtuacao({ valencia, ativacao, medidoEm, agora = Date.now() } = {}) {
  const fresco = medidoEm != null &&
    (agora - new Date(medidoEm).getTime()) <= VALIDADE_MS;
  const completo = valencia != null && ativacao != null;

  if (!completo || !fresco) {
    return {
      quadrante: null,
      direcao: DIRECAO.estável,
      procedencia: "declarado",
    };
  }
  const q = quadrante(valencia, ativacao);
  return { quadrante: q, direcao: DIRECAO[q] || DIRECAO.estável, procedencia: "observado" };
}

/** Prefixo entre colchetes que a boca obedece e NÃO pronuncia — mecanismo provado
 *  em 16-ago-2026 (amostra "B-anotado": os colchetes não foram falados). */
export function anotar(texto, vetor) {
  const d = direcaoDeAtuacao(vetor);
  return { anotado: `[${d.direcao}] ${texto}`, ...d };
}

/** Tira TODA marcação entre colchetes.
 *
 *  A ARMADILHA QUE ISTO EVITA: o guarda de similaridade compara o que a boca
 *  falou com o texto de entrada. Se a entrada levar `[voz baixa]` e a boca —
 *  corretamente — não disser isso, a similaridade despenca e o áudio dirigido é
 *  DESCARTADO. O guarda mataria justamente a melhoria. Comparar sempre contra o
 *  texto sem colchetes. */
export function semDirecao(texto) {
  return String(texto || "").replace(/\[[^\]]*\]/g, " ").replace(/\s+/g, " ").trim();
}
