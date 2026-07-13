# Beagle CPC26 Trump Card — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Beagle reliably usable as an intellectual trump card at CPC26 tomorrow — sharp recall, cited deep-think, demoable, with on-demand capture→synthesis, Sounio woven through.

**Architecture:** Do NOT rebuild #1/#2 (proven conference-grade live). Deliver value through no-rebuild paths: a preflight health script, content ingest of the one grounding gap (Tapestry internals), recall-verification probes, a demo runbook, and an on-demand synthesis prompt-flow that rides the existing recall pipeline. The one rebuild-requiring item (deep-think code fallback) is isolated as stretch with a no-rebuild mitigation as primary.

**Tech Stack:** bash, kubectl (t560 control-plane), memory-pg (Postgres, user `memory` db `memory`), cockpit mobile chat API (`https://beagle.chiuratto.ai` external, `http://10.96.71.119` ClusterIP internal), auth `Bearer $(secret cockpit-mobile-auth PROJECT_COCKPIT_AUTH_TOKEN)`, claude proxy `t560:9500`, LiteLLM router `router.llm-router.svc:4000`.

## Global Constraints

- **No cockpit container rebuild in Tasks 1–7.** Rebuild only in Task 8 (stretch), and only if time + a green post-rebuild preflight allow. A rebuild the night before is a reliability risk.
- **Companion chat request shape:** `POST /api/mobile/v1/chat` + `Authorization: Bearer <PROJECT_COCKPIT_AUTH_TOKEN>` + body `{"prompt":"...","space":"personal"[,"deepThink":true]}`. Version numbers do NOT distinguish anything; behavior does.
- **Anti-confabulation is sacred.** Nothing added may make the companion assert ungrounded claims. It already self-flags stitched fragments — preserve that.
- **Clean up test-pollution.** Every live probe writes ConversationPassage/ChatContextLog records to memory; delete them at the end (Task 9).
- All new files live in the beagle repo on branch `reconcile/unify-beagle`.

---

### Task 1: Preflight health command (A1)

**Files:**
- Create: `scripts/beagle-cpc26-preflight.sh`

**Interfaces:**
- Produces: an executable that exits 0 (all GREEN) or 1 (any RED), printing a per-check verdict. Consumed by the human tomorrow morning and referenced by the demo runbook (Task 7).

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Beagle CPC26 preflight — one command, GREEN/RED before leaving for Yale.
set -uo pipefail
EXT="https://beagle.chiuratto.ai"
INT="http://10.96.71.119"
NS=beagle
fail=0; line(){ printf "%-32s %s\n" "$1" "$2"; }
TOK=$(kubectl -n $NS get secret cockpit-mobile-auth -o jsonpath='{.data.PROJECT_COCKPIT_AUTH_TOKEN}' 2>/dev/null | base64 -d)
[ -n "$TOK" ] || { line "auth token" "RED (no secret)"; exit 1; }

# 1. external healthz
c=$(curl -s -m10 -o /dev/null -w '%{http_code}' "$EXT/healthz")
[ "$c" = 200 ] && line "1 external /healthz" "GREEN ($c)" || { line "1 external /healthz" "RED ($c)"; fail=1; }

# 2. companion personal chat grounded
r=$(curl -s -m85 -X POST "$EXT/api/mobile/v1/chat" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"prompt":"ping preflight","space":"personal"}')
echo "$r" | grep -q '"grounded":true' && line "2 companion (personal)" "GREEN" || { line "2 companion (personal)" "RED"; fail=1; }

# 3. deep-think cites
r=$(curl -s -m175 -X POST "$EXT/api/mobile/v1/chat" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"prompt":"Cite one paper linking network curvature to brain connectivity.","space":"personal","deepThink":true}')
echo "$r" | grep -qiE 'http|doi|[0-9]{4}\)' && line "3 deep-think cites" "GREEN" || { line "3 deep-think cites" "RED"; fail=1; }

