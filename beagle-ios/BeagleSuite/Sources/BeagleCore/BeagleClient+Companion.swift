//
//  BeagleClient+Companion.swift
//  BeagleCore
//
//  Companion chat/streaming SSE, voice synthesis, arrival synthesis, grounding, and space weather.
//

import Foundation

extension BeagleClient {

    // MARK: - Chat (generic exocortex conversation)

    public func chat(
        prompt: String,
        system: String? = nil,
        projectSlug: String = "sounio",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil,
        discussionProfile: DiscussionProfile = .cluster,
        flowState: String? = nil,
        physioPolicy: PhysioConversationPolicy? = nil,
        lastContactAt: Date? = nil,
        history: [[String: String]] = [],
        hrvMs: Double? = nil,
        voiceWpm: Double? = nil,
        voicePausa: Double? = nil,
        readiness: String? = nil,
        sleepHours: Double? = nil,
        kp: Double? = nil,
        dst: Double? = nil,
        solarWind: Double? = nil,
        bz: Double? = nil,
        voiceModel: String? = nil,
        imageBase64: String? = nil,
        imageMimeType: String? = nil
    ) async -> Truthful<ChatResponse> {
        await llmComplete(
            prompt: prompt,
            system: system,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: lastContactAt,
            history: history,
            hrvMs: hrvMs, voiceWpm: voiceWpm, voicePausa: voicePausa,
            readiness: readiness, sleepHours: sleepHours,
            kp: kp, dst: dst, solarWind: solarWind, bz: bz,
            voiceModel: voiceModel,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType
        )
    }

    /// Inject the live body + sky fields into a chat request body (shared by llmComplete +
    /// the streaming path). Only present values are sent — the server's `## Agora` fills in
    /// the rest from its own fetch.
    /// Sinal de TOM (`voiceWpm`/`voicePausa`): derivado no aparelho quando ele falou
    /// em vez de digitar. São dois números; o áudio é descartado no iPhone e nunca
    /// sai. Ausentes quando ele digitou — ausência aqui significa "não falei", não
    /// "falei normal".
    static func addLiveContext(_ body: inout [String: any Sendable], hrvMs: Double?, readiness: String?,
                               sleepHours: Double?, kp: Double?, dst: Double?, solarWind: Double?, bz: Double?,
                               voiceWpm: Double? = nil, voicePausa: Double? = nil) {
        if let hrvMs { body["hrv_ms"] = hrvMs }
        if let readiness, !readiness.isEmpty { body["readiness"] = readiness }
        if let sleepHours { body["sleep_hours"] = sleepHours }
        if let kp { body["kp"] = kp }
        if let dst { body["dst"] = dst }
        if let solarWind { body["solar_wind"] = solarWind }
        if let bz { body["bz"] = bz }
        if let voiceWpm { body["voice_speech_rate_wpm"] = voiceWpm }
        if let voicePausa { body["voice_pause_ratio"] = voicePausa }
    }

    // MARK: - A boca

    /// Pede ao servidor o áudio de `text`. Devolve o WAV pronto para tocar.
    ///
    /// 422 do servidor NÃO é falha a mascarar: é o guarda tendo reprovado a boca
    /// (ela falou outra coisa) ou a voz indisponível. Nos dois casos o certo é
    /// cair para texto — a carta já está na tela.
    public func companionVoice(text: String) async -> Truthful<Data> {
        let cockpitURLs = BeagleEndpoints.cockpitURLs
        let debugLabel = "[CompanionVoice] POST /api/mobile/v1/companion/voice"
        var lastError: String?
        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/companion/voice", relativeTo: base) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            BeagleEndpoints.applyCockpitAuth(to: &request)
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard (200..<300).contains(status) else {
                    lastError = formatError(statusCode: status, data: data, fallback: "HTTP \(status)")
                    // 4xx é veredito, não indisponibilidade: não adianta tentar outro gateway.
                    if (400..<500).contains(status) { break }
                    continue
                }
                struct Env: Decodable { let data: Corpo?; struct Corpo: Decodable { let wav_base64: String } }
                guard let env = try? decoder.decode(Env.self, from: data),
                      let b64 = env.data?.wav_base64,
                      let wav = Data(base64Encoded: b64), !wav.isEmpty else {
                    lastError = "resposta sem áudio"
                    continue
                }
                print("\(debugLabel) ok — \(wav.count / 1024) KB")
                return Truthful(value: wav, mode: .observed, observedAt: .now, source: url.host, error: nil)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        print("\(debugLabel) sem voz — \(lastError ?? "sem detalhe")")
        return Truthful(value: nil, mode: .stale, observedAt: nil, source: nil, error: lastError)
    }

