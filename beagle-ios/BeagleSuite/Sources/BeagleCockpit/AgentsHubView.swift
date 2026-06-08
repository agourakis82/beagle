//
//  AgentsHubView.swift
//  BeagleCockpit
//
//  Unified Agents surface: live work (Work) + terminal fleet (Fleet).
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

struct AgentsHubView: View {
    @Binding var bootError: String?
    @AppStorage("agentsHubSelection") private var selectionRaw: String = AgentsHubSegment.work.rawValue

    enum AgentsHubSegment: String, CaseIterable, Identifiable {
        case work = "Work"
        case fleet = "Terminals"
        var id: String { rawValue }
    }

    private var selection: Binding<AgentsHubSegment> {
        Binding(
            get: { AgentsHubSegment(rawValue: selectionRaw) ?? .work },
            set: { selectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: selection) {
                ForEach(AgentsHubSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.top, BeagleSpacing.xs)
            .padding(.bottom, BeagleSpacing.xs)

            Group {
                switch selection.wrappedValue {
                case .work:
                    WorkView(bootError: $bootError)
                case .fleet:
                    FleetTerminalsView()
                }
            }
        }
        .navigationTitle("Agents")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
