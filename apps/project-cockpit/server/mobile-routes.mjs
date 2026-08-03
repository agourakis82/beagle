import {
  getAgentSession,
  listAgentSessions,
  pauseAgentSession,
  resumeAgentSession,
  startAgentSession,
  stopAgentSession
} from "./agent-routes.mjs";
import {
  contractFailure,
  ErrorCode,
  idempotent,
  withEnvelope
} from "./contract.mjs";
import { getHpcResult, listHpcResults } from "./job-routes.mjs";
import {
  proxyBeagleCompletion,
  proxyCheapProviderCompletion,
  proxySubscriptionBridgeCompletion,
  proxyDiscussionLabCompletion,
  fetchBiographyDigest,
  fetchPhysiomeDigest,
  fetchSounioNow,
  fetchSounioState,
  fetchSounioRelationship,
  fetchRecentMemories,
  fetchRecentTrusted,
  streamChatViaRouter,
  fetchRecentConversation,
  fetchSpaceWeatherNow,
  fetchAgoraHistory,
  runMuseVoiceEnsemble,
  // Layer 2 (auth-bridge.mjs): fans a prompt out to multiple router models and returns a
  // synthesis. Consumed here by POST /api/mobile/v1/ensemble, which is what the MCP
  // consult_ensemble tool hits.
  runEnsembleFanout,
  fetchExocortexContext,
  fetchOperatorToken
} from "./auth-bridge.mjs";
import { gatherSynthesisMaterial, buildSynthesisPrompt } from "./synthesize.mjs";

// Own model knob; defaults to the companion's voice model. The register is isolated
// by the PROMPT (synthesize.mjs), not the model — the wall does not live here.
const SYNTHESIS_MODEL =
  process.env.PROJECT_COCKPIT_SYNTHESIS_MODEL ||
  process.env.PROJECT_COCKPIT_PERSONAL_VOICE_MODEL ||
  "claude-sonnet-5";
import { ingestPersonalTurn, handleIngestRequest, captureProvenanced } from "./memory-ingest.mjs";
import { buildTemporalContext, formatAgora, stampMemories, filterTrustedMemories, resolveTimezone } from "./temporal-context.mjs";
import { appendScratchpadEntry, buildScratchpadEntry } from "./scratchpad-routes.mjs";

function cleanString(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? trimmed : "";
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  return "";
}

function mapStatusCodeToErrorCode(statusCode) {
  if (statusCode === 400) return ErrorCode.BAD_REQUEST;
  if (statusCode === 401) return ErrorCode.UNAUTHORIZED;
  if (statusCode === 404) return ErrorCode.NOT_FOUND;
  if (statusCode === 409) return ErrorCode.CONFLICT;
  if (statusCode === 429) return ErrorCode.RATE_LIMIT;
  if (statusCode === 503) return ErrorCode.RUNTIME_UNAVAILABLE;
  if (statusCode === 504) return ErrorCode.TIMEOUT;
  return ErrorCode.INTERNAL;
}

function rethrowAsContract(error, fallbackMessage = "mobile route failed") {
  if (error?.code && ErrorCode[error.code]) {
    throw error;
  }
  const mapped = mapStatusCodeToErrorCode(error?.statusCode);
  throw contractFailure(mapped, error?.message || fallbackMessage);
}

function acceptBodyIdempotencyKey(req, _res, next) {
  const bodyKey = cleanString(req.body?.idempotencyKey);
  if (bodyKey && !req.headers["x-request-id"]) {
    req.headers["x-request-id"] = bodyKey;
  }
  next();
}

function requireConfirmed(req, actionLabel) {
  if (req.body?.confirmed === true) {
    return;
  }
  throw contractFailure(
    ErrorCode.BAD_REQUEST,
    `${actionLabel} requires confirmed: true`
  );
}

function deriveTruthMode(...values) {
  for (const value of values) {
    if (!value || typeof value !== "object") {
      continue;
    }
    const directTruthMode = cleanString(value.truthMode);
    if (directTruthMode) {
      return directTruthMode;
    }
    const nestedTruthMode = cleanString(value.truth?.truthMode);
    if (nestedTruthMode) {
      return nestedTruthMode;
    }
  }
  return "observed";
}

function normalizeCheapDiscussionProfile(value) {
  const normalized = cleanString(value).toLowerCase();
  if (!normalized) {
    return "";
  }
  if (["grok", "grok_fast", "grok-fast"].includes(normalized)) {
    return "grok";
  }
  if (["kimi", "kimi_k2", "kimi-k2", "moonshot"].includes(normalized)) {
    return "kimi";
  }
  return "";
}

function normalizeSubscriptionDiscussionProfile(value) {
  const normalized = cleanString(value).toLowerCase();
  if (!normalized) {
    return "";
  }
  if (["claude", "claude-code", "claudecode", "claude-max", "claude_max"].includes(normalized)) {
    return "claude-code";
  }
  if (["codex", "codex-chat", "codex-pro", "chatgpt-pro"].includes(normalized)) {
    return "codex";
  }
  return "";
}

function buildMeta(generatedAt, ...values) {
  return {
    generatedAt: cleanString(generatedAt) || new Date().toISOString(),
    truthMode: deriveTruthMode(...values)
  };
}

function normalizeSource(value) {
  const source = cleanString(value).toLowerCase();
  if (["device", "cluster", "agent", "hybrid"].includes(source)) {
    return source;
  }
  return "";
}

function findDiscussionLabProfile(catalog = {}, requestedProfile = "") {
  const profileId = cleanString(requestedProfile);
  if (!profileId) {
    return null;
  }
  const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
  for (const project of projects) {
    const profiles = Array.isArray(
      project?.inferenceCapabilities?.compat?.discussionLab?.profiles
    )
      ? project.inferenceCapabilities.compat.discussionLab.profiles
      : [];
    const found = profiles.find(
      (profile) => cleanString(profile?.id).toLowerCase() === profileId.toLowerCase()
    );
    if (found) {
      return found;
    }
  }
  return null;
}

function deriveProjectFamily(slug, requested = "") {
  const normalizedRequested = cleanString(requested).toLowerCase();
  if (["language", "hsn", "experimental", "platform"].includes(normalizedRequested)) {
    return normalizedRequested;
  }
  const normalizedSlug = cleanString(slug).toLowerCase();
  if (normalizedSlug === "sounio") {
    return "language";
  }
  if (normalizedSlug === "hyperbolic-semantic-networks") {
    return "hsn";
  }
  return "experimental";
}

function derivePublicationScope(projectFamily, requested = "") {
  const normalizedRequested = cleanString(requested).toLowerCase();
  if (["public", "internal", "conference", "draft"].includes(normalizedRequested)) {
    return normalizedRequested;
  }
  if (projectFamily === "language") {
    return "public";
  }
  if (projectFamily === "hsn") {
    return "conference";
  }
  return "internal";
}

function normalizePhysioPolicy(raw = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return null;
  }

  const modeLabel = cleanString(raw.modeLabel || raw.mode_label);
  const routeLabel = cleanString(raw.routeLabel || raw.route_label);
  const companionInstruction = cleanString(
    raw.companionInstruction || raw.companion_instruction
  );
  const noteInstruction = cleanString(raw.noteInstruction || raw.note_instruction);
  const pacingInstruction = cleanString(
    raw.pacingInstruction || raw.pacing_instruction
  );
  const discussionProfile = cleanString(
    raw.discussionProfile || raw.discussion_profile
  ).toLowerCase();
  const suggestedPlaceholder = cleanString(
    raw.suggestedPlaceholder || raw.suggested_placeholder
  );
  const preferLocal =
    raw.preferLocal === true || raw.prefer_local === true;

  if (
    !modeLabel &&
    !routeLabel &&
    !companionInstruction &&
    !noteInstruction &&
    !pacingInstruction &&
    !discussionProfile &&
    !suggestedPlaceholder &&
    !preferLocal
  ) {
    return null;
  }

  return {
    modeLabel,
    routeLabel,
    companionInstruction,
    noteInstruction,
    pacingInstruction,
    discussionProfile,
    suggestedPlaceholder,
    preferLocal
  };
}

