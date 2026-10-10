/// Narrow metadata admission for Matroska on an unshifted display timeline.
enum NativeMKVDurationAdmission {
    static func duration(format: String?, formatStart: Double?, duration: Double?,
                         videoStart: Int64?, timeBaseNumerator: Int32, timeBaseDenominator: Int32) -> Double? {
        guard format?.split(separator: ",").contains("matroska") == true,
              let formatStart, formatStart == 0,
              let duration, duration.isFinite, duration > 0,
              let videoStart, videoStart != Int64.min, videoStart >= 0,
              timeBaseNumerator > 0, timeBaseDenominator > 0 else { return nil }
        let videoSeconds = Double(videoStart) * Double(timeBaseNumerator) / Double(timeBaseDenominator)
        guard videoSeconds.isFinite, videoSeconds < duration else { return nil }
        return duration
    }
}