    // MARK: - A chegada (síntese proativa)

    public struct ArrivalSynthesis: Sendable {
        public let texto: String
        /// O servidor se recusou a sintetizar por falta de material. É o
        /// comportamento correto, não uma falha.
        public let insuficiente: Bool
    }

    /// Busca o que ele deixou. Acumula o SSE inteiro em vez de transmitir: isto
    /// não é fala ao vivo, é algo que já estava dito quando ele abriu o app —
    /// mostrar aparecendo letra a letra mentiria sobre o tempo.
    public func arrivalSynthesis(windowDays: Int = 3) async -> Truthful<ArrivalSynthesis> {
        let debugLabel = "[ArrivalSynthesis] POST /api/mobile/v1/synthesize"
        let cockpitURLs = BeagleEndpoints.cockpitURLs
        var lastError: String?
        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/synthesize", relativeTo: base) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            BeagleEndpoints.applyCockpitAuth(to: &request)
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["windowDays": windowDays])
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                    continue
                }
                var texto = ""
                var insuficiente = false
                for try await linha in bytes.lines {
                    guard linha.hasPrefix("data:") else { continue }
                    let bruto = String(linha.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    guard let d = bruto.data(using: .utf8),
                          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                    if let t = j["token"] as? String { texto += t }
                    if j["done"] != nil {
                        insuficiente = (j["insufficient"] as? Bool) ?? false
                        break
                    }
                }
                print("\(debugLabel) ok — \(texto.count) chars, insuficiente=\(insuficiente)")
                return Truthful(value: ArrivalSynthesis(texto: texto, insuficiente: insuficiente),
                                mode: .observed, observedAt: .now, source: url.host, error: nil)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        print("\(debugLabel) falhou — \(lastError ?? "sem detalhe")")
        return Truthful(value: nil, mode: .stale, observedAt: nil, source: nil, error: lastError)
    }

    internal func postPublicMobileChat(body: [String: any Sendable]) async -> Truthful<ChatResponse> {
        let cockpitURLs = BeagleEndpoints.cockpitURLs

        var lastError = "mobile chat gateway unreachable"
        let debugLabel = "[\(ChatResponse.self)] POST /api/mobile/v1/chat"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/chat", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.timeoutInterval = 60
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatMobileError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<ChatResponse>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile chat returned ok=false"
                    print("[BeagleClient] \(debugLabel) ❌ envelope ok=false")
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile chat returned no data"
                    print("[BeagleClient] \(debugLabel) ❌ envelope missing data")
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                print("[BeagleClient] \(debugLabel) ✅ success")
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                continue
            }
        }

        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError, source: "cockpit-mobile-gateway")
    }

    // MARK: - Companion grounding (cache offline)

    /// O pacote de identidade dele, montado pelo cluster: persona, biografia viva,
    /// Sounio, continuidade. ~18 KB de texto.
    public struct CompanionGrounding: Decodable, Sendable {
        public let system: String
        public let bytes: Int?
    }

    /// Busca o grounding para o app guardar em disco. Existe por um motivo concreto:
    /// dentro do hospital a rede cai, e sem isto o modelo no aparelho responde como um
    /// estranho educado usando o nome dele - justamente quando ele está mais sozinho.
    public func companionGrounding() async -> Truthful<CompanionGrounding> {
        let cockpitURLs = BeagleEndpoints.cockpitURLs
        let body: [String: any Sendable] = ["space": "personal", "prompt": "grounding"]
        var lastError = "grounding gateway unreachable"
        let debugLabel = "[CompanionGrounding] POST /api/mobile/v1/companion/grounding"

        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/companion/grounding", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.timeoutInterval = 60
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = "HTTP \(statusCode)"
                    print("[BeagleClient] \(debugLabel) HTTP \(statusCode)")
                    continue
                }
                let envelope = try decoder.decode(MobileEnvelope<CompanionGrounding>.self, from: data)
                guard envelope.ok != false, let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "grounding returned no data"
                    continue
                }
                print("[BeagleClient] \(debugLabel) ok — \(payload.bytes ?? payload.system.count) bytes")
                return Truthful(value: payload, mode: .observed, observedAt: .now, source: url.host, error: nil)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError, source: "cockpit-mobile-gateway")
    }

    // MARK: - Streaming chat (SSE: /api/mobile/v1/chat/stream)
    //
    // Streams tokens from the cockpit's SSE endpoint as they arrive — the user sees
    // the companion typing live instead of a frozen 7-9s wait. Server writes
    // `data: {"token":"..."}\n\n` per token and a final `data: {"done":true,...}` event.
    // The returned AsyncThrowingStream yields one String per token.
    public nonisolated func chatStream(
        prompt: String,
        system: String? = nil,
        projectSlug: String = "sounio",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil,
        discussionProfile: DiscussionProfile = .cluster,
        flowState: String? = nil,
        physioPolicy: PhysioConversationPolicy? = nil,
        lastContactAt: Date? = nil,
        history: [[String: String]] = [],
        hrvMs: Double? = nil,
        voiceWpm: Double? = nil,
        voicePausa: Double? = nil,
        readiness: String? = nil,
        sleepHours: Double? = nil,
        kp: Double? = nil,
        dst: Double? = nil,
        solarWind: Double? = nil,
        bz: Double? = nil,
        voiceModel: String? = nil,
        deepThink: Bool = false,
        imageBase64: String? = nil,
        imageMimeType: String? = nil,
        // Presence channel (2026-08-02-companion-presence-design.md §5): the server writes
        // {"event":"presence"|"phase", ...} at t≈0 and while it waits. Optional callback
        // instead of widening the stream element type, so the other call-site
        // (DailySynthesisView) keeps compiling untouched. Invoked off the main actor.
        onPhase: (@Sendable (String, String) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let effectivePrompt: String
        if let system, !system.isEmpty {
            effectivePrompt = "System instruction:\n\(system)\n\nUser prompt:\n\(prompt)"
        } else {
            effectivePrompt = prompt
        }
        let family = projectFamily ?? .fromProjectSlug(projectSlug)
        let scope = publicationScope ?? .forProjectFamily(family)
        var body: [String: any Sendable] = [
            "prompt": effectivePrompt,
            "projectSlug": projectSlug,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue,
            "discussionProfile": discussionProfile.rawValue,
            "space": "personal",
            "clientTime": ISO8601DateFormatter().string(from: Date()),
            "timezone": TimeZone.current.identifier
        ]
        if let lastContactAt {
            body["lastContactAt"] = ISO8601DateFormatter().string(from: lastContactAt)
        }
        if let flowState, !flowState.isEmpty {
            body["flow_state"] = flowState
        }
        if let physioPolicy {
            body["physio_policy"] = physioPolicy.requestBody
        }
        if !history.isEmpty {
            body["history"] = history
        }
        // Depth gear: a non-default voiceModel asks the personal-voice path for a stronger model
        // (e.g. "Pensar" → glm-5.2). nil → server default voice ("Rápido").
        if let voiceModel, !voiceModel.isEmpty {
            body["voiceModel"] = voiceModel
        }
        // Deep-think gear: asks the server to route this turn through the grounded/agentic
        // path (web + cluster + fs tools) instead of the fast conversational default.
        if deepThink {
            body["deepThink"] = true
        }
        if let imageBase64, !imageBase64.isEmpty {
            body["imageBase64"] = imageBase64
            body["imageMimeType"] = imageMimeType ?? "image/jpeg"
        }
        Self.addLiveContext(&body, hrvMs: hrvMs, readiness: readiness, sleepHours: sleepHours,
                            kp: kp, dst: dst, solarWind: solarWind, bz: bz,
                            voiceWpm: voiceWpm, voicePausa: voicePausa)

        let cockpitURLs: [URL] = BeagleEndpoints.cockpitURLs

        // Use an ephemeral session for the stream (long-lived, SSE) — avoids needing
        // to reach into actor-isolated self.session from this nonisolated method.
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        cfg.httpAdditionalHeaders = ["User-Agent": "BeagleCockpit/1.0 (iOS exocortex stream)"]
        let session = URLSession(configuration: cfg)
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()

        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: Error? = nil
                for base in cockpitURLs {
                    guard let url = URL(string: "/api/mobile/v1/chat/stream", relativeTo: base) else { continue }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    BeagleEndpoints.applyCockpitAuth(to: &request)
                    request.timeoutInterval = 120
                    request.httpBody = payload
                    do {
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse,
                              (200..<300).contains(http.statusCode) else {
                            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                            lastError = NSError(domain: "BeagleChatStream", code: status,
                                userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
                            continue
                        }
                        // Parse SSE: lines starting with "data: <json>", events split by blank line.
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            guard line.hasPrefix("data:") else { continue }
                            let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            guard let data = json.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                continue
                            }
                            // ORDER IS CONTRACT: done → error → event → token. `done` carries a
                            // `presence` field of its own (the FLOOR layer) — checking presence
                            // first would swallow every degraded `done` and hang the stream.
                            if obj["done"] as? Bool == true {
                                if let err = obj["error"] as? String {
                                    continuation.finish(throwing: NSError(domain: "BeagleChatStream", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: err]))
                                    return
                                }
                                continuation.finish()
                                return
                            } else if let err = obj["error"] as? String {
                                continuation.finish(throwing: NSError(domain: "BeagleChatStream", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: err]))
                                return
                            } else if let event = obj["event"] as? String,
                                      event == "presence" || event == "phase" {
                                let phase = obj["phase"] as? String ?? event
                                let text = obj["text"] as? String ?? ""
                                onPhase?(phase, text)
                            } else if let token = obj["token"] as? String, !token.isEmpty {
                                continuation.yield(token)
                            }
                        }
                        continuation.finish()
                        return
                    } catch {
                        lastError = error
                        continue
                    }
                }
                continuation.finish(throwing: lastError ?? NSError(domain: "BeagleChatStream", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "all cockpit URLs failed"]))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Space weather (Kp/F10.7/solar wind for AuroraPresence)

    /// Fetch the latest geomagnetic snapshot from physiome (NOAA SWPC poller writes
    /// it every 2h), wrapped in `Truthful` with epistemic provenance and error detail.
    public func latestSpaceWeather() async -> Truthful<SpaceWeatherStore.Snapshot> {
        let bases = baseURLs == BeagleEndpoints.beagleServerURLs ? BeagleEndpoints.physiomeURLs : baseURLs
        print("[SpaceWeather/Client] ensureAuth…")
        let authed = await ensureAuth()
        print("[SpaceWeather/Client] auth=\(authed) trying \(bases.count) bases")
        var lastError = "space-weather endpoint unreachable"
        for base in bases {
            guard let url = URL(string: "/api/physiome/space-weather/latest", relativeTo: base) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            applyAuth(&request)
            do {
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[SpaceWeather/Client] \(base.host ?? "?") → HTTP \(code) (\(data.count)B)")
                guard (200..<300).contains(code) else {
                    lastError = "HTTP \(code)"
                    continue
                }
                struct Resp: Decodable { let ok: Bool; let latest: Latest? ; struct Latest: Decodable { let ts: String; let kp: Double; let dst: Double?; let f107: Double; let solar_wind_speed: Double?; let bz: Double?; let hp30: Double?; let ap30: Double?; let hp60: Double?; let cosmic_ray_oulu: Double?; let schumann_f1: Double?; let schumann_f2: Double?; let schumann_f3: Double?; let xray_flux: Double?; let proton_flux: Double?; let aurora_power: Double?; let sym_h: Double?; let ae_index: Double?; let source: String } }
                let resp = try decoder.decode(Resp.self, from: data)
                guard let l = resp.latest else {
                    return .staleError("space-weather payload contained no latest snapshot", source: url.host)
                }
                let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let ts = f.date(from: l.ts) ?? ISO8601DateFormatter().date(from: l.ts) ?? Date()
                let snapshot = SpaceWeatherStore.Snapshot(ts: ts, kp: l.kp, dst: l.dst, f107: l.f107, solarWindSpeed: l.solar_wind_speed, bz: l.bz, hp30: l.hp30, ap30: l.ap30, hp60: l.hp60, cosmicRayOulu: l.cosmic_ray_oulu, schumannF1: l.schumann_f1, schumannF2: l.schumann_f2, schumannF3: l.schumann_f3, xrayFlux: l.xray_flux, protonFlux: l.proton_flux, auroraPower: l.aurora_power, symH: l.sym_h, aeIndex: l.ae_index, source: l.source)
                return .observed(snapshot, source: url.host)
            } catch {
                lastError = error.localizedDescription
                print("[SpaceWeather/Client] \(base.host ?? "?") error: \(error.localizedDescription)")
                continue
            }
        }
        return .staleError(lastError)
    }

    /// Forecast (the forward half of the Agora charts): hourly temp/UV/AQI + the NOAA
    /// planetary-K 3-day forecast. Public endpoint (no auth), wrapped in `Truthful`.
    public func physiomeForecast() async -> Truthful<AgoraForecast> {
        let bases = BeagleEndpoints.physiomeURLs
        var lastError = "physiome forecast unreachable"
        for base in bases {
            guard let url = URL(string: "/api/physiome/forecast", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else {
                    lastError = "HTTP \(code)"
                    continue
                }
                let decoded = try decoder.decode(AgoraForecast.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                print("[AgoraForecast] \(base.host ?? "?") error: \(error.localizedDescription)")
                continue
            }
        }
        return .staleError(lastError)
    }
}
