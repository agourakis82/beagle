// Vigia até a fila drenar. SÓ LEITURA.
//
// "Drenar" não pode ser `pending == 0`: material novo entra o tempo todo (~100 registros/h),
// então o zero talvez nunca aconteça. O que interessa é o BACKLOG ter ido embora — daí o
// piso de 200, bem abaixo dos 9.177 de agora.
//
// E o vigia avisa também se EMPACAR. Um vigia que só fala quando dá certo transforma pane em
// silêncio, que é exatamente como a extração passou 29 dias morta sem ninguém ver.
const pg = require("pg"), fs = require("fs");
const PISO = 200;
const INTERVALO_MIN = 10;
const PARADO_MAX = 4; // 40 min sem progresso => empacou

const ler = async (p) => (await p.query(
  `SELECT (SELECT count(*)::int FROM pending_graph WHERE status='pending') fila,
          (SELECT count(*)::int FROM pending_graph WHERE status='done') pronto,
          (SELECT count(*)::int FROM facts) facts,
          (SELECT count(*)::int FROM facts WHERE self_report = true) auto,
          (SELECT count(*)::int FROM failed_graph) dlq`)).rows[0];

(async () => {
  const p = new pg.Pool({ connectionString: fs.readFileSync("/tmp/prod_dsn", "utf8").trim() });
  let a = await ler(p);
  console.log(`base: fila=${a.fila} facts=${a.facts} dlq=${a.dlq} auto=${a.auto}`);
  let parado = 0;

  for (let i = 1; i <= 200; i++) {
    await new Promise((s) => setTimeout(s, INTERVALO_MIN * 60000));
    const b = await ler(p);
    const proc = b.pronto - a.pronto;
    const taxa = Math.round((proc / INTERVALO_MIN) * 60);
    console.log(`[${i * INTERVALO_MIN}min] fila=${b.fila} (${taxa}/h) facts=${b.facts} dlq=${b.dlq} auto=${b.auto}`);

    if (b.fila <= PISO) {
      console.log(`\n>>> FILA DRENOU: ${b.fila} pendentes (piso ${PISO})`);
      console.log(`    facts: ${a.facts} -> ${b.facts}   auto-relatos: ${b.auto}   DLQ: ${b.dlq}`);
      break;
    }
    parado = proc <= 0 ? parado + 1 : 0;
    if (parado >= PARADO_MAX) {
      console.log(`\n>>> EMPACOU: ${parado * INTERVALO_MIN} min sem processar nada, fila em ${b.fila}`);
      console.log(`    (checar o modelo do worker e o Ollama do Spark — ver a nota de memoria)`);
      break;
    }
    a = b;
  }
  await p.end();
})();
