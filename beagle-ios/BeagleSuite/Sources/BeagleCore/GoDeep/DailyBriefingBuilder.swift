//
//  DailyBriefingBuilder.swift
//  BeagleCore
//
//  Daily Morning Briefing Builder (GPT-6.2 Astra × Fisioma × Céu × Agenda):
//  live context gathering, UserDefaults/AppGroup digest caching, Markdown section
//  parsing, and multi-tier morning synthesis streaming.
//

import Foundation

// ============================================================================
// MARK: - Daily Morning Briefing Builder (GPT-6.2 Astra × Fisioma × Céu × Agenda)
// ============================================================================

public enum DailyBriefingBuilder {

    public struct ContextSnapshot: Sendable {
        public let dateISO: String
        public let physioBlock: String
        public let readinessLabel: String?
        public let hrvMs: Double?
        public let sleepHours: Double?
        public let skyBlock: String
        public let kpIndex: Double?
        public let skyBandLabel: String?
        public let calendarBlock: String
        public let remindersBlock: String
        public let captureLines: [String]
        public let memoryBlock: String?

        public init(
            dateISO: String,
            physioBlock: String,
            readinessLabel: String? = nil,
            hrvMs: Double? = nil,
            sleepHours: Double? = nil,
            skyBlock: String,
            kpIndex: Double? = nil,
            skyBandLabel: String? = nil,
            calendarBlock: String,
            remindersBlock: String,
            captureLines: [String],
            memoryBlock: String? = nil
        ) {
            self.dateISO = dateISO
            self.physioBlock = physioBlock
            self.readinessLabel = readinessLabel
            self.hrvMs = hrvMs
            self.sleepHours = sleepHours
            self.skyBlock = skyBlock
            self.kpIndex = kpIndex
            self.skyBandLabel = skyBandLabel
            self.calendarBlock = calendarBlock
            self.remindersBlock = remindersBlock
            self.captureLines = captureLines
            self.memoryBlock = memoryBlock
        }

        public func composedPrompt(projectSlug: String) -> String {
            let capturesSection: String = captureLines.isEmpty
                ? "Nenhuma captura explícita registrada desde a meia-noite local ainda."
                : captureLines.map { "- \($0)" }.joined(separator: "\n")

            var sections: [String] = [
                "Data/hora local: \(dateISO)",
                "Projeto ativo em foco: \(projectSlug)",
                "## 1. Fisioma & Sinais Autonômicos (Apple Watch / HealthKit)\n\(physioBlock)",
                "## 2. Clima Espacial & Heliobiologia (NOAA SWPC / GFZ)\n\(skyBlock)",
                "## 3. Agenda & Plantões nas Próximas 48h (EventKit)\n\(calendarBlock)",
                "## 4. Lembretes Pendentes\n\(remindersBlock)",
                "## 5. Capturas de Hoje no Exocórtex\n\(capturesSection)"
            ]

            if let memoryBlock, !memoryBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## 6. Memórias Relevantes do Exocórtex (GraphRAG++)\n\(memoryBlock)")
            }

