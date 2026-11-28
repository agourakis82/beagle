import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import BeagleCore

private final class DirectBrainStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(contentsOf: buffer.prefix(count))
            }
            data = collected
        }
        guard let data,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = body["model"] as? String else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        // A substituted fallback model succeeds, making the rejection checks fail.
        let status = model == "gpt-5.5" ? 400 : (model == "gpt-5" ? 404 : 200)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]) else { return }
        guard url.path == "/v1/responses", body["input"] != nil,
              body["messages"] == nil, body["store"] as? Bool == false else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if let tools = body["tools"] as? [[String: Any]],
           tools.contains(where: { tool in
               if tool["function"] != nil { return true }
               let toolType = tool["type"] as? String ?? ""
               if toolType == "tool_search" || toolType == "web_search" || toolType == "mcp" {
                   return false
               }
               return tool["name"] == nil
           }) {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var payload: String
        if status != 200 {
            payload = "{\"error\":{\"message\":\"Rejected request\"}}"
        } else if model == "gpt-6.2-astra-fixture" {
            guard body["instructions"] as? String == "Agora: HRV 68 ms",
                  (body["reasoning"] as? [String: Any])?["effort"] as? String == "low" else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let output: [[String: Any]] = [
                ["type": "tool_search_call", "id": "tsc_1", "execution": "server", "status": "completed"],
                ["type": "web_search_call", "id": "ws_1", "status": "completed"],
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [[
                        "type": "output_text",
                        "text": "Dose conferida.",
                        "annotations": [[
                            "type": "url_citation",
                            "title": "PCDT SUS",
                            "url": "https://sus.gov.br/pcdt"
                        ]]
                    ]]
                ]
            ]
            let completedEvent: [String: Any] = [
                "type": "response.completed",
                "response": [
                    "status": "completed",
                    "model": "gpt-6.2-astra-2026-11-05",
                    "output": output
                ]
            ]
            let completedJSON = String(data: (try? JSONSerialization.data(withJSONObject: completedEvent)) ?? Data(), encoding: .utf8) ?? "{}"
            payload = "data: {\"type\":\"response.tool_search_call.searching\"}\n\n"
                + "data: {\"type\":\"response.web_search_call.searching\"}\n\n"
                + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Dose conferida.\"}\n\n"
                + "data: \(completedJSON)\n\n"
        } else if model == "failed-fixture" {
            payload = "data: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\"}}\n\n"
        } else if model == "truncated-fixture" {
            payload = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"
        } else if model == "tools-fixture" {
            let output: [[String: Any]] = [
                ["type": "reasoning", "id": "rs_fixture", "summary": [], "encrypted_content": "opaque-fixture"],
                ["type": "function_call", "id": "fc_fixture", "call_id": "call_fixture",
                 "name": "recall", "arguments": "{}"]
            ]
            let event: [String: Any] = ["type": "response.completed", "response": [
                "status": "completed", "model": "provider-snapshot", "output": output
            ]]
            let encoded = (try? JSONSerialization.data(withJSONObject: event)) ?? Data()
            payload = "data: " + (String(data: encoded, encoding: .utf8) ?? "") + "\n\n"
        } else {
            payload = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Olá\"}\n\n"
                + "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"model\":\"provider-snapshot\",\"output\":[]}}\n\n"
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ScienceStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let host = url.host?.lowercased() ?? ""
        let path = url.path

        var statusCode = 200
        var contentType = "application/json; charset=utf-8"
        var body = "{}"

        if host.contains("eutils.ncbi.nlm.nih.gov") && path.contains("esearch.fcgi") {
            body = #"{"esearchresult":{"count":"42","idlist":["38412345"]}}"#
        } else if host.contains("eutils.ncbi.nlm.nih.gov") && path.contains("efetch.fcgi") {
            contentType = "application/xml; charset=utf-8"
            body = """
            <?xml version="1.0"?>
            <PubmedArticleSet>
              <PubmedArticle>
                <MedlineCitation>
                  <PMID>38412345</PMID>
                  <Article>
                    <Journal>
                      <JournalIssue><PubDate><Year>2025</Year></PubDate></JournalIssue>
                      <Title>New England Journal of Medicine</Title>
                    </Journal>
                    <ArticleTitle>Intravenous Ketamine vs ECT in Treatment-Resistant Depression.</ArticleTitle>
                    <Abstract>
                      <AbstractText Label="BACKGROUND">Treatment-resistant depression remains challenging.</AbstractText>
                      <AbstractText Label="RESULTS">Response rate was 55.4% with ketamine vs 41.2% with ECT.</AbstractText>
                    </Abstract>
                    <AuthorList>
                      <Author><LastName>Anand</LastName><Initials>A</Initials></Author>
                      <Author><LastName>Mathew</LastName><Initials>SJ</Initials></Author>
                    </AuthorList>
                    <PublicationTypeList>
                      <PublicationType>Randomized Controlled Trial</PublicationType>
                    </PublicationTypeList>
                  </Article>
                </MedlineCitation>
                <PubmedData>
                  <ArticleIdList>
                    <ArticleId IdType="pubmed">38412345</ArticleId>
                    <ArticleId IdType="doi">10.1056/NEJMoa2302399</ArticleId>
                  </ArticleIdList>
                  <ReferenceList>
                    <Reference>
                      <ArticleIdList>
                        <ArticleId IdType="pubmed">11111111</ArticleId>
                        <ArticleId IdType="doi">10.1000/wrong-reference-doi</ArticleId>
                      </ArticleIdList>
                    </Reference>
                  </ReferenceList>
                </PubmedData>
              </PubmedArticle>
            </PubmedArticleSet>
            """
        } else if host.contains("api.crossref.org") {
            body = #"{"message":{"title":["Ketamine Comparative Effectiveness Trial"],"container-title":["NEJM"],"issued":{"date-parts":[[2025]]},"is-referenced-by-count":184,"author":[{"family":"Anand","given":"Amit"}]}}"#
        } else if host.contains("ebi.ac.uk") {
            body = #"{"resultList":{"result":[{"title":"Ketamine Comparative Effectiveness Trial","journalTitle":"NEJM","pubYear":"2025","pmid":"38412345","doi":"10.1056/NEJMoa2302399","abstractText":"Enriched abstract from EuropePMC confirming noninferiority of ketamine."}]}}"#
        } else if host.contains("export.arxiv.org") {
            contentType = "application/atom+xml; charset=utf-8"
            body = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <entry>
                <id>http://arxiv.org/abs/2405.12345v2</id>
                <published>2024-05-20T18:00:00Z</published>
                <title>Mechanistic PBPK Modeling of Rapid Antidepressants</title>
                <summary>We derive a multi-compartment blood-brain barrier model for S-ketamine.</summary>
                <author><name>Demetrios Agourakis</name></author>
              </entry>
            </feed>
            """
        } else if host.contains("html.duckduckgo.com") {
            contentType = "text/html; charset=utf-8"
            body = """
            <html><body>
              <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fsus.gov.br%2Fpcdt-depressao">PCDT Depressão SUS 2026</a>
              <a class="result__snippet">Diretriz oficial atualizada do Ministério da Saúde para manejo clínico.</a>
            </body></html>
            """
        } else if host.contains("example.org") {
            contentType = "text/html; charset=utf-8"
            body = """
            <html>
              <head><title>Diretriz Clínica de Teste</title><script>window.secret = 123;</script></head>
              <body>
                <h1>Resumo Executivo</h1>
                <p>Monitorar intervalo QTc &amp; função renal a cada 48h.</p>
              </body>
            </html>
            """
        } else {
            statusCode = 404
        }

        guard let resp = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ) else { return }
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct DirectBrainTransportTests {
    private func client() -> DirectBrainClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DirectBrainStubProtocol.self]
        return DirectBrainClient(session: URLSession(configuration: config))
    }

    @Test(arguments: [("gpt-5.5", 400), ("gpt-5", 404)])
    func providerErrorsDoNotSwitchModels(model: String, status: Int) async {
        do {
            _ = try await client().performOpenAIStreamRound(apiKey: "synthetic-fixture",
                model: model, messages: [], tools: [], onToken: { _ in })
            Issue.record("Provider rejection must propagate without model substitution.")
        } catch {
            #expect((error as NSError).code == status)
        }
    }

    @Test
    func recordsModelReportedByProvider() async throws {
        let result = try await client().performOpenAIStreamRound(apiKey: "synthetic-fixture",
            model: "requested-alias", messages: [], tools: [], onToken: { _ in })
        #expect(result.model == "provider-snapshot")
        #expect(result.content == "Olá")
    }

    @Test(arguments: ["failed-fixture", "truncated-fixture"])
    func rejectsFailedAndInterruptedResponses(model: String) async {
        do {
            _ = try await client().performOpenAIStreamRound(apiKey: "synthetic-fixture",
                model: model, messages: [], tools: [], onToken: { _ in })
            Issue.record("Incomplete Responses stream must fail.")
        } catch {
            #expect((error as NSError).domain == "DirectBrainClient" || error is URLError)
        }
    }

    @Test
    func preservesToolCallIdentityAndEncryptedReasoning() async throws {
        let result = try await client().performOpenAIStreamRound(apiKey: "synthetic-fixture",
            model: "tools-fixture", messages: [],
            tools: [["type": "function", "function": ["name": "recall", "parameters": ["type": "object"]]]],
            onToken: { _ in })
        #expect(result.toolCalls.first?.id == "call_fixture")
        #expect(result.toolCalls.first?.name == "recall")
        let data = try #require(result.outputItemsData)
        var continuation = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(continuation.first?["encrypted_content"] as? String == "opaque-fixture")
        continuation.append(["type": "function_call_output", "call_id": "call_fixture", "output": "memory"])
        let replay = DirectBrainClient.responsesInput(continuation)
        #expect(replay.last?["call_id"] as? String == "call_fixture")
        #expect(replay.first?["encrypted_content"] as? String == "opaque-fixture")
    }

    @Test
    func convertsVisionInput() {
        let result = DirectBrainClient.responsesInput([["role": "user", "content": [
            ["type": "text", "text": "Look"],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,fixture", "detail": "high"]]
        ]]])
        let content = result.first?["content"] as? [[String: Any]]
        #expect(content?.first?["type"] as? String == "input_text")
        #expect(content?.last?["type"] as? String == "input_image")
        #expect(content?.last?["image_url"] as? String == "data:image/jpeg;base64,fixture")
    }

    @Test
    func appleDeviceToolsSerializeAndExecuteCleanly() async throws {
        let defs = AppleDeviceToolsBridge.openAIToolDefinitions()
        #expect(defs.count == 7)
        let round = try await client().performOpenAIStreamRound(
            apiKey: "synthetic-fixture",
            model: "requested-alias",
            messages: [],
            tools: defs,
            onToken: { _ in }
        )
        #expect(round.content == "Olá")

        let badges = AppleDeviceToolsBridge.provenanceBadges(for: [
            "apple_calendar_list_events",
            "apple_calendar_create_event",
            "apple_reminders_create",
            "beagle_lookup_bula_pcdt",
            "apple_health_live_snapshot",
            "beagle_search_pubmed"
        ])
        #expect(badges == ["Agenda", "Lembretes", "Bula/PCDT", "HealthKit", "PubMed"])

        AppleDeviceToolsBridge.shared.registerLivePhysioProvider { refresh in
            "HRV 64 ms · refresh=\(refresh)"
        }
        let physioOut = await AppleDeviceToolsBridge.shared.execute(
            name: "apple_health_live_snapshot",
            args: ["refresh": false]
        )
        #expect(physioOut == "HRV 64 ms · refresh=false")
    }

    @Test
    func companionVoiceSanitizesAndChunksSpokenPortuguese() {
        let raw = """
        Nota rápida: pergunta viva sobre vancomicina.
        ---
        ### Ajuste renal
        Olha o **esquema** no [protocolo](https://sus.gov.br):
        ```swift
        let dose = 15
        ```
        Fica tranquilo comigo.
        """
        let clean = CompanionVoice.prepararTextoParaFala(raw)
        #expect(!clean.contains("Nota rápida"))
        #expect(!clean.contains("**"))
        #expect(!clean.contains("https://sus.gov.br"))
        #expect(clean.contains("protocolo"))
        #expect(clean.contains("Deixei o trecho de código escrito na mensagem."))
        #expect(clean.contains("Fica tranquilo comigo."))

        let longParagraph = Array(repeating: "Frase curta de teste clínico em português. ", count: 120).joined()
        let chunks = CompanionVoice.fatiarEmBlocosDeFala(longParagraph, limite: 1200)
        #expect(chunks.count >= 4)
        #expect(chunks.allSatisfy { $0.count <= 1200 && !$0.isEmpty })
    }

    @Test
    func pdfDocumentExtractsPagesAndSharedInboxRoundTrips() throws {
        // Synthesize a 2-page PDF in memory using CoreGraphics + CoreText
        let pdfBuffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfBuffer as CFMutableData) else {
            Issue.record("Failed to allocate CGDataConsumer")
            return
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            Issue.record("Failed to create PDF CGContext")
            return
        }
        let pages = [
            "Hemograma completo: Hemoglobina 14.8 g/dL, Ferritina 112 ng/mL",
            "Conclusão clínica: parâmetros hematológicos normais em vancomicina."
        ]
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        for pageText in pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(mediaBox)
            let attr = NSAttributedString(
                string: pageText,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font
                ]
            )
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 48, y: 740)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()

        let pdfData = pdfBuffer as Data
        let extracted = ChatDocumentPayload.extractSync(from: pdfData, fileName: "exame_hemograma.pdf")
        #expect(extracted != nil)
        #expect(extracted?.pageCount == 2)
        #expect(extracted?.extractedText.contains("[Pág. 1]") == true)
        #expect(extracted?.extractedText.contains("Hemoglobina 14.8") == true)
        #expect(extracted?.extractedText.contains("[Pág. 2]") == true)
        #expect(extracted?.coverJPEGData != nil)
        #expect(extracted?.promptBlock(maxChars: 4000).contains("exame_hemograma.pdf") == true)

        // Verify BeagleSharedInbox FIFO round-trip and automatic binary cleanup
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("beagle-shared-inbox-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let ok = BeagleSharedInbox.enqueue(
            text: "Olha este exame que recebi no WhatsApp",
            urls: ["https://pubmed.ncbi.nlm.nih.gov/12345/"],
            pdfData: pdfData,
            originalPDFName: "exame_hemograma.pdf",
            overrideRoot: tempRoot
        )
        #expect(ok == true)

        let loaded = BeagleSharedInbox.dequeueNext(overrideRoot: tempRoot)
        #expect(loaded != nil)
        #expect(loaded?.item.text == "Olha este exame que recebi no WhatsApp")
        #expect(loaded?.item.urls == ["https://pubmed.ncbi.nlm.nih.gov/12345/"])
        #expect(loaded?.item.originalPDFName == "exame_hemograma.pdf")
        #expect(loaded?.pdfData?.count == pdfData.count)
        // Queue must now be empty and binary file cleaned up
        #expect(BeagleSharedInbox.dequeueNext(overrideRoot: tempRoot) == nil)

        // Also check PDF provenance badge
        let pdfBadges = AppleDeviceToolsBridge.provenanceBadges(for: ["local_pdf_reader", "beagle_lookup_bula_pcdt"])
        #expect(pdfBadges == ["PDF", "Bula/PCDT"])
    }

    @Test
    func scienceAndWebBridgeParsesPubMedArXivWebAndExtractsReferences() async throws {
        // 1. Verify OpenAI /v1/responses tool serialization compatibility
        let scienceDefs = ScienceAndWebBridge.openAIToolDefinitions()
        #expect(scienceDefs.count == 4)
        let round = try await client().performOpenAIStreamRound(
            apiKey: "synthetic-fixture",
            model: "requested-alias",
            messages: [],
            tools: scienceDefs,
            onToken: { _ in }
        )
        #expect(round.content == "Olá")

        // 2. Verify reference detection (URLs, PubMed links, DOIs, arXiv IDs, PMIDs)
        let samplePrompt = "Compara https://pubmed.ncbi.nlm.nih.gov/38412345/, o DOI 10.1056/NEJMoa2302399, arXiv:2405.12345v2 e https://example.org/nota."
        let refs = ScienceAndWebBridge.extractReferences(from: samplePrompt, maxCount: 4)
        #expect(refs == [
            .pmid("38412345"),
            .url(URL(string: "https://example.org/nota")!),
            .doi("10.1056/NEJMoa2302399"),
            .arxiv("2405.12345v2")
        ])

        // 3. Verify stubbed end-to-end PubMed XML, Crossref+EuropePMC DOI, arXiv Atom, URL reader, and Web Search
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScienceStubProtocol.self]
        let bridge = ScienceAndWebBridge(session: URLSession(configuration: config), allowOpenAIHostedSearch: false)

        let pubmedOut = await bridge.execute(
            name: "beagle_search_pubmed",
            args: ["query": "ketamine ect depression", "max_results": 3, "min_year": 2023]
        )
        #expect(pubmedOut.contains("Intravenous Ketamine vs ECT"))
        #expect(pubmedOut.contains("PMID 38412345"))
        #expect(pubmedOut.contains("10.1056/NEJMoa2302399"))
        #expect(!pubmedOut.contains("10.1000/wrong-reference-doi"))
        #expect(!pubmedOut.contains("11111111"))
        #expect(pubmedOut.contains("Background: Treatment-resistant depression"))
        #expect(pubmedOut.contains("Results: Response rate was 55.4%"))

        let doiOut = await bridge.execute(
            name: "beagle_lookup_scientific_work",
            args: ["identifier_or_query": "10.1056/NEJMoa2302399"]
        )
        #expect(doiOut.contains("Ketamine Comparative Effectiveness Trial"))
        #expect(doiOut.contains("184 citações"))
        #expect(doiOut.contains("Enriched abstract from EuropePMC"))

        let arxivOut = await bridge.execute(
            name: "beagle_lookup_scientific_work",
            args: ["identifier_or_query": "arXiv:2405.12345v2"]
        )
        #expect(arxivOut.contains("Mechanistic PBPK Modeling of Rapid Antidepressants"))
        #expect(arxivOut.contains("Demetrios Agourakis"))

        let urlOut = await bridge.execute(
            name: "beagle_read_url",
            args: ["url": "https://example.org/diretriz"]
        )
        #expect(urlOut.contains("Diretriz Clínica de Teste"))
        #expect(urlOut.contains("Monitorar intervalo QTc & função renal a cada 48h."))
        #expect(!urlOut.contains("window.secret"))

        let searchOut = await bridge.execute(
            name: "beagle_web_search",
            args: ["query": "pcdt depressao sus"]
        )
        #expect(searchOut.contains("PCDT Depressão SUS 2026"))
        #expect(searchOut.contains("https://sus.gov.br/pcdt-depressao"))

        let prefetched = await bridge.prefetchContextForPrompt("Analisa https://pubmed.ncbi.nlm.nih.gov/38412345/ e https://example.org/diretriz")
        #expect(prefetched != nil)
        #expect(prefetched?.executedTools == ["beagle_search_pubmed", "beagle_read_url"])
        #expect(prefetched?.contextBlock.contains("PMID 38412345") == true)
        #expect(prefetched?.contextBlock.contains("Resumo Executivo") == true)

        // 4. Verify provenance badges on assistant bubbles
        let badges = AppleDeviceToolsBridge.provenanceBadges(for: [
            "beagle_search_pubmed",
            "beagle_lookup_scientific_work",
            "beagle_read_url",
            "beagle_web_search"
        ])
        #expect(badges == ["PubMed", "DOI/arXiv", "Web", "Busca Web"])
    }

    @Test
    @MainActor
    func spotlightIndexerAndCompanionDeepLinksRoundTrip() {
        // 1. DeepLinkRouter: Action Button voice, Siri prompt, Spotlight conversation jump, and Capture sheet
        let voiceURL = URL(string: "beagle://voice")!
        #expect(DeepLinkRouter.destination(for: voiceURL) == .chat)
        #expect(DeepLinkRouter.companionAction(for: voiceURL) == CompanionLaunchAction(
            startHandsFreeVoice: true,
            continuousVoiceSession: true
        ))

        let singleVoiceURL = URL(string: "beagle://voice?continuous=0")!
        #expect(DeepLinkRouter.companionAction(for: singleVoiceURL) == CompanionLaunchAction(
            startHandsFreeVoice: true,
            continuousVoiceSession: false
        ))

        let askURL = URL(string: "beagle://ask?q=ajuste%20renal%20vancomicina&send=1")!
        #expect(DeepLinkRouter.companionAction(for: askURL) == CompanionLaunchAction(
            initialPrompt: "ajuste renal vancomicina",
            autoSendPrompt: true,
            startHandsFreeVoice: false
        ))

        let convURL = URL(string: "beagle://conversation/conv:abc-123")!
        #expect(DeepLinkRouter.companionAction(for: convURL) == CompanionLaunchAction(conversationId: "conv:abc-123"))

        let router = DeepLinkRouter.shared
        #expect(router.open(voiceURL) == true)
        #expect(router.pending == .chat)
        let consumedAction = router.consumeCompanionAction()
        #expect(consumedAction?.startHandsFreeVoice == true)
        #expect(router.consumeCompanionAction() == nil)
        _ = router.consume()

        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://capture")!) == .capture)

        // 2. ConversationSpotlightIndexer: ID round-trip + searchable OCR / PDF / PubMed corpus
        let convId = "conv:fisioma-99"
        let spotId = ConversationSpotlightIndexer.spotlightIdentifier(for: convId)
        #expect(spotId == "beagle.conversation.conv:fisioma-99")
        #expect(ConversationSpotlightIndexer.conversationId(fromSpotlightIdentifier: spotId) == convId)
        #expect(ConversationSpotlightIndexer.conversationId(fromSpotlightIdentifier: "unrelated.item") == nil)

        let snapshot = SpotlightConversationSnapshot(
            conversationId: convId,
            title: "Nova conversa",
            projectSlug: "sounio",
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            rollingSummary: "Discussão prévia sobre PBPK cerebral e barreira hematoencefálica.",
            turns: [
                SpotlightMessageTurn(
                    role: "user",
                    content: "📄 hemograma.pdf · 2 pág.\nCompara este exame com o artigo PMID 38412345.",
                    attachmentDigest: "PDF anexado (hemograma.pdf): [Pág. 1] Ferritina 112 ng/mL\n### Artigo PubMed detectado no turno\nDOI 10.1056/NEJMoa2302399",
                    hasImage: true
                ),
                SpotlightMessageTurn(
                    role: "assistant",
                    content: "Nota rápida: checando ferritina.\n---\n**Ferritina em 112 ng/mL** está adequada e alinhada ao protocolo."
                )
            ]
        )
        let payload = ConversationSpotlightIndexer.buildSearchablePayload(from: snapshot)
        #expect(payload.uniqueIdentifier == spotId)
        #expect(payload.title.contains("hemograma.pdf"))
        #expect(payload.summaryDescription.contains("📄 PDF"))
        #expect(payload.summaryDescription.contains("📷 Imagem"))
        #expect(payload.summaryDescription.contains("🔬 Artigo"))
        #expect(payload.summaryDescription.contains("Ferritina em 112 ng/mL está adequada"))
        #expect(!payload.summaryDescription.contains("Nota rápida"))
        #expect(payload.fullTextCorpus.contains("barreira hematoencefálica"))
        #expect(payload.fullTextCorpus.contains("NEJMoa2302399"))
        #expect(payload.keywords.contains("PDF"))
        #expect(payload.keywords.contains("PubMed"))
    }

    @Test
    @MainActor
    func liveVoiceWalkieTalkieStateAndCommandBusRoundTrip() throws {
        var session = CompanionLiveVoiceSessionState()
        #expect(session.isActive == false)
        #expect(session.phase == .ended)

        // 1. Start session → Ouvindo
        session.start(voiceLabel: "MoE · Local + GPT")
        #expect(session.isActive == true)
        #expect(session.phase == .listening)
        #expect(session.turnCount == 0)
        #expect(session.phase.shortBadge == "OUV")

        // 2. Partial transcript → Committed utterance → Pensando → Falando → Rearm Ouvindo
        session.updatePartialTranscript("Qual a meia-vida plasmática da")
        #expect(session.liveLine.contains("meia-vida"))

        session.onUserUtteranceCommitted("Qual a meia-vida plasmática da cetamina?")
        #expect(session.phase == .thinking)
        #expect(session.turnCount == 1)
        #expect(session.phase.shortBadge == "PENS")

        session.updateThinkingNote("Consultando bula e PubMed…")
        #expect(session.liveLine == "Consultando bula e PubMed…")

        session.onAssistantSpeaking("Nota interna\n---\n**A meia-vida de eliminação** da cetamina gira em torno de 2 a 3 horas.")
        #expect(session.phase == .speaking)
        #expect(session.phase.shortBadge == "VOZ")
        #expect(!session.liveLine.contains("Nota interna"))
        #expect(!session.liveLine.contains("**"))
        #expect(session.liveLine.contains("A meia-vida de eliminação"))

        #expect(session.onSpeechFinishedRearm() == true)
        #expect(session.phase == .listening)

        // 3. Inactivity protection: 1st empty window re-arms; 2nd consecutive empty window auto-pauses
        #expect(session.onEmptySilenceWindow(maxStrikes: 2) == true)
        #expect(session.phase == .listening)
        #expect(session.emptySilenceStrikes == 1)

        #expect(session.onEmptySilenceWindow(maxStrikes: 2) == false)
        #expect(session.phase == .paused)
        #expect(session.phase.shortBadge == "PAUS")

        // 4. Interactive commands: resume from pause, interrupt speech, and end session
        session.apply(command: .togglePause)
        #expect(session.phase == .listening)
        #expect(session.emptySilenceStrikes == 0)

        session.onAssistantSpeaking("Continuando a explicação sobre o metabólito norcetamina…")
        #expect(session.phase == .speaking)
        session.apply(command: .interruptAndListen)
        #expect(session.phase == .listening)

        session.apply(command: .endSession)
        #expect(session.isActive == false)
        #expect(session.phase == .ended)
        #expect(session.onSpeechFinishedRearm() == false)

        // 5. CompanionLiveVoiceBus: in-memory dispatch + App Group UserDefaults fallback round-trip
        let suiteName = "beagle.livevoice.test.\(UUID().uuidString)"
        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let bus = CompanionLiveVoiceBus()
        var received: [CompanionLiveVoiceCommand] = []
        bus.onCommand = { cmd in received.append(cmd) }
        bus.dispatch(.togglePause, persistInDefaults: testDefaults)
        #expect(received == [.togglePause])
        #expect(bus.consumePendingCommand(from: testDefaults) == nil)

        // Simulate Dynamic Island LiveActivityIntent waking without an active ChatScreen listener
        bus.onCommand = nil
        bus.dispatch(.interruptAndListen, persistInDefaults: testDefaults)
        #expect(bus.consumePendingCommand(from: testDefaults) == .interruptAndListen)
        #expect(bus.consumePendingCommand(from: testDefaults) == nil)
    }

    @Test
    @MainActor
    func liveActivityClusterCoordinatorLifecycleAndRedaction() async throws {
        let suiteName = "beagle.livecluster.test.\(UUID().uuidString)"
        let testDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let token1 = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
        let token2 = "f0e1d2c3b4a5968778695a4b3c2d1e0ff0e1d2c3b4a5968778695a4b3c2d1e0f"

        let samplePayload = LiveActivityRegistrationPayload(
            installationId: "inst-test",
            activityId: "act-research-42",
            kind: .research,
            canonicalId: "run-42",
            projectSlug: "science",
            bundleId: "dev.sounio.cockpit",
            apnsEnvironment: "development",
            pushToken: token1,
            tokenRevision: 1
        )
        #expect(!String(describing: samplePayload).contains(token1))
        #expect(!String(reflecting: samplePayload).contains(token1))
        #expect(String(describing: samplePayload).contains("<redacted>"))

        actor MockGateway {
            var shouldFail = true
            var remoteDeliveryActive = false
            var registrations: [LiveActivityRegistrationPayload] = []
            var revocations: [(String, String, String)] = []

            func configure(shouldFail: Bool, remoteDeliveryActive: Bool) {
                self.shouldFail = shouldFail
                self.remoteDeliveryActive = remoteDeliveryActive
            }

            func register(_ p: LiveActivityRegistrationPayload) -> Truthful<LiveActivityRegistrationAck> {
                registrations.append(p)
                if shouldFail {
                    return .staleError("offline")
                }
                return .observed(
                    LiveActivityRegistrationAck(
                        registrationId: "reg-1",
                        activityId: p.activityId,
                        installationId: p.installationId,
                        kind: p.kind,
                        canonicalId: p.canonicalId,
                        agentKind: p.agentKind,
                        projectSlug: p.projectSlug,
                        bundleId: p.bundleId,
                        apnsEnvironment: p.apnsEnvironment,
                        tokenRevision: p.tokenRevision,
                        registeredAt: "2026-11-26T15:00:00Z",
                        updatedAt: "2026-11-26T15:00:00Z",
                        expiresAt: "2026-11-26T23:00:00Z",
                        revoked: false,
                        terminal: false,
                        apnsConfigured: remoteDeliveryActive,
                        remoteDeliveryActive: remoteDeliveryActive
                    ),
                    source: "mock-cockpit"
                )
            }

            func revoke(activityId: String, installationId: String, reason: String) -> Truthful<LiveActivityRevokeAck> {
                revocations.append((activityId, installationId, reason))
                return .observed(
                    LiveActivityRevokeAck(activityId: activityId, revoked: true, alreadyAbsent: false),
                    source: "mock-cockpit"
                )
            }
        }

        let gateway = MockGateway()
        let coordinator = LiveActivityClusterCoordinator(
            defaults: testDefaults,
            bundleId: "dev.sounio.cockpit",
            apnsEnvironment: "development",
            observeNetworkReconnect: false,
            registerTransport: { payload in await gateway.register(payload) },
            revokeTransport: { actId, instId, reason in
                await gateway.revoke(activityId: actId, installationId: instId, reason: reason)
            }
        )

        // 1. Offline registration fails gracefully and preserves local foreground writes
        let offlineAck = await coordinator.submitHexPushToken(
            token1,
            activityId: "act-research-42",
            kind: .research,
            canonicalId: "run-42",
            projectSlug: "science"
        )
        #expect(offlineAck == nil)
        #expect(coordinator.shouldWriteLocally(activityId: "act-research-42") == true)

        // 2. Reconnect resubmission with APNs active flips writer handoff (shouldWriteLocally == false)
        await gateway.configure(shouldFail: false, remoteDeliveryActive: true)
        await coordinator.resubmitAllActive()
        #expect(coordinator.shouldWriteLocally(activityId: "act-research-42") == false)
        #expect((await gateway.registrations).count == 2)

        // 3. Duplicate submission of the exact same acknowledged token is suppressed
        let dupAck = await coordinator.submitHexPushToken(
            token1,
            activityId: "act-research-42",
            kind: .research,
            canonicalId: "run-42",
            projectSlug: "science"
        )
        #expect(dupAck == nil)
        #expect((await gateway.registrations).count == 2)

        // 4. Token rotation advances tokenRevision monotonically and never persists raw token in UserDefaults
        let rotatedAck = await coordinator.submitHexPushToken(
            token2,
            activityId: "act-research-42",
            kind: .research,
            canonicalId: "run-42",
            projectSlug: "science"
        )
        #expect(rotatedAck?.tokenRevision == 2)
        let persistedData = try #require(
            testDefaults.data(forKey: "dev.sounio.cockpit.liveActivity.associations.v1")
        )
        let persistedJSON = String(decoding: persistedData, as: UTF8.self)
        #expect(!persistedJSON.contains(token1))
        #expect(!persistedJSON.contains(token2))

        // 5. Relaunch reloads association metadata and reconcileSurvivingActivities revokes missing IDs
        let relaunched = LiveActivityClusterCoordinator(
            defaults: testDefaults,
            bundleId: "dev.sounio.cockpit",
            apnsEnvironment: "development",
            observeNetworkReconnect: false,
            registerTransport: { payload in await gateway.register(payload) },
            revokeTransport: { actId, instId, reason in
                await gateway.revoke(activityId: actId, installationId: instId, reason: reason)
            }
        )
        #expect(relaunched.installationId == coordinator.installationId)
        #expect(relaunched.associations["act-research-42"]?.tokenRevision == 2)

        await relaunched.reconcileSurvivingActivities(activeIds: [])
        #expect(relaunched.associations.isEmpty)
        let revocations = await gateway.revocations
        #expect(revocations.count == 1)
        #expect(revocations[0].0 == "act-research-42")
        #expect(revocations[0].2 == "relaunch_missing")
    }

    // The package's hostless iOS runner has no Keychain access group. Exercise
    // the real Keychain lifecycle on macOS instead of weakening accessibility.
    #if os(macOS)
    @Test
    func migratesReplacesAndClearsLegacyCredential() {
        let account = "beagle.fixture.\(UUID().uuidString)"
        defer {
            DirectCredentialKeychain.save("", account: account)
            UserDefaults.standard.removeObject(forKey: account)
        }
        UserDefaults.standard.set(" synthetic-fixture ", forKey: account)
        #expect(DirectCredentialKeychain.load(account: account) == "synthetic-fixture")
        #expect(UserDefaults.standard.object(forKey: account) == nil)
        #expect(DirectCredentialKeychain.load(account: account) == "synthetic-fixture")
        #expect(DirectCredentialKeychain.save("replacement-fixture", account: account))
        #expect(DirectCredentialKeychain.load(account: account) == "replacement-fixture")
        #expect(DirectCredentialKeychain.save("", account: account))
        #expect(DirectCredentialKeychain.load(account: account) == nil)
    }
    #endif

    @Test
    @MainActor
    func openAIRealtime21MiniAndGPTLive11ProtocolRoundTrip() throws {
        // 1. CompanionVoice: PCM16LE 24kHz -> 44-byte RIFF/WAVE header + odd-byte trimming
        let pcmSamples = Data([0x01, 0x02, 0x03, 0x04, 0xFF]) // 5 bytes -> trims trailing odd byte -> 4 bytes payload
        let wav = CompanionVoice.encapsularPCM16EmWAV(pcmSamples, sampleRate: 24_000, channels: 1, bitsPerSample: 16)
        #expect(wav.count == 48) // 44 header + 4 aligned PCM bytes
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: wav[12..<16], as: UTF8.self) == "fmt ")
        #expect(String(decoding: wav[36..<40], as: UTF8.self) == "data")

        // 2. Voice normalization for GPT-Live vs GA Realtime TTS
        #expect(CompanionVoice.normalizedLiveVoice("tempo") == "tempo")
        #expect(CompanionVoice.normalizedLiveVoice("bossa") == "bossa")
        #expect(CompanionVoice.normalizedLiveVoice("onyx") == "cedar")
        #expect(CompanionVoice.normalizedRealtimeTTSVoice("tempo") == "cedar")
        #expect(CompanionVoice.normalizedRealtimeTTSVoice("bossa") == "marin")
        #expect(CompanionVoice.normalizedRealtimeTTSVoice("marin") == "marin")

        // 3. GA Realtime `session.update` & out-of-band `response.create` (`conversation: "none"`, `output_modalities: ["audio"]`)
        let sessionUpdate = CompanionVoice.realtimeSessionUpdatePayload(voice: "tempo")
        let rtSession = try #require(sessionUpdate["session"] as? [String: Any])
        #expect(rtSession["type"] as? String == "realtime")
        #expect(rtSession["output_modalities"] as? [String] == ["audio"])
        let rtAudioOut = try #require((rtSession["audio"] as? [String: Any])?["output"] as? [String: Any])
        #expect(rtAudioOut["voice"] as? String == "cedar")
        #expect((rtAudioOut["format"] as? [String: Any])?["rate"] as? Int == 24_000)

        let speechCreate = CompanionVoice.realtimeSpeechResponsePayload(texto: "Bom plantão, Demetrios.")
        let rtResp = try #require(speechCreate["response"] as? [String: Any])
        #expect(rtResp["conversation"] as? String == "none")
        #expect(rtResp["output_modalities"] as? [String] == ["audio"])

        // 4. GPT-Live (`gpt-live-1.1`) `session.start` with `delegation: { type: "client" }`
        let inputItems = OpenAILiveProtocol.buildInitialInputItems(
            priorMessages: [(.user, "Oi"), (.assistant, "Tô contigo.")],
            agoraDeveloperNote: "HRV 68 ms",
            greetOnOpen: true
        )
        #expect(inputItems.count == 4)
        let startPayload = OpenAILiveProtocol.buildSessionStartPayload(
            voice: "marin",
            instructions: OpenAILiveProtocol.buildBeagleLiveInstructions(),
            inputItems: inputItems
        )
        #expect(startPayload["type"] as? String == "session.start")
        let liveSession = try #require(startPayload["session"] as? [String: Any])
        #expect(liveSession["model"] as? String == "gpt-live-1.1")
        #expect((liveSession["delegation"] as? [String: Any])?["type"] as? String == "client")

        // 5. 2-byte PCM16 carryover alignment across odd WebSocket mic frames
        var carryover = Data()
        let firstOdd = OpenAILiveProtocol.buildInputAudioAppendPayload(chunk: Data([0xAA, 0xBB, 0xCC]), carryoverByte: &carryover)
        #expect(carryover == Data([0xCC]))
        let firstDecoded = try #require(Data(base64Encoded: (firstOdd?["audio"] as? String) ?? ""))
        #expect(firstDecoded == Data([0xAA, 0xBB]))

        let secondOdd = OpenAILiveProtocol.buildInputAudioAppendPayload(chunk: Data([0xDD]), carryoverByte: &carryover)
        #expect(carryover.isEmpty)
        let secondDecoded = try #require(Data(base64Encoded: (secondOdd?["audio"] as? String) ?? ""))
        #expect(secondDecoded == Data([0xCC, 0xDD]))

        // 6. <=500-token context append serialization (`null` vs string `delegation_id`)
        let longText = Array(repeating: "Dose verificada na bula ANVISA de cetamina endovenosa. ", count: 60).joined()
        let delAppend = try #require(OpenAILiveProtocol.buildContextAppendPayload(
            kind: .thinking,
            delegationId: "del_99",
            content: longText
        ))
        let delJSON = String(decoding: try JSONSerialization.data(withJSONObject: delAppend), as: UTF8.self)
        #expect(delJSON.contains("\"delegation_id\":\"del_99\""))
        #expect(((delAppend["content"] as? String)?.count ?? 9999) <= OpenAILiveProtocol.maxAppendCharacters + 4)

        let globalAppend = try #require(OpenAILiveProtocol.buildContextAppendPayload(
            kind: .instructions,
            delegationId: nil,
            content: "Escute em silêncio."
        ))
        let globalJSON = String(decoding: try JSONSerialization.data(withJSONObject: globalAppend), as: UTF8.self)
        #expect(globalJSON.contains("\"delegation_id\":null"))

        // 7. Server event parsing + ConversationStore live bubble upsert
        let delEventData = Data(#"{"type":"session.delegation.created","delegation":{"id":"del_abc","target":"client"},"offset_ms":4200}"#.utf8)
        #expect(OpenAILiveProtocol.parseServerEvent(delEventData) == .delegationCreated(id: "del_abc", target: "client", offsetMs: 4200))

        let store = ConversationStore()
        let bubbleId = UUID()
        store.upsertGPTLiveBubble(id: bubbleId, role: .assistant, text: "Checando a meia-vida", isFinal: false)
        #expect(store.messages.count == 1)
        #expect(store.messages.first?.isStreaming == true)
        store.upsertGPTLiveBubble(id: bubbleId, role: .assistant, text: "Checando a meia-vida: 2,5 horas.", isFinal: true, executedTools: ["beagle_lookup_bula_pcdt"])
        #expect(store.messages.count == 1)
        #expect(store.messages.first?.isStreaming == false)
        #expect(store.messages.first?.executedTools == ["beagle_lookup_bula_pcdt"])
    }

    @Test
    func gpt62PromptCachingToolSearchAndWebSearchEndToEnd() async throws {
        // 1. Catalog & GPT-6.2 reasoning.effort constraints ("none" -> "low" on gpt-6*)
        #expect(OpenAIModelCatalog.defaultFlagshipModel == "gpt-6.2-astra")
        #expect(OpenAIModelCatalog.defaultDailyAgentModel == "gpt-6.2-sol")
        #expect(OpenAIModelCatalog.supportsToolSearch("gpt-6.2-astra") == true)
        #expect(OpenAIModelCatalog.supportsToolSearch("gpt-4o-mini") == false)
        #expect(OpenAIReasoningEffort.sanitizedEffort("none", forModel: "gpt-6.2-astra") == "low")
        #expect(OpenAIReasoningEffort.sanitizedEffort("none", forModel: "gpt-5.5") == "none")
        #expect(OpenAIReasoningEffort.sanitizedEffort("auto", forModel: "gpt-6.2-astra") == nil)

        // 2. Split prompt preserves reusable developer prefix vs per-turn dynamic instructions
        let split = await client().buildSplitSystemPrompt(
            cachedGrounding: "Identidade estavel do Beagle para Demetrios.",
            physioSummary: nil,
            physioContext: "HRV 68 ms",
            currentSky: nil,
            flowState: "FLOW",
            sleepQuality01: 0.82,
            voiceTone: nil,
            lastContactAt: nil,
            rollingSummary: "Resumo anterior.",
            recentThreadDigest: nil,
            recalledMemories: "Memória PBPK.",
            moeLocalUncensoredDraft: "Rascunho local."
        )
        #expect(split.developerPrefix.contains("Identidade estavel do Beagle"))
        #expect(!split.developerPrefix.contains("HRV 68 ms"))
        #expect(split.turnInstructions.contains("HRV 68 ms"))
        #expect(split.turnInstructions.contains("Memória PBPK."))
        #expect(split.turnInstructions.contains("Rascunho local."))

        // 3. Responses 2026 tool namespaces (< 10 tools per namespace, immediate Bula/PCDT + memory, tool_search + web_search)
        let dummyMCP = (1...12).map { idx in
            MCPToolSummary(name: "mcp_custom_\(idx)", title: "Custom \(idx)", description: "Desc \(idx)", inputSchema: nil, annotations: nil)
        }
        let tools2026 = client().buildResponsesTools2026(
            mcpTools: dummyMCP,
            model: "gpt-6.2-astra",
            enableNativeWebSearch: true,
            enableToolSearch: true
        )
        let topImmediateFunctions = tools2026.filter { ($0["type"] as? String) == "function" }
        let immediateNames = Set(topImmediateFunctions.compactMap { $0["name"] as? String })
        #expect(immediateNames == ["beagle_search_memory", "beagle_store_memory", "beagle_lookup_bula_pcdt"])
        #expect(topImmediateFunctions.allSatisfy { $0["defer_loading"] == nil })

        let namespaces = tools2026.filter { ($0["type"] as? String) == "namespace" }
        #expect(namespaces.count >= 4) // science_literature, apple_device, beagle_mcp, beagle_mcp_2
        for ns in namespaces {
            let nsTools = try #require(ns["tools"] as? [[String: Any]])
            #expect(nsTools.count < 10)
            #expect(nsTools.allSatisfy { ($0["defer_loading"] as? Bool) == true })
        }
        #expect(tools2026.contains(where: { ($0["type"] as? String) == "tool_search" }))
        #expect(tools2026.contains(where: { ($0["type"] as? String) == "web_search" }))

        // 4. End-to-end round with GPT-6.2 instructions, sanitized reasoning.effort, tool_search, web_search, and URL citations
        actor StatusCollector {
            var statuses: [String] = []
            func append(_ s: String) { statuses.append(s) }
        }
        let collector = StatusCollector()
        let round = try await client().performOpenAIStreamRound(
            apiKey: "synthetic-fixture",
            model: "gpt-6.2-astra-fixture",
            messages: [["role": "developer", "content": split.developerPrefix], ["role": "user", "content": "Confere o PCDT."]],
            tools: tools2026,
            instructions: "Agora: HRV 68 ms",
            reasoningEffort: "none",
            onStatus: { s in await collector.append(s) },
            onToken: { _ in }
        )
        #expect(round.model == "gpt-6.2-astra-2026-11-05")
        #expect(round.builtInToolsUsed == ["openai_tool_search", "openai_web_search"])
        #expect(round.content.contains("Dose conferida."))
        #expect(round.content.contains("[PCDT SUS](https://sus.gov.br/pcdt)"))
        let statuses = await collector.statuses
        #expect(statuses.count == 2)

        let badges = AppleDeviceToolsBridge.provenanceBadges(for: round.builtInToolsUsed)
        #expect(badges == ["Tool Search", "Web OpenAI"])
    }

    @Test
    func openAIAgentsSessionProtocolAndSSELifecycle() throws {
        // 1. Create Session Request (`POST /v1/agents/sessions`, `OpenAI-Beta: agents=v1`, `openai_hosted`)
        let createReq = try OpenAIAgentsSessionClient.buildCreateSessionRequest(
            apiKey: "sk-test-agents",
            model: "gpt-6.2-astra",
            instructions: "Inspecione o repositório Sounio.",
            initialInput: "Rode os testes unitários."
        )
        #expect(createReq.httpMethod == "POST")
        #expect(createReq.url?.absoluteString == "https://api.openai.com/v1/agents/sessions")
        #expect(createReq.value(forHTTPHeaderField: "OpenAI-Beta") == "agents=v1")
        let createData = try #require(createReq.httpBody)
        let createBody = try #require(JSONSerialization.jsonObject(with: createData) as? [String: Any])
        #expect((createBody["agent"] as? [String: Any])?["model"] as? String == "gpt-6.2-astra")
        #expect((createBody["environment"] as? [String: Any])?["type"] as? String == "openai_hosted")
        #expect(createBody["stream"] as? Bool == true)

        // 2. Mid-turn steering / follow-up message (`Idempotency-Key` + `agent.session.input.message`)
        let steerReq = try OpenAIAgentsSessionClient.buildSendMessageRequest(
            apiKey: "sk-test-agents",
            sessionId: "ses_123",
            text: "Foque primeiro em BeagleCore.",
            submissionKey: "idem-uuid-42"
        )
        #expect(steerReq.url?.absoluteString == "https://api.openai.com/v1/agents/sessions/ses_123/events")
        #expect(steerReq.value(forHTTPHeaderField: "Idempotency-Key") == "idem-uuid-42")
        #expect(steerReq.value(forHTTPHeaderField: "OpenAI-Beta") == "agents=v1")

        // 3. Cancel active turn (`agent.session.input.cancel`)
        let cancelReq = try OpenAIAgentsSessionClient.buildCancelTurnRequest(
            apiKey: "sk-test-agents",
            sessionId: "ses_123"
        )
        let cancelData = try #require(cancelReq.httpBody)
        let cancelBody = try #require(JSONSerialization.jsonObject(with: cancelData) as? [String: Any])
        let events = try #require(cancelBody["events"] as? [[String: Any]])
        #expect(events.first?["type"] as? String == "agent.session.input.cancel")

        // 4. SSE event parsing (root turn vs subagent turn completion)
        let createdEvt = try OpenAIAgentsSessionClient.parseEventJSON([
            "type": "agent.session.created",
            "session_id": "ses_123"
        ])
        #expect(createdEvt.extractedSessionId == "ses_123")
        #expect(createdEvt.mapped == .sessionCreated(sessionId: "ses_123"))

        let deltaEvt = try OpenAIAgentsSessionClient.parseEventJSON([
            "type": "agent.session.turn.output_text.delta",
            "item_id": "msg_1",
            "delta": "Compilação limpa."
        ])
        #expect(deltaEvt.mapped == .textDelta(itemId: "msg_1", delta: "Compilação limpa."))

        // Subagent turn completion MUST NOT end the root turn
        let subagentCompleted = try OpenAIAgentsSessionClient.parseEventJSON([
            "type": "agent.session.turn.completed",
            "turn": ["id": "turn_sub", "subagent_id": "sub_99"]
        ])
        #expect(subagentCompleted.isRootTurnTerminal == false)
        #expect(subagentCompleted.mapped != .turnCompleted)

        // Root turn completion (`subagent_id` nil) ends the turn
        let rootCompleted = try OpenAIAgentsSessionClient.parseEventJSON([
            "type": "agent.session.turn.completed",
            "turn": ["id": "turn_root"]
        ])
        #expect(rootCompleted.isRootTurnTerminal == true)
        #expect(rootCompleted.mapped == .turnCompleted)
    }

    @Test
    @MainActor
    func goDeepStoreAstraXHighRosalindAndStructuredFallback() async throws {
        final class OfflineClusterProtocol: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url,
                      let resp = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(#"{"error":"cluster offline"}"#.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        final class ModoFundoStubProtocol: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url else { return }
                var data = request.httpBody
                if data == nil, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buf = [UInt8](repeating: 0, count: 4096)
                    var out = Data()
                    while stream.hasBytesAvailable {
                        let n = stream.read(&buf, maxLength: buf.count)
                        if n <= 0 { break }
                        out.append(contentsOf: buf.prefix(n))
                    }
                    data = out
                }
                guard let data,
                      let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let model = body["model"] as? String else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                    return
                }
                let effort = (body["reasoning"] as? [String: Any])?["effort"] as? String ?? ""
                let textOut: String
                var outputItems: [[String: Any]] = []

                if model == "gpt-6.2-astra" && effort == "xhigh" {
                    textOut = "A cinética fractal de S-cetamina exibe acoplamento multiescala na BHE.\n\nEvidência primária em [NEJM 2025](https://doi.org/10.1056/NEJMoa2302399)."
                    outputItems = [["type": "web_search_call", "id": "ws_astra", "status": "completed"]]
                } else if model == "gpt-rosalind" {
                    #expect(effort == "high")
                    textOut = "O clearance hepático CYP2B6/CYP3A4 governa a conversão em norcetamina.\n\nRef: [PMID 38412345](https://pubmed.ncbi.nlm.nih.gov/38412345/)."
                } else if model == "gpt-6.2-sol" {
                    textOut = #"{"summary":"Bloqueio NMDA dispara BDNF sináptico.","nodes":[{"id":"n1","label":"NMDA","type":"cause"},{"id":"n2","label":"BDNF","type":"outcome"}],"edges":[{"source":"NMDA","target":"BDNF","strength":0.89,"label":"desinibe"}]}"#
                } else {
                    // Synthesis pass on gpt-6.2-astra (effort == "high")
                    textOut = "Síntese convergente: cinética PBPK na BHE + desinibição glutamatérgica via BDNF."
                }

                outputItems.append([
                    "type": "message",
                    "role": "assistant",
                    "content": [["type": "output_text", "text": textOut]]
                ])
                let completed: [String: Any] = [
                    "type": "response.completed",
                    "response": ["status": "completed", "model": model, "output": outputItems]
                ]
                let json = String(data: (try? JSONSerialization.data(withJSONObject: completed)) ?? Data(), encoding: .utf8) ?? "{}"
                let sse = "data: {\"type\":\"response.output_text.delta\",\"delta\":\(String(data: (try? JSONSerialization.data(withJSONObject: [textOut])) ?? Data(), encoding: .utf8)?.dropFirst().dropLast() ?? "\"\"")}\n\ndata: \(json)\n\n"

                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(sse.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        DirectBrainCredentials.testOpenAIKeyOverride = "sk-test-fundo"
        defer { DirectBrainCredentials.testOpenAIKeyOverride = nil }

        let clusterCfg = URLSessionConfiguration.ephemeral
        clusterCfg.protocolClasses = [OfflineClusterProtocol.self]
        let offlineCluster = BeagleClient(
            session: URLSession(configuration: clusterCfg),
            baseURLs: [URL(string: "https://offline.beagle.test")!]
        )

        let brainCfg = URLSessionConfiguration.ephemeral
        brainCfg.protocolClasses = [ModoFundoStubProtocol.self]
        let stubBrain = DirectBrainClient(session: URLSession(configuration: brainCfg), skipRemoteMCPTools: true)

        let store = GoDeepStore(
            client: offlineCluster,
            directBrain: stubBrain,
            enabledModalities: [.astraDeep, .rosalindBio, .causalExtract]
        )
        store.enableLiveResearchTools = false // skip external PubMed prefetch in unit test

        await store.goDeeperAndWait(prompt: "Modelagem PBPK da S-cetamina na depressão resistente")

        #expect(store.allComplete == true)
        #expect(store.hasErrors == false)
        #expect(store.completedCount == 3)
        #expect(store.synthesis?.contains("Síntese convergente") == true)

        let astraState = try #require(store.modalityStates.first(where: { $0.modality == .astraDeep }))
        if case .astraDeep(let t) = try #require(astraState.result) {
            #expect(t.value?.reasoningEffort == "xhigh")
            #expect(t.value?.executedTools.contains("openai_web_search") == true)
            #expect(t.value?.citations.first?.url == "https://doi.org/10.1056/NEJMoa2302399")
        } else {
            Issue.record("Expected .astraDeep result")
        }

        let rosalindState = try #require(store.modalityStates.first(where: { $0.modality == .rosalindBio }))
        if case .rosalindBio(let t) = try #require(rosalindState.result) {
            #expect(t.value?.model == "gpt-rosalind")
            #expect(t.value?.citations.first?.url == "https://pubmed.ncbi.nlm.nih.gov/38412345/")
        } else {
            Issue.record("Expected .rosalindBio result")
        }

        let causalState = try #require(store.modalityStates.first(where: { $0.modality == .causalExtract }))
        if case .causal(let t) = try #require(causalState.result) {
            #expect(t.mode == .observed)
            #expect(t.value?.edges?.first?.strength == 0.89)
        } else {
            Issue.record("Expected .causal structured fallback result")
        }

        // Also test RoundTableStore parallel Direct Brain fallback using the same offline cluster + stub brain
        let mesa = RoundTableStore(client: offlineCluster, directBrain: stubBrain)
        mesa.enableLiveResearchTools = false
        mesa.selectedVoices = [.consciousness, .reality, .quantum]
        await mesa.debate(prompt: "PBPK fractal e consciência")

        let mesaResult = try #require(mesa.result)
        #expect(mesa.error == nil)
        #expect(mesaResult.voices?.count == 3)
        let pci = try #require(mesaResult.pciScore)
        #expect(pci >= 0.42 && pci <= 0.96)
        #expect(mesaResult.synthesis?.isEmpty == false)
        let chatMsgs = mesa.resultAsMessages()
        #expect(chatMsgs.count == 4)
        #expect(chatMsgs.last?.voiceName?.contains("Síntese") == true)
    }

    @Test
    @MainActor
    func liveActivityDeepLinksAndLensProgressTransitions() async throws {
        // 1. DeepLinkRouter routes beagle://fundo and beagle://sintese + aliases
        let router = DeepLinkRouter.shared
        _ = router.consume()
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://fundo")!) == .fundo)
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://modo-fundo")!) == .fundo)
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://sintese")!) == .sintese)
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://daily-synthesis")!) == .sintese)
        router.request(.fundo)
        #expect(router.consume() == .fundo)
        router.request(.sintese)
        #expect(router.consume() == .sintese)

        // 2. ResearchRunAttributes.ContentState backward compatibility with legacy cluster APNs payloads
        #if os(iOS)
        let legacyJSON = Data(#"{"stepCurrent":2,"stepTotal":5,"etaSeconds":45}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(ResearchRunAttributes.ContentState.self, from: legacyJSON)
        #expect(decodedLegacy.stepCurrent == 2)
        #expect(decodedLegacy.activeLens == nil)
        #expect(decodedLegacy.isCompleted == nil)

        let richState = ResearchRunAttributes.ContentState(
            stepCurrent: 3,
            stepTotal: 4,
            etaSeconds: 12,
            activeLens: "Síntese Executiva",
            summarySnippet: "Convergência PBPK confirmada.",
            isCompleted: false
        )
        let encodedRich = try JSONEncoder().encode(richState)
        let decodedRich = try JSONDecoder().decode(ResearchRunAttributes.ContentState.self, from: encodedRich)
        #expect(decodedRich.activeLens == "Síntese Executiva")
        #expect(decodedRich.summarySnippet == "Convergência PBPK confirmada.")
        #expect(decodedRich.isCompleted == false)
        #endif

        // 3. GoDeepStore emits lens transitions through onResearchStateChange
        final class FastStubProtocol: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url else { return }
                if url.host == "offline.beagle.test" {
                    let r = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
                    client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
                let completed: [String: Any] = [
                    "type": "response.completed",
                    "response": [
                        "status": "completed",
                        "model": "gpt-6.2-astra",
                        "output": [[
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": "Resultado conciso verificado."]]
                        ]]
                    ]
                ]
                let json = String(data: (try? JSONSerialization.data(withJSONObject: completed)) ?? Data(), encoding: .utf8) ?? "{}"
                let sse = "data: \(json)\n\n"
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(sse.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        DirectBrainCredentials.testOpenAIKeyOverride = "sk-test-la"
        defer { DirectBrainCredentials.testOpenAIKeyOverride = nil }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FastStubProtocol.self]
        let session = URLSession(configuration: cfg)
        let store = GoDeepStore(
            client: BeagleClient(session: session, baseURLs: [URL(string: "https://offline.beagle.test")!]),
            directBrain: DirectBrainClient(session: session, skipRemoteMCPTools: true),
            enabledModalities: [.astraDeep, .rosalindBio]
        )
        store.enableLiveResearchTools = false

        var recordedLenses: [String] = []
        var sawCompleted = false
        store.onResearchStateChange = { _, _, _, lens, _, done in
            if let lens { recordedLenses.append(lens) }
            if done { sawCompleted = true }
        }

        await store.goDeeperAndWait(prompt: "Teste Live Activity Modo Fundo")
        #expect(recordedLenses.first == "Astra xhigh · Rosalind PBPK")
        #expect(recordedLenses.contains("Síntese Executiva"))
        #expect(recordedLenses.last == "Concluído")
        #expect(sawCompleted == true)
    }

    @Test
    func scientificDossierExporterHarvestsCitationsBibTeXMarkdownAndVectorPDF() async throws {
        var astraState = ModalityState(modality: .astraDeep)
        astraState.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        astraState.completedAt = Date(timeIntervalSince1970: 1_700_000_004)
        astraState.phase = .resolved(.astraDeep(.observed(
            FrontierResearchResult(
                model: "gpt-6.2-astra",
                reasoningEffort: "xhigh",
                thesis: "Acoplamento PBPK fractal.",
                analysisMarkdown: "Evidência primária em [Trial NEJM 2025](https://doi.org/10.1056/NEJMoa2302399) e preprint arXiv:2603.12345v2.",
                executedTools: ["openai_web_search"],
                citations: [FrontierCitation(title: "Trial NEJM 2025", url: "https://doi.org/10.1056/NEJMoa2302399")]
            ),
            source: "gpt-6.2-astra"
        )))

        var rosalindState = ModalityState(modality: .rosalindBio)
        rosalindState.phase = .resolved(.rosalindBio(.observed(
            FrontierResearchResult(
                model: "gpt-rosalind",
                reasoningEffort: "high",
                thesis: "Clearance CYP2B6.",
                analysisMarkdown: "Farmacocinética clínica confirmada em PMID: 38412345.",
                executedTools: ["beagle_search_pubmed"],
                citations: []
            ),
            source: "gpt-rosalind"
        )))

        let roundTable = RoundTableResult(
            voices: [RoundTableVoice(name: "Consciência — Astra", content: "Convergência com DOI 10.1038/s41586-026-00001-1.")],
            pciScore: 0.78,
            synthesis: "Interferência construtiva confirmada."
        )

        let citations = ScientificDossierExporter.harvestCitations(
            prompt: "PBPK fractal da S-cetamina",
            modalityStates: [astraState, rosalindState],
            synthesis: "Síntese final validada.",
            roundTable: roundTable
        )

        #expect(citations.count == 4)
        #expect(citations.contains(where: { $0.doi == "10.1056/NEJMoa2302399" }))
        #expect(citations.contains(where: { $0.pmid == "38412345" }))
        #expect(citations.contains(where: { $0.arxivId == "2603.12345v2" }))
        #expect(citations.contains(where: { $0.doi == "10.1038/s41586-026-00001-1" }))

        // Test Crossref BibTeX enrichment + fallback
        final class CrossrefBibStub: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url else { return }
                if url.path.contains("10.1056") {
                    let bib = "@article{NEJM2025,\n  author = {Silva, A.},\n  title = {Ketamine Trial},\n  journal = {NEJM},\n  year = {2025}\n}"
                    let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/x-bibtex"])!
                    client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data(bib.utf8))
                    client?.urlProtocolDidFinishLoading(self)
                } else {
                    let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                    client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocolDidFinishLoading(self)
                }
            }
            override func stopLoading() {}
        }

        let bibCfg = URLSessionConfiguration.ephemeral
        bibCfg.protocolClasses = [CrossrefBibStub.self]
        let enrichedBib = await ScientificDossierExporter.buildEnrichedBibTeX(
            prompt: "PBPK fractal da S-cetamina",
            citations: citations,
            session: URLSession(configuration: bibCfg)
        )
        #expect(enrichedBib.contains("@article{NEJM2025,"))
        #expect(enrichedBib.contains("pmid = {38412345}"))
        #expect(enrichedBib.contains("eprint = {2603.12345v2}"))

        // Test Markdown + Multi-page Vector PDF generation
        let md = ScientificDossierExporter.buildMarkdown(
            prompt: "PBPK fractal da S-cetamina",
            startedAt: astraState.startedAt,
            completedAt: astraState.completedAt,
            modalityStates: [astraState, rosalindState],
            synthesis: "Síntese final validada.",
            roundTable: roundTable
        )
        #expect(md.contains("## Síntese Executiva"))
        #expect(md.contains("Φ = 0.78"))
        #expect(md.contains("## Referências Verificadas (DOI · PMID · arXiv)"))

        let pdfData = ScientificDossierExporter.renderPDFData(
            title: "Dossiê Científico — Beagle Modo Fundo",
            subtitle: "PBPK fractal da S-cetamina",
            markdownBody: md,
            citations: citations
        )
        #expect(pdfData.count > 1_000)
        let pdfHeader = String(data: pdfData.prefix(5), encoding: .ascii)
        #expect(pdfHeader == "%PDF-")

        let exportedURL = try ScientificDossierExporter.writeTemporaryExportFile(
            prompt: "PBPK fractal da S-cetamina",
            fileExtension: "pdf",
            data: pdfData
        )
        #expect(FileManager.default.fileExists(atPath: exportedURL.path))
        try? FileManager.default.removeItem(at: exportedURL)
    }

    @Test
    func dailyBriefingBuilderSynthesizesPhysiomeSpaceWeatherAndCacheEvenWithoutCaptures() async throws {
        final class MorningAstraStub: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url else { return }
                if url.host == "offline.beagle.test" {
                    let r = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
                    client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
                var bodyData = request.httpBody
                if bodyData == nil, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buf = [UInt8](repeating: 0, count: 4096)
                    var out = Data()
                    while stream.hasBytesAvailable {
                        let n = stream.read(&buf, maxLength: buf.count)
                        if n <= 0 { break }
                        out.append(contentsOf: buf.prefix(n))
                    }
                    bodyData = out
                }
                if let bodyData,
                   let jsonObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    #expect(jsonObj["model"] as? String == "gpt-6.2-astra")
                    let effort = (jsonObj["reasoning"] as? [String: Any])?["effort"] as? String
                    #expect(effort == "medium")
                }

                let reply = "### 1. Pulso Autonômico & Céu\nHRV 68 ms restaurado sob tempestade Kp 5.7.\n\n### 4. Três Alavancas Concretas para Hoje\n1. Avançar compilador Sounio."
                let completed: [String: Any] = [
                    "type": "response.completed",
                    "response": [
                        "status": "completed",
                        "model": "gpt-6.2-astra",
                        "output": [[
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": reply]]
                        ]]
                    ]
                ]
                let json = String(data: (try? JSONSerialization.data(withJSONObject: completed)) ?? Data(), encoding: .utf8) ?? "{}"
                let sse = "data: \(json)\n\n"
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(sse.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        DirectBrainCredentials.testOpenAIKeyOverride = "sk-test-morning"
        defer { DirectBrainCredentials.testOpenAIKeyOverride = nil }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MorningAstraStub.self]
        let session = URLSession(configuration: cfg)
        let offlineClient = BeagleClient(session: session, baseURLs: [URL(string: "https://offline.beagle.test")!])
        let stubBrain = DirectBrainClient(session: session, skipRemoteMCPTools: true)

        let physio = PhysioSummary(
            hrvMs: 68,
            restingHeartRate: 54,
            sleepHours: 7.4,
            mindfulMinutes: 10,
            workoutCount: 1,
            observedAt: .now,
            authorizationState: .authorized,
            readiness: .restored
        )
        let sky = SpaceWeatherStore.Snapshot(
            ts: .now,
            kp: 5.7,
            dst: -62,
            f107: 168,
            solarWindSpeed: 610,
            bz: -7.4,
            source: "noaa-swpc"
        )

        let ctx = await DailyBriefingBuilder.gatherLiveContext(
            captureLines: [],
            physioSummary: physio,
            sky: sky,
            projectSlug: "sounio",
            client: offlineClient,
            directBrain: stubBrain,
            includeDeviceTools: false
        )

        let prompt = ctx.composedPrompt(projectSlug: "sounio")
        #expect(prompt.contains("HRV SDNN: 68 ms"))
        #expect(prompt.contains("Sono: 7.4 h"))
        #expect(prompt.contains("Tempestade Geomagnética"))
        #expect(prompt.contains("Kp 5.7"))
        #expect(prompt.contains("Dst: -62 nT"))
        #expect(prompt.contains("Nenhuma captura explícita"))

        let generated = try await DailyBriefingBuilder.generateMorningSynthesis(
            context: ctx,
            projectSlug: "sounio",
            client: offlineClient,
            directBrain: stubBrain
        )
        #expect(generated.contains("Pulso Autonômico & Céu"))
        #expect(generated.contains("HRV 68 ms"))

        let suiteName = "beagle.test.daily.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fixedDate = Date(timeIntervalSince1970: 1_795_000_000)
        #expect(DailyBriefingBuilder.cachedTodaySynthesis(now: fixedDate, defaults: defaults) == nil)
        DailyBriefingBuilder.saveTodaySynthesis(generated, context: ctx, now: fixedDate, defaults: defaults)
        #expect(DailyBriefingBuilder.cachedTodaySynthesis(now: fixedDate, defaults: defaults) == generated)

        let widgetDigest = try #require(DailyBriefingBuilder.cachedWidgetDigest(now: fixedDate, defaults: defaults))
        #expect(widgetDigest.hrvMs == 68)
        #expect(widgetDigest.sleepHours == 7.4)
        #expect(widgetDigest.kpIndex == 5.7)
        #expect(widgetDigest.headline.contains("HRV 68 ms"))

        let fullBriefing = """
        ### 1. Pulso Autonômico & Céu
        HRV 68 ms restaurado sob tempestade Kp 5.7.

        ### 2. Janelas de Foco & Plantão (Próximas 48h)
        Manhã livre até 14h; plantão noturno amanhã.

        ### 3. Síntese Cognitiva & Fios Abertos
        Avanço na tipagem linear de Sounio.

        ### 4. Três Alavancas Concretas para Hoje
        1. Fechar testes do compilador.
        """
        let sections = DailyBriefingBuilder.parseSections(fullBriefing)
        #expect(sections.count == 4)
        #expect(sections[0].systemImage == "waveform.path.ecg")
        #expect(sections[3].title.contains("Três Alavancas"))

        DailyBriefingBuilder.clearTodaySynthesis(now: fixedDate, defaults: defaults)
        #expect(DailyBriefingBuilder.cachedTodaySynthesis(now: fixedDate, defaults: defaults) == nil)
        #expect(DailyBriefingBuilder.cachedWidgetDigest(now: fixedDate, defaults: defaults) == nil)
    }

    @Test
    @MainActor
    func modoFundoHydrationSimulationSandboxComparisonAndDeepVoiceIntent() async throws {
        // 1. Deep Voice Intent Classification (GPT-Live 1.1 -> Background Delegation)
        #expect(ConversationStore.classifyDeepVoiceIntent("Roda o modo fundo sobre neuroplasticidade glutamatérgica") == .modoFundo)
        #expect(ConversationStore.classifyDeepVoiceIntent("Calcula a farmacocinética PBPK da S-cetamina no Rosalind") == .rosalindBio)
        #expect(ConversationStore.classifyDeepVoiceIntent("Me lê a síntese matinal de hoje") == .morningSynthesis)
        #expect(ConversationStore.classifyDeepVoiceIntent("Bom dia, tudo tranquilo?") == nil)

        // 2. Instant Hydration + Citation & Simulation Persistence + Dossier Export
        let modalitiesDict: [String: String] = [
            GoDeepModality.astraDeep.displayName: "Convergência estrutural em [Nature 2026](https://doi.org/10.1038/s41586-026-00999-1).",
            GoDeepModality.rosalindBio.displayName: "Clearance hepático validado em PMID: 38999111."
        ]
        let modalitiesData = try JSONEncoder().encode(modalitiesDict)
        let modalitiesJSON = try #require(String(data: modalitiesData, encoding: .utf8))

        let store = GoDeepStore(enabledModalities: [.astraDeep, .rosalindBio])
        let start = Date(timeIntervalSince1970: 1_795_100_000)
        let end = Date(timeIntervalSince1970: 1_795_100_042)
        store.hydrateFromPersisted(
            prompt: "Cinética PBPK de cetamina intranasal",
            startedAt: start,
            completedAt: end,
            synthesis: "Síntese consolidada com janela terapêutica segura.",
            modalityResultsJSON: modalitiesJSON,
            simulationOutput: "AUC_0-24 = 412 ng·h/mL · C_max = 84 ng/mL"
        )

        #expect(store.isRunning == false)
        #expect(store.modalityStates.count == 2)
        #expect(store.synthesis == "Síntese consolidada com janela terapêutica segura.")
        #expect(store.simulationOutput?.contains("AUC_0-24 = 412") == true)

        let payload = store.makePersistencePayload(prompt: "Cinética PBPK de cetamina intranasal")
        #expect(payload.modalityCount == 2)
        #expect(payload.simulationOutput?.contains("C_max = 84") == true)
        let citationsData = try #require(payload.citationsJSON?.data(using: .utf8))
        let decodedCitations = try JSONDecoder().decode([ScientificDossierExporter.HarvestedCitation].self, from: citationsData)
        #expect(decodedCitations.count == 2)
        #expect(decodedCitations.contains(where: { $0.doi == "10.1038/s41586-026-00999-1" }))
        #expect(decodedCitations.contains(where: { $0.pmid == "38999111" }))

        let persistedModel = PersistedDeepSession(
            prompt: "Cinética PBPK de cetamina intranasal",
            startedAt: start,
            modalityCount: payload.modalityCount,
            citationsJSON: payload.citationsJSON,
            simulationOutput: payload.simulationOutput,
            pciScore: 0.84
        )
        persistedModel.synthesisText = payload.synthesis
        persistedModel.modalityResults = payload.modalityResultsJSON
        persistedModel.completedAt = end
        #expect(persistedModel.citationCount == 2)
        #expect(persistedModel.pciScore == 0.84)

        let dossierMD = ScientificDossierExporter.buildMarkdown(
            prompt: "Cinética PBPK de cetamina intranasal",
            startedAt: start,
            completedAt: end,
            modalityStates: store.modalityStates,
            synthesis: store.synthesis,
            simulationOutput: store.simulationOutput
        )
        #expect(dossierMD.contains("## Simulação & Execução Agêntica Verificada"))
        #expect(dossierMD.contains("AUC_0-24 = 412 ng·h/mL"))

        // 3. OpenAIAgentsSessionClient Scientific Simulation (Hosted Sandbox -> Fallback to GPT-6.2 Sol)
        final class SimFallbackStub: URLProtocol, @unchecked Sendable {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url else { return }
                if url.path.contains("/v1/agents/sessions") {
                    // Simulate beta sandbox unavailable -> triggers automatic GPT-6.2 Sol fallback
                    let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                    client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
                let completed: [String: Any] = [
                    "type": "response.completed",
                    "response": [
                        "status": "completed",
                        "model": "gpt-6.2-sol",
                        "output": [[
                            "type": "message",
                            "role": "assistant",
                            "content": [["type": "output_text", "text": "t_1/2 = 2.6 h; C_max = 82.4 ng/mL (IC95% 74-91)."]]
                        ]]
                    ]
                ]
                let json = String(data: (try? JSONSerialization.data(withJSONObject: completed)) ?? Data(), encoding: .utf8) ?? "{}"
                let sse = "data: \(json)\n\n"
                let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
                client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(sse.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        DirectBrainCredentials.testOpenAIKeyOverride = "sk-test-sim"
        defer { DirectBrainCredentials.testOpenAIKeyOverride = nil }

        let simCfg = URLSessionConfiguration.ephemeral
        simCfg.protocolClasses = [SimFallbackStub.self]
        let simSession = URLSession(configuration: simCfg)
        let agentsClient = OpenAIAgentsSessionClient(session: simSession)
        let stubBrain = DirectBrainClient(session: simSession, skipRemoteMCPTools: true)

        let simStore = GoDeepStore(
            client: BeagleClient(session: simSession, baseURLs: [URL(string: "https://offline.beagle.test")!]),
            directBrain: stubBrain,
            enabledModalities: [.astraDeep]
        )
        simStore.synthesis = "Hipótese PBPK inicial."
        await simStore.runSimulation(
            prompt: "Simular meia-vida de S-cetamina",
            agentsClient: agentsClient
        )
        #expect(simStore.isSimulating == false)
        #expect(simStore.simulationOutput?.contains("t_1/2 = 2.6 h") == true)

        // 4. Longitudinal Comparison between 2 Explorations
        let comparison = await GoDeepStore.compareExplorations(
            firstPrompt: "Exploração A",
            firstDate: start,
            firstSynthesis: "Síntese A inicial.",
            secondPrompt: "Exploração B",
            secondDate: end,
            secondSynthesis: "Síntese B evoluída.",
            directBrain: stubBrain,
            client: BeagleClient(session: simSession, baseURLs: [URL(string: "https://offline.beagle.test")!])
        )
        #expect(!comparison.isEmpty)
    }
}
