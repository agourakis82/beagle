// runner.mjs — Phase B: run the functor F over a trajectory via the souc binary.
// Generates the driver .sio, compiles+runs it with `souc run`, parses the TELEM
// blocks. This is the bit-exact execution path (the telemetry IS the souc number).
//
// Env:
//   SOUC_BIN              path to the souc launcher (default: <sounio>/bin/souc)
//   SOUNIO_STDLIB_PATH    stdlib path (default: <sounio>/stdlib)
//   SOUNIO_REPO           sounio repo root (default: /home/devsounio/sounio)

import { writeFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { genDriverSio } from "./siogen.mjs";
import { parseTelemetry } from "./parse.mjs";

const pExecFile = promisify(execFile);

function resolveEnv() {
  const repo = process.env.SOUNIO_REPO || "/home/devsounio/sounio";
  return {
    soucBin: process.env.SOUC_BIN || join(repo, "bin", "souc"),
    stdlib: process.env.SOUNIO_STDLIB_PATH || join(repo, "stdlib"),
    repo,
  };
}

/**
 * Run F over one trajectory and return the per-turn telemetry.
 * @param {Array<{speaker:number, content:number[], uncertainty:number[]}>} trajectory
 * @param {{ruptureThresh?:number, timeoutMs?:number}} [opts]
 */
export async function runTapestry(trajectory, opts = {}) {
  if (!Array.isArray(trajectory) || trajectory.length === 0) return [];
  const { soucBin, stdlib, repo } = resolveEnv();
  const sio = genDriverSio(trajectory, opts);
  const dir = await mkdtemp(join(tmpdir(), "tapestry-"));
  const file = join(dir, "driver.sio");
  try {
    await writeFile(file, sio);
    const { stdout } = await pExecFile(soucBin, ["run", file], {
      cwd: repo,
      env: { ...process.env, SOUNIO_STDLIB_PATH: stdlib },
      timeout: opts.timeoutMs ?? 120000,
      maxBuffer: 32 * 1024 * 1024,
    });
    return parseTelemetry(stdout);
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

export default runTapestry;
