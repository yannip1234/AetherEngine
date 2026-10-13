import XCTest
@testable import AetherEngine

final class ExternalSubtitleDrainTests: XCTestCase {
    @MainActor
    func testDrainWaitsForCurrentAndRetiredWorkers() async throws {
        let engine = try AetherEngine()
        let retired = HeldSubtitleWorker()
        let current = HeldSubtitleWorker()
        engine.startTrackedExternalNativeStoreFill { await retired.hold() }
        await retired.waitUntilStarted()
        engine.startTrackedExternalNativeStoreFill { await current.hold() }
        await current.waitUntilStarted()
        XCTAssertEqual(engine.pendingExternalNativeStoreFillTasks.count, 2)
        var finished = false
        let drain = Task { @MainActor in
            await engine.stopAndDrainExternalSubtitleReads()
            finished = true
        }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(finished)
        await current.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(finished, "A retired worker still holds its file")
        await retired.release()
        await drain.value
        XCTAssertTrue(finished)
        XCTAssertTrue(engine.pendingExternalNativeStoreFillTasks.isEmpty)
        let retiredCancelled = await retired.sawCancellation
        let currentCancelled = await current.sawCancellation
        XCTAssertTrue(retiredCancelled)
        XCTAssertTrue(currentCancelled)
    }

    @MainActor
    func testExternalIDMapsToActualNativeTableOrdinal() throws {
        let engine = try AetherEngine()
        let id = AetherEngine.externalSubtitleTrackIDBase
        engine.nativeSubtitleTrackTable = [
            .init(sourceStreamIndex: 2, language: "en"),
            .init(sourceStreamIndex: nil, externalID: id, language: nil)
        ]
        XCTAssertEqual(engine.nativeExternalSubtitleOrdinal(registrationIndex: 0), 1)
        XCTAssertNil(engine.nativeExternalSubtitleOrdinal(registrationIndex: 1))
        XCTAssertNil(engine.nativeExternalSubtitleOrdinal(registrationIndex: -1))
        XCTAssertNil(engine.nativeExternalSubtitleOrdinal(registrationIndex: Int.max))
    }
}

private actor HeldSubtitleWorker {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var sawCancellation = false

    func hold() async {
        await withCheckedContinuation { continuation = $0 }
        sawCancellation = Task.isCancelled
    }

    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
