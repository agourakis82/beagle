//
//  CaptureReviewSheet.swift
//  BeagleCockpit
//
//  Sounio-typed capture candidate review sheet and voice/image candidate builder.
//

import SwiftUI
import BeagleCore

struct CaptureReviewSheet: View {
    let candidates: [CaptureReviewCandidate]
    let onPromote: ([CaptureReviewCandidate]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { candidate in
                    Button {
                        if selectedIDs.contains(candidate.id) {
                            selectedIDs.remove(candidate.id)
                        } else {
                            selectedIDs.insert(candidate.id)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(candidate.id) ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.title)
                                    .font(.headline)
                                Text(candidate.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(candidate.kind)
                                    .font(.caption2)
                                    .foregroundStyle(BeagleTheme.truthRemembered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Promote") {
                        let selected = candidates.filter { selectedIDs.contains($0.id) }
                        onPromote(selected.isEmpty ? candidates : selected)
                    }
                }
            }
            .onAppear {
                selectedIDs = Set(candidates.prefix(3).map(\.id))
            }
        }
        .presentationDetents([.medium, .large])
    }
}

enum CaptureCandidateBuilder {
    static func voiceCandidates(
        transcript: String,
        sessionId: String?,
        projectSlug: String
    ) -> [CaptureReviewCandidate] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = sessionId.map { ["capture_session:\($0)"] } ?? []
        let sentence = trimmed
            .split(whereSeparator: { ".?!\n".contains($0) })
            .first
            .map(String.init) ?? String(trimmed.prefix(180))
        return [
            CaptureReviewCandidate(
                kind: "moment",
                title: "Thinking aloud moment",
                summary: String(trimmed.prefix(420)),
                evidenceRefs: evidence,
                nextAction: "Turn this into the next concrete Sounio move.",
                confidence: 0.72,
                provenance: .object(["capture_mode": .string("voice")])
            ),
            CaptureReviewCandidate(
                kind: "claim_seed",
                title: "Claim seed",
                summary: "Candidate claim from spoken thought.",
                evidenceRefs: evidence,
                claimText: sentence,
                epistemicStatus: "belief",
                confidence: 0.58,
                provenance: .object(["project_slug": .string(projectSlug)])
            )
        ]
    }

    static func imageCandidates(
        summary: String,
        artifactId: String,
        projectSlug: String
    ) -> [CaptureReviewCandidate] {
        [
            CaptureReviewCandidate(
                kind: "claim_seed",
                title: "Visual claim seed",
                summary: String(summary.prefix(360)),
                evidenceRefs: ["visual_artifact:\(artifactId)"],
                claimText: "Visual evidence suggests: \(String(summary.prefix(220)))",
                epistemicStatus: "belief",
                confidence: 0.54,
                provenance: .object([
                    "capture_mode": .string("image"),
                    "project_slug": .string(projectSlug)
                ])
            )
        ]
    }
}
