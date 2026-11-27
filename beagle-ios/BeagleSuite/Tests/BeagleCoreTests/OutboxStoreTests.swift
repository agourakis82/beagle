import Foundation
import SwiftData
import Testing
@testable import BeagleCore

@Suite
@MainActor
struct OutboxStoreTests {
    private func memoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PendingIngest.self, configurations: config)
        return ModelContext(container)
    }

    @Test func testEnqueueThenPendingReturnsIt() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "guarda X", assistantText: "ok", clientTime: "", timezone: "UTC")
        let pending = store.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.userText == "guarda X")
    }

    @Test func testDeleteRemovesFromPending() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "a", assistantText: "b", clientTime: "", timezone: "")
        let item = try #require(store.pending().first)
        store.delete(item)
        #expect(store.pending().isEmpty)
    }

    @Test func testEnqueueSkipsEmptySides() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "", assistantText: "b", clientTime: "", timezone: "")
        #expect(store.pending().isEmpty)
    }
}
