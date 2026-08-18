// agreement.mjs — a regra de decisão CONGELADA do pré-registro `direcao-v1`.
//
// Ver `docs/PREREG_FASE2_DIRECAO_v1.md`. Este arquivo não decide nada: ele executa o que
// aquele documento fixou, e recusa-se a rodar se o documento tiver mudado.
//
// A ordem importou. Estas direções foram escritas ANTES de a polaridade do auto-relato existir
// no banco — `facts` guardava o canal (sono, ativação…) e não o sinal (mal/bem). Sem o sinal
// nenhuma direção era aplicável, então ninguém, nem por acidente, tinha visto concordância
// alguma no momento em que elas foram fixadas.

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

export const PREREG_VERSION = "direcao-v2";

/** SHA-256 de `docs/PREREG_FASE2_DIRECAO_v1.md` no momento do congelamento. */
export const PREREG_SHA256 = "d695e800a3e19ad210f3a45a198423ecc8fd20bf251816e5ad4b14a379947fd8";

/** Limiares fixados na §4 do pré-registro. Não ajustáveis por parâmetro, de propósito. */
export const ALTO = 0.70;
export const BAIXO = 0.30;
export const MIN_BASELINE_N = 30;

/**
 * Direções da §2. `alto` é a cauda predita quando a polaridade do relato é `alta`
 * (ativado / cansado / dormiu MUITO) — e a oposta quando é `baixa`.
 *
 * `papel`:
 *   primaria     decide sozinha
 *   secundaria   só reforça; NUNCA substitui a primária
 *   exploratoria sem direção pré-registrada; nunca conta
 */
export const DIRECOES = {
  arousal: {
    HKQuantityTypeIdentifierHeartRate: { papel: "primaria", altoQuando: "alta" },
    HKQuantityTypeIdentifierHeartRateVariabilitySDNN: { papel: "secundaria", altoQuando: "baixa" },
    HKQuantityTypeIdentifierRespiratoryRate: { papel: "exploratoria" },
  },
  fatigue: {
    HKQuantityTypeIdentifierRestingHeartRate: { papel: "primaria", altoQuando: "alta" },
    HKQuantityTypeIdentifierHeartRateVariabilitySDNN: { papel: "secundaria", altoQuando: "baixa" },
  },
  sleep: {
    HKCategoryTypeIdentifierSleepAnalysis: { papel: "primaria", altoQuando: "alta" },
    HKQuantityTypeIdentifierRespiratoryRate: { papel: "exploratoria" },
  },
  // valence, pain e oncall estao AUSENTES de proposito: inelegiveis por construcao (§2).
  // Ausencia aqui e a mesma decisao declarada la, nao esquecimento.
};

/**
 * Confere que o documento no disco ainda é o que foi congelado.
 *
 * Um pré-registro que pode ser editado sem que nada quebre não é pré-registro. Se o hash
 * divergir, isto LANÇA: melhor parar de julgar do que julgar sob uma regra que mudou sem
 * ninguém declarar.
 */
export async function verificarPrereg(caminho) {
  const txt = await readFile(caminho);
  const sha = createHash("sha256").update(txt).digest("hex");
  if (sha !== PREREG_SHA256) {
    throw new Error(
      `pré-registro ALTERADO: ${caminho} tem sha256=${sha}, congelado=${PREREG_SHA256}. ` +
      `Mudar a direção exige nova versão (direcao-v3) com o motivo escrito.`,
    );
  }
  return { versao: PREREG_VERSION, sha256: sha };
}

/**
 * Julga UMA medida contra o relato, sob a regra congelada.
 *
 * @param {{channel:string, measure_type:string, n_samples:number, baseline_pct:number|null,
 *          baseline_n:number, independent:boolean}} m  linha de fact_measurements
 * @param {"alta"|"baixa"|null} polaridade  o sinal do relato (dormiu MAL vs BEM)
 * @returns {{veredito:string, motivo:string, papel:string|null, versao:string}}
 */
export function julgar(m, polaridade) {
  const V = (veredito, motivo, papel = null) => ({ veredito, motivo, papel, versao: PREREG_VERSION });

  const canal = DIRECOES[m.channel];
  if (!canal) return V("INELEGIVEL", `canal '${m.channel}' excluido por construcao (§2)`);

  const d = canal[m.measure_type];
  if (!d) return V("INELEGIVEL", `medida '${m.measure_type}' fora do pre-registro`);
  if (d.papel === "exploratoria") return V("EXPLORATORIO", "sem direcao pre-registrada", d.papel);

  // Independência não é opinião: `false` significa outro auto-relato por outra porta.
  if (!m.independent) return V("INELEGIVEL", "medida nao independente", d.papel);
  if (!(m.n_samples >= 1)) return V("INELEGIVEL", "sem cobertura no instante (n_samples=0)", d.papel);
  if (!(m.baseline_n >= MIN_BASELINE_N)) {
    return V("INELEGIVEL", `linha de base insuficiente (${m.baseline_n} < ${MIN_BASELINE_N})`, d.papel);
  }
  if (m.baseline_pct === null || m.baseline_pct === undefined) {
    return V("INELEGIVEL", "sem percentil", d.papel);
  }
  // Sem o sinal do relato nao ha o que confrontar. Este e o estado de TODO o corpus no dia em
  // que o pre-registro foi congelado — e e por isso que ele pode ser confiavel.
  if (polaridade !== "alta" && polaridade !== "baixa") {
    return V("INELEGIVEL", "auto-relato sem polaridade registrada", d.papel);
  }

  const pct = Number(m.baseline_pct);
  const esperaAlto = d.altoQuando === polaridade;
  const naAlta = pct > ALTO;
  const naBaixa = pct < BAIXO;

  if (!naAlta && !naBaixa) {
    // A faixa central NAO e "nao discorda": e ausencia de evidencia. Colapsa-la em apoio
    // transformaria ruido em confirmacao.
    return V("INCONCLUSIVO", `percentil ${pct.toFixed(2)} na faixa central`, d.papel);
  }
  const caiuAlto = naAlta;
  const concorda = caiuAlto === esperaAlto;
  return V(
    concorda ? "CONCORDA" : "DISCORDA",
    `percentil ${pct.toFixed(2)} na cauda ${caiuAlto ? "superior" : "inferior"}; ` +
    `predito ${esperaAlto ? "superior" : "inferior"} para relato '${polaridade}'`,
    d.papel,
  );
}

/**
 * Veredito de um auto-relato a partir de TODAS as suas medidas.
 *
 * A primária decide. As secundárias só reforçam — deixar qualquer medida do canal decidir
 * seria escolher, depois do fato, a que deu certo.
 */
export function julgarRelato(medidas, polaridade) {
  const jul = medidas.map((m) => ({ m, j: julgar(m, polaridade) }));
  const prim = jul.find((x) => x.j.papel === "primaria");
  if (!prim) {
    return { veredito: "INELEGIVEL", motivo: "sem medida primaria", reforco: 0, versao: PREREG_VERSION };
  }
  const reforco = jul.filter(
    (x) => x.j.papel === "secundaria" && x.j.veredito === prim.j.veredito &&
           (prim.j.veredito === "CONCORDA" || prim.j.veredito === "DISCORDA"),
  ).length;
  return { veredito: prim.j.veredito, motivo: prim.j.motivo, reforco, versao: PREREG_VERSION };
}

export default { PREREG_VERSION, PREREG_SHA256, DIRECOES, verificarPrereg, julgar, julgarRelato };
