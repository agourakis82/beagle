// O portão precisa pegar erro cru E deixar passar fala legítima sobre erro.
// Um portão que censura o companion é pior que o bug que ele previne: ele
// silenciaria justamente as respostas em que o companion admite limitação —
// que são as mais honestas que ele dá.

import test from "node:test";
import assert from "node:assert/strict";
import { avaliarFala, avaliarParcial } from "./portao-de-fala.mjs";

// ---------- tem que REPROVAR ----------

test("o 401 exato do incidente de 07-ago", () => {
  const r = avaliarFala("Failed to authenticate. API Error: 401 Invalid bearer token");
  assert.equal(r.ok, false);
});

test("HTML de gateway", () => {
  assert.equal(avaliarFala("<html><head><title>502 Bad Gateway</title></head></html>").ok, false);
});

test("JSON de erro cru", () => {
  assert.equal(avaliarFala('{"error":{"message":"upstream unavailable"}}').ok, false);
});

test("resposta vazia", () => {
  assert.equal(avaliarFala("   ").ok, false);
});

test("palavra mecânica solta", () => {
  assert.equal(avaliarFala("undefined").ok, false);
  assert.equal(avaliarFala("Error").ok, false);
});

test("erro de rede cru", () => {
  assert.equal(avaliarFala("fetch failed").ok, false);
  assert.equal(avaliarFala("ECONNREFUSED 10.96.0.10:53").ok, false);
});

// ---------- tem que DEIXAR PASSAR ----------

test("fala legítima ADMITINDO falha não é erro", () => {
  const t = "Estou sem alcance do cluster agora, então não tenho a memória longa aqui comigo. "
    + "Posso te ajudar com o que guardei no aparelho, mas se for dose eu não vou chutar número.";
  assert.equal(avaliarFala(t).ok, true);
});

test("fala longa que MENCIONA um erro técnico no meio", () => {
  const t = "Aquele problema que você me contou ontem, do serviço que morria com fetch failed — "
    + "eu fiquei pensando nele. Não é a rede: é que a sonda e o alarme moram no mesmo lugar. "
    + "Se um cai, o outro cai junto, e você fica sabendo por acidente.";
  assert.equal(avaliarFala(t).ok, true);
});

test("resposta curta mas humana passa", () => {
  assert.equal(avaliarFala("Estou aqui com você.").ok, true);
});

test("fala sobre o próprio 401, se ele perguntar", () => {
  const t = "Sim, foi isso mesmo que apareceu na sua tela: um 401. O que aconteceu é que eu estava "
    + "mandando um texto de guarda no lugar da credencial, e o servidor recusou. A culpa é minha, "
    + "não sua, e já está consertado.";
  assert.equal(avaliarFala(t).ok, true);
});

// ---------- stream parcial ----------

test("stream: início limpo não é julgado cedo demais", () => {
  assert.equal(avaliarParcial("Estou").ok, true);
  assert.equal(avaliarParcial("Estou aqui com você, e o que você").ok, true);
});

test("stream: o 401 é pego antes de virar bolha", () => {
  assert.equal(avaliarParcial("Failed to authenticate. API Error: 401 Invalid bearer token").ok, false);
});
