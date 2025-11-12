import SwiftUI
import Combine
import CoreData
import Network
import UIKit

// MARK: - Domain Models

enum ContentType: String, Codable, CaseIterable, Identifiable {
    case text
    case image
    case audio
    case video
    case metadata

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Texto"
        case .image: return "Imagem"
        case .audio: return "Áudio"
        case .video: return "Vídeo"
        case .metadata: return "Metadados"
        }
    }
}

struct Node: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var type: ContentType
    var createdAt: Date
    var isPending: Bool

    init(id: UUID = UUID(), content: String, type: ContentType, createdAt: Date = Date(), isPending: Bool = false) {
        self.id = id
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.isPending = isPending
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, type, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(ContentType.self, forKey: .type)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isPending = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Core Data Layer

@objc(StoredNode)
final class StoredNode: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var content: String
    @NSManaged var typeRaw: String
    @NSManaged var createdAt: Date
    @NSManaged var isPending: Bool
}

extension StoredNode {
    @nonobjc class func fetchRequest() -> NSFetchRequest<StoredNode> {
        NSFetchRequest<StoredNode>(entityName: "StoredNode")
    }
}

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "BeagleModel", managedObjectModel: model)

        if inMemory {
            if let description = container.persistentStoreDescriptions.first {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Erro ao carregar o Core Data: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "StoredNode"
        entity.managedObjectClassName = NSStringFromClass(StoredNode.self)

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false

        let content = NSAttributeDescription()
        content.name = "content"
        content.attributeType = .stringAttributeType
        content.isOptional = false

        let typeRaw = NSAttributeDescription()
        typeRaw.name = "typeRaw"
        typeRaw.attributeType = .stringAttributeType
        typeRaw.isOptional = false

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType
        createdAt.isOptional = false

        let isPending = NSAttributeDescription()
        isPending.name = "isPending"
        isPending.attributeType = .booleanAttributeType
        isPending.isOptional = false
        isPending.defaultValue = false

        entity.properties = [id, content, typeRaw, createdAt, isPending]

        model.entities = [entity]
        return model
    }

    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Networking

struct BeagleAPI {
    enum APIError: Error {
        case invalidURL
        case unexpectedStatus(code: Int)
        case decodingFailure
    }

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: String, session: URLSession = .shared) {
        guard let url = URL(string: baseURL) else {
            fatalError("URL base inválida: \(baseURL)")
        }
        self.baseURL = url
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = encoder
        self.decoder = decoder
    }

    func listNodes() async throws -> [Node] {
        let url = baseURL.appendingPathComponent("nodes")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.decodingFailure }
        guard 200..<300 ~= http.statusCode else { throw APIError.unexpectedStatus(code: http.statusCode) }
        do {
            return try decoder.decode([Node].self, from: data)
        } catch {
            throw APIError.decodingFailure
        }
    }

    func createNode(content: String, type: ContentType, id: UUID, createdAt: Date) async throws -> Node {
        let url = baseURL.appendingPathComponent("nodes")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Encodable {
            let id: UUID
            let content: String
            let type: ContentType
            let createdAt: Date
        }

        let payload = Payload(id: id, content: content, type: type, createdAt: createdAt)
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.decodingFailure }
        guard 200..<300 ~= http.statusCode else { throw APIError.unexpectedStatus(code: http.statusCode) }
        do {
            return try decoder.decode(Node.self, from: data)
        } catch {
            throw APIError.decodingFailure
        }
    }
}

// MARK: - Node Store

@MainActor
final class NodeStore: ObservableObject {
    static let shared = NodeStore()

    @Published private(set) var nodes: [Node] = []
    @Published var lastSyncError: Error?

    private let persistence: PersistenceController
    private let api: BeagleAPI
    private let monitor = NWPathMonitor()
    private var isOnline: Bool = false
    private let monitorQueue = DispatchQueue(label: "beagle.node-store.network-monitor")

    private init(persistence: PersistenceController = .shared,
                 api: BeagleAPI = BeagleAPI(baseURL: "http://localhost:3000")) {
        self.persistence = persistence
        self.api = api
        configureNetworkMonitoring()
        Task {
            await refreshFromCache()
            await processPendingQueue()
        }
    }

    deinit {
        monitor.cancel()
    }

    func createNode(_ content: String, type: ContentType) async {
        lastSyncError = nil
        let provisional = Node(content: content, type: type, createdAt: Date(), isPending: !isOnline)

        do {
            try await persist(node: provisional, pending: true)
            nodes.insert(provisional, at: 0)
            if isOnline {
                try await sendNodeToServer(local: provisional)
            }
        } catch {
            lastSyncError = error
        }
    }

    func syncNodes() async throws {
        guard isOnline else {
            try await processPendingQueue()
            await refreshFromCache()
            throw SyncError.offline
        }

        lastSyncError = nil

        let remoteNodes = try await api.listNodes()
        try await persistence.performBackgroundTask { context in
            let request = StoredNode.fetchRequest()
            let stored = try context.fetch(request)
            var storedDictionary = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })

            for remote in remoteNodes {
                let managed = storedDictionary.removeValue(forKey: remote.id) ?? StoredNode(context: context)
                managed.id = remote.id
                managed.content = remote.content
                managed.typeRaw = remote.type.rawValue
                managed.createdAt = remote.createdAt
                managed.isPending = false
            }

