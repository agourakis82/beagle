import { For, Show, createMemo, createResource, createSignal, onCleanup, onMount } from "solid-js";
import { useParams } from "@solidjs/router";
import { useTitle } from "../hooks/useTitle";
import { fetchWithTruth } from "../stores/truth";
import "./WorkbenchMirror.css";

const AGENTS = [
  { id: "claude", label: "Claude Code", color: "#b46f5b", state: "drafting" },
  { id: "codex", label: "Codex", color: "#5e8f85", state: "ready" },
  { id: "cursor", label: "Cursor", color: "#7f7f86", state: "quiet" },
  { id: "kimi", label: "Kimi CLI", color: "#8b7aa8", state: "available" },
];

const MCP_CLIENTS = [
  { id: "claude-desktop", label: "Claude Desktop", transport: "STDIO MCP", status: "wired" },
  { id: "chatgpt", label: "ChatGPT", transport: "Apps SDK / HTTP MCP", status: "wired" },
  { id: "grok", label: "Grok", transport: "Custom MCP", status: "ready" },
  { id: "local-agents", label: "CLI agents", transport: "Darwin MCP + zellij", status: "live" },
];

const SUBSCRIPTION_TARGETS = [
  { id: "claude-desktop", label: "Claude Desktop", note: "Use your Claude subscription; read Beagle MCP/context." },
  { id: "claude-code", label: "Claude Code", note: "Use the local coding agent with Beagle MCP." },
  { id: "chatgpt", label: "ChatGPT", note: "Use the ChatGPT app/subscription with the MCP context bridge." },
  { id: "grok", label: "Grok", note: "Use Grok subscription or API only when explicitly selected." },
  { id: "cursor", label: "Cursor", note: "Use Cursor as the editor client with the shared packet." },
  { id: "kimi", label: "Kimi", note: "Use Kimi CLI/subscription lane for critique or review." },
];

const STARTERS = [
  {
    label: "Plan",
    text: "Turn this conversation into a concrete plan. No code yet.",
  },
  {
    label: "Ask Kimi",
    text: "Ask Kimi for a blunt critique of this direction before we implement.",
  },
  {
    label: "Give to Codex",
    text: "Prepare this as an implementation brief for Codex, including guardrails.",
  },
];

const CODING_STARTERS = [
  {
    id: "resume",
    label: "Continue",
    text: "Resume the current Darwin-MFC work from Workbench Context. Name the next concrete coding step, files to inspect, and validation gate before editing.",
  },
  {
    id: "review-kimi",
    label: "Ask Kimi",
    text: "Send this current coding state to Kimi for a concise review. Ask for UX/accessibility blind spots and one high-leverage next fix.",
  },
  {
    id: "implement",
    label: "Prepare build",
    text: "Turn this into an implementation pass: inspect the relevant files, make the smallest useful change, run validation, and checkpoint the result.",
  },
  {
    id: "checkpoint",
    label: "Save point",
    text: "Write a Workbench Context checkpoint for the current Darwin-MFC coding state, including changed files, validation commands, and next step.",
  },
];

