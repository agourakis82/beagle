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
    private let eventStore = EKEventStore()
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

    // MARK: - EventKit Calendar & Reminders

    private enum AccessResult {
        case success(Void)
        case failure(String)
    }

    #if canImport(EventKit) && !os(watchOS)
    private func ensureCalendarAccess() async -> AccessResult {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            return .success(())
        }
        if status == .denied || status == .restricted {
            return .failure("Acesso ao Calendário está negado no iOS. Peça para liberar em Ajustes › Privacidade e Segurança › Calendários › BeagleCockpit.")
        }
        return await withCheckedContinuation { continuation in
            self.eventStore.requestFullAccessToEvents { granted, error in
                if granted {
                    continuation.resume(returning: .success(()))
                } else {
                    let msg = error?.localizedDescription ?? "Permissão de acesso ao Calendário não concedida."
                    continuation.resume(returning: .failure("Sem acesso ao Calendário: \(msg)"))
                }
            }
        }
    }

    private func ensureRemindersAccess() async -> AccessResult {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess {
            return .success(())
        }
        if status == .denied || status == .restricted {
            return .failure("Acesso aos Lembretes está negado no iOS. Peça para liberar em Ajustes › Privacidade e Segurança › Lembretes › BeagleCockpit.")
        }
        return await withCheckedContinuation { continuation in
            self.eventStore.requestFullAccessToReminders { granted, error in
                if granted {
                    continuation.resume(returning: .success(()))
                } else {
                    let msg = error?.localizedDescription ?? "Permissão de acesso aos Lembretes não concedida."
                    continuation.resume(returning: .failure("Sem acesso aos Lembretes: \(msg)"))
                }
            }
        }
    }

    private func listCalendarEvents(daysAhead: Int, daysBack: Int, search: String?) async -> String {
        switch await ensureCalendarAccess() {
        case .failure(let msg):
            return msg
        case .success:
            break
        }

        let cal = Calendar.current
        let now = Date()
        let clampedBack = min(max(daysBack, 0), 30)
        let clampedAhead = min(max(daysAhead, 0), 90)
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -clampedBack, to: now) ?? now)
        let endBase = cal.date(byAdding: .day, value: max(clampedAhead, 1), to: start) ?? now.addingTimeInterval(86400 * 7)
        let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        var events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        if let search, !search.isEmpty {
            let needle = Self.fold(search)
            events = events.filter { ev in
                let hay = Self.fold([ev.title, ev.location, ev.notes, ev.calendar?.title].compactMap { $0 }.joined(separator: " "))
                return hay.contains(needle)
            }
        }

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "pt_BR")
        dateFmt.dateFormat = "EEE dd/MM"

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "pt_BR")
        timeFmt.dateFormat = "HH:mm"

        if events.isEmpty {
            let rangeStr = "\(dateFmt.string(from: start)) a \(dateFmt.string(from: end))"
            if let search, !search.isEmpty {
                return "Nenhum evento encontrado na Agenda para '\(search)' entre \(rangeStr)."
            }
            return "Agenda livre — nenhum compromisso encontrado entre \(rangeStr)."
        }

        let lines = events.prefix(30).map { ev -> String in
            let day = dateFmt.string(from: ev.startDate)
            let when = ev.isAllDay
                ? "\(day) (dia inteiro)"
                : "\(day) \(timeFmt.string(from: ev.startDate))–\(timeFmt.string(from: ev.endDate))"
            var parts = ["• [\(when)] \(ev.title ?? "(sem título)")"]
            if let calTitle = ev.calendar?.title, !calTitle.isEmpty {
                parts.append("(\(calTitle))")
            }
            if let loc = ev.location, !loc.isEmpty {
                parts.append("📍 \(loc)")
            }
            if let notes = ev.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                let clean = notes.replacingOccurrences(of: "\n", with: " ").prefix(120)
                parts.append("— \(clean)")
            }
            return parts.joined(separator: " ")
        }

        return "Eventos na Agenda (\(events.count) encontrados):\n" + lines.joined(separator: "\n")
    }

    private func createCalendarEvent(
        title: String,
        startISO: String,
        endISO: String?,
        durationMinutes: Int,
        location: String?,
        notes: String?,
        allDay: Bool,
        alarmMinutesBefore: Int
    ) async -> String {
        guard !title.isEmpty else {
            return "Erro: informe um 'title' para criar o evento."
        }
        guard let startDate = Self.parseFlexibleDate(startISO, defaultHour: 9) else {
            return "Erro: não consegui interpretar 'start_iso' ('\(startISO)'). Use ISO-8601 ou 'yyyy-MM-dd HH:mm'."
        }

        switch await ensureCalendarAccess() {
        case .failure(let msg):
            return msg
        case .success:
            break
        }

        guard let targetCalendar = eventStore.defaultCalendarForNewEvents ?? eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            return "Erro: nenhum calendário gravável disponível neste dispositivo."
        }

        let clampedDuration = max(durationMinutes, 5)
        let endDate: Date = {
            if let endISO, !endISO.isEmpty, let parsedEnd = Self.parseFlexibleDate(endISO, defaultHour: 10), parsedEnd > startDate {
                return parsedEnd
            }
            return startDate.addingTimeInterval(Double(clampedDuration) * 60)
        }()

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = allDay
        if let location, !location.isEmpty { event.location = location }
        if let notes, !notes.isEmpty { event.notes = notes }
        event.calendar = targetCalendar
        if alarmMinutesBefore > 0 {
            event.addAlarm(EKAlarm(relativeOffset: -Double(alarmMinutesBefore) * 60))
        }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "pt_BR")
            fmt.dateFormat = allDay ? "EEEE, dd/MM/yyyy" : "EEEE, dd/MM/yyyy 'às' HH:mm"
            let endFmt = DateFormatter()
            endFmt.locale = Locale(identifier: "pt_BR")
            endFmt.dateFormat = "HH:mm"
            let whenStr = allDay
                ? "\(fmt.string(from: startDate)) (dia inteiro)"
                : "\(fmt.string(from: startDate)) até \(endFmt.string(from: endDate))"
            return "Evento criado no Calendário '\(targetCalendar.title)': '\(title)' em \(whenStr)."
        } catch {
            return "Falha ao salvar evento no Calendário: \(error.localizedDescription)"
        }
    }

    private func listReminders(includeCompleted: Bool, search: String?) async -> String {
        switch await ensureRemindersAccess() {
        case .failure(let msg):
            return msg
        case .success:
            break
        }

        let predicate = includeCompleted
            ? eventStore.predicateForReminders(in: nil)
            : eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)

        let needle = search.flatMap { $0.isEmpty ? nil : Self.fold($0) }

        return await withCheckedContinuation { continuation in
            self.eventStore.fetchReminders(matching: predicate) { rawReminders in
                let list = (rawReminders ?? []).filter { rem in
                    guard let needle else { return true }
                    let hay = Self.fold([rem.title, rem.notes, rem.calendar?.title].compactMap { $0 }.joined(separator: " "))
                    return hay.contains(needle)
                }

                if list.isEmpty {
                    let emptyMsg = needle != nil
                        ? "Nenhum lembrete encontrado para '\(search ?? "")'."
                        : "Nenhum lembrete pendente no momento."
                    continuation.resume(returning: emptyMsg)
                    return
                }

                let cal = Calendar.current
                let sorted = list.sorted { a, b in
                    let da = a.dueDateComponents.flatMap { cal.date(from: $0) } ?? .distantFuture
                    let db = b.dueDateComponents.flatMap { cal.date(from: $0) } ?? .distantFuture
                    if da != db { return da < db }
                    return a.priority < b.priority
                }

                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "pt_BR")
                fmt.dateFormat = "dd/MM HH:mm"

                let lines = sorted.prefix(30).map { rem -> String in
                    let check = rem.isCompleted ? "✓" : "○"
                    var parts = ["\(check) \(rem.title ?? "(sem título)")"]
                    if let due = rem.dueDateComponents.flatMap({ cal.date(from: $0) }) {
                        parts.append("[prazo: \(fmt.string(from: due))]")
                    }
                    if rem.priority >= 1 && rem.priority <= 4 {
                        parts.append("[alta prioridade]")
                    }
                    if let listName = rem.calendar?.title, !listName.isEmpty {
                        parts.append("(\(listName))")
                    }
                    parts.append("[id: \(rem.calendarItemIdentifier)]")
                    return parts.joined(separator: " ")
                }
                continuation.resume(returning: "Lembretes (\(list.count) encontrados):\n" + lines.joined(separator: "\n"))
            }
        }
    }

    private func createReminder(title: String, dueISO: String?, notes: String?, priority: String?) async -> String {
        guard !title.isEmpty else {
            return "Erro: informe um 'title' para o lembrete."
        }

        switch await ensureRemindersAccess() {
        case .failure(let msg):
            return msg
        case .success:
            break
        }

        guard let targetList = eventStore.defaultCalendarForNewReminders() ?? eventStore.calendars(for: .reminder).first(where: { $0.allowsContentModifications }) else {
            return "Erro: nenhuma lista de Lembretes gravável disponível neste dispositivo."
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = targetList
        if let notes, !notes.isEmpty {
            reminder.notes = notes
        }
        switch (priority ?? "").lowercased() {
        case "high", "alta": reminder.priority = 1
        case "medium", "media", "média": reminder.priority = 5
        case "low", "baixa": reminder.priority = 9
        default: reminder.priority = 0
        }

        var dueDescription = ""
        if let dueISO, !dueISO.isEmpty, let dueDate = Self.parseFlexibleDate(dueISO, defaultHour: 9) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "pt_BR")
            fmt.dateFormat = "dd/MM/yyyy 'às' HH:mm"
            dueDescription = " com alerta para \(fmt.string(from: dueDate))"
        }

        do {
            try eventStore.save(reminder, commit: true)
            return "Lembrete criado em '\(targetList.title)': '\(title)'\(dueDescription)."
        } catch {
            return "Falha ao salvar lembrete: \(error.localizedDescription)"
        }
    }

    private func completeReminder(titleOrId: String) async -> String {
        guard !titleOrId.isEmpty else {
            return "Informe 'title_or_id' do lembrete a concluir."
        }

        switch await ensureRemindersAccess() {
        case .failure(let msg):
            return msg
        case .success:
            break
        }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let needle = Self.fold(titleOrId)

        return await withCheckedContinuation { continuation in
            self.eventStore.fetchReminders(matching: predicate) { rawReminders in
                let candidates = rawReminders ?? []
                let matched = candidates.first(where: { $0.calendarItemIdentifier == titleOrId })
                    ?? candidates.first(where: { Self.fold($0.title ?? "").contains(needle) })

                guard let reminder = matched else {
                    continuation.resume(returning: "Nenhum lembrete pendente encontrado correspondente a '\(titleOrId)'.")
                    return
                }

                reminder.isCompleted = true
                reminder.completionDate = Date()
                do {
                    try self.eventStore.save(reminder, commit: true)
                    continuation.resume(returning: "Lembrete concluído com sucesso: '\(reminder.title ?? titleOrId)'.")
                } catch {
                    continuation.resume(returning: "Erro ao concluir lembrete: \(error.localizedDescription)")
                }
            }
        }
    }
    #else
    private func listCalendarEvents(daysAhead: Int, daysBack: Int, search: String?) async -> String {
        "EventKit Calendar não disponível nesta plataforma."
    }

    private func createCalendarEvent(
        title: String,
        startISO: String,
        endISO: String?,
        durationMinutes: Int,
        location: String?,
        notes: String?,
        allDay: Bool,
        alarmMinutesBefore: Int
    ) async -> String {
        "EventKit Calendar não disponível nesta plataforma."
    }

    private func listReminders(includeCompleted: Bool, search: String?) async -> String {
        "EventKit Reminders não disponível nesta plataforma."
    }

    private func createReminder(title: String, dueISO: String?, notes: String?, priority: String?) async -> String {
        "EventKit Reminders não disponível nesta plataforma."
    }

    private func completeReminder(titleOrId: String) async -> String {
        "EventKit Reminders não disponível nesta plataforma."
    }
    #endif

    // MARK: - Parsing Helpers

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    private static func intArg(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func boolArg(_ raw: Any?) -> Bool? {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String {
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "sim": return true
            case "false", "0", "no", "nao", "não": return false
            default: return nil
            }
        }
        return nil
    }

    public static func parseFlexibleDate(_ raw: String, defaultHour: Int = 9) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: trimmed) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }

        let localFormats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "dd/MM/yyyy HH:mm"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for fmt in localFormats {
            df.dateFormat = fmt
            if let d = df.date(from: trimmed) { return d }
        }

        let dateOnlyFormats = ["yyyy-MM-dd", "dd/MM/yyyy"]
        for fmt in dateOnlyFormats {
            df.dateFormat = fmt
            if let dayStart = df.date(from: trimmed) {
                return Calendar.current.date(bySettingHour: defaultHour, minute: 0, second: 0, of: dayStart) ?? dayStart
            }
        }

        return nil
    }
}