            for orphan in storedDictionary.values where !orphan.isPending {
                context.delete(orphan)
            }
        }

        await refreshFromCache()
        try await processPendingQueue()
    }

    @discardableResult
    func performBackgroundRefresh() async throws -> Bool {
        let originalSnapshot = nodes
        do {
            try await syncNodes()
            return originalSnapshot != nodes
        } catch SyncError.offline {
            try await processPendingQueue()
            return false
        } catch {
            lastSyncError = error
            throw error
        }
    }

    enum SyncError: Error {
        case offline
    }
}

// MARK: - Private helpers

private extension NodeStore {
    func configureNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                if self?.isOnline == true && wasOnline == false {
                    await self?.processPendingQueue()
                    await self?.attemptRemoteRefresh()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func attemptRemoteRefresh() async {
        do {
            try await syncNodes()
        } catch {
            lastSyncError = error
        }
    }

    func refreshFromCache() async {
        let context = persistence.container.viewContext
        let request = StoredNode.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            let stored = try context.fetch(request)
            nodes = stored.map { managed in
                Node(id: managed.id,
                     content: managed.content,
                     type: ContentType(rawValue: managed.typeRaw) ?? .text,
                     createdAt: managed.createdAt,
                     isPending: managed.isPending)
            }
        } catch {
            lastSyncError = error
        }
    }

    func persist(node: Node, pending: Bool) async throws {
        try await persistence.performBackgroundTask { context in
            let stored = StoredNode(context: context)
            stored.id = node.id
            stored.content = node.content
            stored.typeRaw = node.type.rawValue
            stored.createdAt = node.createdAt
            stored.isPending = pending
        }
    }

    func sendNodeToServer(local: Node) async throws {
        do {
            let remote = try await api.createNode(content: local.content, type: local.type, id: local.id, createdAt: local.createdAt)
            try await persistence.performBackgroundTask { context in
                let request = StoredNode.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", local.id as CVarArg)
                if let stored = try context.fetch(request).first {
                    stored.id = remote.id
                    stored.content = remote.content
                    stored.typeRaw = remote.type.rawValue
                    stored.createdAt = remote.createdAt
                    stored.isPending = false
                }
            }
            await refreshFromCache()
        } catch {
            lastSyncError = error
            throw error
        }
    }

    func processPendingQueue() async throws {
        let context = persistence.container.viewContext
        let request = StoredNode.fetchRequest()
        request.predicate = NSPredicate(format: "isPending == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        let pendingManaged = try context.fetch(request)
        guard !pendingManaged.isEmpty else { return }

        for managed in pendingManaged {
            let payload = Node(id: managed.id,
                               content: managed.content,
                               type: ContentType(rawValue: managed.typeRaw) ?? .text,
                               createdAt: managed.createdAt,
                               isPending: true)
            guard isOnline else { break }
            do {
                try await sendNodeToServer(local: payload)
            } catch {
                lastSyncError = error
                break
            }
        }
        await refreshFromCache()
    }
}

// MARK: - UIApplicationDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.setMinimumBackgroundFetchInterval(15 * 60)
        return true
    }

    func application(_ application: UIApplication,
                     performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            do {
                let updated = try await NodeStore.shared.performBackgroundRefresh()
                completionHandler(updated ? .newData : .noData)
            } catch {
                completionHandler(.failed)
            }
        }
    }
}

// MARK: - SwiftUI App

@main
struct BeagleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NodeStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

// MARK: - SwiftUI Views

struct ContentView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var content: String = ""
    @State private var type: ContentType = .text
    @State private var isSyncing: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                creationForm
                Divider()
                NodeListView()
            }
            .padding()
            .navigationTitle("Nós Beagle")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await triggerSync()
                        }
                    } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isSyncing)
                }
            }
            .alert("Erro de Sincronização",
                   isPresented: Binding(
                    get: { store.lastSyncError != nil },
                    set: { value in
                        if !value { store.lastSyncError = nil }
                    }),
                   actions: {
                       Button("OK") { store.lastSyncError = nil }
                   },
                   message: {
                       Text(store.lastSyncError?.localizedDescription ?? "Ocorreu um erro desconhecido.")
                   })
        }
    }

    private var creationForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Criar novo nó")
                .font(.headline)

            TextField("Conteúdo", text: $content, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            Picker("Tipo", selection: $type) {
                ForEach(ContentType.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.segmented)

            Button {
                Task {
                    await createNode()
                }
            } label: {
                Label("Adicionar", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func createNode() async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await store.createNode(trimmed, type: type)
        content = ""
        type = .text
    }

    private func triggerSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await store.syncNodes()
        } catch {
            // Erros offline já são tratados no store
        }
    }
}

struct NodeListView: View {
    @EnvironmentObject private var store: NodeStore

    var body: some View {
        List(store.nodes) { node in
            NodeRow(node: node)
        }
        .listStyle(.plain)
        .refreshable {
            try? await store.syncNodes()
        }
        .overlay {
            if store.nodes.isEmpty {
                ContentUnavailableView("Nenhum nó", systemImage: "network.slash") {
                    Text("Crie nós ou sincronize para visualizar conteúdo.")
                }
            }
        }
    }
}

struct NodeRow: View {
    let node: Node

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(node.content)
                    .font(.body)
                    .foregroundColor(.primary)
                Spacer()
                Text(node.type.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
            }
            HStack(spacing: 8) {
                Text(node.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(node.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if node.isPending {
                    Label("Pendente", systemImage: "icloud.and.arrow.up")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(NodeStore.shared)
    }
}
#endif









