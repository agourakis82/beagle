// pipeline.mjs — Phase B orchestration: one session → telemetry, written back.
// pull → embed (bge-m3) → project(1024→8) + affect proxy → F (souc) → cognitive_telemetry.

import { project } from "./project.mjs";
import { affectUncertainty } from "./affect.mjs";
import { runTapestry } from "./runner.mjs";
import { writeTelemetry } from "./writeback.mjs";

/**
 * Process one session end-to-end and write its telemetry.
 * @param {import("pg").Pool} pool
 * @param {{session_id:string, occurred_at?:(string|null), turns:Array<{speaker:number,content:string}>}} session
 * @param {{embed:(texts:string[])=>Promise<number[][]>, ruptureThresh?:number}} deps
 * @returns {Promise<{session_id:string, turns:number, written:number}>}
 */
export async function processSession(pool, session, deps) {
  const { embed, ruptureThresh = 0.15 } = deps;
  const texts = session.turns.map((t) => t.content);
  const embeddings = await embed(texts);
  const trajectory = session.turns.map((t, i) => ({
    speaker: t.speaker,
    content: project(embeddings[i]),
    uncertainty: affectUncertainty(t.content),
  }));
  const telemetry = await runTapestry(trajectory, { ruptureThresh });
  const written = await writeTelemetry(pool, session, telemetry);
  return { session_id: session.session_id, turns: session.turns.length, written };
}

export default processSession;
