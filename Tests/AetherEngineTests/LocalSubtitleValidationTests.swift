import XCTest
@testable import AetherEngine

final class LocalSubtitleValidationTests: XCTestCase {
    private func withFile(_ contents: String, extension suffix: String = "srt",
                          check: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("subtitle.\(suffix)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try await check(url)
    }

    func testValidSRTAndWebVTT() async throws {
        try await withFile("1\n00:00:01,000 --> 00:00:02,000\nHello\n\n") { url in
            let count = try await AetherEngine.validateLocalSubtitleFile(at: url)
            XCTAssertEqual(count, 1)
        }
        try await withFile("WEBVTT\n\n00:01.000 --> 00:02.000\nHello\n\n", extension: "vtt") { url in
            let count = try await AetherEngine.validateLocalSubtitleFile(at: url)
            XCTAssertEqual(count, 1)
        }
    }

    func testMalformedEmptyAndOutOfBoundsFiles() async throws {
        for contents in ["", "not subtitles", "1\n25:00:00,000 --> 25:00:02,000\nHello\n\n",
                         "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nhttps://example.invalid/segment.ts\n"] {
            try await withFile(contents) { url in
                do {
                    _ = try await AetherEngine.validateLocalSubtitleFile(at: url)
                    XCTFail("Expected rejection")
                } catch is LocalSubtitleValidationError { }
            }
        }
    }

    func testRejectsRemoteURLSymlinkAndOversizedFile() async throws {
        do {
            _ = try await AetherEngine.validateLocalSubtitleFile(at: URL(string: "https://example.invalid/file.srt")!)
            XCTFail("Expected rejection")
        } catch let error as LocalSubtitleValidationError { XCTAssertEqual(error, .invalidFile) }
        try await withFile("1\n00:00:01,000 --> 00:00:02,000\nHello\n\n") { url in
            let link = url.deletingLastPathComponent().appendingPathComponent("link.srt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
            do {
                _ = try await AetherEngine.validateLocalSubtitleFile(at: link)
                XCTFail("Expected rejection")
            } catch let error as LocalSubtitleValidationError { XCTAssertEqual(error, .invalidFile) }
        }
        try await withFile(String(repeating: "x", count: 2 * 1_024 * 1_024 + 1)) { url in
            do {
                _ = try await AetherEngine.validateLocalSubtitleFile(at: url)
                XCTFail("Expected rejection")
            } catch let error as LocalSubtitleValidationError { XCTAssertEqual(error, .tooLarge) }
        }
    }
}