function multimodelWsUrl(slug) {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/ws/projects/${encodeURIComponent(slug)}/multimodel-chat`;
}

function cleanText(value) {
  return String(value || "").trim();
}

function displayProviderLabel(event) {
  if (event?.label) return event.label;
  if (event?.provider === "synthesis") return "Synthesis";
  if (event?.provider === "claude") return "Claude Code";
  if (event?.provider === "codex") return "Codex";
  if (event?.provider === "cursor") return "Cursor Agent";
  if (event?.provider === "kimi") return "Kimi";
  return event?.provider || "Model";
}

async function fetchWorkbench(slug) {
  return fetchWithTruth(`/api/projects/${slug}/go-work-now?depth=deep`, 8000);
}

async function fetchClusterSummary() {
  return fetchWithTruth("/api/cluster/ops/summary", 15000);
}

async function fetchMcpDiscovery() {
  return fetchWithTruth("/api/auth/beagle-discover", 8000);
}

async function fetchContextStatus(slug) {
  return fetchWithTruth(`/api/workbench/${slug}/context/status`, 8000);
}

let workbenchContextTokenPromise;

async function fetchWorkbenchContextToken() {
  if (!workbenchContextTokenPromise) {
    workbenchContextTokenPromise = fetch("/api/auth/beagle-token", {
      signal: AbortSignal.timeout(8000),
    })
      .then(async (res) => {
        const payload = await res.json().catch(() => ({}));
        if (!res.ok || !payload?.token) throw new Error(payload?.error || `token ${res.status}`);
        return payload.token;
      })
      .catch((error) => {
        workbenchContextTokenPromise = null;
        throw error;
      });
  }
  return workbenchContextTokenPromise;
}

async function fetchContextJson(url, options = {}) {
  const method = options.method || "GET";
  const timeoutMs = options.timeoutMs || 15000;
  const body = options.body === undefined ? undefined : JSON.stringify(options.body);
  const baseHeaders = {
    ...(body ? { "content-type": "application/json" } : {}),
    ...(options.headers || {}),
  };

  async function request(headers) {
    const res = await fetch(url, {
      method,
      headers,
      body,
      signal: AbortSignal.timeout(timeoutMs),
    });
    const payload = await res.json().catch(() => ({}));
    return { res, payload };
  }

  let { res, payload } = await request(baseHeaders);
  if (res.status === 401) {
    const token = await fetchWorkbenchContextToken();
    ({ res, payload } = await request({
      ...baseHeaders,
      authorization: `Bearer ${token}`,
    }));
  }
  if (!res.ok) throw new Error(payload?.error || `${res.status}`);
  return payload;
}

async function fetchRagContext(slug) {
  try {
    const data = await fetchContextJson(`/api/workbench/${slug}/context/query`, {
      method: "POST",
      body: {
        query: `${slug} Beagle MCP shared context Claude Desktop ChatGPT Grok RAG++ agents`,
        scope: "general",
        max_items: 5,
      },
      timeoutMs: 15000,
    });
    return {
      data,
      truthMode: "observed",
      observedAt: new Date().toISOString(),
    };
  } catch (error) {
    return {
      data: null,
      truthMode: "stale",
      observedAt: null,
      error: error.message,
    };
  }
}

async function fetchHandoffMessages(slug) {
  try {
    const data = await fetchContextJson(`/api/workbench/${slug}/context/messages?limit=12`, {
      timeoutMs: 12000,
    });
    return {
      data,
      truthMode: "observed",
      observedAt: new Date().toISOString(),
    };
  } catch (error) {
    return {
      data: null,
      truthMode: "stale",
      observedAt: null,
      error: error.message,
    };
  }
}

async function fetchHandoffBoard(slug) {
  try {
    const data = await fetchContextJson(`/api/workbench/${slug}/context/messages/board?limit=80&stale_after_minutes=90`, {
      timeoutMs: 12000,
    });
    return {
      data,
      truthMode: "observed",
      observedAt: new Date().toISOString(),
    };
  } catch (error) {
    return {
      data: null,
      truthMode: "stale",
      observedAt: null,
      error: error.message,
    };
  }
}

async function fetchContextPresence(slug) {
  try {
    const data = await fetchContextJson(`/api/workbench/${slug}/context/presence?limit=120&stale_after_minutes=90`, {
      timeoutMs: 12000,
    });
    return {
      data,
      truthMode: "observed",
      observedAt: new Date().toISOString(),
    };
  } catch (error) {
    return {
      data: null,
      truthMode: "stale",
      observedAt: null,
      error: error.message,
    };
  }
}

async function fetchContextContinuity(slug) {
  try {
    const data = await fetchContextJson(`/api/workbench/${slug}/context/continuity?limit=80&handoff_limit=24&recent_limit=10`, {
      timeoutMs: 12000,
    });
    return {
      data,
      truthMode: "observed",
      observedAt: new Date().toISOString(),
    };
  } catch (error) {
    return {
      data: null,
      truthMode: "stale",
      observedAt: null,
      error: error.message,
    };
  }
}

function statusLabel(workspace) {
  if (workspace?.status) return workspace.status;
  if (workspace?.ready) return "live";
  return "checking";
}

function formatGeneratedAt(value) {
  if (!value) return "not observed";
  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(value));
  } catch {
    return "observed";
  }
}

function PresenceDots() {
  return (
    <div class="wm-presence" aria-label="Agent presence">
      <For each={AGENTS}>
        {(agent) => (
          <span class="wm-presence-dot" title={`${agent.label}: ${agent.state}`} style={{ "--agent-color": agent.color }} />
        )}
      </For>
    </div>
  );
}

function TopStrip(props) {
  return (
    <header class="wm-top-strip">
      <button class="wm-sidebar-button" type="button" onClick={props.onToggleSidebar} aria-label="Toggle lanes">
        <span />
        <span />
      </button>

      <div class="wm-project-title">
        <strong>{props.projectSlug}</strong>
      </div>

      <div class="wm-top-actions">
        <button class="wm-chrome-button" type="button" onClick={props.onToggleInspector} aria-label="Open details">
          Details
        </button>
      </div>
    </header>
  );
}

function Sidebar(props) {
  const lanes = [
    { id: "code", label: "Code", path: "M7 8 3 12l4 4m10-8 4 4-4 4M14 4l-4 16" },
    { id: "conversation", label: "Conversation", path: "M4 6.5C4 4.6 5.6 3 7.5 3h9C18.4 3 20 4.6 20 6.5v4c0 1.9-1.6 3.5-3.5 3.5H11l-4 3v-3.1C5.3 13.7 4 12.2 4 10.5v-4Z" },
    { id: "artifact", label: "Artifact", path: "M7 3h7l4 4v14H7V3Zm7 1v4h4" },
    { id: "context", label: "Context", path: "M5 7.5 12 4l7 3.5-7 3.5L5 7.5Zm0 4 7 3.5 7-3.5M5 15.5 12 19l7-3.5" },
    { id: "terminal", label: "Terminals", path: "M4 5h16v14H4V5Zm3 4 3 3-3 3m5 0h5" },
    { id: "hpc", label: "HPC", path: "M5 12h4m2 0h8M7 8h10M7 16h10M9 4v16m6-16v16" },
  ];

  return (
    <aside class={`wm-sidebar ${props.open ? "open" : ""}`} aria-label="Workspace lanes">
      <For each={lanes}>
        {(lane) => (
          <button
            class={`wm-lane ${props.selectedTab === lane.id ? "active" : ""}`}
            type="button"
            onClick={() => props.onSelectTab(lane.id)}
            aria-label={lane.label}
          >
            <svg class="wm-lane-icon" aria-hidden="true" viewBox="0 0 24 24">
              <path d={lane.path} />
            </svg>
            <span class="wm-lane-label">{lane.label}</span>
          </button>
        )}
      </For>
    </aside>
  );
}

function codingCommands(slug) {
  if (slug === "darwin-mfc") {
    return [
      "source /home/devsounio/projects/darwin-mfc/darwin-mfc-env.sh",
      "pnpm type-check",
      "pnpm test",
      "PLAYWRIGHT_BASE_URL=http://127.0.0.1:3024 pnpm test:e2e:entry --project=chromium",
      "pnpm build:vercel",
    ];
  }
  return [
    "dev status",
    "dev whereami",
    "run the project validation gate",
  ];
}

function MessageThread(props) {
  return (
    <div class="wm-message-list">
      <For each={props.messages || []}>
        {(message) => (
          <article class={`wm-message ${message.role}`}>
            <div>
              <strong>{message.role === "operator" ? "You" : message.agent}</strong>
              <span>{message.time}</span>
            </div>
            <p>{message.text}</p>
          </article>
        )}
      </For>
    </div>
  );
}

function CodeTab(props) {
  const goWork = () => props.data?.goWorkNow || {};
  const project = () => goWork().project || {};
  const workspace = () => goWork().workspace || {};
  const workspaceState = () => goWork().workspaceState || {};
  const continuity = () => props.continuity?.data || {};
  const handoffBoard = () => props.handoffBoard?.data || {};
  const ragData = () => props.ragContext?.data || {};
  const nextActions = () => handoffBoard().next_actions || [];
  const highlights = () => ragData().highlights || ragData().results || [];
  const compiled = () => props.compiledHandoff || null;
  const commands = () => codingCommands(props.projectSlug);
  const repoRoot = () => workspace().root || (props.projectSlug === "darwin-mfc" ? "/home/devsounio/darwin-MFC" : project().workspaceId || props.projectSlug);
  const activeHandoff = () =>
    nextActions().find((item) => item.to_client === "kimi" || item.to_client === "codex" || item.to_client === "claude-desktop") ||
    nextActions()[0];

  return (
    <section class="wm-code" aria-label="Code studio">
      <div class="wm-code-hero">
        <p class="wm-kicker">Studio</p>
        <h1>Darwin-MFC</h1>
        <p>
          Write what you are thinking. When it has shape, hand it to an agent,
          save a point, or prepare the next build.
        </p>
      </div>

      <div class="wm-studio-layout">
        <article class="wm-code-panel wm-code-chat">
          <div class="wm-rag-head">
            <div>
              <h2>Chat</h2>
              <p>Use the field at the bottom. Your notes stay here.</p>
            </div>
            <button type="button" onClick={() => props.onSelectTab("conversation")}>Expand</button>
          </div>
          <MessageThread messages={props.messages} />
        </article>

        <aside class="wm-studio-side">
          <div class="wm-next-card">
            <span class={`wm-mini-dot ${props.continuity?.truthMode || "declared"}`} />
            <div>
              <strong>{continuity().resume_brief ? "Context is ready" : "Context is loading"}</strong>
              <p>{continuity().resume_brief ? "I can pick up the thread from memory." : props.continuity?.error || "Waiting for project memory."}</p>
            </div>
          </div>

          <div class="wm-code-actions">
            <For each={CODING_STARTERS}>
              {(starter) => (
                <button type="button" onClick={() => props.onCodeAction(starter)}>
                  {starter.label}
                </button>
              )}
            </For>
            <span class={`wm-code-action-status ${props.codeActionStatus || "idle"}`}>
              {props.codeActionStatus || "idle"}
            </span>
          </div>

          <Show when={activeHandoff()}>
            {(item) => (
              <div class="wm-next-card compact">
                <span class="wm-mini-dot waiting" />
                <div>
                  <strong>{item().to_client} has an open handoff</strong>
                  <p>{item().subject}</p>
                </div>
              </div>
            )}
          </Show>
        </aside>
      </div>

      <details class="wm-technical-details">
        <summary>Project details</summary>
        <div class="wm-code-grid">
          <article class="wm-code-panel primary">
            <div class="wm-rag-head">
              <div>
                <h2>Memory</h2>
                <p>{continuity().resume_brief ? "Continuity packet is available." : props.continuity?.error || "Waiting for continuity."}</p>
              </div>
              <button type="button" onClick={props.onRefresh}>Refresh</button>
            </div>
            <pre>{continuity().resume_brief || "No resume packet yet."}</pre>
          </article>

          <article class="wm-code-panel">
            <h2>Repository</h2>
            <dl class="wm-code-facts">
              <div><dt>Root</dt><dd>{repoRoot()}</dd></div>
              <div><dt>Branch</dt><dd>{props.projectSlug === "darwin-mfc" ? "main" : project().posture || "-"}</dd></div>
              <div><dt>Workspace</dt><dd>{statusLabel(workspaceState())} · {workspace().tmuxSession || "not attached"}</dd></div>
              <div><dt>Pod</dt><dd>{workspace().pod || workspaceState().podName || "-"}</dd></div>
            </dl>
          </article>

          <article class="wm-code-panel">
            <h2>Validation</h2>
            <div class="wm-command-list">
              <For each={commands()}>
                {(command) => <code>{command}</code>}
              </For>
            </div>
          </article>

          <article class="wm-code-panel">
            <h2>Agent handoff</h2>
            <Show when={activeHandoff()} fallback={<p class="wm-rag-empty">No open handoff needs attention.</p>}>
              {(item) => (
                <div class="wm-code-handoff">
                  <strong>{item().to_client}</strong>
                  <span>{item().status}{item().stale ? " · stale" : ""}</span>
                  <p>{item().subject}</p>
                  <div class="wm-code-handoff-actions">
                    <button type="button" onClick={() => props.onCompileHandoff(item().message_id)}>Compile</button>
                    <Show when={item().status === "sent"}>
                      <button type="button" onClick={() => props.onHandoffLifecycle?.("ack", item())}>Ack</button>
                    </Show>
                    <Show when={item().status === "acknowledged" || item().status === "sent"}>
                      <button type="button" onClick={() => props.onHandoffLifecycle?.("claim", item())}>Claim</button>
                    </Show>
                    <Show when={item().status === "claimed"}>
                      <button type="button" onClick={() => props.onHandoffLifecycle?.("heartbeat", item())}>Beat</button>
                      <button type="button" onClick={() => props.onHandoffLifecycle?.("release", item())}>Release</button>
                      <button type="button" onClick={() => props.onHandoffLifecycle?.("complete", item())}>Complete</button>
                    </Show>
                  </div>
                </div>
              )}
            </Show>
            <button type="button" onClick={() => props.onSelectTab("context")}>Open board</button>
          </article>
        </div>

        <div class="wm-code-panel wide">
          <div class="wm-rag-head">
            <div>
              <h2>Compiled packet</h2>
              <p>{compiled() ? `${compiled().graph?.nodes?.length || 0} graph nodes · ${compiled().highlights?.length || 0} highlights` : "Compile an open handoff to prepare an agent packet."}</p>
            </div>
          </div>
          <Show when={compiled()} fallback={<p class="wm-rag-empty">No compiled packet yet.</p>}>
            {(packet) => <pre>{packet().compiled_context_text || "Compiled packet returned without text."}</pre>}
          </Show>
        </div>

        <div class="wm-code-panel wide">
          <div class="wm-rag-head">
            <div>
              <h2>Memory readback</h2>
              <p>{props.ragContext?.truthMode === "observed" ? `${highlights().length} highlights` : props.ragContext?.error || "Waiting for memory."}</p>
            </div>
            <button type="button" onClick={props.onRefresh}>Refresh</button>
          </div>
          <Show when={highlights().length} fallback={<p class="wm-rag-empty">No memory highlights returned yet.</p>}>
            <div class="wm-code-highlights">
              <For each={highlights().slice(0, 3)}>
                {(item) => (
                  <article>
                    <strong>{item.source || item.id || item.title || "memory"}</strong>
                    <p>{item.text || item.snippet || item.content || item.summary || JSON.stringify(item).slice(0, 220)}</p>
                  </article>
                )}
              </For>
            </div>
          </Show>
        </div>
      </details>
    </section>
  );
}

function ContextInline(props) {
  const rag = () => props.ragContext || {};
  const summary = () => rag().data?.summary || rag().data?.message || "";
  const state = () => rag().truthMode || "declared";
  const writeStatus = () =>
    typeof props.memoryWriteStatus === "function"
      ? props.memoryWriteStatus()
      : props.memoryWriteStatus || "idle";

  return (
    <div class="wm-context-inline">
      <div>
        <span class={`wm-mini-dot ${state()}`} />
        <strong>MCP + RAG++</strong>
        <span>Claude Desktop, ChatGPT, Grok, and local agents share the Beagle memory surface.</span>
        <span class={`wm-write-status ${writeStatus()}`}>{writeStatus()}</span>
      </div>
      <Show when={summary()} fallback={<em>{rag().error ? `memory readback stale: ${rag().error}` : "memory readback pending"}</em>}>
        <em>{summary()}</em>
      </Show>
    </div>
  );
}

function ConversationTab(props) {
  const latestUser = () => [...(props.messages || [])].reverse().find((message) => message.role === "operator");

  return (
    <section class="wm-conversation wm-plain-studio" aria-label="Conversation">
      <div class="wm-code-hero">
        <p class="wm-kicker">Chat</p>
        <h1>Darwin-MFC</h1>
        <p>
          Escreva aqui para montar contexto. Para falar com modelo de verdade,
          envie o pacote para um cliente de assinatura.
        </p>
      </div>
      <MessageThread messages={props.messages} />
      <div class="wm-subscription-panel">
        <div>
          <h2>Send to a real client</h2>
          <p>Claude, ChatGPT, Grok, Cursor and Kimi should read this through Beagle MCP/context, not through a fake API chat.</p>
        </div>
        <div class="wm-subscription-grid">
          <For each={SUBSCRIPTION_TARGETS}>
            {(target) => (
              <button
                type="button"
                disabled={!latestUser()}
                title={target.note}
                onClick={() => props.onSendToClient?.(target, latestUser())}
              >
                {target.label}
              </button>
            )}
          </For>
        </div>
        <p class="wm-rag-empty">
          Latest note: {latestUser()?.text || "write something first"}
        </p>
      </div>
    </section>
  );
}

function ContextTab(props) {
  const [handoffTo, setHandoffTo] = createSignal("kimi");
  const [handoffSubject, setHandoffSubject] = createSignal("handoff");
  const [handoffBody, setHandoffBody] = createSignal("");
  const [handoffStatus, setHandoffStatus] = createSignal("idle");
  const discover = () => props.discovery?.data || {};
  const contextStatus = () => props.contextStatus?.data || {};
  const rag = () => props.ragContext || {};
  const handoffs = () => props.handoffs?.data || {};
  const handoffBoard = () => props.handoffBoard?.data || {};
  const presence = () => props.presence?.data || {};
  const continuity = () => props.continuity?.data || {};
  const handoffMessages = () => handoffs().messages || [];
  const boardSummary = () => handoffBoard().summary || {};
  const boardClients = () => handoffBoard().clients || [];
  const presenceSummary = () => presence().summary || {};
  const presenceClients = () => presence().clients || [];
  const nextActions = () => handoffBoard().next_actions || [];
  const ragData = () => rag().data || {};
  const highlights = () => ragData().highlights || ragData().results || [];
  const endpoints = () => discover().endpoints || {};
  const counts = () => contextStatus().counts || {};
  const clients = () => presenceClients().length ? presenceClients() : contextStatus().clients?.length ? contextStatus().clients : MCP_CLIENTS;
  const clientOptions = () => clients().map((client) => client.client_id || client.id).filter(Boolean);

  async function submitHandoff(event) {
    event.preventDefault();
    const content = handoffBody().trim();
    if (!content) return;
    setHandoffStatus("sending");
    try {
      await props.onSendHandoff?.({
        from_client: "operator",
        to_client: handoffTo(),
        subject: handoffSubject().trim() || "handoff",
        content,
        priority: "normal",
        requires_response: true,
        tags: ["web-mirror"],
      });
      setHandoffBody("");
      setHandoffStatus("sent");
    } catch (error) {
      setHandoffStatus(`stale: ${error.message}`);
    }
  }

  return (
    <section class="wm-context-tab" aria-label="Context mesh">
      <div>
        <p class="wm-kicker">Context Mesh</p>
        <h1>MCP is the shared memory bus.</h1>
        <p>
          Claude Desktop, ChatGPT, Grok, and the local zellij agents should not
          keep separate private truths. They read and write through Beagle MCP,
          then RAG++ compiles the context before work is delegated.
        </p>
      </div>

      <div class="wm-context-stats">
        <span>{counts().local_records || 0} memories</span>
        <span>{counts().local_clients || 0} clients</span>
        <span>{counts().local_sessions || 0} sessions</span>
        <span>{counts().local_sources || 0} sources</span>
        <span>{presenceSummary().active || 0} agents active</span>
        <span>{presenceSummary().waiting || 0} agents waiting</span>
        <span>{boardSummary().waiting || 0} waiting</span>
        <span>{boardSummary().active || 0} active</span>
        <span>{boardSummary().canceled || 0} canceled</span>
        <span>{boardSummary().stale || 0} stale</span>
      </div>

      <div class="wm-context-grid">
        <For each={clients()}>
          {(client) => (
            <article class="wm-context-client">
              <span class={`wm-mini-dot ${client.state || client.status}`} />
              <strong>{client.label}</strong>
              <p>{client.state || client.status} · {client.work?.active || 0} active · {client.work?.waiting || 0} waiting · {client.memory_count || 0} memories</p>
            </article>
          )}
        </For>
      </div>

      <div class="wm-continuity-panel">
        <div class="wm-rag-head">
          <div>
            <h2>Continuity</h2>
            <p>{props.continuity?.truthMode === "observed" ? "Resume packet is live." : props.continuity?.error || "Waiting for continuity."}</p>
          </div>
          <button type="button" onClick={props.onRefreshContinuity}>Refresh</button>
        </div>
        <pre>{continuity().resume_brief || "No continuity packet yet."}</pre>
      </div>

      <div class="wm-handoff-board">
        <div class="wm-rag-head">
          <div>
            <h2>Agent board</h2>
            <p>{props.handoffBoard?.truthMode === "observed" ? `${boardSummary().total || 0} handoffs on the mesh` : props.handoffBoard?.error || "Waiting for board."}</p>
          </div>
          <button type="button" onClick={props.onRefreshHandoffs}>Refresh</button>
        </div>

        <div class="wm-board-columns">
          {["waiting", "active", "done", "canceled"].map((column) => (
            <section class="wm-board-column">
              <strong>{column}</strong>
              <span>{handoffBoard().columns?.[column]?.length || 0}</span>
            </section>
          ))}
        </div>

        <Show when={nextActions().length} fallback={
          <p class="wm-rag-empty">No open handoff needs attention.</p>
        }>
          <div class="wm-next-actions">
            <For each={nextActions()}>
              {(item) => (
                <article>
                  <div>
                    <strong>{item.to_client}</strong>
                    <span>{item.status}{item.stale ? " · stale" : ""}</span>
                  </div>
                  <p>{item.subject}</p>
                </article>
              )}
            </For>
          </div>
        </Show>

        <div class="wm-client-board">
          <For each={boardClients().filter((client) => client.waiting || client.active || client.stale || client.done || client.canceled).slice(0, 8)}>
            {(client) => (
              <article>
                <strong>{client.label || client.client_id}</strong>
                <span>{client.waiting || 0} waiting · {client.active || 0} active · {client.done || 0} done · {client.canceled || 0} canceled</span>
              </article>
            )}
          </For>
        </div>
      </div>

      <div class="wm-handoff-panel">
        <div class="wm-rag-head">
          <div>
            <h2>Agent handoff</h2>
            <p>{props.handoffs?.truthMode === "observed" ? `${handoffMessages().length} recent messages` : props.handoffs?.error || "Waiting for inbox."}</p>
            <p>Send, inspect, and acknowledge messages on the same RAG++ memory bus.</p>
          </div>
          <button type="button" onClick={props.onRefreshHandoffs}>Refresh</button>
        </div>

        <form class="wm-handoff-form" onSubmit={submitHandoff}>
          <select value={handoffTo()} onInput={(event) => setHandoffTo(event.currentTarget.value)} aria-label="Recipient">
            <For each={clientOptions()}>
              {(client) => <option value={client}>{client}</option>}
            </For>
          </select>
          <input
            value={handoffSubject()}
            onInput={(event) => setHandoffSubject(event.currentTarget.value)}
            placeholder="Subject"
            aria-label="Subject"
          />
          <textarea
            value={handoffBody()}
            onInput={(event) => setHandoffBody(event.currentTarget.value)}
            placeholder="Message for the agent"
            rows="3"
            aria-label="Handoff message"
          />
          <div>
            <span class={`wm-write-status ${handoffStatus()}`}>{handoffStatus()}</span>
            <button type="submit" disabled={!handoffBody().trim() || handoffStatus() === "sending"}>Send</button>
          </div>
        </form>

        <Show when={handoffMessages().length} fallback={
          <p class="wm-rag-empty">No handoffs yet. Send one when an agent needs context, critique, or a clean next move.</p>
        }>
          <div class="wm-handoff-list">
            <For each={handoffMessages()}>
              {(message) => (
                <article class="wm-handoff-item">
                  <div>
                    <strong>{message.from_client} → {message.to_client}</strong>
                    <span>{message.status}</span>
                  </div>
                  <p>{message.subject}</p>
                  <Show when={message.claimed_by || message.completed_by}>
                    <p>{message.completed_by ? `Completed by ${message.completed_by}` : `Claimed by ${message.claimed_by}`}</p>
                  </Show>
                  <Show when={message.canceled_by || message.last_heartbeat_at}>
                    <p>{message.canceled_by ? `Canceled by ${message.canceled_by}` : `Heartbeat ${message.last_heartbeat_at}`}</p>
                  </Show>
                  <em>{message.snippet || message.text}</em>
                  <Show when={message.status === "sent"}>
                    <button type="button" onClick={() => props.onAckHandoff?.(message.message_id, message.to_client)}>
                      Ack
                    </button>
                  </Show>
                  <Show when={message.status === "acknowledged" || message.status === "sent"}>
                    <button type="button" onClick={() => props.onClaimHandoff?.(message.message_id, message.to_client)}>
                      Claim
                    </button>
                  </Show>
                  <Show when={message.status === "claimed"}>
                    <button type="button" onClick={() => props.onHeartbeatHandoff?.(message.message_id, message.claimed_by || message.to_client)}>
                      Beat
                    </button>
                    <button type="button" onClick={() => props.onReleaseHandoff?.(message.message_id, message.claimed_by || message.to_client)}>
                      Release
                    </button>
                    <button type="button" onClick={() => props.onCompleteHandoff?.(message.message_id, message.claimed_by || message.to_client)}>
                      Complete
                    </button>
                  </Show>
                  <Show when={message.status !== "completed" && message.status !== "canceled"}>
                    <button type="button" onClick={() => props.onCancelHandoff?.(message.message_id, "operator")}>
                      Cancel
                    </button>
                  </Show>
                  <Show when={message.status === "completed" || message.status === "canceled"}>
                    <button type="button" onClick={() => props.onReopenHandoff?.(message.message_id, "operator")}>
                      Reopen
                    </button>
                  </Show>
                </article>
              )}
            </For>
          </div>
        </Show>
      </div>

      <div class="wm-rag-panel">
        <div class="wm-rag-head">
          <div>
            <h2>RAG++ readback</h2>
            <p>{rag().truthMode === "observed" ? "Observed through the Cockpit Beagle proxy." : rag().error || "Waiting for memory query."}</p>
            <p>Last write: {props.memoryWriteStatus?.() || "idle"}</p>
            <p>Graph: {ragData().node_count || 0} nodes · {ragData().edge_count || 0} edges</p>
          </div>
        <button type="button" onClick={props.onRefresh}>Refresh</button>
      </div>

        <Show when={ragData().summary || highlights().length} fallback={
          <p class="wm-rag-empty">No memory highlights returned yet. The contract is still visible so the workspace does not forget the spine.</p>
        }>
          <Show when={ragData().summary}>
            <p class="wm-rag-summary">{ragData().summary}</p>
          </Show>
          <div class="wm-rag-highlights">
            <For each={highlights().slice(0, 5)}>
              {(item) => (
                <article>
                  <strong>{item.source || item.id || item.title || "memory"}</strong>
                  <p>{item.text || item.snippet || item.content || item.summary || JSON.stringify(item).slice(0, 220)}</p>
                </article>
              )}
            </For>
          </div>
        </Show>
      </div>

      <div class="wm-tool-contract">
        <span>{endpoints().workbench_mcp_http || "POST /api/workbench/:slug/mcp"}</span>
        <span>{endpoints().workbench_context_connect || "GET /api/workbench/:slug/context/connect"}</span>
        <span>{endpoints().workbench_context_mcp_http || "POST /api/workbench/:slug/context/mcp"}</span>
        <span>{endpoints().workbench_context_doctor || "POST /api/workbench/:slug/context/doctor"}</span>
        <span>{endpoints().workbench_context_status || "GET /api/workbench/:slug/context/status"}</span>
        <span>{endpoints().workbench_context_presence || "GET /api/workbench/:slug/context/presence"}</span>
        <span>{endpoints().workbench_context_continuity || "GET /api/workbench/:slug/context/continuity"}</span>
        <span>{endpoints().workbench_context_recent || "GET /api/workbench/:slug/context/recent"}</span>
        <span>{endpoints().workbench_context_query || "POST /api/workbench/:slug/context/query"}</span>
        <span>{endpoints().workbench_context_ingest || "POST /api/workbench/:slug/context/ingest"}</span>
        <span>{endpoints().workbench_context_message_send || "POST /api/workbench/:slug/context/messages/send"}</span>
        <span>{endpoints().workbench_context_message_inbox || "GET /api/workbench/:slug/context/messages/inbox/:client_id"}</span>
        <span>{endpoints().workbench_context_message_board || "GET /api/workbench/:slug/context/messages/board"}</span>
        <span>{endpoints().workbench_context_message_compile || "POST /api/workbench/:slug/context/messages/:message_id/compile"}</span>
        <span>{endpoints().workbench_context_message_claim || "POST /api/workbench/:slug/context/messages/:message_id/claim"}</span>
        <span>{endpoints().workbench_context_message_complete || "POST /api/workbench/:slug/context/messages/:message_id/complete"}</span>
        <span>{endpoints().workbench_context_message_release || "POST /api/workbench/:slug/context/messages/:message_id/release"}</span>
        <span>{endpoints().workbench_context_message_cancel || "POST /api/workbench/:slug/context/messages/:message_id/cancel"}</span>
        <span>{endpoints().workbench_context_message_reopen || "POST /api/workbench/:slug/context/messages/:message_id/reopen"}</span>
        <span>{endpoints().workbench_context_message_heartbeat || "POST /api/workbench/:slug/context/messages/:message_id/heartbeat"}</span>
        <span>{endpoints().workbench_context_import || "POST /api/workbench/:slug/context/import"}</span>
        <span>{endpoints().workbench_context_graphrag || "POST /api/workbench/:slug/context/graphrag/query"}</span>
        <span>{endpoints().workbench_context_compile || "POST /api/workbench/:slug/context/compiler/compile"}</span>
      </div>
    </section>
  );
}

function ArtifactTab(props) {
  const goWork = () => props.data?.goWorkNow || {};
  const posture = () => props.data?.operatingPosture || {};

  return (
    <section class="wm-artifact" aria-label="Artifact">
      <div>
        <p class="wm-kicker">Working note</p>
        <h1>{goWork().primaryEntry || "sounio dev"}</h1>
        <p>{posture().summary || goWork().summary || "Open an artifact or continue the conversation."}</p>
      </div>
      <div class="wm-document">
        <h2>Current posture</h2>
        <p>{posture().project?.nextSafeMove || "Treat the workspace as live, and turn intent into an explicit handoff before mutation."}</p>
        <h2>Workspace</h2>
        <p>{goWork().workspaceState?.summary || "Waiting for workspace state."}</p>
      </div>
    </section>
  );
}

function TerminalTab(props) {
  const tabs = () => props.data?.project?.zellijTabs || props.data?.goWorkNow?.project?.zellijTabs || [];

  return (
    <section class="wm-terminal" aria-label="Terminals">
      <div class="wm-terminal-header">
        <span>{props.data?.goWorkNow?.workspace?.tmuxSession || "sounio-dev"}</span>
        <span>{tabs().length} tabs</span>
      </div>
      <div class="wm-tab-grid">
        <For each={tabs()}>
          {(tab) => <button type="button">{tab}</button>}
        </For>
      </div>
    </section>
  );
}

function HpcTab(props) {
  const cluster = () => props.cluster || {};
  const counts = () => cluster().nodes || cluster().lanes?.kubernetes?.counts || {};

  return (
    <section class="wm-hpc" aria-label="HPC summary">
      <div>
        <p class="wm-kicker">Cluster</p>
        <h1>{cluster().status || "unknown"}</h1>
        <p>Visible because you opened it. It stays out of the room by default.</p>
      </div>
      <div class="wm-hpc-grid">
        <span><strong>{counts().ready ?? "-"}</strong> ready nodes</span>
        <span><strong>{counts().gpuAllocatable ?? "-"}</strong> GPUs allocatable</span>
        <span><strong>{cluster().slurm || cluster().lanes?.slurm?.status || "-"}</strong> Slurm</span>
        <span><strong>{cluster().orangefs?.risk || cluster().lanes?.orangefs?.status || "-"}</strong> OrangeFS</span>
      </div>
    </section>
  );
}

function Inspector(props) {
  const workspace = () => props.data?.goWorkNow?.workspaceState || {};
  const tabs = () => props.data?.project?.zellijTabs || [];

  return (
    <aside class={`wm-inspector ${props.open ? "open" : ""}`} aria-label="Inspector">
      <div class="wm-inspector-head">
        <strong>Inspector</strong>
        <button type="button" onClick={props.onClose}>Close</button>
      </div>

      <section>
        <h2>Workspace</h2>
        <dl>
          <div><dt>Status</dt><dd>{statusLabel(workspace())}</dd></div>
          <div><dt>Node</dt><dd>{workspace().nodeName || "-"}</dd></div>
          <div><dt>Pod</dt><dd>{workspace().podName || "-"}</dd></div>
        </dl>
      </section>

      <section>
        <h2>Agents</h2>
        <For each={AGENTS}>
          {(agent) => (
            <div class="wm-agent-row">
              <span style={{ "--agent-color": agent.color }} />
              <strong>{agent.label}</strong>
              <em>{agent.state}</em>
            </div>
          )}
        </For>
      </section>

      <section>
        <h2>Zellij</h2>
        <p>{tabs().length || 0} tabs · {props.data?.goWorkNow?.workspace?.tmuxSession || "sounio-dev"}</p>
      </section>
    </aside>
  );
}

function Composer(props) {
  const [draft, setDraft] = createSignal("");

  function submit() {
    const value = draft().trim();
    if (!value) return;
    props.onSubmit(value);
    setDraft("");
  }

  return (
    <form class="wm-composer" onSubmit={(event) => { event.preventDefault(); submit(); }}>
      <textarea
        value={draft()}
        onInput={(event) => setDraft(event.currentTarget.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter" && !event.shiftKey) {
            event.preventDefault();
            submit();
          }
        }}
        placeholder="Talk through the work, or ask an agent to take it."
        rows="1"
      />
      <button type="submit" disabled={!draft().trim()} aria-label="Send">
        ↑
      </button>
    </form>
  );
}

export default function WorkbenchMirror() {
  const params = useParams();
  const projectSlug = () => params.slug || "sounio";
  useTitle("Beagle Workbench");

  const [selectedTab, setSelectedTab] = createSignal("code");
  const [sidebarOpen, setSidebarOpen] = createSignal(false);
  const [inspectorOpen, setInspectorOpen] = createSignal(false);
  const [memoryWriteStatus, setMemoryWriteStatus] = createSignal("idle");
  const [codeActionStatus, setCodeActionStatus] = createSignal("idle");
  const [compiledHandoff, setCompiledHandoff] = createSignal(null);
  const [messages, setMessages] = createSignal([
    {
      id: "welcome",
      role: "agent",
      agent: "Beagle",
      time: "now",
      text: "Escreva aqui para montar o pacote. Quando quiser uma resposta de modelo real, envie para Claude, ChatGPT, Grok, Cursor ou Kimi.",
    },
  ]);

  const [workbench, { refetch: refetchWorkbench }] = createResource(projectSlug, fetchWorkbench);
  const [cluster, { refetch: refetchCluster }] = createResource(fetchClusterSummary);
  const [discovery] = createResource(fetchMcpDiscovery);
  const [contextStatus, { refetch: refetchContextStatus }] = createResource(projectSlug, fetchContextStatus);
  const [presence, { refetch: refetchPresence }] = createResource(projectSlug, fetchContextPresence);
  const [continuity, { refetch: refetchContinuity }] = createResource(projectSlug, fetchContextContinuity);
  const [ragContext, { refetch: refetchRagContext }] = createResource(projectSlug, fetchRagContext);
  const [handoffs, { refetch: refetchHandoffs }] = createResource(projectSlug, fetchHandoffMessages);
  const [handoffBoard, { refetch: refetchHandoffBoard }] = createResource(projectSlug, fetchHandoffBoard);
  const data = () => workbench()?.data || {};
  const workspace = () => data().goWorkNow?.workspaceState || {};
  const clusterData = () => cluster()?.data || {};

  const canvasClass = createMemo(() => `wm-canvas ${selectedTab()}`);

  async function ingestTurn(message, turnIndex) {
    setMemoryWriteStatus("writing");
    try {
      const payload = await fetchContextJson(`/api/workbench/${projectSlug()}/context/ingest`, {
        method: "POST",
        body: {
          source: "project-cockpit-workbench",
          session_id: `workbench:${projectSlug()}:${new Date().toISOString().slice(0, 10)}`,
          turns: [
            {
              role: message.role === "operator" ? "user" : "assistant",
              content: message.text,
            },
          ],
          tags: ["beagle-workbench", projectSlug(), "mcp-context", "rag-plus-plus"],
          metadata: {
            domain: "beagle-workbench",
            provider: "beagle-web-mirror",
            workspace_id: data().goWorkNow?.project?.workspaceId || projectSlug(),
            zellij_session: data().goWorkNow?.workspace?.tmuxSession || "sounio-dev",
            turn_index: turnIndex,
          },
        },
        timeoutMs: 15000,
      });
      setMemoryWriteStatus(payload?.searchable === false ? "stored" : "indexed");
      refetchRagContext();
      refetchContextStatus();
      refetchPresence();
      refetchContinuity();
    } catch (error) {
      setMemoryWriteStatus(`stale: ${error.message}`);
    }
  }

  async function sendHandoff(payload) {
    const result = await fetchContextJson(`/api/workbench/${projectSlug()}/context/messages/send`, {
      method: "POST",
      body: payload,
      timeoutMs: 15000,
    });
    refetchHandoffs();
    refetchHandoffBoard();
    refetchRagContext();
    refetchContextStatus();
    refetchPresence();
    refetchContinuity();
    return result;
  }

  async function ackHandoff(messageId, clientId) {
    const result = await fetchContextJson(`/api/workbench/${projectSlug()}/context/messages/${encodeURIComponent(messageId)}/ack`, {
      method: "POST",
      body: {
        client_id: clientId || "operator",
        note: "Acknowledged from Beagle Workbench web mirror.",
      },
      timeoutMs: 15000,
    });
    refetchHandoffs();
    refetchHandoffBoard();
    refetchRagContext();
    refetchContextStatus();
    refetchPresence();
    refetchContinuity();
    return result;
  }

  async function claimHandoff(messageId, clientId) {
    const result = await fetchContextJson(`/api/workbench/${projectSlug()}/context/messages/${encodeURIComponent(messageId)}/claim`, {
      method: "POST",
      body: {
        client_id: clientId || "operator",
        note: "Claimed from Beagle Workbench web mirror.",
      },
      timeoutMs: 15000,
    });
    refetchHandoffs();
    refetchHandoffBoard();
    refetchRagContext();
    refetchContextStatus();
    refetchPresence();
    refetchContinuity();
    return result;
  }

  async function completeHandoff(messageId, clientId) {
    const result = await fetchContextJson(`/api/workbench/${projectSlug()}/context/messages/${encodeURIComponent(messageId)}/complete`, {
      method: "POST",
      body: {
        client_id: clientId || "operator",
        result: "Marked complete from Beagle Workbench web mirror.",
      },
      timeoutMs: 15000,
    });
    refetchHandoffs();
    refetchHandoffBoard();
    refetchRagContext();
    refetchContextStatus();
    refetchPresence();
    refetchContinuity();
    return result;
  }

  async function lifecycleHandoff(messageId, action, clientId, body = {}) {
    const result = await fetchContextJson(`/api/workbench/${projectSlug()}/context/messages/${encodeURIComponent(messageId)}/${action}`, {
      method: "POST",
      body: {
        client_id: clientId || "operator",
        ...body,
      },
      timeoutMs: 15000,
    });
    refetchHandoffs();
    refetchHandoffBoard();
    refetchRagContext();
    refetchContextStatus();
    refetchPresence();
    refetchContinuity();
    return result;
  }

  function releaseHandoff(messageId, clientId) {
    return lifecycleHandoff(messageId, "release", clientId, {
      note: "Released from Beagle Workbench web mirror.",
    });
  }

  function cancelHandoff(messageId, clientId) {
    return lifecycleHandoff(messageId, "cancel", clientId, {
      reason: "Canceled from Beagle Workbench web mirror.",
    });
  }

  function reopenHandoff(messageId, clientId) {
    return lifecycleHandoff(messageId, "reopen", clientId, {
      note: "Reopened from Beagle Workbench web mirror.",
    });
  }

  function heartbeatHandoff(messageId, clientId) {
    return lifecycleHandoff(messageId, "heartbeat", clientId, {
      progress: "Still working from Beagle Workbench web mirror.",
    });
  }

  async function compileHandoffPacket(messageId) {
    if (!messageId) return null;
    setCodeActionStatus("compiling packet");
    try {
      const result = await fetchContextJson(`/api/workbench/${projectSlug()}/context/messages/${encodeURIComponent(messageId)}/compile?client_id=workbench-web`, {
        timeoutMs: 15000,
      });
      setCompiledHandoff(result);
      setCodeActionStatus("packet compiled");
      return result;
    } catch (error) {
      setCodeActionStatus(`stale: ${error.message}`);
      throw error;
    }
  }

  async function handleCodeHandoffLifecycle(action, item) {
    if (!item?.message_id) return null;
    const clientId = item.claimed_by || item.to_client || "operator";
    const workingLabels = {
      ack: "acknowledging handoff",
      claim: "claiming handoff",
      heartbeat: "sending heartbeat",
      release: "releasing handoff",
      complete: "completing handoff",
    };
    const doneLabels = {
      ack: "handoff acknowledged",
      claim: "handoff claimed",
      heartbeat: "heartbeat sent",
      release: "handoff released",
      complete: "handoff completed",
    };

    setCodeActionStatus(workingLabels[action] || "updating handoff");
    try {
      let result = null;
      if (action === "ack") result = await ackHandoff(item.message_id, clientId);
      if (action === "claim") result = await claimHandoff(item.message_id, clientId);
      if (action === "heartbeat") result = await heartbeatHandoff(item.message_id, clientId);
      if (action === "release") result = await releaseHandoff(item.message_id, clientId);
      if (action === "complete") result = await completeHandoff(item.message_id, clientId);
      setCodeActionStatus(doneLabels[action] || "handoff updated");
      return result;
    } catch (error) {
      setCodeActionStatus(`stale: ${error.message}`);
      throw error;
    }
  }

  function codeStateSummary() {
    const goWork = data().goWorkNow || {};
    const continuityPacket = continuity()?.data || {};
    const board = handoffBoard()?.data || {};
    const rag = ragContext()?.data || {};
    const openActions = board.next_actions || [];
    return [
      `project: ${projectSlug()}`,
      `workspace: ${statusLabel(workspace())} · ${goWork.workspace?.tmuxSession || "not attached"}`,
      `repo: ${goWork.workspace?.root || (projectSlug() === "darwin-mfc" ? "/home/devsounio/darwin-MFC" : projectSlug())}`,
      `continuity: ${continuityPacket.resume_brief ? "available" : "pending"}`,
      `open handoffs: ${openActions.length}`,
      `rag highlights: ${(rag.highlights || rag.results || []).length}`,
      "",
      "validation:",
      ...codingCommands(projectSlug()).map((command) => `- ${command}`),
      "",
      "continuity excerpt:",
      (continuityPacket.resume_brief || "No resume packet returned yet.").slice(0, 1200),
    ].join("\n");
  }

  async function generateStudioReply(message, turnIndex) {
    const turnId = `studio_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const statusId = `${turnId}:status`;
    const responseIds = new Map();
    const responseTexts = new Map();
    let socket = null;
    let completed = false;

    function updateMessage(messageId, patch) {
      setMessages((items) => items.map((item) => (
        item.id === messageId ? { ...item, ...patch } : item
      )));
    }

    function ensureProviderMessage(event) {
      const provider = event.provider || "model";
      if (responseIds.has(provider)) return responseIds.get(provider);
      const messageId = `${turnId}:${provider}`;
      responseIds.set(provider, messageId);
      responseTexts.set(provider, "");
      setMessages((items) => [
        ...items,
        {
          id: messageId,
          role: "agent",
          agent: displayProviderLabel(event),
          time: "now",
          text: "...",
        },
      ]);
      return messageId;
    }

    function failWithHonestMessage(error) {
      if (completed) return;
      completed = true;
      try { socket?.close(); } catch {
        // already closed
      }
      updateMessage(statusId, {
        agent: "Workbench",
        text: [
          "Não consegui abrir uma resposta de modelo real agora.",
          "",
          `Erro: ${error.message || error}`,
          "",
          "A mensagem foi salva no contexto. Não gerei fallback local."
        ].join("\n"),
      });
      setCodeActionStatus("model offline");
      void ingestTurn({
        role: "agent",
        agent: "Workbench",
        text: `Multimodel turn failed without fallback: ${error.message || error}`,
      }, turnIndex + 1);
    }

    setMessages((items) => [
      ...items,
      {
        id: statusId,
        role: "agent",
        agent: "Workbench",
        time: "now",
        text: "Abrindo canal multimodelo real...",
      },
    ]);
    setCodeActionStatus("connecting models");

    try {
      const recentThread = messages()
        .slice(-10)
        .map((item) => `${item.role === "operator" ? "User" : item.agent || "Model"}: ${item.text}`)
        .join("\n\n");
      socket = new WebSocket(multimodelWsUrl(projectSlug()));
      const timeout = window.setTimeout(() => {
        failWithHonestMessage(new Error("timeout waiting for multimodel WebSocket response"));
      }, 300000);

      socket.addEventListener("open", () => {
        setCodeActionStatus("models connected");
      });

      socket.addEventListener("error", () => {
        window.clearTimeout(timeout);
        failWithHonestMessage(new Error("WebSocket error"));
      });

      socket.addEventListener("message", (raw) => {
        let event = null;
        try {
          event = JSON.parse(raw.data);
        } catch {
          window.clearTimeout(timeout);
          failWithHonestMessage(new Error("invalid multimodel event"));
          return;
        }

        if (event.type === "ready") {
          const providers = Array.isArray(event.defaultProviders) && event.defaultProviders.length
            ? event.defaultProviders
            : (event.providers || [])
              .filter((provider) => provider.status === "available" && provider.immediateRealtime !== false)
              .map((provider) => provider.id)
              .filter((provider) => ["claude", "codex", "cursor", "kimi", "grok"].includes(provider));
          if (!providers.length) {
            window.clearTimeout(timeout);
            failWithHonestMessage(new Error("no real-time provider is available"));
            return;
          }
          socket.send(JSON.stringify({
            type: "chat",
            turnId,
            providers,
            enableSynthesis: true,
            history: recentThread ? [{ role: "thread", content: recentThread }] : [],
            message: [
              "Responda em português, direto e sem teatro.",
              "Se for conversa, converse antes de transformar em tarefa.",
              "Se mencionar execução, deixe claro que você só está propondo, a menos que tenha de fato executado.",
              "",
              "Estado do projeto como contexto, não como painel:",
              codeStateSummary().slice(0, 1600),
              "",
              "Mensagem atual do usuário:",
              message.text,
            ].join("\n"),
          }));
          updateMessage(statusId, {
            text: `Enviado para ${providers.join(", ")}. Aguardando respostas reais...`,
          });
          return;
        }

        if (event.type === "turn_started") {
          setCodeActionStatus(`streaming ${event.availableProviders?.join(", ") || "models"}`);
          return;
        }

        if (event.type === "provider_started") {
          const messageId = ensureProviderMessage(event);
          updateMessage(messageId, { agent: displayProviderLabel(event), text: "..." });
          return;
        }

        if (event.type === "delta" && event.provider) {
          const messageId = ensureProviderMessage(event);
          const nextText = `${responseTexts.get(event.provider) || ""}${event.text || ""}`;
          responseTexts.set(event.provider, nextText);
          updateMessage(messageId, { text: nextText || "..." });
          return;
        }

        if (event.type === "provider_done" && event.provider) {
          const messageId = ensureProviderMessage(event);
          const text = cleanText(event.text || responseTexts.get(event.provider));
          responseTexts.set(event.provider, text);
          updateMessage(messageId, {
            agent: displayProviderLabel(event),
            text: text || "(resposta vazia do provedor)",
          });
          if (text) {
            void ingestTurn({
              role: "agent",
              agent: displayProviderLabel(event),
              text,
            }, turnIndex + 1 + responseTexts.size);
          }
          return;
        }

        if ((event.type === "provider_error" || event.type === "provider_unavailable") && event.provider) {
          const messageId = ensureProviderMessage(event);
          updateMessage(messageId, {
            agent: displayProviderLabel(event),
            text: `${event.type === "provider_unavailable" ? "Indisponível" : "Erro"}: ${event.error || event.reason || "sem detalhe"}`,
          });
          return;
        }

        if (event.type === "turn_done" && event.turnId === turnId) {
          completed = true;
          window.clearTimeout(timeout);
          try { socket.close(); } catch {
            // already closed
          }
          const responded = [...responseTexts.values()].filter((text) => cleanText(text)).length;
          updateMessage(statusId, {
            text: responded
              ? `Turn multimodelo concluído com ${responded} resposta(s) real(is).`
              : "Turn concluído, mas nenhum provedor retornou texto útil.",
          });
          setCodeActionStatus(responded ? "responded" : "empty response");
          refetchRagContext();
          refetchContextStatus();
          refetchPresence();
          refetchContinuity();
        }
      });
    } catch (error) {
      failWithHonestMessage(error);
    }
  }

  async function checkpointCodeState(reason = "manual") {
    setCodeActionStatus("checkpointing");
    const payload = await fetchContextJson(`/api/workbench/${projectSlug()}/context/ingest`, {
      method: "POST",
      body: {
        source: "project-cockpit-workbench",
        provider: "beagle-web-mirror",
        client_id: "workbench-web",
        session_id: `workbench:${projectSlug()}:coding-app:${new Date().toISOString().slice(0, 10)}`,
        conversation_id: `workbench:${projectSlug()}:coding-app`,
        tags: ["beagle-workbench", projectSlug(), "coding-app", "checkpoint", "rag-plus-plus"],
        metadata: {
          domain: "beagle-workbench-coding-app",
          workspace_id: data().goWorkNow?.project?.workspaceId || projectSlug(),
          zellij_session: data().goWorkNow?.workspace?.tmuxSession || "",
          reason,
        },
        turns: [{
          role: "assistant",
          content: `Workbench Code checkpoint (${reason})\n\n${codeStateSummary()}`,
        }],
      },
      timeoutMs: 15000,
    });
    refetchRagContext();
    refetchContextStatus();
    refetchPresence();
    refetchContinuity();
    setCodeActionStatus(payload?.stored ? "checkpointed" : "stored");
    return payload;
  }

  function subscriptionPacket(target, sourceMessage) {
    return [
      `Target client: ${target.label}`,
      `Project: ${projectSlug()}`,
      "",
      "User note:",
      sourceMessage?.text || "(empty)",
      "",
      "Workbench state:",
      codeStateSummary(),
      "",
      "Instruction:",
      "Use Beagle MCP / Workbench Context as the source of truth. Respond in the subscription client, and write useful conclusions or handoffs back to shared context.",
    ].join("\n");
  }

  async function sendToSubscriptionClient(target, sourceMessage) {
    if (!target || !sourceMessage) return;
    setCodeActionStatus(`sending to ${target.label}`);
    const packet = subscriptionPacket(target, sourceMessage);
    try {
      await sendHandoff({
        from_client: "workbench-web",
        to_client: target.id,
        subject: `${projectSlug()} subscription-client packet`,
        content: packet,
        priority: "normal",
        requires_response: true,
        tags: ["subscription-client", target.id, projectSlug()],
      });
      if (navigator?.clipboard?.writeText) {
        await navigator.clipboard.writeText(packet).catch(() => {});
      }
      appendMessage(
        `Packet sent to ${target.label}. Open ${target.label} from your subscription and ask it to read the Beagle Workbench MCP/context inbox for ${projectSlug()}. I also tried to copy the packet to the clipboard.`,
        "agent",
        "Workbench"
      );
      setCodeActionStatus(`sent to ${target.label}`);
    } catch (error) {
      appendMessage(
        `Could not send the packet to ${target.label}: ${error.message}`,
        "agent",
        "Workbench"
      );
      setCodeActionStatus("send failed");
    }
  }

  async function handleCodeAction(action) {
    if (!action) return;
    if (action.id === "review-kimi") {
      setCodeActionStatus("sending handoff");
      appendMessage(action.text, "operator", "You", { respond: false });
      await sendHandoff({
        from_client: "workbench-web",
        to_client: "kimi",
        subject: `${projectSlug()} coding app review`,
        content: `${action.text}\n\nCurrent code-state packet:\n\n${codeStateSummary()}`,
        priority: "normal",
        requires_response: true,
        tags: ["coding-app", "review", projectSlug()],
      });
      appendMessage("Sent to Kimi as an agent handoff. It is now visible on the board and searchable in Workbench Context.", "agent", "Beagle");
      setCodeActionStatus("handoff sent");
      return;
    }

    if (action.id === "checkpoint") {
      await checkpointCodeState("code-tab-button");
      appendMessage("Checkpoint written to Workbench Context for this coding state.", "agent", "Beagle");
      return;
    }

    appendMessage(action.text, "operator", "You", { respond: false });
    appendMessage("Added to the studio thread and queued into shared context.", "agent", "Beagle");
    setCodeActionStatus(action.id === "implement" ? "implementation brief queued" : "resume queued");
  }

  function appendMessage(text, role = "operator", agent = "You", options = {}) {
    const turnIndex = messages().length;
    const message = {
      id: `msg_${Date.now()}_${Math.random().toString(16).slice(2)}`,
      role,
      agent,
      time: "now",
      text,
    };
    setMessages((items) => [
      ...items,
      message,
    ]);
    if (role === "operator") {
      setMemoryWriteStatus("queued");
      void ingestTurn(message, turnIndex);
      if (options.respond !== false) {
        void generateStudioReply(message, turnIndex);
      }
    }
  }

  function handleKeydown(event) {
    if (event.key === "Escape") {
      setInspectorOpen(false);
      setSidebarOpen(false);
    }
    if (event.key.toLowerCase() === "i" && event.metaKey && event.altKey) {
      event.preventDefault();
      setInspectorOpen((value) => !value);
    }
    if (event.key.toLowerCase() === "r" && event.metaKey) {
      event.preventDefault();
      refetchWorkbench();
      refetchCluster();
      refetchContextStatus();
      refetchRagContext();
      refetchHandoffs();
      refetchHandoffBoard();
      refetchPresence();
      refetchContinuity();
    }
  }

  onMount(() => window.addEventListener("keydown", handleKeydown));
  onCleanup(() => window.removeEventListener("keydown", handleKeydown));

  return (
    <div class="wm-shell">
      <TopStrip
        projectSlug={projectSlug()}
        workspace={workspace()}
        cluster={clusterData()}
        onToggleSidebar={() => setSidebarOpen((value) => !value)}
        onToggleInspector={() => setInspectorOpen((value) => !value)}
      />

      <div class="wm-body">
        <Sidebar
          open={sidebarOpen()}
          selectedTab={selectedTab()}
          onSelectTab={(tab) => { setSelectedTab(tab); setSidebarOpen(false); }}
        />

        <main class="wm-main">
          <nav class="wm-tabs" aria-label="Canvas tabs">
            <button class={selectedTab() === "code" ? "active" : ""} type="button" onClick={() => setSelectedTab("code")}>Studio</button>
            <button class={selectedTab() === "conversation" ? "active" : ""} type="button" onClick={() => setSelectedTab("conversation")}>Chat</button>
            <button class={selectedTab() === "context" ? "active" : ""} type="button" onClick={() => setSelectedTab("context")}>Context</button>
          </nav>

          <div class={canvasClass()}>
            <Show when={selectedTab() === "code"}>
              <CodeTab
                projectSlug={projectSlug()}
                data={data()}
                continuity={continuity()}
                ragContext={ragContext()}
                handoffBoard={handoffBoard()}
                onRefresh={() => { refetchWorkbench(); refetchContextStatus(); refetchPresence(); refetchContinuity(); refetchRagContext(); refetchHandoffs(); refetchHandoffBoard(); }}
                onSelectTab={setSelectedTab}
                onCodeAction={handleCodeAction}
                onCompileHandoff={compileHandoffPacket}
                onHandoffLifecycle={handleCodeHandoffLifecycle}
                compiledHandoff={compiledHandoff()}
                codeActionStatus={codeActionStatus()}
                messages={messages()}
              />
            </Show>
            <Show when={selectedTab() === "conversation"}>
              <ConversationTab
                messages={messages()}
                ragContext={ragContext()}
                memoryWriteStatus={memoryWriteStatus}
                onUseStarter={(text) => appendMessage(text)}
                onSendToClient={sendToSubscriptionClient}
              />
            </Show>
            <Show when={selectedTab() === "artifact"}>
              <ArtifactTab data={data()} />
            </Show>
            <Show when={selectedTab() === "context"}>
              <ContextTab
                discovery={discovery()}
                contextStatus={contextStatus()}
                presence={presence()}
                continuity={continuity()}
                ragContext={ragContext()}
                handoffs={handoffs()}
                handoffBoard={handoffBoard()}
                memoryWriteStatus={memoryWriteStatus}
                onRefresh={() => { refetchContextStatus(); refetchPresence(); refetchContinuity(); refetchRagContext(); refetchHandoffs(); refetchHandoffBoard(); }}
                onRefreshContinuity={refetchContinuity}
                onRefreshHandoffs={() => { refetchHandoffs(); refetchHandoffBoard(); refetchPresence(); refetchContinuity(); }}
                onSendHandoff={sendHandoff}
                onAckHandoff={ackHandoff}
                onClaimHandoff={claimHandoff}
                onCompleteHandoff={completeHandoff}
                onReleaseHandoff={releaseHandoff}
                onCancelHandoff={cancelHandoff}
                onReopenHandoff={reopenHandoff}
                onHeartbeatHandoff={heartbeatHandoff}
              />
            </Show>
            <Show when={selectedTab() === "terminal"}>
              <TerminalTab data={data()} />
            </Show>
            <Show when={selectedTab() === "hpc"}>
              <HpcTab cluster={clusterData()} />
            </Show>
          </div>

          <Composer onSubmit={(text) => appendMessage(text)} />
        </main>

        <Show when={inspectorOpen()}>
          <Inspector open data={data()} onClose={() => setInspectorOpen(false)} />
        </Show>
      </div>
    </div>
  );
}