# 4. memory recall (ORC + Sounio present)
orc=$(kubectl -n $NS exec memory-pg-0 -- sh -lc "psql -U memory -d memory -tAc \"SELECT count(*) FROM records WHERE content ~* 'ollivier|hyperbolic|HSN'\"" 2>/dev/null | tr -d '[:space:]')
sou=$(kubectl -n $NS exec memory-pg-0 -- sh -lc "psql -U memory -d memory -tAc \"SELECT count(*) FROM records WHERE content ~* 'sounio|souc|tapestry'\"" 2>/dev/null | tr -d '[:space:]')
{ [ "${orc:-0}" -gt 0 ] && [ "${sou:-0}" -gt 0 ]; } && line "4 memory recall" "GREEN (orc=$orc sounio=$sou)" || { line "4 memory recall" "RED (orc=${orc:-?} sounio=${sou:-?})"; fail=1; }

# 5. claude proxy up (deep-think brain)
c=$(curl -s -m8 -o /dev/null -w '%{http_code}' http://127.0.0.1:9500/v1/models)
[ "$c" = 200 ] && line "5 claude proxy t560:9500" "GREEN ($c)" || { line "5 claude proxy t560:9500" "RED ($c)"; fail=1; }

echo "----"
[ "$fail" = 0 ] && echo "VERDICT: GREEN — Beagle ready for CPC26." || echo "VERDICT: RED — fix above before relying on it."
exit $fail
```

- [ ] **Step 2: Make executable + run it**

Run: `chmod +x scripts/beagle-cpc26-preflight.sh && scripts/beagle-cpc26-preflight.sh`
Expected: 5 lines, each GREEN, final `VERDICT: GREEN`. If any RED, that check names the failing subsystem — fix before proceeding (it is telling you the truth about tomorrow).

- [ ] **Step 3: Commit**

```bash
git add scripts/beagle-cpc26-preflight.sh
git commit -m "cpc26: preflight health command (external chat + deep-think + recall + proxy)"
```

---

### Task 2: Proxy durability verification (A3)

**Files:** none (verification only).

- [ ] **Step 1: Confirm the claude proxy is reboot-durable**

Run: `systemctl --user is-enabled claude-oauth-proxy && loginctl show-user "$USER" -p Linger`
Expected: `enabled` and `Linger=yes`. If not enabled/lingered, the proxy will not survive a t560 reboot (it has died this way before).

- [ ] **Step 2: If not durable, enable it**

Run (only if Step 1 failed): `systemctl --user enable claude-oauth-proxy && loginctl enable-linger "$USER"`
Expected: no error; re-run Step 1 → both green.

- [ ] **Step 3: Record the manual fallback in the runbook (done in Task 7).** No commit here.

---

### Task 3: Ingest O-CSSM/Tapestry internals (S2 — the one grounding gap)

**Files:** none new; uses the existing ingest path. This closes the single measured gap (companion has his *claims* about Tapestry but not the *internals*).

**Interfaces:**
- Produces: memory records containing the Tapestry/O-CSSM internal construction, verifiable by a recall probe.

- [ ] **Step 1: Locate the Tapestry/O-CSSM source in the Sounio repo**

Run: `ls -1 /home/devsounio/sounio 2>/dev/null | head; grep -rl -iE 'tapestry|o-cssm|zero.divisor|octonion|sedenion' /home/devsounio/sounio --include=*.sio --include=*.md 2>/dev/null | head -20`
Expected: a list of the .sio/.md files that build the functor. Note their paths.

- [ ] **Step 2: Ingest those files into memory via the assisted-import path (SEQUENTIAL only — concurrency corrupts JSONL)**

Ingest each identified file one at a time through the companion's `deep_fetch(read=true)` / assisted-import mechanism used for his ORC paper. For a local file, capture its content as a memory record tagged as reference (source_type reference/MemoryAtom), one file per call, waiting for each to finish before the next.
Expected: each import returns extracted-char count > 0; no JSONL corruption.

- [ ] **Step 3: Verify the internals are now recallable**

Run: `kubectl -n beagle exec memory-pg-0 -- sh -lc "psql -U memory -d memory -tAc \"SELECT count(*) FROM records WHERE content ~* 'zero.divisor|octonion|sedenion|Cayley.Dickson'\""`
Expected: count strictly greater than the pre-ingest baseline (record the baseline first).

- [ ] **Step 4: Live probe — does the companion now discuss internals, not just claims?**

Run the companion (`space:personal`) with: "Explique o INTERNO do funtor O-CSSM/Tapestry: como o divisor de zero mapeia dissociação, no build bit-exato em Sounio."
Expected: the response now references construction detail (Cayley–Dickson, the specific zero-divisor pair) rather than only "o fio que você plantou". If still thin, note it — the runbook (Task 7) falls back to his claims honestly.

- [ ] **Step 5: Commit** (only if any tracked file changed; ingest itself writes to memory-pg, not git — so likely no commit. Record the outcome in the runbook instead.)

---

### Task 4: Recall verification probes (B1) + conference-mode preamble (B2/C1, no rebuild)

**Files:**
- Create: `scripts/beagle-cpc26-recall-probes.sh`
- Create: `docs/cpc26-conference-mode-preamble.md`

**Interfaces:**
- Consumes: the chat request shape (Global Constraints).
- Produces: a probe script that exercises ≥5 key results; a copy-paste preamble the human can prepend to sharpen any answer WITHOUT a server change.

- [ ] **Step 1: Write the probe script**

```bash
#!/usr/bin/env bash
set -uo pipefail
TOK=$(kubectl -n beagle get secret cockpit-mobile-auth -o jsonpath='{.data.PROJECT_COCKPIT_AUTH_TOKEN}' | base64 -d)
ask(){ curl -s -m85 -X POST http://10.96.71.119/api/mobile/v1/chat -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d "{\"prompt\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"),\"space\":\"personal\"}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("grounded=",d["data"].get("grounded"),"\n",d["data"]["response"][:500],"\n---")'; }
for q in \
 "Minha descoberta central com Ollivier-Ricci, precisa." \
 "O que é o Experimento 06 e o elo ORC↔gap espectral?" \
 "O núcleo epistêmico do Sounio: Knowledge[T], GUM, smt.check — o que EU construí?" \
 "A ponte HSN → psiquiatria computacional, na minha formulação." \
 "O interno do funtor O-CSSM/Tapestry (divisor de zero ↔ dissociação)."; do
  echo "Q: $q"; ask "$q"; done
```

- [ ] **Step 2: Run it and grade each answer sharp/thin**

Run: `chmod +x scripts/beagle-cpc26-recall-probes.sh && scripts/beagle-cpc26-recall-probes.sh`
Expected: ≥4 of 5 sharp with `grounded=True` leading with his own framing. The Tapestry one should be sharp IF Task 3 succeeded; note any that are thin.

- [ ] **Step 3: Write the conference-mode preamble (no server change)**

```markdown
# Conference-mode preamble (prepend to any question when precision matters)

"Modo conferência: responda com precisão de par acadêmico, citando fonte ou dizendo
que a literatura é rala — nunca claim nua. Lidere com a MINHA formulação e distinga
o que EU construí (observado) do que aquilo significa (minha fala). Não sobre-afirme."
```

- [ ] **Step 4: Commit**

```bash
git add scripts/beagle-cpc26-recall-probes.sh docs/cpc26-conference-mode-preamble.md
git commit -m "cpc26: recall probes (5 key results) + conference-mode preamble (no rebuild)"
```

---

### Task 5: On-demand capture→synthesis flow (E2 — the #4, no rebuild)

**Files:**
- Create: `docs/cpc26-synthesis-flow.md`

**Interfaces:**
- Consumes: the drawer "Capturar pensamento" (already writes captures to memory) + the companion's existing recent+broad recall.
- Produces: a documented, verified synthesis command the human triggers end-of-session.

- [ ] **Step 1: Verify a capture round-trips and is recallable**

Capture a distinctive test thought via the app drawer (e.g. "CPC26 captura teste: curvatura e dissociação em Sounio"). Then query:
Run: `kubectl -n beagle exec memory-pg-0 -- sh -lc "psql -U memory -d memory -tAc \"SELECT source_type,to_char(created_at,'HH24:MI'),left(content,80) FROM records WHERE content ~* 'CPC26 captura teste' ORDER BY created_at DESC LIMIT 3\""`
Expected: the capture appears (source_type MemoryAtom or similar), created within the last minutes. If it does NOT appear, capture→memory is broken → escalate (this is the load-bearing assumption for #4).

- [ ] **Step 2: Run the synthesis prompt against the working recall pipeline**

Ask the companion (`space:personal`): "Sintetiza minhas capturas de hoje contra o meu trabalho (ORC/HSN/Sounio): o que conecta, o que é novo, o que contradiz meu trabalho anterior, o que seguir. Cite quando puder."
Expected: a structured synthesis that references the captured test thought AND connects to his ORC/Sounio work with at least one grounded link/citation. This proves #4 works with zero code change.

- [ ] **Step 3: If Step 2 recall of today's captures is weak, add a recency hint**

Fallback prompt variant (document both): prepend "Considere especificamente as notas que capturei nas últimas horas:" — nudges the recency window. Verify it surfaces the capture.

- [ ] **Step 4: Write the flow doc**

Document in `docs/cpc26-synthesis-flow.md`: how to capture during talks (drawer button), the exact synthesis prompt (Step 2), the recency-hint fallback (Step 3), and the verified expectation. Include the note that this is on-demand end-of-session, not real-time.

- [ ] **Step 5: Commit**

```bash
git add docs/cpc26-synthesis-flow.md
git commit -m "cpc26: on-demand capture->synthesis flow (rides existing recall, no rebuild)"
```

---

### Task 6: Delete stale digest / verify no confabulation in synthesis (guard)

**Files:** none (verification).

- [ ] **Step 1: Confirm the synthesis + recall never assert ungrounded**

Re-read the Task 4 and Task 5 outputs. Confirm every non-grounded statement is self-flagged ("o fio que você plantou" / "costurando fragmento"). If any bare over-claim appears, capture the exact prompt+response and STOP — report it; do not ship a confabulating trunfo.
Expected: no bare over-claims; anti-confabulation intact.

---

### Task 7: Demo runbook (D1 / #3 showcase)

**Files:**
- Create: `docs/cpc26-demo-runbook.md`

- [ ] **Step 1: Write the 2-minute demo runbook**

Document the exact sequence, each step referencing a verified capability from Tasks 1–5:
1. Preflight GREEN (Task 1) — "it's live."
2. Living memory + provenance (anti-confabulation: `claimed` vs `unverified`) — show a recall.
3. Live recall of his ORC finding (Task 4 probe 1).
4. Deep-think citing a real paper (Task 1 check 3 / a live `deepThink:true`).
5. **Sounio**: epistemic types `Knowledge[T]`+GUM, `smt.check` UNSAT/SAT, the packaged stats suite, and the **Tapestry functor** as the formal comp-psych bridge (Task 3/4).
6. On-demand synthesis (Task 5) — capture a thought, synthesize live.
Include the manual fallback (if deep-think is slow/down, normal chat still answers via router) and the preflight command to run first.

- [ ] **Step 2: Walk the runbook end-to-end, fixing any step that doesn't work**

Execute every step live. Any step that fails is a runbook bug — fix the step or the underlying issue (within no-rebuild scope) before marking done.
Expected: all 6 steps demonstrably work.

- [ ] **Step 3: Commit**

```bash
git add docs/cpc26-demo-runbook.md
git commit -m "cpc26: 2-minute demo runbook (showcase #3), end-to-end verified"
```

---

### Task 8 (STRETCH — requires cockpit rebuild; do ONLY if time + green preflight): Deep-think code fallback (A2)

**Files:**
- Modify: `apps/project-cockpit/server/mobile-routes.mjs` (`proxyDeepThinkAgentic`, ~lines 716–756)

**Interfaces:**
- Consumes: `LITELLM_ROUTER_URL` (already in env), `routerChat`/router `claude-opus-4-8` (proven reachable).
- Produces: on agentic-proxy fetch failure, a still-cited (non-agentic) answer via the router instead of a 503.

- [ ] **Step 1: Write the failing test** (in the existing mjs test harness, mirror `mobile-floor.test.mjs`)

```javascript
// deep-think falls back to router when the agentic proxy is unreachable
test("proxyDeepThinkAgentic falls back to router on ECONNREFUSED", async () => {
  const res = await proxyDeepThinkAgentic({ prompt: "hi", _forceProxyUrl: "http://127.0.0.1:1/" });
  assert.ok(res.text && res.source === "router-fallback");
});
```

- [ ] **Step 2: Run it — expect FAIL** (`node --test apps/project-cockpit/server/…`) with no `router-fallback` source.

- [ ] **Step 3: Implement the fallback** — wrap the `fetch(${DEEP_THINK_PROXY_URL}/v1/chat/completions)` in try/catch; on failure call the router (`${LITELLM_ROUTER_URL}/v1/chat/completions`, model `claude-opus-4-8`) and return `{ text, model:"claude-opus-4-8", source:"router-fallback" }`.

- [ ] **Step 4: Run the test — expect PASS.**

- [ ] **Step 5: Rebuild + redeploy cockpit** (buildah/kaniko → registry 192.168.3.207:5003 → rollout), THEN re-run `scripts/beagle-cpc26-preflight.sh`. If preflight is not GREEN after redeploy, `kubectl rollout undo` immediately — a broken cockpit the night before is worse than no fallback.

- [ ] **Step 6: Commit** `git commit -m "cockpit: deep-think falls back to router on proxy failure (A2)"`

---

### Task 9: Clean up test-pollution

**Files:** none.

- [ ] **Step 1: List today's probe records**

Run: `kubectl -n beagle exec memory-pg-0 -- sh -lc "psql -U memory -d memory -tAc \"SELECT id,source_type,left(content,60) FROM records WHERE source_type IN ('ConversationPassage','ChatContextLog') AND created_at::date='2026-07-13' ORDER BY created_at\""`
Expected: the probe Q/A from Tasks 1,4,5 (ping preflight, the 5 recall probes, the synthesis test). Identify which are test noise vs any real use.

- [ ] **Step 2: Delete only the test-noise records by id** (transaction: delete derived facts by `source_record_id` first, then records — the pattern proven earlier today). Verify count of test records for today is 0 afterward.

- [ ] **Step 3: Final preflight** — `scripts/beagle-cpc26-preflight.sh` → GREEN. This is the last word before tomorrow.

---

## Self-Review

**Spec coverage:** A1→T1, A2→T8(stretch), A3→T2, B1→T4, B2/C1→T4(preamble), C2→verified in T1/T7, D1→T7, E1/E2→T5, S1→T4, S2→T3, S3→T7, S4→T5, success-criteria→T1/T4/T5/T7/T9, cleanup→T9. All covered.
**Placeholder scan:** no TBD/TODO; each code/script step shows real content; ingest (T3) references the concrete existing path; synthesis (T5) gives exact prompts.
**Type consistency:** request shape identical across T1/T4/T5; `source:"router-fallback"` defined in T8 and asserted in T8; recall-count SQL consistent across T1/T3/T4/T9.
**Ordering:** no-rebuild value (T1–T7) before the rebuild-gated stretch (T8); cleanup + final preflight last (T9).
