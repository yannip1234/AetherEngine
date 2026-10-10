import Foundation
import XCTest
@testable import AetherEngine

final class NativeSubtitleManifestTests: XCTestCase {
    func testOverlayDefaultAndNativeRendererEligibilityPreserveMetadata() async throws {
        XCTAssertFalse(LoadOptions().nativeSubtitleRendererOwnsSelection)
        for native in [false, true] {
            let provider = SubtitleProvider()
            let server = HLSLocalServer(provider: provider, nativeSubtitleRendererOwnsSelection: native)
            try server.start()
            defer { server.stop() }
            let url = try XCTUnwrap(server.playlistURL)
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertTrue(text.contains("DEFAULT=NO,AUTOSELECT=\(native ? "YES" : "NO")"))
            XCTAssertEqual(text.contains("FORCED=YES"), native)
            XCTAssertEqual(text.contains("public.accessibility.transcribes-spoken-dialog"), native)
            XCTAssertEqual(text.contains("public.accessibility.describes-music-and-sound"), native)
        }
    }
}
private final class SubtitleProvider: HLSSegmentProvider, @unchecked Sendable {
    func initSegment() -> Data? { Data([0]) }
    func mediaSegment(at index: Int) -> Data? { Data([0]) }
    var segmentCount: Int { 1 }
    func segmentDuration(at index: Int) -> Double { 4 }
    var playlistType: HLSPlaylistType { .vod }
    var masterCodecs: String? { "avc1.640028" }
    var nativeSubtitleRenditions: [(ordinal: Int, language: String?, name: String, isForced: Bool, isHearingImpaired: Bool)] {
        [(0, "en", "English forced SDH", true, true)]
    }
}
