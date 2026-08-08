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
    /// Set when the Frota hands a lane over to the Terminals segment ("jump to that lane").
    @State private var openLane: String?

    enum AgentsHubSegment: String, CaseIterable, Identifiable {
        case frota = "Frota"
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
                case .frota:
                    // Mission Control: who needs you. Tapping a lane jumps to its terminal.
                    FrotaView(onOpenLane: { lane in
                        openLane = lane
                        selection.wrappedValue = .fleet
                    })
                case .work:
                    WorkView(bootError: $bootError)
                case .fleet:
                    FleetTerminalsView(initialAgent: openLane)
                }
            }
        }
        .navigationTitle("Agents")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
