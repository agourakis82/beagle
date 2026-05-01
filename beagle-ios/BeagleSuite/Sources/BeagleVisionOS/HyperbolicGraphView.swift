//
//  HyperbolicGraphView.swift
//  BeagleVisionOS
//
//  Hyperbolic knowledge graph visualization in Poincare disk space.
//  Renders captured thoughts as nodes in a Poincare disk model,
//  projected onto a 3D dome for spatial navigation on visionOS.
//
//  The Poincare disk naturally models knowledge hierarchies:
//  center = root concepts, boundary = specialized details,
//  with exponential growth toward the edge.
//

#if os(visionOS)

import SwiftUI
import RealityKit
import BeagleCore

// MARK: - Poincare Node Model

struct PoincaréNode: Identifiable {
    let id: UUID
    let label: String
    let detail: String?
    var diskPosition: SIMD2<Float>  // position in Poincare disk (-1..1, -1..1)
    var depth: Int                  // 0 = root, higher = more specialized
    var cluster: String             // topic cluster this belongs to
    var thoughtId: String?          // original ThoughtCapture id, nil for synthetic cluster nodes

    /// Convert Poincare disk coords to 3D spatial position on a dome.
    var spatialPosition: SIMD3<Float> {
        let r = sqrt(diskPosition.x * diskPosition.x + diskPosition.y * diskPosition.y)
        let scale: Float = 0.6  // meters — fits well in a volumetric window
        let x = diskPosition.x * scale
        let z = diskPosition.y * scale
        // Center is highest point of the dome; boundary is lowest
        let y = (1.0 - r) * scale * 0.4
        return SIMD3(x, y, z)
    }

    /// Node radius: center nodes are larger, boundary nodes shrink exponentially
    var nodeRadius: Float {
        let base: Float = 0.035
        let r = sqrt(diskPosition.x * diskPosition.x + diskPosition.y * diskPosition.y)
        return base * (1.0 - r * 0.6)
    }

    /// Opacity: center = fully opaque, boundary fades
    var nodeOpacity: Float {
        let r = sqrt(diskPosition.x * diskPosition.x + diskPosition.y * diskPosition.y)
        return max(0.3, 1.0 - r * 0.5)
    }
}

// MARK: - Graph Edge

struct PoincaréEdge: Identifiable {
    let id = UUID()
    let from: UUID
    let to: UUID
}

// MARK: - Keyword Extraction

private struct KeywordExtractor {

    /// Stop words to ignore when extracting keywords.
    static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "shall",
        "should", "may", "might", "must", "can", "could", "to", "of", "in",
        "for", "on", "with", "at", "by", "from", "as", "into", "through",
        "during", "before", "after", "above", "below", "between", "out",
        "off", "over", "under", "again", "further", "then", "once", "here",
        "there", "when", "where", "why", "how", "all", "both", "each",
        "few", "more", "most", "other", "some", "such", "no", "nor", "not",
        "only", "own", "same", "so", "than", "too", "very", "just", "about",
        "and", "but", "or", "if", "while", "that", "this", "it", "its",
        "i", "me", "my", "we", "our", "you", "your", "he", "him", "his",
        "she", "her", "they", "them", "their", "what", "which", "who",
        "also", "like", "think", "know", "need", "want", "get", "make",
        "use", "new", "one", "two", "way", "because", "even", "much",
        "many", "well", "still", "really", "right", "now", "going",
        "de", "da", "do", "dos", "das", "em", "no", "na", "nos", "nas",
        "um", "uma", "para", "com", "por", "que", "se", "mais", "como",
        "mas", "ou", "e", "o", "os", "as", "esse", "essa", "isso",
        // Portuguese stop words for bilingual support
    ]

    /// Extract top keywords from a text, returning them lowercased.
    static func keywords(from text: String, limit: Int = 5) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        var freq: [String: Int] = [:]
        for word in words {
            freq[word, default: 0] += 1
        }
        return freq.sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    /// Group thoughts by their dominant keyword cluster.
    static func cluster(thoughts: [ThoughtCapture]) -> [String: [ThoughtCapture]] {
        var clusters: [String: [ThoughtCapture]] = [:]

        for thought in thoughts {
            let text = thought.refinedText ?? thought.rawText ?? ""
            guard !text.isEmpty else { continue }
            let kws = keywords(from: text, limit: 3)
            // Primary cluster is the most frequent keyword
            let cluster = kws.first ?? "misc"
            clusters[cluster, default: []].append(thought)
        }
        return clusters
    }
}

