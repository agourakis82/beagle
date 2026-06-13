#!/usr/bin/env python3
"""Build a domain golden from the harvested darwin-papers: for each cluster tag,
pick one real paper and make a title->paper retrieval test (query = title prefix,
expect = that paper's doc_id). Honest domain-relevance baseline over the real corpus."""
import urllib.request, json, re, sys

Q = "http://localhost:6333"
COLL = "darwin-papers"

# scroll all points, collapse to per-doc_id (first chunk's title+tags)
docs = {}
nxt = None
total = 0
while True:
    body = {"limit": 256, "with_payload": True, "with_vector": False}
    if nxt:
        body["offset"] = nxt
    req = urllib.request.Request(Q + "/collections/" + COLL + "/points/scroll",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=20))["result"]
    for p in r["points"]:
        total += 1
        pl = p.get("payload", {})
        did = pl.get("doc_id")
        if not did:
            continue
        if did not in docs:
            docs[did] = {
                "title": (pl.get("title") or "").strip(),
                "tags": pl.get("tags") or [],
            }
    nxt = r.get("next_page_offset")
    if not nxt:
        break

print("scroll: %d points, %d distinct docs" % (total, len(docs)), file=sys.stderr)

# group doc_ids by tag (cluster)
by_tag = {}
for did, d in docs.items():
    for t in d["tags"]:
        by_tag.setdefault(t, []).append(did)

# one golden per tag: pick a doc with a substantive, distinctive title
def clean(s):
    s = re.sub(r"\s+", " ", s).strip().replace('"', "'")
    return s

picked = []
used = set()
for tag in sorted(by_tag):
    for did in by_tag[tag]:
        title = docs[did]["title"]
        words = title.split()
        if did in used or len(words) < 5:
            continue
        q = clean(" ".join(words[:14]))
        picked.append((tag, q, did))
        used.add(did)
        break

lines = [
    "# Domain golden over the harvested darwin-papers corpus (title -> paper retrieval).",
    "# One query per research cluster; query = a real paper title prefix, expect = its doc_id.",
    "# A domain-relevance regression baseline (gates #12 migration); refine queries by hand anytime.",
    "collections:",
    "  - darwin-papers",
    "",
    "k: 10",
    "",
    "tests:",
]
for tag, q, did in picked:
    lines.append("  - name: %s" % tag)
    lines.append('    query: "%s"' % q)
    lines.append("    expect_doc_ids:")
    lines.append('      - "%s"' % did)

open("scripts/darwin-eval.yaml", "w").write("\n".join(lines) + "\n")
print("golden: %d cluster queries -> scripts/darwin-eval.yaml" % len(picked), file=sys.stderr)
for tag, q, did in picked:
    print("  [%s] %s <- %s" % (tag, did[:28], q[:60]), file=sys.stderr)
