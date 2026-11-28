//
//  ShareViewController.swift
//  BeagleShare
//
//  Share Extension multimodal — recebe imagens, PDFs (artigos, exames, laudos),
//  links e textos de qualquer app (WhatsApp, Fotos, Arquivos, Safari, Mail)
//  e entrega direto ao Chat do Beagle (ou salva silenciosamente na Memória).
//

import UIKit
import Social
import Synchronization
import UniformTypeIdentifiers
import CoreSpotlight

@objc(ShareViewController)
class ShareViewController: SLComposeServiceViewController {

    private let appGroupId = "group.dev.sounio.cockpit"
    private var routeToChat: Bool = true
    private lazy var destinationConfigItem: SLComposeSheetConfigurationItem? = {
        let item = SLComposeSheetConfigurationItem()
        item?.title = "Destino"
        item?.value = "Conversar no Chat"
        item?.tapHandler = { [weak self] in
            guard let self else { return }
            self.routeToChat.toggle()
            self.destinationConfigItem?.value = self.routeToChat ? "Conversar no Chat" : "Salvar na Memória"
        }
        return item
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        placeholder = "Pergunte sobre este arquivo, exame ou link…"
    }

    override func isContentValid() -> Bool {
        !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments
    }

    override func configurationItems() -> [Any]! {
        if let item = destinationConfigItem {
            return [item]
        }
        return []
    }

