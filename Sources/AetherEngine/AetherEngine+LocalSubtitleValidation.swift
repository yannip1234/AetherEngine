import Foundation

/// Errors suitable for presenting when importing an app-owned subtitle file.
public enum LocalSubtitleValidationError: Error, LocalizedError, Equatable, Sendable {
    case invalidFile
    case tooLarge
    case invalidSubtitles

    public var errorDescription: String? {
        switch self {
        case .invalidFile: "Choose a readable local SRT or VTT file."
        case .tooLarge: "Subtitle files must be 2 MB or smaller."
        case .invalidSubtitles: "This file does not contain valid text subtitles."
        }
    }
}

extension AetherEngine {
    /// Validates an app-owned, canonical file before registering or publishing its subtitle track.
    /// The caller must keep the file private and unchanged through subsequent playback.
    /// shortcut: FFmpeg may skip malformed source records; add strict parsing if whole-file completeness is required.
    public nonisolated static func validateLocalSubtitleFile(at url: URL) async throws -> Int {
        try Task.checkCancellation()
        do {
            let original = try LocalSubtitleFileSnapshot(url: url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: LocalSubtitleFileSnapshot.maximumBytes + 1) ?? Data()
            guard data.count <= LocalSubtitleFileSnapshot.maximumBytes else {
                throw LocalSubtitleValidationError.tooLarge
            }
            guard data.count == original.size, !data.isEmpty, String(data: data, encoding: .utf8) != nil else {
                throw LocalSubtitleValidationError.invalidSubtitles
            }
            let result = try await SubtitleDecoder.decodeFile(
                url: url, httpHeaders: [:], localInputFormat: url.pathExtension.lowercased() == "srt" ? "srt" : "webvtt")
            try Task.checkCancellation()
            guard !result.cues.isEmpty, result.cues.count <= 10_000,
                  result.cues.allSatisfy({ cue in
                      cue.startTime.isFinite && cue.endTime.isFinite && cue.startTime >= 0 &&
                      cue.endTime > cue.startTime && cue.endTime <= 86_400 &&
                      !(cue.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                  }) else { throw LocalSubtitleValidationError.invalidSubtitles }
            guard try LocalSubtitleFileSnapshot(url: url) == original else {
                throw LocalSubtitleValidationError.invalidFile
            }
            return result.cues.count
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalSubtitleValidationError {
            throw error
        } catch {
            throw LocalSubtitleValidationError.invalidSubtitles
        }
    }
}

private struct LocalSubtitleFileSnapshot: Equatable {
    static let maximumBytes = 2 * 1_024 * 1_024
    let size: Int
    let inode: UInt64
    let device: UInt64
    let modified: Date

    init(url: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, !url.pathComponents.contains(".."),
              !url.pathComponents.contains("."), ["srt", "vtt"].contains(url.pathExtension.lowercased()),
              url.path == url.standardizedFileURL.resolvingSymlinksInPath().path else {
            throw LocalSubtitleValidationError.invalidFile
        }
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch { throw LocalSubtitleValidationError.invalidFile }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else {
            throw LocalSubtitleValidationError.invalidFile
        }
        guard size.intValue <= Self.maximumBytes else { throw LocalSubtitleValidationError.tooLarge }
        self.size = size.intValue
        self.inode = inode.uint64Value
        self.device = device.uint64Value
        self.modified = modified
    }
}
