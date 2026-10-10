import XCTest
@testable import AetherEngine

final class NativeMKVDurationAdmissionTests: XCTestCase {
    func testFiniteMatroskaDurationAdmissionBoundaries() {
        var count = 0
        func check(_ expected: Double?, format: String? = "matroska,webm", start: Double? = 0,
                   duration: Double? = 180.021, video: Int64? = 21, numerator: Int32 = 1, denominator: Int32 = 1000) {
            let actual = NativeMKVDurationAdmission.duration(format: format, formatStart: start, duration: duration,
                videoStart: video, timeBaseNumerator: numerator, timeBaseDenominator: denominator)
            XCTAssertEqual(actual, expected, "case \(count): \(String(describing: actual)) != \(String(describing: expected))")
            count += 1
        }
        check(180.021)
        check(180.021, video: 0)
        check(180.021, video: 5000)
        check(12.021, duration: 12.021)
        check(nil, format: "mpegts")
        check(nil, format: "fake-matroska")
        check(nil, format: nil)
        for start: Double? in [nil, -1, 3599.979, .nan, .infinity] { check(nil, start: start) }
        for duration: Double? in [nil, 0, -1, .nan, .infinity] { check(nil, duration: duration) }
        for video: Int64? in [nil, Int64.min, -1, 180021, 180022] { check(nil, video: video) }
        for value: Int32 in [0, -1] { check(nil, numerator: value); check(nil, denominator: value) }
        XCTAssertEqual(count, 26)
    }
}