// MARK: - Graph Layout Engine

private struct PoincaréLayoutEngine {

    /// Build nodes and edges from thoughts using keyword clustering.
    /// Layout: root at center, cluster heads in first ring, individual thoughts in outer rings.
    static func build(from thoughts: [ThoughtCapture], maxNodes: Int = 200) -> (nodes: [PoincaréNode], edges: [PoincaréEdge]) {
        guard !thoughts.isEmpty else { return ([], []) }

        var nodes: [PoincaréNode] = []
        var edges: [PoincaréEdge] = []

        // Root node — the exocortex center
        let rootId = UUID()
        nodes.append(PoincaréNode(
            id: rootId,
            label: "Exocortex",
            detail: "\(thoughts.count) thoughts captured",
            diskPosition: SIMD2<Float>(0, 0),
            depth: 0,
            cluster: "root",
            thoughtId: nil
        ))

        // Cluster thoughts by keyword
        let clusters = KeywordExtractor.cluster(thoughts: Array(thoughts.prefix(maxNodes)))
        let clusterNames = Array(clusters.keys.sorted { (clusters[$0]?.count ?? 0) > (clusters[$1]?.count ?? 0) })

        guard !clusterNames.isEmpty else { return (nodes, edges) }

        // Place cluster head nodes in first ring (Poincare radius ~0.35)
        let clusterRadius: Float = 0.35
        var clusterNodeIds: [String: UUID] = [:]

        for (i, name) in clusterNames.enumerated() {
            let angle = Float(i) * (2 * .pi / Float(clusterNames.count)) - .pi / 2
            let x = cos(angle) * clusterRadius
            let y = sin(angle) * clusterRadius
            let nodeId = UUID()
            let count = clusters[name]?.count ?? 0

            nodes.append(PoincaréNode(
                id: nodeId,
                label: name.capitalized,
                detail: "\(count) thought\(count == 1 ? "" : "s")",
                diskPosition: SIMD2<Float>(x, y),
                depth: 1,
                cluster: name,
                thoughtId: nil
            ))

            clusterNodeIds[name] = nodeId

            // Connect cluster head to root
            edges.append(PoincaréEdge(from: rootId, to: nodeId))
        }

        // Place individual thoughts in outer rings (Poincare radius ~0.55-0.85)
        for (clusterName, clusterThoughts) in clusters {
            guard let clusterHeadId = clusterNodeIds[clusterName] else { continue }
            let clusterHead = nodes.first(where: { $0.id == clusterHeadId })!

            for (j, thought) in clusterThoughts.enumerated() {
                let text = thought.refinedText ?? thought.rawText ?? ""
                guard !text.isEmpty else { continue }

                // Spread thoughts radially outward from cluster head
                let spreadAngle = atan2(clusterHead.diskPosition.y, clusterHead.diskPosition.x)
                let angularSpread: Float = .pi / Float(max(clusterNames.count, 2))
                let thoughtAngle = spreadAngle + angularSpread * (Float(j) - Float(clusterThoughts.count - 1) / 2) / Float(max(clusterThoughts.count, 1))

                // Radial distance increases with index, staying within the disk
                let baseRadius: Float = 0.55
                let radialStep: Float = min(0.06, 0.3 / Float(max(clusterThoughts.count, 1)))
                let r = min(baseRadius + Float(j) * radialStep, 0.92)

                let x = cos(thoughtAngle) * r
                let y = sin(thoughtAngle) * r
                let nodeId = UUID()

                // Label: first ~40 chars of thought
                let label = String(text.prefix(40)) + (text.count > 40 ? "..." : "")

                nodes.append(PoincaréNode(
                    id: nodeId,
                    label: label,
                    detail: text,
                    diskPosition: SIMD2<Float>(x, y),
                    depth: 2,
                    cluster: clusterName,
                    thoughtId: thought.id
                ))

                // Connect thought to its cluster head
                edges.append(PoincaréEdge(from: clusterHeadId, to: nodeId))
            }
        }

        return (nodes, edges)
    }
}

