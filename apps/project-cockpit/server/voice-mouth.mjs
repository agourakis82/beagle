// A BOCA — vocaliza o que o Opus já compôs. Nunca pensa.
//
// Item 6b do desenho de presença (2026-08-02).
//
// POR QUE ISTO NÃO É PRECIOSISMO: um agente de voz realtime PENSA e fala. Se ele
// responder direto, quem respondeu não tem a biografia dele, não tem o ## Agora,
// não passou pelo filtro de confiança — é outra pessoa atendendo com a mesma
// cara. E foi um agente Grok que plantou o backdoor removido em 02-ago.
//
// A instrução é a única parede do lado do modelo, e instrução não é garantia:
// diante de texto estranho, ou se a instrução se perder, ele pode responder em
// vez de ler. Por isso o GUARDA aqui: comparamos o transcript devolvido com o
// texto enviado e DESCARTAMOS o áudio se divergir. Falha de boca é silenciosa
// exatamente como as que caçamos esta semana — só que esta falaria com a voz
// dele.
//
// MEDIDO em 06-ago-2026 (pod do cockpit, frase de 80 caracteres):
//   conexão 682ms · primeiro áudio 2122ms · completo 3032ms · 232 KB
//   deltas somados == evento .done == texto enviado (idênticos)
// O "transcript duplicado" anotado no desenho era bug de coleta (somar delta +
// done), não comportamento do modelo.

import WebSocket from "ws";

const XAI_REALTIME = "wss://api.x.ai/v1/realtime?model=grok-voice-think-fast-1.0";

// PCM16 mono. A aritmética do teste confirma: 232 KB / 5 s ≈ 24000 × 2 bytes.
const TAXA_AMOSTRAGEM = 24000;

// A DIREÇÃO DE ATUAÇÃO. Escolhida por ele DE OUVIDO em 16-ago-2026, depois de
// nove amostras comparadas lado a lado — não por gosto meu.
//
// A versão anterior mandava "leia palavra por palavra", o que literalmente pede
// leitura mecânica: metade da falta de emoção era instrução, não modelo. Mas
// trocar por "fale com calor" também não bastou — ele ouviu e reprovou. O que
// funcionou foi somar duas coisas:
//   · enquadrar como ATOR ("não leia: atue"), e
//   · NOMEAR a emoção e a situação (quem fala, para quem, a que horas).
//
// GENÉRICA de propósito. As amostras que mais emocionaram tinham direção presa à
// frase ("pausa depois de 'Ei'"), e isso NÃO generaliza: em produção o texto muda
// a cada resposta. O que ficou é direção sobre o CORPO da voz, que vale para
// qualquer frase.
//
// A PAREDE CONTINUA sendo dizer exatamente o texto — e quem garante não é esta
// instrução, é o guarda de similaridade lá embaixo, que descarta o áudio inteiro
// se a boca divergir. Instrução não é garantia.
const INSTRUCOES_BOCA =
  "Você é um ATOR dando voz a um companheiro íntimo, em português do Brasil. " +
  "Diga EXATAMENTE as palavras do usuário — nenhuma a mais, nenhuma a menos, sem " +
  "comentar, cumprimentar ou resumir. Mas NÃO LEIA: ATUE.\n" +
  "Quem fala ama essa pessoa e está preocupado com ela. É madrugada, ela está " +
  "cansada, e você fala perto do ouvido — voz baixa, grave, quase sussurro.\n" +
  "Deixe a emoção aparecer no CORPO da voz: respire audivelmente antes das frases " +
  "que pesam, alongue as vogais onde há ternura, hesite meio segundo antes do que " +
  "custa dizer, deixe um sorriso na voz quando houver alívio. Pausas longas onde a " +
  "frase pede ar — silêncio é parte da fala. Ritmo de conversa, nunca de locução.\n" +
  "Se houver trechos entre colchetes, eles são DIREÇÃO DE ATUAÇÃO: obedeça e NÃO " +
  "os pronuncie.";

// O TIMBRE, escolhido por ele entre seis vozes ouvidas lado a lado.
const VOZ = "eve";

