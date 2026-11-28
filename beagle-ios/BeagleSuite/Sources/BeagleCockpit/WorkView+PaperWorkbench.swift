//
//  WorkView+PaperWorkbench.swift
//  BeagleCockpit
//
//  Sounio PaperRun Theatre workbench sheet for WorkView.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

struct SounioPaperWorkbenchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Ready"
    @State private var paperRun: PaperRun?
    @State private var artifacts: PaperRunArtifactsResponse?
    @State private var theatre: PaperRunTheatreSnapshot?
    @State private var publicDigest: PublicDigestArtifact?

    var body: some View {
        List {
            Section("PaperRun") {
                Text(paperRun?.title ?? "Beagle self-writing systems paper")
                    .font(BeagleFont.body.font)
                Text(status)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                if let run = paperRun {
                    LabeledContent("Temporal", value: run.temporalStatus)
                    LabeledContent("Approval", value: run.approvalState)
                    LabeledContent("Stage", value: run.currentStage ?? run.status)
                    LabeledContent("Digest", value: run.publicDigestStatus ?? "not generated")
                    if let pending = run.pendingApprovalStep {
                        LabeledContent("Pending", value: pending)
                    }
                    if let summary = run.interactionSummary, !summary.isEmpty {
                        Text(summary)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }
            }
            if let theatre {
                Section("Theatre") {
                    LabeledContent("Stage", value: theatre.currentStage)
                    LabeledContent("Next", value: theatre.nextAction)
                    LabeledContent("Claims", value: "\(theatre.claimGraph.claims.count)")
                    LabeledContent("Unsupported", value: "\(theatre.claimGraph.unsupportedClaimIds.count)")
                    LabeledContent("Private trace", value: theatre.privateTraceRef)
                        .font(BeagleFont.caption.font)
                    statusGrid(theatre.claimGraph.statusCounts)
                }
                if !theatre.claimGraph.claims.isEmpty {
                    Section("Claims") {
                        ForEach(theatre.claimGraph.claims) { claim in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(claim.epistemicStatus.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(statusColor(claim.epistemicStatus))
                                    Spacer()
                                    Text(claim.publicationReadiness)
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(claim.claimText)
                                    .font(BeagleFont.caption.font)
                                Text("\(claim.evidenceRefs.count) evidence refs · confidence \(claim.confidence, specifier: "%.2f")")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            Section("Actions") {
                Button {
                    Task { await startPaperRun() }
                } label: {
                    Label("Start PaperRun", systemImage: "play.circle")
                }
                .disabled(status == "Starting")
                if let run = paperRun, let pending = run.pendingApprovalStep {
                    Button {
                        Task { await approve(run: run, step: pending) }
                    } label: {
                        Label("Approve \(pending)", systemImage: "checkmark.seal")
                    }
                }
                if let run = paperRun {
                    Button {
                        Task { await loadArtifacts(run.id) }
                    } label: {
                        Label("Load Artifacts", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        Task { await loadTheatre(run.id) }
                    } label: {
                        Label("Open Theatre", systemImage: "theatermasks")
                    }
                    Button {
                        Task { await addSedenionClaim(run) }
                    } label: {
                        Label("Add Sedenion SSM Claim", systemImage: "function")
                    }
                    if let firstClaim = theatre?.claimGraph.claims.first {
                        Button {
                            Task { await reviewClaim(run: run, claim: firstClaim) }
                        } label: {
                            Label("Review First Claim", systemImage: "checkmark.seal")
                        }
                    }
                    Button {
                        Task { await loadPublicDigest(run.id) }
                    } label: {
                        Label("Public Digest", systemImage: "doc.plaintext")
                    }
                }
            }
            if let artifacts {
                Section("Manuscript") {
                    Text(artifacts.manuscriptMarkdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            if let publicDigest {
                Section("Public Digest") {
                    Text(publicDigest.thesis)
                        .font(BeagleFont.caption.font)
                    Text(publicDigest.disclosure)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Text(publicDigest.manuscriptExcerpt)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("PaperRun Theatre")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func startPaperRun() async {
        status = "Starting"
        let result = await BeagleClient.shared.startSounioPaperRun()
        if let run = result.value {
            paperRun = run
            status = "\(run.status) · \(run.temporalStatus)"
            await loadTheatre(run.id)
        } else {
            status = result.error ?? "PaperRun failed"
        }
    }

    private func approve(run: PaperRun, step: String) async {
        status = "Approving \(step)"
        let result = await BeagleClient.shared.approveSounioPaperRunStep(
            paperRunId: run.id,
            stepId: step,
            rationale: "Approved from Beagle Apple Paper Workbench."
        )
        if let updated = result.value {
            paperRun = updated
            status = "\(updated.status) · \(updated.temporalStatus)"
            await loadTheatre(updated.id)
        } else {
            status = result.error ?? "Approval failed"
        }
    }

    private func loadArtifacts(_ paperRunId: String) async {
        status = "Loading artifacts"
        let result = await BeagleClient.shared.sounioPaperRunArtifacts(paperRunId)
        if let response = result.value {
            artifacts = response
            status = "Artifacts loaded"
        } else {
            status = result.error ?? "Artifact load failed"
        }
    }

    private func loadTheatre(_ paperRunId: String) async {
        status = "Loading Theatre"
        let result = await BeagleClient.shared.sounioPaperRunTheatre(paperRunId)
        if let response = result.value {
            theatre = response
            paperRun = response.paperRun
            status = "Theatre loaded · \(response.currentStage)"
        } else {
            status = result.error ?? "Theatre load failed"
        }
    }

    private func addSedenionClaim(_ run: PaperRun) async {
        status = "Typing Sedenion SSM claim"
        let claim = SounioClaimInput(
            id: "claim-sedenion-ssm-arc",
            claimText: "The Sedenion SSM arc is the first strong Beagle/Sounio demonstration because it combines hypercomplex primitives, theorem-like claims, artifacts, and epistemic verification.",
            subject: "sedenion_ssm_arc",
            epistemicStatus: "contest",
            evidenceRefs: [
                "artifact:sedenion_ssm_arc",
                "theorem_refs:sedenion_ssm",
                "paperrun:beagle_self_writing_systems"
            ],
            provenance: .object([
                "source": .string("beagle-apple-paper-workbench"),
                "case": .string("sedenion-ssm-arc"),
                "independent_verification": .bool(false)
            ]),
            confidence: 0.72,
            contestation: .object([
                "reason": .string("Requires human review and independent theorem/evidence mapping before Knowledge<T>.")
            ]),
            sectionId: "Sounio IR",
            agentRefs: ["beagle-app"],
            artifactRefs: ["/orangefs/beagle-memory-lab/paperruns/\(run.id)/sedenion_ssm_public_case.json"],
            privacyClass: "sensitive",
            rationale: "This is a demonstrative claim, not yet Robust<T>."
        )
        let result = await BeagleClient.shared.addSounioClaim(paperRunId: run.id, claim: claim)
        if let added = result.value {
            status = "Claim \(added.epistemicStatus) added"
            await loadTheatre(run.id)
        } else {
            status = result.error ?? "Claim add failed"
        }
    }

    private func reviewClaim(run: PaperRun, claim: SounioClaim) async {
        status = "Reviewing claim"
        let decision = claim.epistemicStatus == "belief" || claim.epistemicStatus == "contest"
            ? "promote_to_knowledge"
            : "approved"
        let result = await BeagleClient.shared.reviewSounioClaim(
            paperRunId: run.id,
            claimId: claim.id,
            decision: decision,
            rationale: "Reviewed from iPhone/iPad PaperRun Theatre; Knowledge<T> remains evidence/provenance-gated.",
            evidenceRefs: claim.evidenceRefs,
            epistemicStatus: nil,
            publicationReadiness: nil,
            provenance: .object([
                "source": .string("beagle-apple-paper-workbench"),
                "human_review": .bool(true)
            ])
        )
        if let reviewed = result.value {
            status = "Claim reviewed as \(reviewed.epistemicStatus)"
            await loadTheatre(run.id)
        } else {
            status = result.error ?? "Claim review failed"
        }
    }

    private func loadPublicDigest(_ paperRunId: String) async {
        status = "Loading public digest"
        let result = await BeagleClient.shared.sounioPaperRunPublicDigest(paperRunId)
        if let response = result.value {
            publicDigest = response
            status = "Public digest sanitized"
            await loadTheatre(paperRunId)
        } else {
            status = result.error ?? "Public digest failed"
        }
    }

    @ViewBuilder
    private func statusGrid(_ counts: [String: Int]) -> some View {
        if counts.isEmpty {
            Text("No typed claims yet")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        } else {
            HStack {
                ForEach(counts.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading) {
                        Text(key.uppercased())
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(statusColor(key))
                        Text("\(counts[key] ?? 0)")
                            .font(BeagleFont.body.font)
                    }
                    Spacer()
                }
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "robust":
            return BeagleTheme.truthObserved
        case "knowledge":
            return BeagleTheme.truthRemembered
        case "contest":
            return BeagleTheme.postureWarm
        default:
            return BeagleTheme.textSecondary
        }
    }
}
