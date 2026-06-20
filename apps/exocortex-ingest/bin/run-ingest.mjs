import { ingestRoot } from "../src/ingest.mjs";

const root = process.argv[2] || process.env.INGEST_ROOT || "/corpus";
const dryRun = process.argv.includes("--dry-run");
const stats = await ingestRoot(root, { dryRun });
console.log("[ingest]", JSON.stringify(stats));