// MARK: - Hyperbolic Graph View

struct HyperbolicGraphView: View {
    let thoughts: [ThoughtCapture]

    @State private var nodes: [PoincaréNode] = []
    @State private var edges: [PoincaréEdge] = []
    @State private var selectedNodeId: UUID?

    private var selectedNode: PoincaréNode? {
        guard let id = selectedNodeId else { return nil }
        return nodes.first(where: { $0.id == id })
    }

    // Color palette for clusters — cycles through intensity colors
    private static let clusterColors: [Color] = [
        BeagleTheme.truthObserved,        // teal
        BeagleTheme.intensityCalm,        // cool cyan
        BeagleTheme.intensityEngaged,     // gold
        BeagleTheme.intensityChallenge,   // warm orange
        BeagleTheme.intensityMinimal,     // muted indigo
        BeagleTheme.postureWarm,          // amber
        Color(hue: 280/360, saturation: 0.50, brightness: 0.80), // violet
        Color(hue: 140/360, saturation: 0.55, brightness: 0.80), // green
    ]

    var body: some View {
        ZStack {
            RealityView { content in
                buildScene(content: content)
            } update: { content in
                updateScene(content: content)
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        let tappedName = value.entity.name
                        if let node = nodes.first(where: { $0.id.uuidString == tappedName }) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedNodeId = (selectedNodeId == node.id) ? nil : node.id
                            }
                        }
                    }
            )

            // Detail panel overlay
            VStack {
                Spacer()
                if let selected = selectedNode {
                    detailPanel(for: selected)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: selectedNodeId)
        }
        .onAppear {
            let (n, e) = PoincaréLayoutEngine.build(from: thoughts)
            nodes = n
            edges = e
        }
    }

    // MARK: - Scene Building

    private func buildScene(content: RealityViewContent) {
        guard !nodes.isEmpty else { return }

        let clusterNames = Array(Set(nodes.map(\.cluster)).sorted())
        let colorMap = buildColorMap(clusterNames: clusterNames)

        // Add nodes
        for node in nodes {
            let color = (node.depth == 0)
                ? BeagleTheme.truthObserved
                : (colorMap[node.cluster] ?? BeagleTheme.truthObserved)

            let entity = makeNodeEntity(node: node, color: color)
            content.add(entity)
        }

        // Add edges
        for edge in edges {
            guard let fromNode = nodes.first(where: { $0.id == edge.from }),
                  let toNode = nodes.first(where: { $0.id == edge.to }) else { continue }

            let entity = makeEdgeEntity(
                from: fromNode.spatialPosition,
                to: toNode.spatialPosition,
                opacity: min(fromNode.nodeOpacity, toNode.nodeOpacity) * 0.3
            )
            entity.name = "edge-\(edge.id.uuidString)"
            content.add(entity)
        }

        // Disk floor — subtle reference circle
        let diskFloor = makeDiskFloor()
        content.add(diskFloor)
    }

    private func updateScene(content: RealityViewContent) {
        // Highlight selected node, dim others
        for entity in content.entities {
            guard let model = entity as? ModelEntity else { continue }
            if let node = nodes.first(where: { $0.id.uuidString == entity.name }) {
                let isSelected = (node.id == selectedNodeId)
                let scale: Float = isSelected ? 1.4 : 1.0
                model.scale = SIMD3<Float>(repeating: scale)
            }
        }
    }

    // MARK: - Entity Factories

    private func makeNodeEntity(node: PoincaréNode, color: Color) -> Entity {
        let mesh = MeshResource.generateSphere(radius: node.nodeRadius)

        var material = PhysicallyBasedMaterial()
        let uiColor = UIColor(resolvableColor: color)
        material.emissiveColor = .init(color: uiColor)
        material.emissiveIntensity = node.depth == 0 ? 0.8 : 0.4
        material.baseColor = .init(tint: uiColor)
        material.metallic = 0.4
        material.roughness = 0.5
        material.blending = .transparent(opacity: .init(floatLiteral: node.nodeOpacity))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = node.spatialPosition
        entity.name = node.id.uuidString

        // Interactive
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: node.nodeRadius * 1.5)]))
        entity.components.set(HoverEffectComponent())

        return entity
    }

    private func makeEdgeEntity(from start: SIMD3<Float>, to end: SIMD3<Float>, opacity: Float) -> Entity {
        let midpoint = (start + end) / 2
        let length = simd_distance(start, end)
        guard length > 0.001 else { return Entity() }

        let mesh = MeshResource.generateCylinder(height: length, radius: 0.001)
        var material = UnlitMaterial()
        material.color = .init(tint: .init(white: 1, alpha: CGFloat(opacity)))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = midpoint

        let dir = simd_normalize(end - start)
        let up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(dir, up)) < 0.999 {
            entity.orientation = simd_quatf(from: up, to: dir)
        }

        return entity
    }

    private func makeDiskFloor() -> Entity {
        // A thin, subtle ring showing the Poincare disk boundary
        let mesh = MeshResource.generateCylinder(height: 0.001, radius: 0.6)
        var material = UnlitMaterial()
        material.color = .init(tint: .init(white: 1, alpha: 0.05))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3<Float>(0, -0.01, 0)
        entity.name = "disk-floor"
        return entity
    }

    // MARK: - Color Map

    private func buildColorMap(clusterNames: [String]) -> [String: Color] {
        var map: [String: Color] = [:]
        for (i, name) in clusterNames.enumerated() where name != "root" {
            map[name] = Self.clusterColors[i % Self.clusterColors.count]
        }
        return map
    }

    // MARK: - Detail Panel

    private func detailPanel(for node: PoincaréNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Self.clusterColors[
                        max(0, Array(Set(nodes.map(\.cluster)).sorted()).firstIndex(of: node.cluster) ?? 0) %
                        Self.clusterColors.count
                    ])
                    .frame(width: 8, height: 8)
                Text(node.label)
                    .font(BeagleTheme.uiFont(size: 16, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(2)
                Spacer()
                Button {
                    selectedNodeId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if let detail = node.detail, !detail.isEmpty {
                Text(detail)
                    .font(BeagleTheme.uiFont(size: 13))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(6)
            }

            HStack(spacing: 12) {
                Label("Depth \(node.depth)", systemImage: "circle.grid.3x3")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textTertiary)

                Label(node.cluster.capitalized, systemImage: "tag")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textTertiary)

                if node.thoughtId != nil {
                    Label("Thought", systemImage: "brain.head.profile")
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 420)
        .glassBackgroundEffect()
    }
}

// MARK: - Preview

#Preview(windowStyle: .volumetric) {
    HyperbolicGraphView(thoughts: [
        ThoughtCapture(
            nodeId: "1", refinedText: "Hyperbolic geometry models hierarchical data naturally",
            rawText: nil, source: "test", createdAt: nil, syncedToServer: false, syncState: .localOnly
        ),
        ThoughtCapture(
            nodeId: "2", refinedText: "State-space models are the future of on-device inference",
            rawText: nil, source: "test", createdAt: nil, syncedToServer: false, syncState: .localOnly
        ),
        ThoughtCapture(
            nodeId: "3", refinedText: "Knowledge graphs need spatial navigation for insight discovery",
            rawText: nil, source: "test", createdAt: nil, syncedToServer: false, syncState: .localOnly
        ),
    ])
}

#endif