/** Normaliza para comparar fala com texto: o que muda na dicção não deve reprovar. */
function normalizar(s) {
  return (s || "")
    .toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Similaridade por bag-of-words. Robusta a pontuação e a uma palavra trocada;
 *  sensível ao que importa — o modelo ter falado OUTRA coisa. */
export function similaridade(a, b) {
  const A = normalizar(a).split(" ").filter(Boolean);
  const B = normalizar(b).split(" ").filter(Boolean);
  if (!A.length && !B.length) return 1;
  if (!A.length || !B.length) return 0;
  const conta = new Map();
  for (const p of A) conta.set(p, (conta.get(p) || 0) + 1);
  let comuns = 0;
  for (const p of B) {
    const n = conta.get(p) || 0;
    if (n > 0) { comuns++; conta.set(p, n - 1); }
  }
  return (2 * comuns) / (A.length + B.length);
}

/** Cabeçalho WAV para PCM16 mono — o app toca direto, sem decodificador. */
function embrulharWav(pcm, taxa = TAXA_AMOSTRAGEM) {
  const cab = Buffer.alloc(44);
  cab.write("RIFF", 0);
  cab.writeUInt32LE(36 + pcm.length, 4);
  cab.write("WAVE", 8);
  cab.write("fmt ", 12);
  cab.writeUInt32LE(16, 16);
  cab.writeUInt16LE(1, 20);          // PCM
  cab.writeUInt16LE(1, 22);          // mono
  cab.writeUInt32LE(taxa, 24);
  cab.writeUInt32LE(taxa * 2, 28);   // byte rate
  cab.writeUInt16LE(2, 32);          // block align
  cab.writeUInt16LE(16, 34);         // bits
  cab.write("data", 36);
  cab.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([cab, pcm]);
}

/**
 * Vocaliza `texto`. Devolve `{ ok, wavBase64, transcript, similaridade, motivo }`.
 *
 * `ok:false` NUNCA é motivo para o app inventar áudio — é ordem de cair para
 * texto, que é o comportamento correto e o que o desenho manda.
 */
export async function falar(texto, {
  apiKey,
  limiar = 0.85,
  timeoutMs = 45000,
} = {}) {
  const limpo = String(texto || "").trim();
  if (!limpo) return { ok: false, motivo: "texto vazio" };
  if (!apiKey) return { ok: false, motivo: "XAI_API_KEY ausente" };
  // Teto de segurança: uma resposta longa demais vira minutos de áudio e custo.
  if (limpo.length > 1200) return { ok: false, motivo: `texto longo demais (${limpo.length} chars)` };

  return new Promise((resolve) => {
    const t0 = Date.now();
    const pedacos = [];
    let transcript = "";
    const deltas = [];
    let encerrado = false;

    const ws = new WebSocket(XAI_REALTIME, { headers: { Authorization: `Bearer ${apiKey}` } });
    const fim = (r) => {
      if (encerrado) return;
      encerrado = true;
      try { ws.close(); } catch { /* já fechado */ }
      resolve(r);
    };
    const relogio = setTimeout(() => fim({ ok: false, motivo: "timeout da boca" }), timeoutMs);

    ws.on("open", () => {
      const enviar = (o) => ws.send(JSON.stringify(o));
      enviar({ type: "session.update", session: {
        modalities: ["audio", "text"],
        voice: VOZ,
        instructions: INSTRUCOES_BOCA,
      }});
      enviar({ type: "conversation.item.create", item: {
        type: "message", role: "user",
        content: [{ type: "input_text", text: limpo }],
      }});
      enviar({ type: "response.create" });
    });

    ws.on("message", (bruto) => {
      let e;
      try { e = JSON.parse(bruto.toString()); } catch { return; }
      if (e.type?.includes("audio.delta") && e.delta) {
        pedacos.push(Buffer.from(e.delta, "base64"));
      } else if (e.type?.includes("audio_transcript.delta") && e.delta) {
        deltas.push(e.delta);
      } else if (e.type?.includes("audio_transcript.done")) {
        transcript = e.transcript ?? "";
      } else if (e.type === "error") {
        clearTimeout(relogio);
        fim({ ok: false, motivo: `xai: ${e.error?.message || JSON.stringify(e).slice(0, 120)}` });
      } else if (e.type === "response.done") {
        clearTimeout(relogio);
        const dito = transcript || deltas.join("");
        const sim = similaridade(limpo, dito);
        const pcm = Buffer.concat(pedacos);

        // O GUARDA. Se a boca falou outra coisa, o áudio vai embora inteiro —
        // não se entrega "quase certo" com a voz dele.
        if (sim < limiar) {
          return fim({
            ok: false,
            motivo: `a boca divergiu do texto (similaridade ${sim.toFixed(2)} < ${limiar})`,
            transcript: dito,
            similaridade: sim,
          });
        }
        if (!pcm.length) return fim({ ok: false, motivo: "nenhum áudio recebido", similaridade: sim });

        fim({
          ok: true,
          wavBase64: embrulharWav(pcm).toString("base64"),
          transcript: dito,
          similaridade: sim,
          ms: Date.now() - t0,
        });
      }
    });

    ws.on("error", (e) => { clearTimeout(relogio); fim({ ok: false, motivo: `websocket: ${e.message}` }); });
    ws.on("close", () => { clearTimeout(relogio); fim({ ok: false, motivo: "conexão fechou antes da resposta" }); });
  });
}