    override func didSelectPost() {
        let userNote = contentText ?? ""
        let collector = SharedAttachmentCollector()
        let group = DispatchGroup()

        if let items = extensionContext?.inputItems as? [NSExtensionItem] {
            for item in items {
                for provider in item.attachments ?? [] {
                    if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { itemData, _ in
                            if let fileURL = itemData as? URL,
                               let data = try? Data(contentsOf: fileURL), !data.isEmpty {
                                collector.setPDF(data: data, name: fileURL.lastPathComponent)
                            } else if let data = itemData as? Data, !data.isEmpty {
                                collector.setPDF(data: data, name: "compartilhado.pdf")
                            }
                            group.leave()
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { itemData, _ in
                            if let fileURL = itemData as? URL,
                               let data = try? Data(contentsOf: fileURL),
                               let image = UIImage(data: data),
                               let jpeg = image.jpegData(compressionQuality: 0.88) {
                                collector.setImage(jpeg)
                            } else if let image = itemData as? UIImage,
                                      let jpeg = image.jpegData(compressionQuality: 0.88) {
                                collector.setImage(jpeg)
                            } else if let data = itemData as? Data,
                                      let image = UIImage(data: data),
                                      let jpeg = image.jpegData(compressionQuality: 0.88) {
                                collector.setImage(jpeg)
                            }
                            group.leave()
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { itemData, _ in
                            if let url = itemData as? URL {
                                if url.isFileURL, url.pathExtension.lowercased() == "pdf",
                                   let data = try? Data(contentsOf: url), !data.isEmpty {
                                    collector.setPDF(data: data, name: url.lastPathComponent)
                                } else {
                                    collector.appendURL(url.absoluteString)
                                }
                            }
                            group.leave()
                        }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { itemData, _ in
                            if let str = itemData as? String, !str.isEmpty {
                                collector.appendExtraText(str)
                            }
                            group.leave()
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let snapshot = collector.snapshot()
            let combinedText = Self.mergeText(userNote: userNote, extraTexts: snapshot.extraTexts)
            if self.routeToChat {
                self.enqueueForCompanionChat(
                    text: combinedText,
                    urls: snapshot.urls,
                    imageData: snapshot.imageData,
                    pdfData: snapshot.pdfData,
                    originalPDFName: snapshot.pdfName
                )
                self.openMainAppChat()
            } else {
                self.saveSharedThought(
                    text: combinedText,
                    urls: snapshot.urls,
                    pdfName: snapshot.pdfName,
                    hasImage: snapshot.imageData != nil
                )
            }
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private static func mergeText(userNote: String, extraTexts: [String]) -> String {
        let trimmedNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !trimmedNote.isEmpty { parts.append(trimmedNote) }
        for extra in extraTexts {
            let t = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !trimmedNote.contains(t) {
                parts.append(t)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private var hasAttachments: Bool {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return false }
        return items.contains { ($0.attachments?.count ?? 0) > 0 }
    }

    private func enqueueForCompanionChat(
        text: String,
        urls: [String],
        imageData: Data?,
        pdfData: Data?,
        originalPDFName: String?
    ) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return
        }
        let dir = base.appendingPathComponent("SharedChatInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let id = UUID().uuidString.lowercased()
        var imageFile: String?
        var pdfFile: String?

        if let imageData, !imageData.isEmpty {
            let fname = "\(id).jpg"
            if (try? imageData.write(to: dir.appendingPathComponent(fname), options: .atomic)) != nil {
                imageFile = fname
            }
        }
        if let pdfData, !pdfData.isEmpty {
            let fname = "\(id).pdf"
            if (try? pdfData.write(to: dir.appendingPathComponent(fname), options: .atomic)) != nil {
                pdfFile = fname
            }
        }

        struct WireItem: Codable {
            let id: String
            let createdAt: Date
            let text: String
            let urls: [String]
            let imageFileName: String?
            let pdfFileName: String?
            let originalPDFName: String?
        }

        let manifestURL = dir.appendingPathComponent("shared_chat_queue.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var queue: [WireItem] = []
        if let raw = try? Data(contentsOf: manifestURL),
           let existing = try? decoder.decode([WireItem].self, from: raw) {
            queue = existing
        }
        queue.append(WireItem(
            id: id,
            createdAt: Date(),
            text: text,
            urls: urls,
            imageFileName: imageFile,
            pdfFileName: pdfFile,
            originalPDFName: originalPDFName
        ))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(queue) {
            try? encoded.write(to: manifestURL, options: .atomic)
        }
    }

    private func openMainAppChat() {
        guard let url = URL(string: "beagle://chat") else { return }
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }

    private func saveSharedThought(text: String, urls: [String], pdfName: String?, hasImage: Bool) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }

        var content = text
        if let pdfName, !pdfName.isEmpty {
            content = (content.isEmpty ? "" : content + "\n") + "[PDF compartilhado: \(pdfName)]"
        } else if hasImage && content.isEmpty {
            content = "[Imagem compartilhada via Share Sheet]"
        }
        if !urls.isEmpty {
            content += (content.isEmpty ? "" : "\n\n") + urls.joined(separator: "\n")
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var pending = defaults.array(forKey: "pendingSharedThoughts") as? [[String: String]] ?? []
        pending.append([
            "content": content,
            "source": "share-extension",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        defaults.set(pending, forKey: "pendingSharedThoughts")

        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = String(content.prefix(120))
        attributes.contentDescription = content

        let item = CSSearchableItem(
            uniqueIdentifier: "shared-\(UUID().uuidString)",
            domainIdentifier: "dev.sounio.cockpit.thoughts",
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }
}

private final class SharedAttachmentCollector: Sendable {
    struct Snapshot: Sendable {
        let urls: [String]
        let extraTexts: [String]
        let imageData: Data?
        let pdfData: Data?
        let pdfName: String?
    }

    private struct State: Sendable {
        var urls: [String] = []
        var extraTexts: [String] = []
        var imageData: Data?
        var pdfData: Data?
        var pdfName: String?
    }

    private let state = Mutex<State>(State())

    func appendURL(_ value: String) {
        state.withLock { $0.urls.append(value) }
    }

    func appendExtraText(_ value: String) {
        state.withLock { $0.extraTexts.append(value) }
    }

    func setImage(_ data: Data) {
        state.withLock {
            if $0.imageData == nil { $0.imageData = data }
        }
    }

    func setPDF(data: Data, name: String) {
        state.withLock {
            if $0.pdfData == nil {
                $0.pdfData = data
                $0.pdfName = name
            }
        }
    }

    func snapshot() -> Snapshot {
        state.withLock {
            Snapshot(
                urls: $0.urls,
                extraTexts: $0.extraTexts,
                imageData: $0.imageData,
                pdfData: $0.pdfData,
                pdfName: $0.pdfName
            )
        }
    }
}