            return sections.joined(separator: "\n\n")
        }
    }

    public static let appGroupSuiteName = "group.dev.sounio.cockpit"

    public struct WidgetBriefingDigest: Codable, Sendable, Equatable {
        public let dateISO: String
        public let headline: String
        public let readinessLabel: String?
        public let hrvMs: Double?
        public let sleepHours: Double?
        public let kpIndex: Double?
        public let skyBandLabel: String?
        public let captureCount: Int

        public init(
            dateISO: String,
            headline: String,
            readinessLabel: String? = nil,
            hrvMs: Double? = nil,
            sleepHours: Double? = nil,
            kpIndex: Double? = nil,
            skyBandLabel: String? = nil,
            captureCount: Int = 0
        ) {
            self.dateISO = dateISO
            self.headline = headline
            self.readinessLabel = readinessLabel
            self.hrvMs = hrvMs
            self.sleepHours = sleepHours
            self.kpIndex = kpIndex
            self.skyBandLabel = skyBandLabel
            self.captureCount = captureCount
        }
    }

    public struct ParsedSection: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let body: String
        public let systemImage: String

        public init(id: String, title: String, body: String, systemImage: String) {
            self.id = id
            self.title = title
            self.body = body
            self.systemImage = systemImage
        }
    }

    public static func cacheKey(for date: Date = .now) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "beagle.dailySynthesis.v2.%04d-%02d-%02d", y, m, d)
    }

    public static func widgetDigestKey(for date: Date = .now) -> String {
        cacheKey(for: date) + ".widgetDigest"
    }

    public static func cachedTodaySynthesis(now: Date = .now, defaults: UserDefaults = .standard) -> String? {
        let key = cacheKey(for: now)
        if let cached = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty {
            return cached
        }
        if defaults === UserDefaults.standard,
           let shared = UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: key)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !shared.isEmpty {
            return shared
        }
        return nil
    }

    public static func saveTodaySynthesis(
        _ text: String,
        context: ContextSnapshot? = nil,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = cacheKey(for: now)
        defaults.set(trimmed, forKey: key)

        let headline = extractHeadline(from: trimmed)
        let digest = WidgetBriefingDigest(
            dateISO: context?.dateISO ?? ISO8601DateFormatter().string(from: now),
            headline: headline,
            readinessLabel: context?.readinessLabel,
            hrvMs: context?.hrvMs,
            sleepHours: context?.sleepHours,
            kpIndex: context?.kpIndex,
            skyBandLabel: context?.skyBandLabel,
            captureCount: context?.captureLines.count ?? 0
        )
        if let encoded = try? JSONEncoder().encode(digest) {
            defaults.set(encoded, forKey: widgetDigestKey(for: now))
            if defaults === UserDefaults.standard,
               let shared = UserDefaults(suiteName: appGroupSuiteName) {
                shared.set(trimmed, forKey: key)
                shared.set(encoded, forKey: widgetDigestKey(for: now))
            }
        } else if defaults === UserDefaults.standard,
                  let shared = UserDefaults(suiteName: appGroupSuiteName) {
            shared.set(trimmed, forKey: key)
        }
    }

    public static func cachedWidgetDigest(now: Date = .now, defaults: UserDefaults? = nil) -> WidgetBriefingDigest? {
        let key = widgetDigestKey(for: now)
        if let defaults,
           let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WidgetBriefingDigest.self, from: data) {
            return decoded
        }
        if let shared = UserDefaults(suiteName: appGroupSuiteName),
           let data = shared.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WidgetBriefingDigest.self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WidgetBriefingDigest.self, from: data) {
            return decoded
        }
        if let text = cachedTodaySynthesis(now: now, defaults: defaults ?? .standard) {
            return WidgetBriefingDigest(
                dateISO: ISO8601DateFormatter().string(from: now),
                headline: extractHeadline(from: text)
            )
        }
        return nil
    }

    public static func clearTodaySynthesis(now: Date = .now, defaults: UserDefaults = .standard) {
        let key = cacheKey(for: now)
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: widgetDigestKey(for: now))
        if defaults === UserDefaults.standard,
           let shared = UserDefaults(suiteName: appGroupSuiteName) {
            shared.removeObject(forKey: key)
            shared.removeObject(forKey: widgetDigestKey(for: now))
        }
    }

    /// Parses the `###` structured Markdown blocks of a morning briefing into dedicated cards.
    public static func parseSections(_ markdown: String) -> [ParsedSection] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sections: [ParsedSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flush() {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                currentLines = []
                return
            }
            let title = (currentTitle ?? "Síntese Matinal").trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(
                ParsedSection(
                    id: "sec_\(sections.count)_\(title.prefix(16))",
                    title: title,
                    body: body,
                    systemImage: iconForSectionTitle(title, index: sections.count)
                )
            )
            currentLines = []
        }

        for line in trimmed.components(separatedBy: "\n") {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("### ") || clean.hasPrefix("## ") {
                flush()
                let stripped = clean.hasPrefix("### ") ? String(clean.dropFirst(4)) : String(clean.dropFirst(3))
                currentTitle = stripped.replacingOccurrences(of: "**", with: "")
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return sections
    }

    private static func iconForSectionTitle(_ title: String, index: Int) -> String {
        let lower = title.lowercased()
        if lower.contains("pulso") || lower.contains("fisioma") || lower.contains("auton") || lower.contains("céu") {
            return "waveform.path.ecg"
        }
        if lower.contains("mapa") || lower.contains("agenda") || lower.contains("plant") {
            return "calendar.badge.clock"
        }
        if lower.contains("fio") || lower.contains("cient") || lower.contains("exoc") {
            return "atom"
        }
        if lower.contains("alavanca") || lower.contains("a\u{00e7}\u{00f5}es") || lower.contains("tres") || lower.contains("tr\u{00ea}s") {
            return "bolt.horizontal.circle.fill"
        }
        let defaults = ["waveform.path.ecg", "calendar.badge.clock", "atom", "bolt.horizontal.circle.fill"]
        return defaults[index % defaults.count]
    }

    private static func extractHeadline(from markdown: String) -> String {
        for raw in markdown.components(separatedBy: "\n") {
            let clean = raw
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty,
                  !clean.hasPrefix("#"),
                  clean.count >= 16 else { continue }
            let withoutBullet = clean.hasPrefix("- ") || clean.hasPrefix("• ")
                ? String(clean.dropFirst(2))
                : clean
            return String(withoutBullet.prefix(140))
        }
        return String(markdown.replacingOccurrences(of: "\n", with: " ").prefix(120))
    }

    /// Gathers real-time Physiome, NOAA Space Weather, EventKit Calendar (48h), Reminders,
    /// today's captures, and GraphRAG++ recall concurrently.
    public static func gatherLiveContext(
        captureLines: [String],
        physioSummary: PhysioSummary? = nil,
        sky: SpaceWeatherStore.Snapshot? = nil,
        projectSlug: String = "sounio",
        client: BeagleClient = .shared,
        directBrain: DirectBrainClient = .shared,
        includeDeviceTools: Bool = true
    ) async -> ContextSnapshot {
        let iso = ISO8601DateFormatter().string(from: .now)

        async let liveSkyFetch: SpaceWeatherStore.Snapshot? = {
            if let sky { return sky }
            return await client.latestSpaceWeather().value
        }()

        async let liveHealthTool: String? = {
            guard includeDeviceTools else { return nil }
            return await AppleDeviceToolsBridge.shared.execute(
                name: "apple_health_live_snapshot",
                args: ["refresh": false]
            )
        }()

        async let liveCalendarTool: String? = {
            guard includeDeviceTools else { return nil }
            return await AppleDeviceToolsBridge.shared.execute(
                name: "apple_calendar_list_events",
                args: ["days_ahead": 2, "days_back": 0]
            )
        }()

        async let liveRemindersTool: String? = {
            guard includeDeviceTools else { return nil }
            return await AppleDeviceToolsBridge.shared.execute(
                name: "apple_reminders_list",
                args: ["limit": 10]
            )
        }()

        let memoryQuery = captureLines.isEmpty
            ? "prioridades recentes \(projectSlug) pesquisa clínica sounio pbpk"
            : String(captureLines.prefix(4).joined(separator: " ").prefix(280))
        async let recalledMemory: String? = {
            guard includeDeviceTools else { return nil }
            return await directBrain.recallRelevantMemory(
                for: memoryQuery,
                projectSlug: projectSlug
            )
        }()

        let resolvedSky = await liveSkyFetch
        let healthToolOut = await liveHealthTool
        let calendarOut = await liveCalendarTool
        let remindersOut = await liveRemindersTool
        let memoryOut = await recalledMemory

        // Build Physio block
        var physioParts: [String] = []
        var readinessLabel: String?
        if let p = physioSummary {
            readinessLabel = p.readiness.rawValue
            physioParts.append("Prontidão: \(p.readiness.title) (\(p.readiness.discussionFlowState))")
            if let hrv = p.hrvMs { physioParts.append(String(format: "HRV SDNN: %.0f ms", hrv)) }
            if let rhr = p.restingHeartRate { physioParts.append(String(format: "FC repouso: %.0f bpm", rhr)) }
            if let sleep = p.sleepHours { physioParts.append(String(format: "Sono: %.1f h", sleep)) }
            if p.workoutCount > 0 { physioParts.append("Treinos recentes: \(p.workoutCount)") }
        }
        if let healthToolOut,
           !healthToolOut.isEmpty,
           !healthToolOut.lowercased().contains("indispon") {
            physioParts.append(healthToolOut)
        }
        let physioBlock = physioParts.isEmpty
            ? "Sem leitura recente do Apple Watch / HealthKit disponível neste instante."
            : physioParts.joined(separator: "\n")

        // Build Space Weather block
        let skyBlock: String
        let skyBandLabel: String?
        if let s = resolvedSky {
            let bandName: String = {
                switch s.band {
                case .calm: return "Calmo"
                case .active: return "Ativo"
                case .storm: return "Tempestade Geomagnética"
                }
            }()
            skyBandLabel = bandName
            var metrics: [String] = [
                String(format: "Banda: %@ · Kp %.1f · Fluxo Solar F10.7 %.0f sfu", bandName, s.kp, s.f107)
            ]
            if let dst = s.dst { metrics.append(String(format: "Dst: %.0f nT", dst)) }
            if let bz = s.bz { metrics.append(String(format: "IMF Bz: %.1f nT", bz)) }
            if let wind = s.solarWindSpeed { metrics.append(String(format: "Vento solar: %.0f km/s", wind)) }
            skyBlock = metrics.joined(separator: " · ")
        } else {
            skyBandLabel = nil
            skyBlock = "Telemetria NOAA SWPC sem leitura ao vivo no momento."
        }

        let cleanCalendar = (calendarOut?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Agenda não consultada ou sem eventos nas próximas 48h."

        let cleanReminders = (remindersOut?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Sem lembretes pendentes lidos."

        return ContextSnapshot(
            dateISO: iso,
            physioBlock: physioBlock,
            readinessLabel: readinessLabel,
            hrvMs: physioSummary?.hrvMs,
            sleepHours: physioSummary?.sleepHours,
            skyBlock: skyBlock,
            kpIndex: resolvedSky?.kp,
            skyBandLabel: skyBandLabel,
            calendarBlock: cleanCalendar,
            remindersBlock: cleanReminders,
            captureLines: captureLines,
            memoryBlock: memoryOut
        )
    }

    /// Streams the Portuguese morning synthesis using GPT-6.2 Astra -> Claude Opus 4.8 -> Cluster -> MLX.
    public static func generateMorningSynthesis(
        context: ContextSnapshot,
        projectSlug: String = "sounio",
        flowState: String = "NORMAL",
        client: BeagleClient = .shared,
        directBrain: DirectBrainClient = .shared,
        onToken: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let systemPrompt = """
        Você é o parceiro científico, clínico e cognitivo matinal de Demetrios no Beagle Exocórtex (GPT-6.2 Astra).
        Responda SEMPRE em português brasileiro natural, lúcido, enxuto e cirúrgico. Nunca invente métricas que não estejam no contexto: quando um sinal estiver ausente, declare isso em meia frase sem rodeios.

        Estruture a Síntese Matinal em 4 blocos curtos com subtítulos Markdown (`###`):
        ### 1. Pulso Autonômico & Céu
        Cruze o estado fisiológico real (sono, HRV, FC de repouso, prontidão) com o clima geomagnético (`Kp`, `Dst`, `Bz`) com rigor científico (tratando heliobiologia como sinal exploratório N-de-1, nunca determinismo) e recomende a marcha cognitiva ideal para hoje.

        ### 2. Mapa do Dia (Plantões, Agenda & Pendências)
        Destaque janelas de plantão, reuniões ou prazos reais nas próximas 48h e onde proteger foco profundo.

        ### 3. Fio Científico & Exocórtex
        Conecte as capturas de hoje (ou, se ainda não houver capturas hoje, as frentes ativas na memória do projeto `\(projectSlug)`) apontando tensões, conexões não óbvias ou hipóteses testáveis.

        ### 4. Três Alavancas Concretas para Hoje
        Liste 3 ações específicas, executáveis e calibradas à energia real do corpo hoje.
        """

        let userPrompt = context.composedPrompt(projectSlug: projectSlug)

        if DirectBrainCredentials.hasOpenAI {
            do {
                let res = try await directBrain.streamOpenAI(
                    model: OpenAIModelCatalog.defaultFlagshipModel,
                    systemPrompt: systemPrompt,
                    developerPrefix: systemPrompt,
                    reasoningEffort: "medium",
                    enableNativeWebSearch: false,
                    enableToolSearch: false,
                    turns: [DirectBrainTurn(role: "user", content: userPrompt)],
                    projectSlug: projectSlug,
                    onStatus: { _ in },
                    onToken: { delta in
                        if let onToken { await onToken(delta) }
                    }
                )
                let trimmed = res.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } catch {
                if !DirectBrainCredentials.hasAnthropic {
                    // Fall through to cluster/local below if available; otherwise rethrow at end
                }
            }
        }

        if DirectBrainCredentials.hasAnthropic {
            if let res = try? await directBrain.streamAnthropic(
                model: "claude-opus-4-8",
                systemPrompt: systemPrompt,
                turns: [DirectBrainTurn(role: "user", content: userPrompt)],
                projectSlug: projectSlug,
                onToken: { delta in
                    if let onToken { await onToken(delta) }
                }
            ) {
                let trimmed = res.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        var clusterBuffer = ""
        let stream = client.chatStream(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            projectSlug: projectSlug,
            discussionProfile: .cluster,
            flowState: flowState,
            deepThink: true
        )
        do {
            for try await token in stream {
                clusterBuffer += token
                if let onToken { await onToken(token) }
            }
            let trimmed = clusterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        } catch {
            // Fall through to local MLX fallback
        }

        let isLocalReady = await MainActor.run { LocalLLMEngine.shared.isReady }
        if isLocalReady {
            let combinedPrompt = "\(systemPrompt)\n\n\(userPrompt)"
            let local = try await LocalLLMEngine.shared.respond(to: combinedPrompt)
            if let onToken { await onToken(local) }
            return local
        }

        throw URLError(.cannotConnectToHost)
    }
}
