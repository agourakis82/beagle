// O PORTÃO DE FALA — nada que não seja fala dele atravessa.
//
// Em 07-ago-2026 o proxy OAuth passou a autenticar com um placeholder e TODA
// resposta virava "Failed to authenticate. API Error: 401 Invalid bearer token".
// A string chegou na TELA do app, dentro da bolha, com a tipografia da carta —
// como se fosse ele falando. Ele é médico, estava no telefone, de madrugada.
//
// Isso é um ERRO DE CATEGORIA: falha de transporte renderizada como fala. E
// atravessou todas as defesas porque elas checam AUSÊNCIA de resposta, não
// qualidade dela. HTTP 200 não prova nada neste sistema.
//
// A sonda que detectou ("voz sem grounding") rodava de 15 em 15 minutos. Uma
// auditoria periódica deixa até 15 minutos de lixo na tela. Promovida para o
// caminho de CADA resposta, ela deixa de ser auditoria e vira parede.
//
// Regra: o canal de saída aceita exatamente dois tipos — fala validada, ou o
// chão. Nunca um terceiro.

/** Assinaturas de que o que chegou é erro de máquina, não fala.
 *
 *  Deliberadamente literais e específicas. Um classificador esperto reprovaria
 *  fala legítima — e o companion FALA sobre falha ("estou sem alcance do
 *  cluster"), sobre erro clínico, sobre 401 se ele perguntar. Censurar o
 *  companion legítimo é pior que o bug. */
const ASSINATURAS = [
  /\bAPI Error:\s*\d{3}\b/i,
  /\bInvalid bearer token\b/i,
  /\bFailed to authenticate\b/i,
  /^\s*<(!doctype|html)\b/i,
  /^\s*\{"error"\s*:/,
  /\b(502 Bad Gateway|503 Service Unavailable|504 Gateway Time-?out)\b/i,
  /\bECONNREFUSED\b|\bETIMEDOUT\b|\bEAI_AGAIN\b/,
  /\bfetch failed\b/i,
  /\bUpstream error\b/i,
];

/** Frases curtas e mecânicas que só fazem sentido como erro. */
const CURTO_E_MECANICO = /^\s*(error|erro|null|undefined|failed|timeout|forbidden|unauthorized)\s*[.!]?\s*$/i;

/**
 * Classifica uma resposta antes de virar fala.
 *
 * Devolve `{ ok:true }` ou `{ ok:false, motivo }`. `ok:false` NUNCA é para ser
 * mostrado ao usuário — é ordem de cair para o chão.
 */
export function avaliarFala(texto, { minimo = 12 } = {}) {
  const t = typeof texto === "string" ? texto.trim() : "";
  if (!t) return { ok: false, motivo: "resposta vazia" };
  if (CURTO_E_MECANICO.test(t)) return { ok: false, motivo: `resposta mecânica: ${JSON.stringify(t.slice(0, 24))}` };

  for (const re of ASSINATURAS) {
    const m = t.match(re);
    if (m) {
      // A assinatura só condena quando ELA É a resposta — não quando ele FALA
      // sobre um erro, que é conversa legítima entre os dois ("o serviço morria
      // com fetch failed" é uma frase dele, não uma falha).
      //
      // Duas formas de ser a resposta:
      //   1. começar o texto — erro cru vem sozinho, do começo;
      //   2. ocupar fatia grande de um texto curto.
      // A primeira versão condenava qualquer assinatura nos primeiros 120
      // caracteres e reprovou fala legítima no teste. Um portão que censura o
      // companion é pior que o bug: silenciaria justamente as respostas em que
      // ele admite limitação, que são as mais honestas que ele dá.
      const pos = t.search(re);
      const comeca = pos <= 15;
      const domina = t.length < 200 && m[0].length / t.length > 0.15;
      if (comeca || domina) {
        return { ok: false, motivo: `assinatura de erro: ${JSON.stringify(m[0].slice(0, 40))}` };
      }
    }
  }
  if (t.length < minimo) return { ok: false, motivo: `curta demais: ${t.length} caracteres` };
  return { ok: true };
}

/** Um pedaço de stream pode ser reprovado ANTES de o usuário ver.
 *
 *  Só decide quando há material suficiente: julgar os primeiros 3 caracteres
 *  reprovaria toda resposta boa. O 401 do incidente tinha 59 caracteres e vinha
 *  inteiro de uma vez — este limiar o pega antes da bolha. */
export function avaliarParcial(acumulado) {
  const t = (acumulado || "").trim();
  if (t.length < 30) return { ok: true };
  for (const re of ASSINATURAS) {
    const pos = t.search(re);
    if (pos >= 0 && pos <= 15) {
      return { ok: false, motivo: `assinatura de erro abrindo o stream` };
    }
  }
  return { ok: true };
}
