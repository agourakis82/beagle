//
//  ShareViewController.swift
//  BeagleShare
//
//  Share Extension — capture text, URLs, and images from any app
//  directly into the Beagle exocortex.
//
//  Uses app group shared container to pass data to the main app.
//  The main app picks up shared thoughts on next launch/foreground.
//

import UIKit
import Social
import UniformTypeIdentifiers
import CoreSpotlight

@objc(ShareViewController)
class ShareViewController: SLComposeServiceViewController {

    private let appGroupId = "group.dev.sounio.cockpit"

    override func isContentValid() -> Bool {
        // Accept any content with text
        return !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasAttachments
    }

    override func didSelectPost() {
        let text = contentText ?? ""
        var urls: [String] = []

        let group = DispatchGroup()

        // Extract URLs
        if let items = extensionContext?.inputItems as? [NSExtensionItem] {
            for item in items {
                for provider in item.attachments ?? [] {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                            if let url = data as? URL {
                                urls.append(url.absoluteString)
                            }
                            group.leave()
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.saveSharedThought(text: text, urls: urls)
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    private var hasAttachments: Bool {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return false }
        return items.contains { ($0.attachments?.count ?? 0) > 0 }
    }

    private func saveSharedThought(text: String, urls: [String]) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }

        // Build the thought content
        var content = text
        if !urls.isEmpty {
            content += "\n\n" + urls.joined(separator: "\n")
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Append to pending shared thoughts queue
        var pending = defaults.array(forKey: "pendingSharedThoughts") as? [[String: String]] ?? []
        pending.append([
            "content": content,
            "source": "share-extension",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        defaults.set(pending, forKey: "pendingSharedThoughts")

        // Also index to Spotlight immediately
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
