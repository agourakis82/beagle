// parse.mjs — Phase B: parse the TELEM blocks emit_turn prints.
// Each block is 8 lines: "TELEM", idx, speaker, coherence, lr, fano, zd, rupture.

/**
 * @param {string} stdout
 * @returns {Array<{idx:number, speaker:number, coherence:number, lr:number, fano:number, zd:number, rupture:boolean}>}
 */
export function parseTelemetry(stdout) {
  const lines = String(stdout).split("\n").map((l) => l.trim());
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i] !== "TELEM") continue;
    const b = lines.slice(i + 1, i + 8);
    if (b.length < 7) break;
    out.push({
      idx: parseInt(b[0], 10),
      speaker: parseInt(b[1], 10),
      coherence: parseFloat(b[2]),
      lr: parseFloat(b[3]),
      fano: parseInt(b[4], 10),
      zd: parseFloat(b[5]),
      rupture: b[6] === "1",
    });
    i += 7;
  }
  return out;
}

export default parseTelemetry;
