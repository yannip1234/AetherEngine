import AVFoundation
import XCTest
@testable import AetherEngine

@MainActor final class NativeCommandPlayerTests: XCTestCase {
    func testExternalCommandsIncludingAlreadyPausedAreReportedOnce() async {
        let player = NativeCommandPlayer()
        var rates: [Float] = []
        player.onCommand = { exact, _, rate in XCTAssertTrue(exact === player); rates.append(rate) }
        player.pause(); player.rate = 0; player.play(); player.playImmediately(atRate: 1.5)
        await Task.yield()
        XCTAssertEqual(rates, [0, 0, 1, 1.5])
    }
    func testEngineCommandsAreSilentAndSuppressionIsNested() async {
        let player = NativeCommandPlayer()
        var rates: [Float] = []
        player.onCommand = { _, _, rate in rates.append(rate) }
        player.internally { player.play(); player.internally { player.rate = 0 }; player.pause() }
        XCTAssertTrue(rates.isEmpty)
        player.rate = 1
        await Task.yield()
        XCTAssertEqual(rates, [1])
    }
    func testReentrantTransportDoesNotDuplicateCommand() async {
        let player = NativeCommandPlayer()
        var rates: [Float] = []
        player.onCommand = { exact, _, rate in rates.append(rate); exact.internally { exact.pause() } }
        player.rate = 1
        await Task.yield()
        XCTAssertEqual(rates, [1])
    }
    func testClosedGateRejectsExternalButPermitsEngineTransport() async {
        let player = NativeCommandPlayer()
        var rates: [Float] = []
        player.onCommand = { _, _, rate in rates.append(rate) }
        player.acceptsExternalCommands = false
        player.play(); player.pause(); player.rate = 1
        await Task.yield()
        XCTAssertTrue(rates.isEmpty)
        player.internally { player.rate = 1 }
        XCTAssertEqual(player.rate, 1)
        player.acceptsExternalCommands = true
        player.pause()
        await Task.yield()
        XCTAssertEqual(rates, [0])
    }
    func testRetiredItemCommandIsNotDelivered() async {
        let player = NativeCommandPlayer()
        var calls = 0
        player.onCommand = { _, _, _ in calls += 1 }
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent")))
        await Task.yield()
        XCTAssertEqual(calls, 0)
    }
    func testCommandBeforeGateRetirementIsNotDeliveredAfterReopening() async {
        let player = NativeCommandPlayer()
        var calls = 0
        player.onCommand = { _, _, _ in calls += 1 }
        player.pause()
        player.acceptsExternalCommands = false
        player.acceptsExternalCommands = true
        await Task.yield()
        XCTAssertEqual(calls, 0)
    }

}
