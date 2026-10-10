import AVFoundation
import XCTest
@testable import AetherEngine

@MainActor
final class NativeSubtitleAutomaticSelectionTests: XCTestCase {
    private func load(_ engine: AetherEngine, fixture: String = "owned-seek-tracks.mkv") async throws -> (AVPlayer, AVPlayerItem, AVMediaSelectionGroup) {
        guard let address = ProcessInfo.processInfo.environment["SIGNAL_CONTAINER_TRACK_ORIGIN"],
              let base = URL(string: address), base.host == "127.0.0.1" else {
            throw XCTSkip("Requires owned loopback multitrack fixture")
        }
        var options = LoadOptions()
        options.autoplay = false
        options.prepareNativeSubtitles = true
        options.eagerNativeSubtitleReaders = true
        options.nativeSubtitleRendererOwnsSelection = true
        options.escalatesToSoftwarePath = false
        try await engine.load(url: base.appendingPathComponent(fixture), options: options)
        let player = try XCTUnwrap(engine.currentAVPlayer)
        let item = try XCTUnwrap(player.currentItem)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while item.status != .readyToPlay, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(item.status, .readyToPlay)
        let group = try await item.asset.loadMediaSelectionGroup(for: .legible)
        return (player, item, try XCTUnwrap(group))
    }

    func testPendingPinCannotRearmAfterAutomaticSelectionAndRetiredOwnerCannotSelect() async throws {
        let engine = try AetherEngine()
        defer { engine.stop() }
        let (player, item, group) = try await load(engine)
        player.setMediaSelectionCriteria(AVPlayerMediaSelectionCriteria(preferredLanguages: ["en"], preferredMediaCharacteristics: nil), forMediaCharacteristic: .legible)
        engine.forceNativeLegibleDeselectedUntilHostSelects()
        XCTAssertNotNil(engine.nativeLegibleDeselectPinTask)
        let selected = await engine.setNativeSubtitleAutomaticSelection(player: player, item: item)
        XCTAssertTrue(selected)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertNil(engine.nativeLegibleDeselectPinTask)
        XCTAssertNil(engine.nativeLegibleDeselectPinObserver)
        XCTAssertNil(engine.nativeSubtitleReapplyOrdinal)
        XCTAssertTrue(player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertTrue(item.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group))
        let (replacement, replacementItem, _) = try await load(engine)
        let request = engine.nativeSubtitleSelectionRequest
        let stale = await engine.setNativeSubtitleAutomaticSelection(player: player, item: item)
        XCTAssertFalse(stale)
        XCTAssertEqual(engine.nativeSubtitleSelectionRequest, request)
        XCTAssertTrue(engine.currentAVPlayer === replacement)
        XCTAssertTrue(engine.currentAVPlayerItem === replacementItem)
        let current = await engine.setNativeSubtitleAutomaticSelection(player: replacement, item: replacementItem)
        XCTAssertTrue(current)
        engine.stop()
        let stopped = await engine.setNativeSubtitleAutomaticSelection(player: replacement, item: replacementItem)
        XCTAssertFalse(stopped)
    }

    func testManualAndPendingSelectionReturnToAutomaticWithoutFixedTrackResurrectionOnSeek() async throws {
        let engine = try AetherEngine()
        defer { engine.stop() }
        let (player, item, group) = try await load(engine)
        engine.setNativeSubtitleSelected(track: 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(16))
        while item.currentMediaSelection.selectedMediaOption(in: group) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(item.currentMediaSelection.selectedMediaOption(in: group))
        XCTAssertEqual(engine.nativeSubtitleReapplyOrdinal, 0)
        engine.setNativeSubtitleSelected(track: 0)
        let automatic = await engine.setNativeSubtitleAutomaticSelection(player: player, item: item)
        XCTAssertTrue(automatic)
        await engine.seek(to: 6)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(engine.currentAVPlayerItem === item)
        XCTAssertNil(engine.nativeSubtitleReapplyOrdinal)
        XCTAssertNil(engine.nativeSubtitleReanchorTask)
        XCTAssertTrue(player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertTrue(item.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group))
        XCTAssertEqual(player.rate, 0)
    }
    func testCaptionlessAutomaticSelectionIsSuccessfulNoOp() async throws {
        guard let address = ProcessInfo.processInfo.environment["SIGNAL_CONTAINER_TRACK_ORIGIN"],
              let base = URL(string: address), base.host == "127.0.0.1" else {
            throw XCTSkip("Requires owned loopback fixture")
        }
        let engine = try AetherEngine()
        defer { engine.stop() }
        var options = LoadOptions()
        options.autoplay = false
        options.prepareNativeSubtitles = true
        options.eagerNativeSubtitleReaders = true
        options.nativeSubtitleRendererOwnsSelection = true
        options.escalatesToSoftwarePath = false
        try await engine.load(url: base.appendingPathComponent("owned.mkv"), options: options)
        let player = try XCTUnwrap(engine.currentAVPlayer)
        let item = try XCTUnwrap(player.currentItem)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (item.status != .readyToPlay || engine.currentAVPlayerItem !== item), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(engine.currentAVPlayerItem === item)
        let result = await engine.setNativeSubtitleAutomaticSelection(player: player, item: item)
        XCTAssertTrue(result)
        XCTAssertTrue(player.appliesMediaSelectionCriteriaAutomatically)
        XCTAssertNil(engine.nativeSubtitleReapplyOrdinal)
        XCTAssertTrue(engine.nativeSubtitleTracks.isEmpty)
    }

