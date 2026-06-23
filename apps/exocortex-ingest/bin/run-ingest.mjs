import { ingestRoot } from "../src/ingest.mjs";

const root = process.argv[2] || process.env.INGEST_ROOT || "/corpus";
const dryRun = process.argv.includes("--dry-run");
const minSignalWeight = process.env.MIN_SIGNAL_WEIGHT ? Number(process.env.MIN_SIGNAL_WEIGHT) : 0;
const stats = await ingestRoot(root, { dryRun, minSignalWeight });
console.log("[ingest]", JSON.stringify(stats));
