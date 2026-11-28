//
//  AppleDeviceToolsBridge.swift
//  BeagleCore
//
//  On-device Apple tool execution bridge (EventKit Calendar/Shifts, Reminders,
//  HealthKit/Physiome live telemetry, and deterministic Bula/PCDT SQLite lookup)
//  exposed natively inside the DirectBrain / MoE / Claude / FoundationModels loops.
//

import Foundation
#if canImport(Synchronization)
import Synchronization
#endif
#if canImport(EventKit) && !os(watchOS)
import EventKit
#endif

public final class AppleDeviceToolsBridge: @unchecked Sendable {
    public static let shared = AppleDeviceToolsBridge()

    public typealias LivePhysioProvider = @Sendable (_ refresh: Bool) async -> String

    #if canImport(Synchronization)
    private let livePhysioProvider = Mutex<LivePhysioProvider?>(nil)
    #else
    private let lock = NSLock()
    private var livePhysioProvider: LivePhysioProvider?
    #endif

    #if canImport(EventKit) && !os(watchOS)
    let eventStore = EKEventStore()
    #endif

    private init() {}

    public func registerLivePhysioProvider(_ provider: @escaping LivePhysioProvider) {
        #if canImport(Synchronization)
        livePhysioProvider.withLock { $0 = provider }
        #else
        lock.lock()
        livePhysioProvider = provider
        lock.unlock()
        #endif
    }

    private func currentPhysioProvider() -> LivePhysioProvider? {
        #if canImport(Synchronization)
        livePhysioProvider.withLock { $0 }
        #else
        lock.lock()
        defer { lock.unlock() }
        return livePhysioProvider
        #endif
    }

    // MARK: - Tool Metadata, Status & Provenance

    public static let nativeToolNames: Set<String> = [
        "apple_calendar_list_events",
        "apple_calendar_create_event",
        "apple_reminders_list",
        "apple_reminders_create",
        "apple_reminders_complete",
        "beagle_lookup_bula_pcdt",
        "apple_health_live_snapshot"
    ]

    public static func isNativeTool(_ name: String) -> Bool {
        nativeToolNames.contains(name)
    }

    public static func humanStatus(for toolName: String) -> String {
        switch toolName {
        case "apple_calendar_list_events":
            return "Consultando tua Agenda no iPhone…"
        case "apple_calendar_create_event":
            return "Agendando compromisso no Calendário…"
        case "apple_reminders_list":
            return "Lendo teus Lembretes no iPhone…"
        case "apple_reminders_create":
            return "Criando lembrete no iPhone…"
        case "apple_reminders_complete":
            return "Concluindo lembrete no iPhone…"
        case "beagle_lookup_bula_pcdt":
            return "Consultando Bula & PCDT verbatim…"
        case "apple_health_live_snapshot":
            return "Lendo sinais ao vivo no HealthKit…"
        case "beagle_search_memory":
            return "Buscando na memória do cluster…"
        case "beagle_store_memory":
            return "Gravando na memória do cluster…"
        case "beagle_search_pubmed":
            return "Pesquisando artigos e abstracts no PubMed (NCBI)…"
        case "beagle_lookup_scientific_work":
            return "Consultando DOI / Crossref / arXiv…"
        case "beagle_read_url":
            return "Lendo página ou artigo no link…"
        case "beagle_web_search":
            return "Pesquisando na web ao vivo…"
        case "openai_web_search":
            return "Pesquisando na web nativa (OpenAI)…"
        case "openai_tool_search":
            return "Carregando ferramentas sob demanda (Tool Search)…"
        case "delegate_to_grok_bot":
            return "Acionando rotina do Grok Bot via Webhook…"
        case "list_grok_bot_routines":
            return "Listando rotinas do Grok Bot…"
        default:
            return "MCP · \(toolName)…"
        }
    }

    public static func provenanceBadges(for executedTools: [String]) -> [String] {
        var seen: Set<String> = []
        var badges: [String] = []
        func add(_ label: String) {
            if seen.insert(label).inserted {
                badges.append(label)
            }
        }
        for name in executedTools {
            switch name {
            case "apple_calendar_list_events", "apple_calendar_create_event":
                add("Agenda")
            case "apple_reminders_list", "apple_reminders_create", "apple_reminders_complete":
                add("Lembretes")
            case "beagle_lookup_bula_pcdt":
                add("Bula/PCDT")
            case "apple_health_live_snapshot":
                add("HealthKit")
            case "beagle_search_memory", "beagle_store_memory":
                add("Memória")
            case "beagle_search_pubmed":
                add("PubMed")
            case "beagle_lookup_scientific_work":
                add("DOI/arXiv")
            case "beagle_read_url":
                add("Web")
            case "beagle_web_search":
                add("Busca Web")
            case "openai_web_search":
                add("Web OpenAI")
            case "openai_tool_search":
                add("Tool Search")
            case "delegate_to_grok_bot", "list_grok_bot_routines":
                add("Grok Bot")
            case "local_pdf_reader":
                add("PDF")
            default:
                add("MCP")
            }
        }
        return badges
    }