    func testExplicitOffWinsOverPendingAutomaticSelection() async throws {
        let engine = try AetherEngine()
        defer { engine.stop() }
        let (player, item, group) = try await load(engine)
        let automatic = Task { await engine.setNativeSubtitleAutomaticSelection(player: player, item: item) }
        await Task.yield()
        engine.setNativeSubtitleSelected(track: nil)
        _ = await automatic.value
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertNil(item.currentMediaSelection.selectedMediaOption(in: group))
        XCTAssertNil(engine.nativeSubtitleReapplyOrdinal)
        XCTAssertFalse(player.appliesMediaSelectionCriteriaAutomatically)
    }

    func testForcedSDHExplicitOffThenAutomaticIsOwnedNativeSelection() async throws {
        let engine = try AetherEngine()
        defer { engine.stop() }
        let (player, item, group) = try await load(engine, fixture: "owned-forced-sdh.mkv")
        let option = try XCTUnwrap(group.options.first)
        XCTAssertTrue(option.hasMediaCharacteristic(.containsOnlyForcedSubtitles))
        XCTAssertTrue(option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility))
        engine.setNativeSubtitleSelected(track: nil)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertNil(item.currentMediaSelection.selectedMediaOption(in: group))
        XCTAssertFalse(player.appliesMediaSelectionCriteriaAutomatically)
        let result = await engine.setNativeSubtitleAutomaticSelection(player: player, item: item)
        XCTAssertTrue(result)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(item.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group))
    }

    func testNativeCriteriaChangesApplyAfterOffToAutomaticOnSameItem() async throws {
        let engine = try AetherEngine()
        defer { engine.stop() }
        let (_, sourceItem, _) = try await load(engine)
        let url = try XCTUnwrap((sourceItem.asset as? AVURLAsset)?.url)
        let item = AVPlayerItem(url: url), player = AVPlayer()
        player.setMediaSelectionCriteria(AVPlayerMediaSelectionCriteria(preferredLanguages: ["en"], preferredMediaCharacteristics: nil), forMediaCharacteristic: .legible)
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.replaceCurrentItem(with: item)
        defer { player.replaceCurrentItem(with: nil) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while item.status != .readyToPlay, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let loaded = try await item.asset.loadMediaSelectionGroup(for: .legible)
        let group = try XCTUnwrap(loaded)
        XCTAssertFalse(item.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group))
        player.appliesMediaSelectionCriteriaAutomatically = false
        item.select(nil, in: group)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(item.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group))
        player.appliesMediaSelectionCriteriaAutomatically = true
        item.selectMediaOptionAutomatically(in: group)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(item.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group))
        let selectedLanguage = try XCTUnwrap(item.currentMediaSelection.selectedMediaOption(in: group)?.extendedLanguageTag)
        XCTAssertEqual(Locale(identifier: selectedLanguage).language.languageCode, Locale(identifier: "en").language.languageCode)
        player.setMediaSelectionCriteria(AVPlayerMediaSelectionCriteria(preferredLanguages: ["es"], preferredMediaCharacteristics: nil), forMediaCharacteristic: .legible)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(player.currentItem === item)
        XCTAssertTrue(item.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group))
        XCTAssertNil(item.currentMediaSelection.selectedMediaOption(in: group))
    }

}
