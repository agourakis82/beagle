import { execFileSync } from "node:child_process";
import { generateDigest } from "../src/digest.mjs";

const REPOS = (process.env.DIGEST_REPOS || "/corpus/beagle,/corpus/sounio").split(",");
function gitRecent(repo) {
  try {
    return execFileSync("git", ["-C", repo, "log", "--all", "--since=21 days ago",
      "--pretty=%cd %s", "--date=short"], { encoding: "utf8" }).trim().split("\n").filter(Boolean);
  } catch { return []; }
}
const gitLines = REPOS.flatMap(gitRecent);
const profileFacts = (process.env.PROFILE_FACTS || "").split("|").filter(Boolean);
const digest = await generateDigest({ gitLines, profileFacts, memoryHighlights: [] });
console.log("[digest]\n" + digest);