    // MARK: - OpenAI / Anthropic Unified Tool Schemas

    public static func openAIToolDefinitions() -> [[String: Any]] {
        [
            [
                "type": "function",
                "function": [
                    "name": "apple_calendar_list_events",
                    "description": "Lista compromissos, plantões médicos, aulas e eventos reais do Calendário nativo do iPhone/Mac (EventKit) em uma janela de dias.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "days_ahead": [
                                "type": "integer",
                                "description": "Quantos dias à frente consultar a partir de hoje (padrão: 7, máximo: 90)."
                            ],
                            "days_back": [
                                "type": "integer",
                                "description": "Quantos dias passados incluir antes de hoje (padrão: 0, máximo: 30)."
                            ],
                            "search": [
                                "type": "string",
                                "description": "Filtro opcional por termo no título, local, notas ou nome do calendário (ex: 'plantão', 'UFPR', 'reunião')."
                            ]
                        ],
                        "required": [] as [String]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "apple_calendar_create_event",
                    "description": "Cria e salva um evento, plantão ou compromisso real no Calendário nativo do iPhone/Mac (EventKit), com alarme opcional.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title": [
                                "type": "string",
                                "description": "Título claro do evento ou plantão (ex: 'Plantão UTI Noturno', 'Reunião Doutorado UFPR')."
                            ],
                            "start_iso": [
                                "type": "string",
                                "description": "Data/hora de início em ISO-8601 ou 'yyyy-MM-dd HH:mm' no fuso local (ex: '2026-11-27T19:00:00-03:00' ou '2026-11-27 19:00')."
                            ],
                            "end_iso": [
                                "type": "string",
                                "description": "Data/hora de término opcional em ISO-8601 ou 'yyyy-MM-dd HH:mm'. Se omitido, usa duration_minutes."
                            ],
                            "duration_minutes": [
                                "type": "integer",
                                "description": "Duração em minutos caso end_iso não seja informado (padrão: 60; ex: 720 para plantão de 12h)."
                            ],
                            "location": [
                                "type": "string",
                                "description": "Local opcional do evento."
                            ],
                            "notes": [
                                "type": "string",
                                "description": "Observações ou contexto clínico/científico para salvar no evento."
                            ],
                            "all_day": [
                                "type": "boolean",
                                "description": "Se true, cria como evento de dia inteiro."
                            ],
                            "alarm_minutes_before": [
                                "type": "integer",
                                "description": "Minutos antes do início para disparar alerta no iPhone (padrão: 30; 0 desativa)."
                            ]
                        ],
                        "required": ["title", "start_iso"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "apple_reminders_list",
                    "description": "Lista lembretes reais do app Lembretes (Reminders / EventKit) no iPhone/Mac.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "include_completed": [
                                "type": "boolean",
                                "description": "Se true, inclui também lembretes já concluídos recentemente (padrão: false)."
                            ],
                            "search": [
                                "type": "string",
                                "description": "Filtro opcional por texto no título ou notas do lembrete."
                            ]
                        ],
                        "required": [] as [String]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "apple_reminders_create",
                    "description": "Cria um lembrete real no app Lembretes do iPhone/Mac com horário de alerta e prioridade opcionais.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title": [
                                "type": "string",
                                "description": "Texto principal do lembrete."
                            ],
                            "due_iso": [
                                "type": "string",
                                "description": "Data/hora opcional do lembrete em ISO-8601 ou 'yyyy-MM-dd HH:mm' para agendar notificação."
                            ],
                            "notes": [
                                "type": "string",
                                "description": "Notas adicionais opcionais (ex: posologia, link, detalhes)."
                            ],
                            "priority": [
                                "type": "string",
                                "description": "Prioridade opcional: 'high', 'medium', 'low' ou 'none'."
                            ]
                        ],
                        "required": ["title"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "apple_reminders_complete",
                    "description": "Marca um lembrete pendente do iPhone/Mac como concluído pelo ID ou por parte do título.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "title_or_id": [
                                "type": "string",
                                "description": "ID do lembrete retornado por apple_reminders_list ou trecho do título do lembrete a concluir."
                            ]
                        ],
                        "required": ["title_or_id"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_lookup_bula_pcdt",
                    "description": "Consulta determinística offline no SQLite embarcado: bulas aprovadas (FDA/DailyMed verbatim com ajuste renal/hepático/gestação/interações/boxed warning) E Protocolos Clínicos e Diretrizes Terapêuticas (PCDT do Ministério da Saúde / SUS). Sempre use antes de citar doses clínicas exatas.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "drug_or_condition": [
                                "type": "string",
                                "description": "Nome do fármaco (PT/EN/marca) ou condição clínica do PCDT (ex: 'enoxaparina', 'vancomicina', 'clozapina', 'sepse')."
                            ],
                            "clinical_question": [
                                "type": "string",
                                "description": "Foco específico para janela de dose (ex: 'ajuste renal ClCr 25', 'gestante', 'interações', 'superdosagem', 'posologia')."
                            ]
                        ],
                        "required": ["drug_or_condition"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "apple_health_live_snapshot",
                    "description": "Lê os sinais fisiológicos e autonômicos reais mais recentes do Apple Watch / HealthKit (HRV SDNN, FC de repouso, horas e qualidade de sono profundo+REM, frequência respiratória, temperatura noturna do punho, Estado da Mente, treinos e clima geomagnético Kp/Dst).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "refresh": [
                                "type": "boolean",
                                "description": "Se true (padrão), força atualização imediata no HealthKit antes de retornar."
                            ]
                        ],
                        "required": [] as [String]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Execution Entry Point

    public func execute(name: String, args: [String: Any]) async -> String {
        switch name {
        case "apple_calendar_list_events":
            let daysAhead = Self.intArg(args["days_ahead"]) ?? 7
            let daysBack = Self.intArg(args["days_back"]) ?? 0
            let search = (args["search"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return await listCalendarEvents(daysAhead: daysAhead, daysBack: daysBack, search: search)

        case "apple_calendar_create_event":
            let title = ((args["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let startISO = ((args["start_iso"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let endISO = (args["end_iso"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = Self.intArg(args["duration_minutes"]) ?? 60
            let location = (args["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (args["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let allDay = Self.boolArg(args["all_day"]) ?? false
            let alarmMins = Self.intArg(args["alarm_minutes_before"]) ?? 30
            return await createCalendarEvent(
                title: title,
                startISO: startISO,
                endISO: endISO,
                durationMinutes: duration,
                location: location,
                notes: notes,
                allDay: allDay,
                alarmMinutesBefore: alarmMins
            )

        case "apple_reminders_list":
            let includeCompleted = Self.boolArg(args["include_completed"]) ?? false
            let search = (args["search"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return await listReminders(includeCompleted: includeCompleted, search: search)

        case "apple_reminders_create":
            let title = ((args["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dueISO = (args["due_iso"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (args["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let priority = (args["priority"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return await createReminder(title: title, dueISO: dueISO, notes: notes, priority: priority)

        case "apple_reminders_complete":
            let target = ((args["title_or_id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return await completeReminder(titleOrId: target)

        case "beagle_lookup_bula_pcdt":
            let drug = ((args["drug_or_condition"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let question = ((args["clinical_question"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return lookupBulaAndPCDT(drugOrCondition: drug, clinicalQuestion: question)

        case "apple_health_live_snapshot":
            let shouldRefresh = Self.boolArg(args["refresh"]) ?? true
            return await readLiveHealthSnapshot(refresh: shouldRefresh)

        default:
            return "Ferramenta local desconhecida: \(name)."
        }
    }

    // MARK: - Clinical Bula & PCDT Lookup

    public func lookupBulaAndPCDT(drugOrCondition: String, clinicalQuestion: String) -> String {
        guard BulaStore.shared.disponivel else {
            return "Banco SQLite offline de bulas/PCDT não está disponível neste bundle."
        }
        let combined = [drugOrCondition, clinicalQuestion]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !combined.isEmpty else {
            return "Informe 'drug_or_condition' para consultar a bula ou o PCDT."
        }

        let bula = BulaStore.shared.consulta(combined) ?? BulaStore.shared.consulta(drugOrCondition)
        let pcdts = BulaStore.shared.consultaPCDTDireta(combined, limite: 3)

        var sections: [String] = []
        if let bula {
            sections.append("""
            ## Bula Oficial Aprovada (VERBATIM — openFDA / DailyMed)
            Fármaco: \(bula.nomePT) (\(bula.generico))
            Citação: \(bula.citacao)

            \(bula.texto)
            """)
        }
        if !pcdts.isEmpty {
            let rendered = pcdts.map { item in
                "Citação: \(item.citacao)\n\(item.texto)"
            }.joined(separator: "\n\n---\n\n")
            sections.append("""
            ## Protocolo Clínico e Diretrizes Terapêuticas (VERBATIM — PCDT / Ministério da Saúde)
            \(rendered)
            """)
        }

        if sections.isEmpty {
            let similares = BulaStore.shared.buscarFarmacosSemelhantes(drugOrCondition, limite: 8)
            if !similares.isEmpty {
                return "Nenhum trecho exato para '\(combined)'. Fármacos próximos disponíveis na base local: \(similares.joined(separator: ", "))."
            }
            return "Nenhum trecho de bula ou PCDT encontrado na base local para '\(combined)'. Não extrapole números clínicos sem fonte."
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - HealthKit / Physiome Live Snapshot

    public func readLiveHealthSnapshot(refresh: Bool) async -> String {
        guard let provider = currentPhysioProvider() else {
            return "Ponte HealthKit ainda não inicializada nesta sessão."
        }
        return await provider(refresh)
    }

}
