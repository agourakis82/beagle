//
//  AppleDeviceToolsBridge+EventKit.swift
//  BeagleCore
//
//  EventKit Calendar & Reminders execution and flexible date/argument parsing
//  for AppleDeviceToolsBridge.
//

import Foundation
#if canImport(EventKit) && !os(watchOS)
import EventKit
#endif

extension AppleDeviceToolsBridge {
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

    func listCalendarEvents(daysAhead: Int, daysBack: Int, search: String?) async -> String {
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

    func createCalendarEvent(
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

    func listReminders(includeCompleted: Bool, search: String?) async -> String {
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

    func createReminder(title: String, dueISO: String?, notes: String?, priority: String?) async -> String {
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

    func completeReminder(titleOrId: String) async -> String {
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
    func listCalendarEvents(daysAhead: Int, daysBack: Int, search: String?) async -> String {
        "EventKit Calendar não disponível nesta plataforma."
    }

    func createCalendarEvent(
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

    func listReminders(includeCompleted: Bool, search: String?) async -> String {
        "EventKit Reminders não disponível nesta plataforma."
    }

    func createReminder(title: String, dueISO: String?, notes: String?, priority: String?) async -> String {
        "EventKit Reminders não disponível nesta plataforma."
    }

    func completeReminder(titleOrId: String) async -> String {
        "EventKit Reminders não disponível nesta plataforma."
    }
    #endif

    // MARK: - Parsing Helpers

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    static func intArg(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    static func boolArg(_ raw: Any?) -> Bool? {
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
