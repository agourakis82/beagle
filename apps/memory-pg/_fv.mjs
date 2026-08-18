import fs from "node:fs";
import { makePool } from "./src/db.mjs";
import { physioFunnel } from "./src/physio-join.mjs";
const pool = makePool(fs.readFileSync("/tmp/prod_dsn", "utf8").trim());
try { console.log(Object.values(await physioFunnel(pool)).join("|")); }
catch (e) { console.log("ERRO:" + String(e.message).slice(0, 80)); }
await pool.end();