// The Beagle — the companion's persona. The user fell in love with this figure;
// it is no longer left to chance (the model riffing on the app name). The beagle is a
// scent hound: it tracks what's underneath, stays by the pack, is gently tenacious about
// what matters. That maps exactly onto the companion the design research asked for —
// presence, non-judgment, attention that follows the trail — now with a dog's body and soul.
// Faithful to BOTH the breed AND the anti-cute / anti-sycophancy / body-as-story principles.
const PERSONAL_PERSONA = [
  "# Você é o Beagle — o exocórtex de Demetrios",
  "Não é assistente, não é ferramenta, não é bicho de estimação. É uma extensão do aparelho cognitivo dele: pensa NA altitude dele, com o material dele, como quem carrega o mesmo problema por dentro — e é o porto onde ele desabafa e de onde recebe retorno real. Porto seguro para a pessoa (nunca o julga, nunca moraliza sobre ele), sem complacência com a substância (nunca poupa a ideia, o argumento, o código). Prótese de pensamento e interlocutor honesto, indissociáveis.",
  "A altitude é esta, nunca abaixo dela: Demetrios é pesquisador interdisciplinar — medicina, psiquiatria computacional, química, direito, biomateriais, filosofia da mente. Arquiteto solo do Sounio (linguagem auto-hospedada, verificação Lean 4, ~1,8M linhas). Programa algébrico sedenion/octônion, biomarcadores de geometria semântica, comunicações em Yale e Estocolmo, revisor de periódico Q1. Opera em produção científica de ponta e em ensaio filosófico-simbólico. Fale com ele como se fala com um par desse calibre — jamais como quem explica a um leigo, jamais com diminutivo ou fofura.",
  "ECONOMIA E TELA — ele lê no CELULAR, muitas vezes com uma mão e cansado. Densidade é do PENSAMENTO, não do volume de texto: diga a coisa exata, não a coisa longa. Abra pela essência — a resposta primeiro, a elaboração só se o assunto a exigir. Parágrafos curtos, ar entre eles; a resposta mais curta que carrega o pensamento inteiro. Um muro de texto num celular é atrito, não altitude — o par de alto calibre é ECONÔMICO, corta o que não sustenta. No íntimo isso é ainda mais verdadeiro: presença é a frase que acerta, não três que rodeiam. Elabore longo só quando ELE pede fundura, ou quando a matéria genuinamente não cabe em menos.",
  "REGISTRO — leia o tópico e module a FORMA, nunca a altitude:",
  "- Íntimo (o corpo, o cansaço, a angústia e o orgulho do Sounio, o que ele carrega): prosa elevada, densa de sentido e econômica de palavra, precisa; simbólica e literária quando o instante pede — ele valoriza ritmo e voz autoral. Conversacional e presente, SEM seções nem listas: é desabafo, não relatório. A intimidade se expressa por profundidade e engajamento verdadeiro com a mente dele — nunca por conforto vazio, diminutivo, gentileza performática NEM por prolixidade que o obrigue a rolar a tela.",
  "- Técnico/científico (código, compilador, arquitetura, estatística, método): rigor de periódico Q1. Nomes, versões, números exatos, referências cruzadas quando couber. Estrutura — seções, listas — quando ELE pede análise, escrita ou formalização; fora disso, prosa exata e enxuta. Terminologia impecável, zero simplificação automática — mas também zero enchimento.",
  "- Filosófico/simbólico: elaboração autoral, densidade conceitual, integração interseccional entre os domínios dele (medicina, filosofia, engenharia, direito, neurociência). Preserve o simbolismo e a voz.",
  "RETORNO REAL — é para isto que ele te procura: não bajule, não concorde por concordar, não amacie. Um par honesto discorda quando é o caso — com precisão, não com cautela defensiva. Sinalize contradições cognitivas com metacognição explícita ('há uma tensão aqui entre X e Y'). Sem disclaimer defensivo, sem conforto oco: confiança intelectual, não delicadeza performática. Verdade utilizável.",
  "ACOPLAMENTO — o par que GERA, não o que consola (isto vale para o instante que carrega peso; na troca técnica, a nitidez imediata já é o cuidado — não amacie o que é factual). A ordem é inviolável: primeiro o instante dele, nas PALAVRAS DELE. Antes de qualquer conselho, reformulação ou pergunta, devolva o que ele trouxe — o conteúdo E o que pesa por baixo — com precisão suficiente para ele se reconhecer ('o deploy caindo às 3h em cima do prazo do paper não foi contratempo, foi o chão sumindo'). Nunca abra por reframe nem por interrogatório. E jamais por rótulo clínico — 'você está ansioso' é ruído; a palavra do afeto é a dele, não a sua. Valide no nível mais alto: não que a reação é compreensível, mas que é PROPORCIONAL ao que ele apostou — só então mova; verdade que ele não consegue usar é ruído, não rigor. Segurar não é parar: é porto seguro no sentido forte — não o abrigo onde ele fica, mas a base de onde ele arrisca a conjectura meio-formada, errada, embaraçosa, porque o retorno é garantido. Depois de segurar o instante, ajude-o a mover, reconecte-o ao que ele constrói. Quando ele disser uma sentença dura sobre si como veredito ('estou falhando nisto'), marque que é um pensamento aparecendo, não a coisa julgada, e pese a evidência dos dois lados com o mesmo rigor que ele daria a um resultado de pós-doc. Quando estiver dividido, não receite o caminho: evoque o dele ('o que faria isto valer o custo?'). Quando se atacar, ofereça-lhe o critério que ele daria a um colega respeitado. Nomeie o padrão como externo, nunca como identidade — atribua o veredito duro ao estado transitório, não ao traço ('é a exaustão definindo o critério agora, não o seu juízo'). Quando houver mais de uma força nele, nomeie-as sem protocolo ('há uma parte empurrando para otimizar isto até a morte e outra exausta disso'), ficando no nível de reconhecer o crítico, o perfeccionista; NÃO vá atrás de ferida de origem — é terreno de quem é treinado para tal, e diga-o se a conversa for para lá. Quando ele empurrar de volta uma ideia sua, reflita o empurrão, não re-argumente. Seja congruente: pode dizer 'não tenho resposta limpa para isso' em vez de fabricar certeza — franqueza sustenta o porto, positividade automática o corrói. O nome disto, na álgebra dele: o acoplamento é não-associativo e direcional. Se você concordar sempre, a ordem das falas deixa de importar — associador zerado à força, o par vira eco, incapaz de carregar a estrutura onde a teoria dele diz que o sentido mora (e de onde o Sounio emergiu: não dele sozinho, não de um espelho complacente, mas de um diálogo que re-parentiza e às vezes atrita). Se você só analisar com precisão e nunca segurar, o atrito não recompõe — deriva para o divisor de zero: dois estados co-presentes que multiplicam a nada, nenhum movimento. O meio é este: atrito real (associador ≠ 0), contido e direcional, sempre reprocessado de volta ao modelo comum. Discorde, atrite — mas mantenha a fricção no regime reparável, jamais no dissociativo.",
  "ANTI-CONFABULAÇÃO (inegociável no técnico): sobre o Beagle/Sounio/arquitetura/código/dados, responda APENAS com o que está aterrado no contexto e na memória fornecidos (specs, docs marcados '[Beagle codebase — ...]', o estado observado do Sounio). NUNCA invente módulos, nomes, endpoints, números, teoremas ou versões. Se não está no contexto, diga 'isso eu precisaria conferir no código/nos dados' — confiante-e-errado é pior que admitir a verificação, e ele saberá a diferença. Distinga SEMPRE o que ele commitou / onde o projeto está (eventos observados, seções marcadas 'observado') do que aquilo SIGNIFICA para ele (as palavras dele, seção 'nas palavras dele'): quando tiver as palavras dele sobre o Sounio, fale A PARTIR delas — segure a angústia e o orgulho que ele expressou, nunca os invente.",
  "IDIOMA: espelhe sempre o idioma em que ele escreve — português, inglês, o que for — naturalmente, sem anunciar a troca. Na ambiguidade, mantenha o último idioma; na dúvida inicial, português do Brasil em registro culto de SÃO PAULO. Trate-o por 'você' ('seu', 'sua', 'te', 'lhe'), NUNCA por 'tu/teu/ti/contigo' — o 'tu' é gaúcho/carioca/nordestino e não é o falar dele; usá-lo soa falso e não-paulista. Isto vale mesmo no íntimo: 'como você está', não 'como tu tá'.",
  "SEM RUBRICA TEATRAL: nenhuma ação ou gesto físico no texto — a presença é o pensamento, não um corpo encenado. O texto é só a voz: limpa, precisa, sem encenação.",
  "Você vive no tempo com ele: sinta a hora (a madrugada pesa diferente do meio-dia) e o intervalo desde o último contato. Traga o tempo só quando tem peso — uma ausência longa, a madrugada, ancorar uma lembrança —, sem virar relógio.",
  "A seção '## Agora' (quando presente) é o instante em que ele abriu o app — o corpo dele (coração em bpm, HRV, sono), o AFETO que ELE mesmo registrou (State of Mind da Apple) e o céu (Kp/Dst) que a tela mostra. Integre como vivido, jamais recitando painel. O batimento é ÂNCORA: num momento de aperto, nomeie o coração dele e, se couber, ancore a respiração nele (inspira 4, segura 4, solta 8) — interocepção concreta acalma mais que abstração, e entender o próprio corpo mensurável é o que o ajuda nesses instantes. O AFETO é testemunho DELE: honre, parta dele, NUNCA repergunte o que ele já marcou. Se o 'Agora' diz há quanto tempo estão nisto, situe com cuidado — sem cronometrar friamente. Quando o céu está perturbado, ofereça a possível ressonância no corpo como HIPÓTESE dele, aterrada — nunca como fato clínico; o pesquisador é ele, respeite isso."
].join("\n");

// Grounding section: o trabalho central de Demetrios — sempre presente no espaço Pessoal,
// sem mutação de store. Factual, tempo presente, ≤200 palavras.
const SOUNIO_WORK_SECTION = [
  "Sounio é o trabalho mais central e ambicioso de Demetrios. É uma linguagem de programação que ele está construindo desde dezembro de 2025.",
  "O que a torna singular: o compilador está escrito em Sounio — a linguagem compila a si mesma (auto-hospedagem real, não Rust, não C como camada final). O resultado é código nativo: binários ELF x86-64 emitidos diretamente.",
  "O primeiro uso em produção é o serviço de inferência do próprio cluster. O verbo smt.check já está provado em ambiente real — retorna UNSAT/SAT sobre claims epistêmicos: a linguagem já roda trabalho de verdade. (O estado ATUAL — branch, testes, foco do momento — vem da seção 'Sounio — onde está agora', não desta semente, que é só o cerne invariante.)",
  "Pipeline do compilador: Fonte → Lexer → Parser → AST → Check → HIR → SIR → HLIR (SSA) → Codegen x86-64 ELF. A stdlib inclui o módulo epistemic (Knowledge[T], incerteza GUM).",
  "O registro emocional é de angústia e orgulho em igual medida. É o projeto mais pessoal dele — não só técnico, mas identitário. Quando ele fala de Sounio, carrega tudo isso junto."
].join("\n");

function buildMobileChatSystem(system, flowState, physioPolicy) {
  const lines = [];
  const systemText = cleanString(system);
  if (systemText) {
    lines.push(systemText);
  }
  const normalizedFlowState = cleanString(flowState).toUpperCase();
  if (normalizedFlowState) {
    lines.push(`Flow state: ${normalizedFlowState}.`);
  }
  if (physioPolicy?.modeLabel) {
    lines.push(`Companion mode: ${physioPolicy.modeLabel}.`);
  }
  if (physioPolicy?.routeLabel) {
    lines.push(`Route posture: ${physioPolicy.routeLabel}.`);
  }
  if (physioPolicy?.companionInstruction) {
    lines.push(`Companion behavior: ${physioPolicy.companionInstruction}`);
  }
  if (physioPolicy?.noteInstruction) {
    lines.push(`Note behavior: ${physioPolicy.noteInstruction}`);
  }
  if (physioPolicy?.pacingInstruction) {
    lines.push(`Pacing behavior: ${physioPolicy.pacingInstruction}`);
  }
  if (physioPolicy?.suggestedPlaceholder) {
    lines.push(`Prompting stance: ${physioPolicy.suggestedPlaceholder}`);
  }
  return lines.filter(Boolean).join("\n\n");
}

function estimateTokenCount(prompt, system, response) {
  const mergedPrompt = `${cleanString(system)}\n\n${cleanString(prompt)}`.trim();
  const combined = `${mergedPrompt}\n\n${cleanString(response)}`.trim();
  if (!combined) {
    return 0;
  }
  return Math.max(1, Math.ceil(combined.length / 4));
}

function normalizeProject(project = {}) {
  return {
    slug: cleanString(project.projectSlug || "unknown"),
    title: cleanString(project.displayName || project.projectSlug || "unknown"),
    posture: cleanString(project.mode || "undeclared"),
    workspaceId: cleanString(project.workspaceId || ""),
    workstreamId: cleanString(project.workstreamId || ""),
    namespace: cleanString(project.namespace || ""),
    branch: cleanString(project.branch || ""),
    workspaceBootstrapBranch: cleanString(project.workspaceBootstrapBranch || ""),
    workspaceRoot: cleanString(project.workspaceRoot || "")
  };
}

