import SwiftUI
import Grape
import BeagleCore

struct GraphRAGVisDatum {
    struct Node: Identifiable, Hashable {
        let id: String
        let label: String
        let group: Int
    }

    struct Link: Hashable, Identifiable {
        var id: String { "\(source)|\(target)" }
        let source: String
        let target: String
    }

    let nodes: [Node]
    let links: [Link]
}

extension GraphRAGQueryResponse {
    var visDatum: GraphRAGVisDatum? {
        guard let rawNodes = nodes, rawNodes.count > 1 else { return nil }
        let mappedNodes: [GraphRAGVisDatum.Node] = rawNodes.compactMap { node in
            guard let id = node.nodeId ?? node.displayName else { return nil }
            let label = node.displayName ?? id
            let group = abs((node.nodeType ?? "node").hashValue) % 8
            return GraphRAGVisDatum.Node(id: id, label: label, group: group)
        }
        guard mappedNodes.count > 1 else { return nil }

        let ids = Set(mappedNodes.map(\.id))
        let mappedLinks: [GraphRAGVisDatum.Link] = (edges ?? []).compactMap { edge in
            guard let from = edge.fromNodeId, let to = edge.toNodeId, ids.contains(from), ids.contains(to) else {
                return nil
            }
            return GraphRAGVisDatum.Link(source: from, target: to)
        }

        return GraphRAGVisDatum(nodes: mappedNodes, links: mappedLinks)
    }
}

private let graphPalette: [Color] = [
    .teal, .indigo, .orange, .pink, .mint, .blue, .purple, .yellow
]

struct GraphRAGGraphView: View {
    let datum: GraphRAGVisDatum

    @State private var stateMixin = ForceDirectedGraphState(
        initialIsRunning: true,
        initialModelTransform: .identity.scale(by: 1.1)
    )

    var body: some View {
        ForceDirectedGraph(states: stateMixin) {
            Series(datum.nodes) { node in
                NodeMark(id: node.id)
                    .symbol(.circle)
                    .symbolSize(radius: 7)
                    .foregroundStyle(graphPalette[node.group % graphPalette.count].opacity(0.9))
                    .stroke(.primary.opacity(0.15))
                    .annotation(node.id, offset: .zero) {
                        if datum.links.count(where: { $0.source == node.id || $0.target == node.id }) > 2 {
                            Text(node.label)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
            }

            Series(datum.links) { link in
                LinkMark(from: link.source, to: link.target)
            }
        } force: {
            .manyBody(strength: -24)
            .center()
            .link(originalLength: 42.0, stiffness: .weightedByDegree { _, _ in 0.8 })
        }
        .frame(minHeight: 220, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}
