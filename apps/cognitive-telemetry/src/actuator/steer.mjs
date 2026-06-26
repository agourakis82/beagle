// actuator/steer.mjs — map {register, license} to a steering DIRECTIVE.
//
// v1 (now): a prompt-level directive — a persona fragment + generation params the
// synthesis layer (TieredRouter / companion) applies. v2 (the contract this
// anticipates): the same register+license selects a blend of EMOTION VECTORS applied
// as activation steering on the sovereign model (representation engineering — the
// "magic"), which needs a serving path with activation hooks. The emotionVectors
// field below IS that v2 contract, already computed, so v2 is a serving change, not a
// redesign.

const PERSONAS = {
  researcher: "Responda com rigor: cite, quantifique, declare incerteza, sem floreio.",
  operator: "Responda como operador: direto, acionável, comandos concretos, sem rodeio.",
  friend: "Responda como amigo que conhece o Demetrios: caloroso, com opinião, presente; não institucional.",
};

/**
 * @param {{register:string, license:number}} decision
 * @returns {{register:string, license:number, persona:string, temperature:number,
 *            emotionVectors:Array<{name:string,weight:number}>}}
 */
export function steerDirective(decision) {
  const reg = decision.register || "friend";
  const lic = Math.max(0, Math.min(1, decision.license ?? 0.3));
  // generation temperature: friend warmer/looser, researcher tighter; scaled by license.
  const baseTemp = reg === "researcher" ? 0.2 : reg === "operator" ? 0.3 : 0.6;
  const temperature = Math.round((baseTemp + 0.3 * lic) * 100) / 100;

  // v2 emotion-vector blend (the activation-steering contract): warmth + directness
  // scale with license; rigor anchors the researcher; the higher the license, the more
  // the model is steered toward intimacy/opinion rather than the institutional default.
  const w = (x) => Math.round(x * 1000) / 1000;
  const emotionVectors = [
    { name: "warmth", weight: w(reg === "friend" ? 0.4 + 0.6 * lic : 0.2 * lic) },
    { name: "directness", weight: w(reg === "operator" ? 0.6 : 0.2 + 0.4 * lic) },
    { name: "rigor", weight: w(reg === "researcher" ? 0.8 : 0.2) },
    { name: "intimacy", weight: w(reg === "friend" ? lic : 0.3 * lic) },
  ];
  return { register: reg, license: lic, persona: PERSONAS[reg], temperature, emotionVectors };
}

export default steerDirective;