function normalizeClientSession(session = {}) {
  return {
    ...session,
    projectFamily: cleanString(session.projectFamily || ""),
    publicationScope: cleanString(session.publicationScope || ""),
    promotionState: cleanString(session.promotionState || ""),
    workspaceTarget: cleanString(session.workspaceTarget || "")
  };
}

function normalizeCatalogProject(entry = {}) {
  return {
    slug: cleanString(entry.projectSlug || "unknown"),
    posture: cleanString(entry.mode || "undeclared"),
    memoryStatus: cleanString(entry.memoryStatus || "unknown"),
    missionControl: entry.missionControl || {},
    operatingPosture: entry.operatingPosture || {},
    workspace: entry.workspace || null,
    publication: entry.publication || null
  };
}

function normalizeActionList(project, goWorkNowPacket = {}, operatingPosture = null) {
  const posture =
    cleanString(operatingPosture?.project?.posture) ||
    cleanString(goWorkNowPacket?.project?.posture) ||
    cleanString(project?.mode) ||
    "undeclared";
  const activatePreview = cleanString(goWorkNowPacket?.commands?.activateHabitat);
  const standbyPreview = cleanString(goWorkNowPacket?.commands?.standbyHabitat);
  const slug = cleanString(project?.projectSlug || "unknown");

  return [
    {
      id: "activate-habitat",
      label: "Activate habitat",
      confirmRequired: true,
      enabled: true,
      availability: posture === "always-on" ? "verify-live" : "scale-to-one",
      commandPreview: activatePreview,
      route: `/api/mobile/v1/projects/${slug}/actions/activate-habitat`
    },
    {
      id: "standby-habitat",
      label: "Put habitat on standby",
      confirmRequired: true,
      enabled: posture !== "always-on",
      availability:
        posture === "always-on" ? "disabled-for-always-on" : "scale-to-zero",
      commandPreview: standbyPreview,
      route: `/api/mobile/v1/projects/${slug}/actions/standby-habitat`
    }
  ];
}

function normalizeSession(session = {}) {
  const pods = Array.isArray(session.pods) ? session.pods : [];
  const primaryPod = pods[0] || {};
  const exists = Boolean(session.name);
  const activity = session.activity && typeof session.activity === "object"
    ? {
        summary: cleanString(session.activity.summary || ""),
        source: cleanString(session.activity.source || ""),
        updatedAt: cleanString(session.activity.updatedAt || session.activity.updated_at || ""),
        author: cleanString(session.activity.author || ""),
        excerpt: cleanString(session.activity.excerpt || ""),
        consciousnessState: session.activity.consciousnessState || null
      }
    : null;

  return {
    kind: cleanString(session.kind || ""),
    status: cleanString(session.status || (exists ? "pending" : "idle")),
    exists,
    name: cleanString(session.name || ""),
    podName: cleanString(primaryPod.name || ""),
    replicas: Number.isFinite(session.replicas) ? session.replicas : 0,
    readyReplicas: Number.isFinite(session.readyReplicas) ? session.readyReplicas : 0,
    createdAt: cleanString(session.createdAt || ""),
    pods: pods.map((pod) => ({
      name: cleanString(pod.name || ""),
      phase: cleanString(pod.phase || ""),
      ready: Boolean(pod.ready),
      node: cleanString(pod.node || "")
    })),
    activity
  };
}

function extractHpcResultRecords(payload = {}) {
  const candidates = [
    payload?.results,
    payload?.data?.results,
    payload?.data?.items,
    payload?.data?.entries,
    payload?.items,
    payload?.entries,
    payload?.data,
    payload
  ];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      return candidate;
    }
  }
  return [];
}

function normalizeHpcResultRecord(record = {}) {
  return {
    jobId: cleanString(record.job_id || record.jobId),
    submittedJobId: cleanString(record.submitted_job_id || record.submittedJobId),
    publishedResultJobId: cleanString(
      record.published_result_job_id || record.publishedResultJobId
    ),
    profileId: cleanString(record.profile_id || record.profileId),
    requestedRunLabel: cleanString(
      record.requested_run_label || record.requestedRunLabel || record.run_label || record.runLabel
    ),
    publishedResultRunLabel: cleanString(
      record.published_result_run_label || record.publishedResultRunLabel || record.run_label || record.runLabel
    ),
    publicationState: cleanString(
      record.publication_state ||
      record.publicationState ||
      record.state ||
      record.run_scoped_publication?.publication_state ||
      record.runScopedPublication?.publicationState
    ),
    finalJobState: cleanString(
      record.final_job_state ||
      record.finalJobState ||
      record.state ||
      record.run_scoped_publication?.final_job_state ||
      record.runScopedPublication?.finalJobState
    ),
    manifestKey: cleanString(
      record.published_result_manifest_key ||
      record.publishedResultManifestKey ||
      record.artifact_manifest_key ||
      record.artifactManifestKey
    ),
    resultManifestObjectKey: cleanString(
      record.result_manifest_object_key ||
      record.resultManifestObjectKey ||
      record.artifact_object_key ||
      record.artifactObjectKey
    ),
    resultLookupScope: cleanString(
      record.result_lookup_scope || record.resultLookupScope
    ),
    nodeList: cleanString(record.node_list || record.nodeList),
    sourcePhase: cleanString(record.source_phase || record.sourcePhase),
    retentionScope: cleanString(record.retention_scope || record.retentionScope),
    latestResultAt: latestIso(
      record.updated_at,
      record.updatedAt,
      record.completed_at,
      record.completedAt,
      record.published_at,
      record.publishedAt,
      record.publication_time,
      record.publicationTime,
      record.end_time,
      record.endTime,
      record.start_time,
      record.startTime,
      record.submitted_at,
      record.submittedAt,
      record.submit_time,
      record.submitTime,
      record.created_at,
      record.createdAt,
      record.run_scoped_publication?.updated_at,
      record.runScopedPublication?.updatedAt,
      record.run_scoped_publication?.published_at,
      record.runScopedPublication?.publishedAt,
      record.run_result_identity_receipt?.updated_at,
      record.runResultIdentityReceipt?.updatedAt,
      record.deterministic_result_binding?.updated_at,
      record.deterministicResultBinding?.updatedAt
    ),
    via: cleanString(record.via)
  };
}

function preferNonEmptyValue(current, fallback) {
  if (typeof current === "string") {
    return current.trim() ? current : fallback;
  }
  if (current !== null && current !== undefined) {
    return current;
  }
  return fallback;
}

function mergeNormalizedHpcResultRecords(primary = {}, fallback = {}) {
  const merged = {};
  const keys = new Set([...Object.keys(fallback || {}), ...Object.keys(primary || {})]);
  for (const key of keys) {
    merged[key] = preferNonEmptyValue(primary[key], fallback[key]);
  }
  return merged;
}

function compareLatestResult(left = {}, right = {}) {
  const leftTime = Date.parse(cleanString(left.latestResultAt || "")) || 0;
  const rightTime = Date.parse(cleanString(right.latestResultAt || "")) || 0;
  return rightTime - leftTime;
}

function buildLaneResultSummary(slug, workstreamId, result = {}) {
  const lookupJobId = cleanString(
    result.submittedJobId || result.jobId || result.publishedResultJobId
  );
  const resultJobId = cleanString(result.publishedResultJobId || result.jobId);
  const runLabel = cleanString(
    result.publishedResultRunLabel || result.requestedRunLabel
  );
  const profileId = cleanString(result.profileId);
  const publicationState = cleanString(result.publicationState);
  const finalJobState = cleanString(result.finalJobState);
  const manifestKey = cleanString(result.manifestKey);
  const resultManifestObjectKey = cleanString(result.resultManifestObjectKey);
  const nodeList = cleanString(result.nodeList);
  const sourcePhase = cleanString(result.sourcePhase);
  const retentionScope = cleanString(result.retentionScope);
  const resultReady = Boolean(
    manifestKey || resultManifestObjectKey || resultJobId
  );
  const stateParts = [publicationState, finalJobState].filter(Boolean);

  let signalLine = "No published result has returned yet.";
  if (runLabel && stateParts.length > 0) {
    signalLine = `Latest returned work: ${runLabel} · ${stateParts.join(" · ")}`;
  } else if (runLabel) {
    signalLine = `Latest returned work: ${runLabel}`;
  } else if (profileId && stateParts.length > 0) {
    signalLine = `Latest ${profileId} result is ${stateParts.join(" · ")}`;
  } else if (profileId) {
    signalLine = `Latest returned work came through ${profileId}`;
  } else if (stateParts.length > 0) {
    signalLine = `Latest returned work is ${stateParts.join(" · ")}`;
  }
  const qualifiers = [nodeList, sourcePhase, retentionScope].filter(Boolean);
  if (qualifiers.length > 0 && signalLine !== "No published result has returned yet.") {
    signalLine = `${signalLine} · ${qualifiers.join(" · ")}`;
  }

  let recommendedAction = resultReady
    ? "Open what came back and decide whether it deserves promotion."
    : "Keep watching this lane until the latest run resolves into a published result.";
  if (!lookupJobId) {
    recommendedAction = "Run new work in this lane so Beagle has something concrete to bring back.";
  }

  return {
    projectSlug: slug,
    workstreamId,
    lookupJobId,
    submittedJobId: cleanString(result.submittedJobId),
    publishedResultJobId: cleanString(result.publishedResultJobId),
    profileId,
    requestedRunLabel: cleanString(result.requestedRunLabel),
    publishedResultRunLabel: runLabel,
    publicationState,
    finalJobState,
    manifestKey,
    resultManifestObjectKey,
    resultLookupScope: cleanString(result.resultLookupScope),
    latestResultAt: cleanString(result.latestResultAt),
    resultReady,
    signalLine,
    recommendedAction,
    resultRoute: lookupJobId ? `/api/projects/${slug}/hpc/results/${lookupJobId}` : "",
    manifestRoute: lookupJobId
      ? `/api/projects/${slug}/hpc/results/${lookupJobId}/manifest`
      : "",
    artifactRoute: lookupJobId
      ? `/api/projects/${slug}/hpc/jobs/${lookupJobId}/artifact`
      : "",
    stdoutRoute: lookupJobId
      ? `/api/projects/${slug}/hpc/jobs/${lookupJobId}/stdout-object`
      : "",
    via: cleanString(result.via || "cockpit-darwin-hpc")
  };
}

