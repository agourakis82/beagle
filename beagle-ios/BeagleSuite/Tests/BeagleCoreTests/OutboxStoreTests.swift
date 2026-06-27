import XCTest
import SwiftData
@testable import BeagleCore

@MainActor
final class OutboxStoreTests: XCTestCase {
    private func memoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PendingIngest.self, configurations: config)
        return ModelContext(container)
    }

    func testEnqueueThenPendingReturnsIt() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "guarda X", assistantText: "ok", clientTime: "", timezone: "UTC")
        let pending = store.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.userText, "guarda X")
    }

    func testDeleteRemovesFromPending() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "a", assistantText: "b", clientTime: "", timezone: "")
        let item = try XCTUnwrap(store.pending().first)
        store.delete(item)
        XCTAssertEqual(store.pending().count, 0)
    }

    func testEnqueueSkipsEmptySides() throws {
        let ctx = try memoryContext()
        let store = OutboxStore(context: ctx)
        store.enqueue(sessionId: "s", userText: "", assistantText: "b", clientTime: "", timezone: "")
        XCTAssertEqual(store.pending().count, 0)
    }
}
