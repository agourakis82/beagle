import { ingestConversations } from "../src/ingest-conversations.mjs";

const root = process.argv[2] || process.env.CONVO_ROOT || "/corpus";
const dryRun = process.argv.includes("--dry-run");
const includeSystem = process.env.INCLUDE_SYSTEM === "1" || process.argv.includes("--include-system");
// Default: trim tool plumbing (keep real prose). --verbatim / FULL_VERBATIM=1 keeps tool I/O.
const trimTools = !(process.env.FULL_VERBATIM === "1" || process.argv.includes("--verbatim"));
const limit = process.env.LIMIT ? Number(process.env.LIMIT) : Infinity;
const concurrency = process.env.CONCURRENCY ? Number(process.env.CONCURRENCY) : 1;
const minSignalChars = process.env.MIN_SIGNAL_CHARS ? Number(process.env.MIN_SIGNAL_CHARS) : 0;
const skipSessions = process.env.SKIP_SESSIONS ? Number(process.env.SKIP_SESSIONS) : 0;
const onProgress = (s) =>
  console.log(`[progress] sessions=${s.sessions} imports=${s.imports} ingested=${s.ingested} secretBlocked=${s.turnsSkippedSecret} errors=${s.errors}`);
const stats = await ingestConversations(root, { dryRun, includeSystem, limit, trimTools, concurrency, onProgress, minSignalChars, skipSessions });
console.log("[conversations]", JSON.stringify(stats));