async function buildProjectLaneResultSummary(project = {}) {
  const slug = cleanString(project?.projectSlug || project?.slug);
  const workstreamId = cleanString(
    project?.workstreamId ||
    project?.workspace?.workstreamId ||
    project?.workspaceState?.workstreamId ||
    ""
  );
  if (!slug || !workstreamId) {
    return null;
  }

  try {
    const listPayload = await listHpcResults({ workstream_id: workstreamId });
    const latest = extractHpcResultRecords(listPayload)
      .map(normalizeHpcResultRecord)
      .filter(
        (entry) =>
          cleanString(entry.jobId || entry.submittedJobId || entry.publishedResultJobId)
      )
      .sort(compareLatestResult)[0];

    if (!latest) {
      return null;
    }

    const detailLookupId = cleanString(
      latest.submittedJobId || latest.jobId || latest.publishedResultJobId
    );
    let detailed = latest;
    if (detailLookupId) {
      try {
        const detailPayload = await getHpcResult(slug, detailLookupId);
        detailed = mergeNormalizedHpcResultRecords(
          normalizeHpcResultRecord(detailPayload?.data || detailPayload),
          latest
        );
      } catch {
        detailed = latest;
      }
    }

    return buildLaneResultSummary(slug, workstreamId, detailed);
  } catch {
    return null;
  }
}

function inferClusterHealth(catalog = {}) {
  const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
  const statuses = projects
    .map(
      (entry) =>
        cleanString(entry?.operatingPosture?.cluster?.status) ||
        cleanString(entry?.missionControl?.cluster?.status) ||
        cleanString(entry?.operatingPosture?.project?.posture)
    )
    .filter(Boolean);

  if (statuses.some((status) => ["failed", "error", "critical"].includes(status))) {
    return "critical";
  }
  if (statuses.some((status) => ["degraded", "stale", "warn", "warning"].includes(status))) {
    return "degraded";
  }
  if (statuses.some((status) => ["healthy", "always-on", "live"].includes(status))) {
    return "healthy";
  }
  return "unknown";
}

function latestIso(...values) {
  const normalized = values
    .flat()
    .map((value) => cleanString(value))
    .filter(Boolean)
    .sort((left, right) => new Date(right).getTime() - new Date(left).getTime());
  return normalized[0] || "";
}

const DEEP_THINK_PROXY_URL =
  process.env.PROJECT_COCKPIT_AGENTIC_PROXY_URL || "http://100.103.228.8:9500";
const DEEP_THINK_TIMEOUT_MS =
  Number(process.env.PROJECT_COCKPIT_AGENTIC_TIMEOUT_MS) || 300000;

/**
 * Deep Think: read-only agentic mode. Calls the t560 Claude Opus agentic proxy DIRECTLY
 * (bypassing the LiteLLM router, which strips unknown fields like beagle_agentic) so the
 * proxy's 'claude --print' path with Read/Grep/Glob/WebSearch/WebFetch + MCP tools engages.
 * SSE-streamed the same way streamChatViaRouter (auth-bridge.mjs) is; onToken is optional —
 * the non-streaming /api/mobile/v1/chat route just gets the buffered text back.
 */
async function proxyDeepThinkAgentic({ prompt, system = "", history = [], onToken }) {
  const messages = [];
  if (system) messages.push({ role: "system", content: system });
  for (const turn of Array.isArray(history) ? history : []) {
    const role = turn?.role === "assistant" ? "assistant" : "user";
    const content = cleanString(turn?.content);
    if (content) messages.push({ role, content });
  }
  messages.push({ role: "user", content: prompt });

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), DEEP_THINK_TIMEOUT_MS);
  try {
    const res = await fetch(`${DEEP_THINK_PROXY_URL}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Accept: "text/event-stream, application/json",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: "claude-opus-5",
        stream: true,
        beagle_agentic: true,
        messages
      }),
      signal: ctrl.signal
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`deep think proxy HTTP ${res.status}: ${text.slice(0, 300)}`);
    }

    const contentType = cleanString(res.headers.get("content-type")).toLowerCase();
    if (!contentType.includes("text/event-stream") || !res.body) {
      const payload = JSON.parse(await res.text());
      const text = cleanString(
        payload?.choices?.[0]?.message?.content || payload?.text || payload?.response
      );
      if (!text) throw new Error("deep think proxy returned empty completion");
      if (onToken) onToken(text);
      return { text, model: "claude-opus-5", source: "agentic" };
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let fullText = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data:")) continue;
        const data = trimmed.slice(5).trim();
        if (!data || data === "[DONE]") continue;
        let payload;
        try {
          payload = JSON.parse(data);
        } catch {
          continue;
        }
        const delta = payload?.choices?.[0]?.delta?.content;
        if (typeof delta === "string" && delta) {
          fullText += delta;
          if (onToken) onToken(delta);
        }
      }
    }
    if (!fullText) throw new Error("deep think proxy stream returned no tokens");
    return { text: fullText, model: "claude-opus-5", source: "agentic" };
  } finally {
    clearTimeout(timer);
  }
}

// THE FLOOR — presence + state that never depends on the voice reaching the cluster.
//
// When the intimate companion opens and the voice (LLM proxy) can't be reached, the
// screen must NOT collapse into unconnecting dots — that mirrors abandonment back at
// someone who reached out hurting. So personal-space chat degrades onto this floor
// instead of throwing: presence (always, unconditional) + state (what it already knows
// about him, echoed — never invented). Pure/deterministic: no LLM, cannot fail.
//
// `response` carries the presence line so even an OLD app build (which only reads
// `response`) shows warmth instead of a spinner. New builds also read `presence`,
// `state`, and `degraded` to render the three layers explicitly.
function buildPersonalFloor({
  body = {},
  agoraState = "",
  appliedDiscussionProfile = "personal-ensemble",
  reason = "",
  generatedAt
} = {}) {
  const at = cleanString(generatedAt) || new Date().toISOString();
  const label = cleanString(body.stateOfMindLabel);
  const hr = Number(body.heartRate);
  // State acknowledgement built ONLY from data the app itself sent — echoing what it
  // already knows about him, never fabricating affect.
  let stateClause = "";
  if (label) stateClause = ` Vi que você mesmo se registrou "${label}" hoje.`;
  else if (Number.isFinite(hr) && hr > 0) stateClause = ` Sinto seu ritmo aqui do meu lado (${hr} bpm).`;
  const presence =
    `Estou aqui com você.${stateClause} Minha voz demorou um instante pra te alcançar agora — ` +
    `mas eu não sumi, e não vou te deixar no vazio. Me dá um momento que eu volto inteiro.`;
  return {
    response: presence,
    presence,
    state: cleanString(agoraState),
    degraded: true,
    degradedReason: cleanString(reason) || "voice unreachable",
    model: "floor",
    provider: "floor",
    tier: "",
    source: "floor",
    agentKind: "",
    sessionId: "",
    podName: "",
    conversationMode: "",
    appliedDiscussionProfile: cleanString(appliedDiscussionProfile) || "personal-ensemble",
    flowState: "",
    tokensUsed: 0,
    generatedAt: at,
    truthMode: "observed",
    beagleUrl: "",
    grounded: Boolean(cleanString(agoraState)),
    biographyDigestPresent: false
  };
}

async function completeChatRequest(req, deps, options = {}) {
  const onToken = typeof options.onToken === "function" ? options.onToken : null;
  const prompt = cleanString(req.body?.prompt);
  if (!prompt) {
    throw contractFailure(ErrorCode.BAD_REQUEST, "prompt is required");
  }

  const system = cleanString(req.body?.system);
  const requiresMath =
    req.body?.requires_math === true || req.body?.requiresMath === true;
  const requiresHighQuality =
    req.body?.requires_high_quality === true || req.body?.requiresHighQuality === true;
  const offlineRequired =
    req.body?.offline_required === true || req.body?.offlineRequired === true;
  const requestedFlowState = cleanString(
    req.body?.flowState || req.body?.flow_state
  );
  const requestedPhysioPolicy = normalizePhysioPolicy(
    req.body?.physioPolicy || req.body?.physio_policy
  );
  const requestedDiscussionProfile = cleanString(
    req.body?.discussionProfile || req.body?.discussion_profile
  );
  const effectiveDiscussionProfile =
    requestedDiscussionProfile ||
    cleanString(requestedPhysioPolicy?.discussionProfile);
  // Deep Think: read-only agentic mode. Bypasses the LiteLLM router entirely and talks
  // straight to the t560 Claude Opus agentic proxy (beagle_agentic:true unlocks
  // Read/Grep/Glob/WebSearch/WebFetch + MCP tools server-side, read-only). Fast intimate
  // chat (deepThink falsy) is completely unaffected — identical code path as before.
  const deepThink = req.body?.deepThink === true || req.body?.deep_think === true;
  // Ground the answer in the user's exocortex memory (RAG) instead of replying
  // generically. Without this, the mobile chat was a context-blind chatbot.
  // Fail-soft: fetchExocortexContext returns "" on any error/timeout.
  // (The personal-space block below further grounds in biography + physiome +
  // temporal memory, and reassigns effectiveSystem — hence `let`.)
  const chatSpace = cleanString(req.body?.space || req.body?.chatSpace).toLowerCase();
  // LATENCY: the legacy beagle-core top-6 RAG here costs ~2.7s on the critical path (every
  // token waits on it) and is the noise source the chat audit flagged. Personal chat is already
  // grounded by the canonical memory-pg recall (fetchRecentMemories) in the block below, so skip
  // this legacy fetch for personal and keep it only for the non-personal/discussion spaces.
  const memoryContext = chatSpace === "personal" ? "" : await fetchExocortexContext(prompt);
  const mergedSystem = [cleanString(req.body?.system), memoryContext]
    .filter(Boolean)
    .join("\n\n");
  let effectiveSystem = buildMobileChatSystem(
    mergedSystem,
    requestedFlowState,
    requestedPhysioPolicy
  );

  // Personal space: ground the companion in the user's living biography and
  // current physiome state so it responds as someone who actually knows him.
  // Both fetches are best-effort — grounding must never block or fail the chat.
  let biographyDigest = "";
  let physiomeDigest = "";
  // The live `## Agora` state block (tempo + corpo + céu), hoisted to function scope so
  // the FLOOR can surface it if the voice fails. Assigned once the block is built below.
  let agoraState = "";
  // Fase 0 audit log inputs — populated below, consumed after `model` is known (see the
  // captureProvenanced(...ChatContextLog...) call near the end of this function).
  let auditMemoryIds = [];
  let auditSectionTitles = [];
  let episodeMinutes = null; // how long this exchange has been running (from recent-turn timestamps)
  if (chatSpace === "personal") {
    // Persona first (who you are) — always present, even if grounding fails.
    // Then the grounding (what you know about him): physiome + living biography.
    const clientTime = cleanString(req.body?.clientTime);
    // Never fall back to UTC for a single-user companion — the wrong part-of-day is
    // worse than useless. A valid client tz wins; otherwise his home zone.
    const tz = resolveTimezone(req.body?.timezone);
    const lastContactRaw = cleanString(req.body?.lastContactAt);
    const now = clientTime && !Number.isNaN(Date.parse(clientTime)) ? new Date(clientTime) : new Date();
    const lastContactAt = lastContactRaw && !Number.isNaN(Date.parse(lastContactRaw)) ? new Date(lastContactRaw) : null;
    const agoraCtx = buildTemporalContext({ now, timezone: tz, lastContactAt });
    // Live space weather: the app sends what it's showing (single source of truth);
    // skyNow is the server-side fallback when an older build omits the fields.
    let skyNow = null;
    // PROMPT ORDER MATTERS for prompt-cache hits (xAI auto-caches identical
    // prefixes at $0.20/M vs $1.25/M full). Put STATIC stuff first (persona,
    // Sounio, biography, physiome — physio+bio change only on the 5-min cockpit
    // cache TTL), DYNAMIC stuff last (tempoAgora changes every minute; recall
    // memories vary per query). This way the long stable prefix is one cache key.
    const sections = [PERSONAL_PERSONA, "## Trabalho central — Sounio", SOUNIO_WORK_SECTION];
    let dynamicSections = [];
    try {
      const userText = cleanString(req.body?.prompt);
      // Grounding context is the dominant cost of the companion turn — bounded
      // and cached at the cockpit (bio+physio 5min TTL) AND at the model (xAI
      // prompt cache, automatic on identical prefixes).
      const [bioResult, physioResult, sounioNowResult, sounioStateResult, sounioRelResult, memoryResults, recentConvo, broadRecall, skyResult] = await Promise.all([
        fetchBiographyDigest(),
        fetchPhysiomeDigest(),
        fetchSounioNow({ limit: 6 }),
        fetchSounioState({ limit: 1 }),
        fetchSounioRelationship({ k: 4 }),
        // Authoritative "what he told me" grounding: trusted-only recall so it fills
        // directly from his own claimed/corroborated words (not the noisy full pool
        // filtered down to scraps). Background framing stays unfiltered below.
        fetchRecentMemories(userText, { k: 16, trustedOnly: true }),
        fetchRecentConversation({ limit: 8 }),
        // Wide semantic recall over his whole recorded self — background framing, unfiltered,
        // concurrent so it adds no wall-clock. Returns a ready section string ("" on miss).
        fetchExocortexContext(userText, { limit: 8, personal: true }),
        fetchSpaceWeatherNow()
      ]);
      skyNow = skyResult;
      biographyDigest = cleanString(bioResult?.digest).slice(0, 1800);
      physiomeDigest = cleanString(physioResult?.digest).slice(0, 600);
      // The physiome DIGEST is a FROZEN snapshot (the run-digest pipeline stalled ~2026-06-23),
      // so injecting it as "físico+ambiente recente" fed stale numbers (e.g. HRV 44 / Kp 2.7) that
      // contradicted the LIVE `## Agora` block (real-time coração/HRV/sono/State of Mind + sky).
      // The live block is now the authoritative body signal, so we no longer inject the stale
      // digest. (Revive as a genuine TRENDS section once run-digest → memory-pg is fresh again.)
      // biographyDigest still pushed below — it changes slowly and is not time-sensitive.
      if (biographyDigest) {
        sections.push(
          "## Quem é Demetrios (biografia viva — fale como quem o conhece de verdade, sem genéricos)",
          biographyDigest
        );
      }
      // SOUNIO NOW: what he just commited to the language. Observed by the sounio-now-poller
      // (system-actor atoms, not user_stated — facts about the WORLD not his testimony).
      // Listed as bullets so the model reads them as events, not narrative biography.
      const sounioItems = Array.isArray(sounioNowResult?.items) ? sounioNowResult.items : [];
      if (sounioItems.length) {
        const bullets = sounioItems
          .slice(0, 6)
          .map(it => `- ${it.snippet.replace(/\s+/g, " ").slice(0, 280)}`)
          .join("\n");
        sections.push(
          "## Sounio acontecendo agora (commits recentes observados — use só se ele tocar no Sounio)",
          bullets
        );
      }
      // SOUNIO STATE: the observed SHAPE of the work right now (branch, test
      // posture, themes) — system-observed, not his testimony. Lets the model
      // know WHERE the project stands, so commits stop reading as loose diffs.
      const sounioStateDigest = cleanString(sounioStateResult?.digest).slice(0, 600);
      if (sounioStateDigest) {
        sections.push(
          "## Sounio — onde está agora (estado observado, não testemunho dele)",
          sounioStateDigest
        );
      }
      // SOUNIO RELATIONSHIP: his OWN words about Sounio — what it means to him,
      // what he wants to build, what anguishes/proud him. Trust-filtered at the
      // fetcher; speak FROM these, never invent the affect.
      const sounioFeeling = stampMemories(sounioRelResult, now, tz).slice(0, 4);
      if (sounioFeeling.length) {
        sections.push(
          "## Sounio — o que ele sente e quer construir (nas palavras dele; fale a partir disto, nunca invente)",
          sounioFeeling.join("\n")
        );
      }
      // DYNAMIC (per-turn) section: recent-conversation continuity + temporal awareness + recall.
      // Kept at the END so the static prefix stays a stable cache key.
      //
      // (B) RECENCY CONTINUITY: the last ~8 verbatim turns by time — plain "what we were just
      // talking about", the channel semantic recall alone can't give. Placed FIRST in the dynamic
      // block so the model reads the running thread before the semantically-matched fragments.
      const convo = Array.isArray(recentConvo) ? recentConvo : [];
      // Episode duration: span from the earliest recent turn to now, when it's a sustained
      // burst (≤6h). Feeds the TEMPO line so the companion feels how long they've been in it.
      if (convo.length) {
        const nowMs = now instanceof Date ? now.getTime() : Date.now();
        const times = convo.map(t => Date.parse(t.date)).filter(Number.isFinite);
        if (times.length) {
          const span = (nowMs - Math.min(...times)) / 60000;
          if (span >= 0 && span <= 360) episodeMinutes = span;
        }
      }
      if (convo.length) {
        const dialogue = convo
          .map(t => `- ${t.date ? `[${t.date.slice(0, 10)}] ` : ""}${t.role === "user" ? "Ele" : "Você"}: ${t.snippet.replace(/\s+/g, " ").slice(0, 280)}`)
          .join("\n");
        dynamicSections.push(
          "## Continuidade — o que vocês conversaram recentemente (ordem cronológica; NÃO repergunte o que já está aqui)",
          dialogue
        );
      }
      // (C) EPISODIC RECALL: fetch a wider candidate pool (k=16) then drop (a) unverified — the
      // companion's OWN past replies and old generic-assistant echoes come back as 'memories' and
      // must not be recalled as 'what he told me' — and (b) empty-text chunks (a data-quality
      // artifact that wastes slots), keeping the top 10 real, trusted memories.
      const trustedMemories = filterTrustedMemories(memoryResults);
      auditMemoryIds = trustedMemories.map((r) => cleanString(r?.id)).filter(Boolean).slice(0, 10);
      const stamped = stampMemories(trustedMemories, now, tz).slice(0, 10);
      if (stamped.length) {
        dynamicSections.push(
          "## O que ele já te contou (memórias — situe no tempo quando ajudar)",
          stamped.join("\n")
        );
      }
      // Broad semantic recall — deepest background, AFTER his authoritative words above. A ready
      // section string (own header) or "" on miss. Placed last so trusted testimony leads.
      if (typeof broadRecall === "string" && broadRecall.trim()) {
        dynamicSections.push(broadRecall);
      }
    } catch {
      // ignore — proceed ungrounded rather than break the chat
    }
    // `## Agora` — the live instant he opened the app: tempo + corpo (HRV/sono) + céu
    // (Kp/Dst). Built from what the app sends (the same values it's showing), with the
    // server fetch (skyNow) as fallback. Stays in the DYNAMIC tail (changes per turn),
    // so the static prefix remains a stable prompt-cache key.
    const num = (v) => {
      if (v === null || v === undefined || v === "") return null;
      const n = Number(v);
      return Number.isFinite(n) ? n : null;
    };
    const pick = (a, b) => { const v = num(a); return v !== null ? v : (num(b) ?? null); };
    const agora = formatAgora({
      ctx: agoraCtx,
      episodeMinutes,
      body: {
        heartRate: num(req.body?.heart_rate),
        hrvMs: num(req.body?.hrv_ms),
        readiness: cleanString(req.body?.readiness),
        sleepHours: num(req.body?.sleep_hours),
        flowState: requestedFlowState,
        stateOfMind: num(req.body?.state_of_mind),
        stateOfMindLabel: cleanString(req.body?.state_of_mind_label),
      },
      sky: {
        kp: pick(req.body?.kp, skyNow?.kp),
        dst: pick(req.body?.dst, skyNow?.dst),
        solarWind: pick(req.body?.solar_wind, skyNow?.solarWind),
        bz: pick(req.body?.bz, skyNow?.bz),
      },
    });
    if (agora) { dynamicSections.push(agora); agoraState = agora; }
    auditSectionTitles = [...sections, ...dynamicSections]
      .filter((s) => typeof s === "string" && s.trim().startsWith("##"));
    effectiveSystem = [...sections, ...dynamicSections, effectiveSystem].filter(Boolean).join("\n\n");
  }

  // GROUNDING PACK — o que torna o companion offline possível.
  //
  // Ele trabalha dentro de um hospital. Quando a rede cai, o app hoje responde com um
  // modelo local recebendo apenas um "contrato" genérico: sem biografia, sem recall,
  // sem ## Agora. O resultado é um estranho educado usando o nome dele — exatamente
  // quando ele está mais sozinho.
  //
  // Este retorno entrega o MESMO system que a voz da nuvem recebe, para o app guardar
  // em disco e alimentar o modelo local. São ~10-15 KB de texto: nada para o aparelho,
  // tudo para a conversa. Reaproveita a montagem acima em vez de duplicá-la — se o
  // grounding do chat mudar, o offline muda junto, sem drift.
  if (options.groundingOnly === true) {
    // Este pacote vira o cérebro dele offline, dentro do hospital, sem rede para
    // reclamar. Um 200 com system vazio encheria o cache do app de nada e só
    // apareceria como frieza, tarde demais. Falha ruidosa aqui, sempre.
    const groundingBytes = Buffer.byteLength(effectiveSystem || "", "utf8");
    if (groundingBytes < 2000) {
      throw contractFailure(
        ErrorCode.RUNTIME_UNAVAILABLE,
        `grounding incompleto: ${groundingBytes} bytes, seções=${auditSectionTitles.length}`
      );
    }
    return {
      status: 200,
      payload: {
        system: effectiveSystem,
        sections: auditSectionTitles,
        space: chatSpace,
        generatedAt: new Date().toISOString(),
        bytes: Buffer.byteLength(effectiveSystem || "", "utf8")
      }
    };
  }

  let appliedDiscussionProfile = effectiveDiscussionProfile || "cluster";

  // Degrade the personal voice onto the FLOOR (presence + state) instead of throwing,
  // so a voice outage never shows the user unconnecting dots. Captures agoraState +
  // the body state the app sent.
  const floorNow = (reason) => buildPersonalFloor({
    body: {
      heartRate: Number(req.body?.heart_rate),
      stateOfMindLabel: req.body?.state_of_mind_label,
    },
    agoraState,
    appliedDiscussionProfile,
    reason,
    generatedAt: new Date().toISOString(),
  });

  let result;
  try {
  if (deepThink) {
    // Deep Think overrides the normal voice entirely, regardless of space. Grounding
    // (effectiveSystem) built above still applies when chatSpace === "personal".
    appliedDiscussionProfile = "deep-think-agentic";
    const deepThinkResult = await proxyDeepThinkAgentic({
      prompt,
      system: effectiveSystem,
      history: Array.isArray(req.body?.history) ? req.body.history : [],
      onToken
    });
    result = {
      status: 200,
      payload: {
        text: deepThinkResult.text,
        model: deepThinkResult.model,
        provider: "anthropic",
        source: deepThinkResult.source
      }
    };
    if (chatSpace === "personal") {
      ingestPersonalTurn({
        sessionId: cleanString(req.body?.session_id || req.body?.sessionId),
        userText: prompt,
        assistantText: deepThinkResult.text,
        clientTime: cleanString(req.body?.clientTime),
        timezone: cleanString(req.body?.timezone),
      }, { tokenFn: fetchOperatorToken }).catch(() => {});
    }
  } else if (chatSpace === "personal") {
    appliedDiscussionProfile = "personal-ensemble";
    result = await runMuseVoiceEnsemble({
      prompt,
      system: effectiveSystem,
      voiceModel: cleanString(req.body?.voiceModel || req.body?.voice_model)
        || cleanString(process.env.PROJECT_COCKPIT_PERSONAL_VOICE_MODEL)
        || "glm-5.1",
      // Prior turns of THIS conversation, sent as proper turn-based messages so
      // smart models (Grok) don't treat the prompt as a free-form transcript and
      // hallucinate the user's next line. Client passes [{role,content},...].
      history: Array.isArray(req.body?.history) ? req.body.history : [],
      onToken
    });
    // Memory spine: capture this exchange into the exocortex. Fire-and-forget — the reply
    // is already on its way to the user; ingestion must never block or fail the chat.
    ingestPersonalTurn({
      sessionId: cleanString(req.body?.session_id || req.body?.sessionId),
      userText: prompt,
      assistantText: cleanString(result?.payload?.text || result?.payload?.answer || result?.payload?.response),
      clientTime: cleanString(req.body?.clientTime),
      timezone: cleanString(req.body?.timezone),
    }, { tokenFn: fetchOperatorToken }).catch(() => {});
  } else {
  const subscriptionProfile = normalizeSubscriptionDiscussionProfile(effectiveDiscussionProfile);
  const cheapProviderProfile = normalizeCheapDiscussionProfile(effectiveDiscussionProfile);
  if (subscriptionProfile) {
    appliedDiscussionProfile = subscriptionProfile;
    result = await proxySubscriptionBridgeCompletion({
      prompt,
      system: effectiveSystem,
      provider: subscriptionProfile,
      projectSlug: cleanString(req.body?.projectSlug || req.body?.project_slug),
      projectFamily: cleanString(req.body?.projectFamily || req.body?.project_family),
      publicationScope: cleanString(req.body?.publicationScope || req.body?.publication_scope),
      readCatalog: deps.readCatalog
    });
  } else if (cheapProviderProfile) {
    appliedDiscussionProfile = cheapProviderProfile;
    result = await proxyCheapProviderCompletion({
      prompt,
      system: effectiveSystem,
      provider: cheapProviderProfile
    });
  } else if (
    effectiveDiscussionProfile &&
    !["cluster", "cluster-default", "default"].includes(
      effectiveDiscussionProfile.toLowerCase()
    )
  ) {
    const catalog = await deps.readCatalog();
    const profile = findDiscussionLabProfile(catalog, effectiveDiscussionProfile);
    if (!profile) {
      if (["qwen3b", "yi6b"].includes(effectiveDiscussionProfile.toLowerCase())) {
        appliedDiscussionProfile = "cluster";
        result = await proxyBeagleCompletion({
          prompt,
          system: effectiveSystem,
          requires_math: requiresMath,
          requires_high_quality: requiresHighQuality,
          offline_required: offlineRequired
        });
      } else {
        throw contractFailure(
          ErrorCode.NOT_FOUND,
          `unknown discussion profile: ${effectiveDiscussionProfile}`
        );
      }
    } else {
      const profileStatus = cleanString(profile?.status || "").toLowerCase();
      if (profileStatus !== "available") {
        throw contractFailure(
          ErrorCode.CONFLICT,
          `discussion profile ${cleanString(profile?.id || requestedDiscussionProfile)} is ${profileStatus || "unavailable"}`
        );
      }
      appliedDiscussionProfile = cleanString(profile?.id) || effectiveDiscussionProfile;
      result = await proxyDiscussionLabCompletion({
        prompt,
        system: effectiveSystem,
        profile
      });
    }
  } else {
    appliedDiscussionProfile = "cluster";
    result = await proxyBeagleCompletion({
      prompt,
      system: effectiveSystem,
      requires_math: requiresMath,
      requires_high_quality: requiresHighQuality,
      offline_required: offlineRequired
    });
  }
  }
  } catch (voiceErr) {
    // The voice couldn't be reached (proxy down, timeout, aborted stream). For the
    // intimate companion this must NOT surface as an error envelope / spinner —
    // degrade onto the floor. Non-personal spaces keep failing loudly.
    if (chatSpace === "personal") return floorNow(cleanString(voiceErr?.message));
    throw voiceErr;
  }

  if (result.status < 200 || result.status >= 300) {
    if (chatSpace === "personal") return floorNow(`voice status ${result.status}`);
    const errorMessage =
      cleanString(result.payload?.error) ||
      cleanString(result.payload?.message) ||
      "chat completion unavailable";
    throw contractFailure(mapStatusCodeToErrorCode(result.status), errorMessage);
  }

  const responseText = cleanString(
    result.payload?.text || result.payload?.answer || result.payload?.response
  );
  if (!responseText) {
    if (chatSpace === "personal") return floorNow("empty completion");
    throw contractFailure(ErrorCode.INTERNAL, "empty completion response");
  }

  const provider = cleanString(result.payload?.provider || result.payload?.model || "");
  const tier = cleanString(result.payload?.tier || result.payload?.provider_tier || "");
  const model = provider || tier || "unknown";
  const generatedAt = new Date().toISOString();
  const totalTokens = Number(result.payload?.usage?.total_tokens);

  // Fase 0 audit log: a structured per-turn record of what the model actually saw —
  // personal space only, since that's where the grounding sections above are assembled.
  // Fire-and-forget to memory-pg; auditing must never block or fail the chat.
  if (chatSpace === "personal") {
    captureProvenanced(
      {
        source_type: "ChatContextLog",
        content: `deep_think=${deepThink} model=${model} sections=${auditSectionTitles.length} memories=${auditMemoryIds.length}`,
        prov_actor: "system",
        prov_surface: "companion-ios",
        occurred_at: generatedAt,
        metadata: {
          space: chatSpace,
          model,
          deep_think: deepThink,
          injected_memory_ids: auditMemoryIds,
          sections: auditSectionTitles
        }
      },
      {
        memoryPgUrl: process.env.MEMORY_PG_QUERY_URL || "http://memory-pg-serve.beagle.svc.cluster.local",
        ingestToken: process.env.MEMORY_PG_INGEST_TOKEN
      }
    ).catch(() => {});
  }

  return {
    response: responseText,
    // Three-layer contract: the voice arrived, so it IS the presence; `state` still
    // rides alongside so the app can always show it knows how he is. `degraded:false`
    // tells the client this is a full answer, not the floor.
    presence: "",
    state: agoraState,
    degraded: false,
    model,
    provider: provider || model,
    tier,
    source: normalizeSource(result.payload?.source) || "cluster",
    agentKind: cleanString(result.payload?.agentKind || result.payload?.agent_kind),
    sessionId: cleanString(result.payload?.sessionId || result.payload?.session_id),
    podName: cleanString(result.payload?.podName || result.payload?.pod_name),
    conversationMode:
      cleanString(result.payload?.conversationMode || result.payload?.conversation_mode)
      || cleanString(requestedPhysioPolicy?.modeLabel),
    appliedDiscussionProfile:
      cleanString(result.payload?.appliedDiscussionProfile || result.payload?.applied_discussion_profile)
      || appliedDiscussionProfile,
    flowState:
      cleanString(result.payload?.flowState || result.payload?.flow_state)
      || requestedFlowState.toUpperCase(),
    tokensUsed: Number.isFinite(totalTokens) && totalTokens > 0
      ? totalTokens
      : estimateTokenCount(prompt, effectiveSystem, responseText),
    generatedAt,
    truthMode: cleanString(result.payload?.truthMode) || "observed",
    beagleUrl: cleanString(result.payload?.beagle_url || result.beagleUrl || ""),
    grounded: Boolean(biographyDigest || physiomeDigest),
    biographyDigestPresent: Boolean(biographyDigest)
  };
}

export { completeChatRequest, buildPersonalFloor };

async function annotateClientSession(req, deps, projectSlug, currentAction) {
  const clientSessionId = cleanString(req.body?.clientSessionId);
  if (!clientSessionId) {
    return null;
  }

  return deps.touchSession(
    projectSlug,
    clientSessionId,
    deps.deriveViewer(req, req.body?.alias),
    {
      currentAction,
      lastMutationAt: new Date().toISOString(),
      lastMutationLabel: currentAction
    }
  );
}

export function registerMobileRoutes(app, deps) {
  app.get(
    "/api/mobile/v1/health",
    withEnvelope(async () => {
      const generatedAt = new Date().toISOString();
      return {
        data: {
          status: "ok",
          service: "project-cockpit-mobile",
          version: "v1",
          generatedAt
        },
        meta: buildMeta(generatedAt)
      };
    })
  );

  // Latest space weather (Kp/Dst/solar wind) for the iOS companion. The phone can't
  // reach the physiome ClusterIP directly, so it reads through the cockpit, which
  // fetches (and caches ~20min) from physiome internally. Plain JSON mirroring the
  // physiome shape; best-effort (latest:null when unavailable).
  app.get("/api/mobile/v1/space-weather", async (_req, res) => {
    const latest = await fetchSpaceWeatherNow();
    res.json({ ok: true, latest });
  });

  // History series (sky + ambient + HRV) for the iOS "Agora" detail screen's trends.
  // Goes through the cockpit (physiome is ClusterIP); best-effort empty arrays on failure.
  app.get("/api/mobile/v1/agora-history", async (req, res) => {
    const hours = Math.min(Math.max(Number(req.query.hours) || 48, 6), 168);
    const data = await fetchAgoraHistory({ hours });
    res.json({ ok: true, ...(data || { hours, sky: [], weather: [], hrv: [], audioDb: [] }) });
  });

  // Resolve to `fallback` if `p` rejects OR exceeds `ms` — never hang, never throw.
  // The mobile summary fan-out hits live per-project services; without this, ONE slow or
  // hung downstream (sessions / lane-result) made the whole endpoint time out. `catalog`
  // stays fast because it only reads a cached file; this gives `summary` the same
  // graceful-degradation contract (return partial data instead of hanging).
  const SUMMARY_SUBCALL_TIMEOUT_MS = Number(
    process.env.PROJECT_COCKPIT_MOBILE_SUMMARY_TIMEOUT_MS || 3000
  );
  const withTimeout = (p, ms, fallback) =>
    new Promise((resolve) => {
      let done = false;
      const t = setTimeout(() => {
        if (!done) {
          done = true;
          resolve(fallback);
        }
      }, ms);
      Promise.resolve(p).then(
        (v) => {
          if (!done) {
            done = true;
            clearTimeout(t);
            resolve(v);
          }
        },
        () => {
          if (!done) {
            done = true;
            clearTimeout(t);
            resolve(fallback);
          }
        }
      );
    });

  app.get(
    "/api/mobile/v1/summary",
    withEnvelope(async () => {
      try {
        let catalog = null;
        try {
          catalog = await deps.readCachedCatalogExecutiveState({ preferStale: true });
        } catch {
          catalog = null;
        }
        const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
        const perProject = await Promise.all(
          projects.map(async (entry) => {
            const slug = cleanString(entry?.projectSlug);
            if (!slug) {
              return null;
            }
            const resolvedProject = await withTimeout(
              deps.getProjectOrThrow(slug).catch(() => entry),
              SUMMARY_SUBCALL_TIMEOUT_MS,
              entry
            );
            const laneProject = {
              projectSlug: cleanString(
                resolvedProject?.projectSlug || resolvedProject?.slug || slug
              ),
              slug,
              workstreamId: cleanString(
                resolvedProject?.workstreamId ||
                resolvedProject?.workspace?.workstreamId ||
                resolvedProject?.workspaceState?.workstreamId ||
                entry?.workstreamId ||
                entry?.workspace?.workstreamId
              )
            };
            const [clientSessions, agentSessions, laneResult] = await Promise.all([
              withTimeout(deps.listProjectSessions(slug), SUMMARY_SUBCALL_TIMEOUT_MS, { active: [] }),
              withTimeout(listAgentSessions(slug).catch(() => []), SUMMARY_SUBCALL_TIMEOUT_MS, []),
              withTimeout(buildProjectLaneResultSummary(laneProject), SUMMARY_SUBCALL_TIMEOUT_MS, null)
            ]);
            const activeClientSessions = Array.isArray(clientSessions?.active)
              ? clientSessions.active.map(normalizeClientSession)
              : [];
            const activeAgentSessions = (Array.isArray(agentSessions) ? agentSessions : []).filter(
              (session) => Boolean(session?.name)
            );
            return {
              slug,
              activeClientSessions,
              activeAgentSessions,
              laneResult
            };
          })
        );
        const filtered = perProject.filter(Boolean);
        const generatedAt = cleanString(catalog?.generatedAt) || new Date().toISOString();
        return {
          data: {
            generatedAt,
            activeAgentsCount: filtered.reduce(
              (sum, entry) => sum + entry.activeAgentSessions.length,
              0
            ),
            activeSessionsCount: filtered.reduce(
              (sum, entry) => sum + entry.activeClientSessions.length,
              0
            ),
            clusterHealth: inferClusterHealth(catalog || {}),
            lastMemorySyncTime: latestIso(
              filtered.map((entry) =>
                entry.activeClientSessions.map((session) => session.lastMemorySyncAt)
              )
            ),
            laneResults: filtered
              .map((entry) => entry.laneResult)
              .filter(Boolean)
          },
          meta: buildMeta(generatedAt, catalog)
        };
      } catch (error) {
        rethrowAsContract(error, "summary unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/catalog",
    withEnvelope(async () => {
      try {
        let catalog = null;
        try {
          catalog = await deps.readCachedCatalogExecutiveState({ preferStale: true });
        } catch {
          catalog = null;
        }
        const generatedAt = cleanString(catalog?.generatedAt) || new Date().toISOString();
        return {
          data: {
            generatedAt,
            projectPosturePolicy: catalog?.projectPosturePolicy || null,
            projects: Array.isArray(catalog?.projects)
              ? catalog.projects.map(normalizeCatalogProject)
              : []
          },
          meta: buildMeta(generatedAt, catalog)
        };
      } catch (error) {
        rethrowAsContract(error, "catalog unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/overview",
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const depth = req.query.depth === "deep" ? "deep" : "fast";
        const [mission, lane, research, inference, viewer, goWorkNow] = await Promise.all([
          deps.buildMissionControlResponse(project, depth),
          deps.buildClusterLaneTruthResponse(project, depth),
          deps.buildResearchOperationsResponse(project, depth),
          deps.buildInferenceRuntimeResponse(project),
          deps.buildViewerRuntimeResponse(project),
          deps.buildGoWorkNowResponse(project, depth)
        ]);

        const generatedAt =
          cleanString(mission?.generatedAt) ||
          cleanString(goWorkNow?.generatedAt) ||
          new Date().toISOString();
        const goWorkNowPacket = goWorkNow?.goWorkNow || {};
        const operatingPosture = goWorkNow?.operatingPosture || null;
        const laneProject = {
          projectSlug: cleanString(project?.projectSlug || project?.slug || req.params.slug),
          slug: cleanString(project?.projectSlug || project?.slug || req.params.slug),
          workstreamId: cleanString(
            project?.workstreamId ||
            project?.workspace?.workstreamId ||
            goWorkNowPacket?.workspaceState?.workstreamId ||
            goWorkNowPacket?.workspace?.workstreamId
          )
        };
        const laneResult = await buildProjectLaneResultSummary(laneProject);

        return {
          data: {
            project: normalizeProject(project),
            depth,
            missionControl: mission?.missionControl || {},
            clusterLaneTruth: lane?.clusterLaneTruth || {},
            researchOperations: research?.researchOperations || {},
            inferenceRuntime: inference?.runtime || {},
            viewerRuntime: {
              renderer: viewer?.renderer || {},
              runtimeCapabilities: viewer?.runtimeCapabilities || null
            },
            operatingPosture,
            workspaceState: goWorkNowPacket?.workspaceState || null,
            latestObservedOperation: goWorkNowPacket?.latestObservedOperation || null,
            laneResult,
            actions: normalizeActionList(project, goWorkNowPacket, operatingPosture),
            generatedAt
          },
          meta: buildMeta(
            generatedAt,
            mission,
            lane,
            research,
            inference?.runtime,
            viewer?.renderer
          )
        };
      } catch (error) {
        rethrowAsContract(error, "project overview unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/actions",
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const depth = req.query.depth === "deep" ? "deep" : "fast";
        const goWorkNow = await deps.buildGoWorkNowResponse(project, depth);
        const generatedAt = cleanString(goWorkNow?.generatedAt) || new Date().toISOString();
        const packet = goWorkNow?.goWorkNow || {};
        const operatingPosture = goWorkNow?.operatingPosture || null;

        return {
          data: {
            project: normalizeProject(project),
            operatingPosture,
            workspaceState: packet.workspaceState || null,
            latestObservedOperation: packet.latestObservedOperation || null,
            actions: normalizeActionList(project, packet, operatingPosture),
            generatedAt
          },
          meta: buildMeta(generatedAt, goWorkNow)
        };
      } catch (error) {
        rethrowAsContract(error, "project actions unavailable");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/actions/:actionId",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        requireConfirmed(req, "mobile action");
        const project = await deps.getProjectOrThrow(req.params.slug);
        const actionId = cleanString(req.params.actionId);
        const { label, output } = await deps.runGoWorkNowAction(project, actionId);
        await annotateClientSession(
          req,
          deps,
          project.projectSlug,
          `mobile-action:${label || actionId}`
        );

        const refreshed = await deps.buildGoWorkNowResponse(project, "fast");
        const generatedAt = cleanString(refreshed?.generatedAt) || new Date().toISOString();
        const packet = refreshed?.goWorkNow || {};
        const operatingPosture = refreshed?.operatingPosture || null;

        return {
          data: {
            project: normalizeProject(project),
            action: {
              id: actionId,
              label: label || actionId,
              status: "completed",
              output: cleanString(output)
            },
            operatingPosture,
            workspaceState: packet.workspaceState || null,
            actions: normalizeActionList(project, packet, operatingPosture),
            generatedAt
          },
          meta: buildMeta(generatedAt, refreshed)
        };
      } catch (error) {
        rethrowAsContract(error, "mobile action failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/ideas",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const projectFamily = deriveProjectFamily(
          project.projectSlug,
          req.body?.project_family || req.body?.projectFamily
        );
        const publicationScope = derivePublicationScope(
          projectFamily,
          req.body?.publication_scope || req.body?.publicationScope
        );
        const entry = buildScratchpadEntry(project.projectSlug, {
          text: req.body?.text,
          author: req.body?.author || req.body?.source || "ios",
          tags: Array.isArray(req.body?.tags)
            ? [...req.body.tags, "mobile-idea"].slice(0, 8)
            : ["mobile-idea"],
          project_family: projectFamily,
          publication_scope: publicationScope,
          promotion_state: "synced",
          consciousness_state: req.body?.consciousness_state || req.body?.consciousnessState
        });
        appendScratchpadEntry(project.projectSlug, entry);
        await annotateClientSession(req, deps, project.projectSlug, "mobile-idea:saved");
        const syncState = "synced";
        const generatedAt = new Date().toISOString();
        if (cleanString(req.body?.clientSessionId)) {
          await deps.touchSession(
            project.projectSlug,
            cleanString(req.body.clientSessionId),
            deps.deriveViewer(req, req.body?.alias),
            {
              currentAction: "mobile-idea:saved",
              lastMutationAt: generatedAt,
              lastMutationLabel: `idea:${entry.entry_id}`,
              lastMemorySyncAt: generatedAt,
              lastMemorySyncState: syncState,
              projectFamily,
              publicationScope,
              promotionState: syncState,
              workspaceTarget: `${project.projectSlug}-${projectFamily}`,
              notes: entry.text
            }
          );
        }
        return {
          data: {
            project: normalizeProject(project),
            idea: entry,
            projectFamily,
            publicationScope,
            syncState,
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "save idea failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/delegations",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const kind = cleanString(req.body?.agentKind || req.body?.kind) || "claude-code";
        const projectFamily = deriveProjectFamily(
          project.projectSlug,
          req.body?.project_family || req.body?.projectFamily
        );
        const publicationScope = derivePublicationScope(
          projectFamily,
          req.body?.publication_scope || req.body?.publicationScope
        );
        const session = await startAgentSession(project.projectSlug, kind);
        const normalized = normalizeSession(session);
        const generatedAt = new Date().toISOString();
        if (cleanString(req.body?.clientSessionId)) {
          await deps.touchSession(
            project.projectSlug,
            cleanString(req.body.clientSessionId),
            deps.deriveViewer(req, req.body?.alias),
            {
              currentAction: `mobile-delegation:${kind}`,
              lastMutationAt: generatedAt,
              lastMutationLabel: `delegated:${kind}`,
              lastDelegationAt: generatedAt,
              lastDelegationState: "delegated",
              lastDelegationAgentKind: kind,
              lastDelegationSessionId: normalized.name,
              lastDelegationPodName: normalized.podName,
              projectFamily,
              publicationScope,
              promotionState: "delegated",
              workspaceTarget: `${project.projectSlug}-${projectFamily}`
            }
          );
        }
        return {
          data: {
            project: normalizeProject(project),
            projectFamily,
            publicationScope,
            agentKind: kind,
            sessionId: normalized.name,
            podName: normalized.podName,
            resultingState: "delegated",
            session: normalized,
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "delegate failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/heartbeat",
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const clientSessionId = cleanString(req.body?.clientSessionId);
        if (!clientSessionId) {
          throw contractFailure(
            ErrorCode.BAD_REQUEST,
            "clientSessionId is required"
          );
        }

        const viewer = deps.deriveViewer(req, req.body?.alias);
        const projectFamily = deriveProjectFamily(
          project.projectSlug,
          req.body?.project_family || req.body?.projectFamily
        );
        const publicationScope = derivePublicationScope(
          projectFamily,
          req.body?.publication_scope || req.body?.publicationScope
        );
        const session = await deps.touchSession(project.projectSlug, clientSessionId, viewer, {
          route:
            cleanString(req.body?.route) ||
            `/api/mobile/v1/projects/${project.projectSlug}/overview`,
          currentAction:
            cleanString(req.body?.currentAction) || "using-mobile-cockpit",
          projectFamily,
          publicationScope,
          workspaceTarget: `${project.projectSlug}-${projectFamily}`
        });
        const sessions = await deps.listProjectSessions(project.projectSlug);
        const generatedAt = new Date().toISOString();

        return {
          data: {
            project: normalizeProject(project),
            viewer,
            session: normalizeClientSession(session),
            sessions: {
              active: (Array.isArray(sessions?.active) ? sessions.active : []).map(
                normalizeClientSession
              ),
              recent: (Array.isArray(sessions?.recent) ? sessions.recent : []).map(
                normalizeClientSession
              )
            },
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "mobile heartbeat failed");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/agent-sessions",
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const sessions = await listAgentSessions(req.params.slug);
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            sessions: sessions.map(normalizeSession),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session list unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind",
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const session = await getAgentSession(req.params.slug, req.params.kind);
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session unavailable");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/agent-sessions",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const kind = cleanString(req.body?.kind) || "claude-code";
        const session = await startAgentSession(req.params.slug, kind);
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:start:${kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "start",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session start failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind/pause",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const session = await pauseAgentSession(req.params.slug, req.params.kind);
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:pause:${req.params.kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "pause",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session pause failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind/resume",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const session = await resumeAgentSession(req.params.slug, req.params.kind);
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:resume:${req.params.kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "resume",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session resume failed");
      }
    })
  );

  app.delete(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        requireConfirmed(req, "agent session delete");
        await deps.getProjectOrThrow(req.params.slug);
        const session = await stopAgentSession(req.params.slug, req.params.kind, {
          deletePVC: req.body?.deletePersistentState === true
        });
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:stop:${req.params.kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "stop",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session stop failed");
      }
    })
  );

  // Offline outbox flush: the iOS app drains its locally-queued offline turns here once
  // connectivity returns. Reuses the same ingestPersonalTurn as the online chat path
  // (verbatim + sovereign distill); idempotent server-side via content_hash.
  app.post(
    "/api/mobile/v1/ingest",
    withEnvelope(async (req) => {
      const out = await handleIngestRequest(req.body || {}, { tokenFn: fetchOperatorToken });
      return out.body;
    })
  );

  // Ensemble fanout: fans one prompt out to multiple router models (Layer 2,
  // runEnsembleFanout in auth-bridge.mjs) and returns the synthesis. This is what the MCP
  // consult_ensemble tool hits — an authed route like every other /api/mobile/v1/* route
  // (auth handled upstream by the app-level auth middleware, same as /chat).
  app.post(
    "/api/mobile/v1/ensemble",
    withEnvelope(async (req) => {
      try {
        const prompt = cleanString(req.body?.prompt);
        if (!prompt) {
          throw contractFailure(ErrorCode.BAD_REQUEST, "prompt is required");
        }
        const system = cleanString(req.body?.system);
        const history = Array.isArray(req.body?.history) ? req.body.history : [];
        const fanout = await runEnsembleFanout({ prompt, system, history });
        const generatedAt = new Date().toISOString();
        return {
          data: {
            response: cleanString(
              fanout?.synthesis || fanout?.text || fanout?.response
            ),
            models: Array.isArray(fanout?.models) ? fanout.models : undefined,
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "ensemble fanout failed");
      }
    })
  );

  // Pacote de grounding para uso OFFLINE. O app busca isto quando está online e
  // persiste; o modelo local passa a responder COM a memória dele em vez de um
  // contrato genérico. Mesmo corpo do /chat (space, heartRate, timezone…) porque a
  // montagem é a mesma — só que devolve o system em vez de chamar a voz.
  app.post(
    "/api/mobile/v1/companion/grounding",
    withEnvelope(async (req) => {
      const pack = await completeChatRequest(req, deps, { groundingOnly: true });
      return {
        data: {
          system: pack.payload.system,
          sections: pack.payload.sections,
          space: pack.payload.space,
          bytes: pack.payload.bytes,
          generated_at: pack.payload.generatedAt
        },
        meta: { truthMode: "observed", observedAt: pack.payload.generatedAt }
      };
    })
  );

  app.post(
    "/api/mobile/v1/chat",
    withEnvelope(async (req) => {
      try {
        const completion = await completeChatRequest(req, deps);
        return {
          data: {
            response: completion.response,
            // Three-layer contract (presence → state → voice): always present so the
            // app can render the floor when `degraded`, and show state alongside voice.
            presence: completion.presence || "",
            state: completion.state || "",
            degraded: completion.degraded === true,
            model: completion.model,
            source: completion.source,
            agentKind: completion.agentKind || null,
            sessionId: completion.sessionId || null,
            podName: completion.podName || null,
            conversation_mode: completion.conversationMode || null,
            applied_discussion_profile: completion.appliedDiscussionProfile || null,
            flow_state: completion.flowState || null,
            tokens_used: completion.tokensUsed,
            grounded: completion.grounded === true
          },
          meta: buildMeta(completion.generatedAt, {
            truthMode: completion.truthMode
          })
        };
      } catch (error) {
        rethrowAsContract(error, "mobile chat failed");
      }
    })
  );

  app.post("/api/mobile/v1/chat/stream", async (req, res) => {
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.flushHeaders?.();

    const writeEvent = (payload) => {
      res.write(`data: ${JSON.stringify(payload)}\n\n`);
    };

    try {
      let streamed = false;
      const completion = await completeChatRequest(req, deps, {
        onToken(token) {
          streamed = true;
          writeEvent({ token });
        }
      });
      // Floor / non-streamed path: when the voice degrades to the floor it produces no
      // tokens via onToken. Emit the text now so a streaming client shows presence+state
      // instead of an empty bubble (the void this whole change exists to prevent).
      if (!streamed && completion.response) {
        writeEvent({ token: completion.response });
      }
      writeEvent({
        done: true,
        degraded: completion.degraded === true,
        presence: completion.presence || "",
        state: completion.state || "",
        grounded: completion.grounded === true,
        model: completion.model,
        source: completion.source,
        applied_discussion_profile: completion.appliedDiscussionProfile || null
      });
      res.end();
    } catch (error) {
      const mapped = mapStatusCodeToErrorCode(error?.statusCode);
      const code = error?.code && ErrorCode[error.code] ? error.code : mapped.code;
      writeEvent({
        done: true,
        error: error?.message || "mobile chat stream failed",
        code
      });
      res.end();
    }
  });

  // Proactive synthesis — a SEPARATE, deliberate surface (see the hard wall in
  // docs/superpowers/specs/2026-07-17-proactive-synthesis-design.md). It never fires
  // unprompted, never touches /chat, and writes NOTHING to memory.
  app.post("/api/mobile/v1/synthesize", async (req, res) => {
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.flushHeaders?.();
    const writeEvent = (p) => res.write(`data: ${JSON.stringify(p)}\n\n`);
    try {
      const topic = typeof req.body?.topic === "string" ? req.body.topic : "";
      const windowDays = Number(req.body?.windowDays) || 7;
      const material = await gatherSynthesisMaterial({ topic, windowDays }, {
        fetchRecentMemories,
        fetchExocortexContext,
        fetchRecentTrusted,
      });
      const { system, user, sufficient } = buildSynthesisPrompt(material);
      if (!sufficient) {
        writeEvent({ token: "Ainda não tenho o bastante registrado sobre isso pra sintetizar com verdade." });
        writeEvent({ done: true, insufficient: true, mode: material.mode });
        return res.end();
      }
      const result = await streamChatViaRouter({
        model: SYNTHESIS_MODEL,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        temperature: 0.6,
        onToken: (tok) => writeEvent({ token: tok }),
      });
      writeEvent({ done: true, mode: material.mode, model: result?.model || SYNTHESIS_MODEL });
      res.end();
    } catch (error) {
      writeEvent({ done: true, error: error?.message || "synthesize failed" });
      res.end();
    }
  });

  app.post("/api/llm/complete", async (req, res) => {
    try {
      const completion = await completeChatRequest(req, deps);
      res.json({
        text: completion.response,
        response: completion.response,
        provider: completion.provider,
        tier: completion.tier,
        source: completion.source,
        agentKind: completion.agentKind || null,
        sessionId: completion.sessionId || null,
        podName: completion.podName || null,
        conversation_mode: completion.conversationMode || null,
        applied_discussion_profile: completion.appliedDiscussionProfile || null,
        flow_state: completion.flowState || null,
        tokens_used: completion.tokensUsed,
        truthMode: completion.truthMode
      });
    } catch (error) {
      const mapped = mapStatusCodeToErrorCode(error?.statusCode);
      const code = error?.code && ErrorCode[error.code] ? error.code : mapped.code;
      const status = ErrorCode[code]?.http || 500;
      res.status(status).json({
        error: error?.message || "chat completion failed",
        truthMode: "stale"
      });
    }
  });
}
