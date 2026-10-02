import Foundation
import GlucoseCore

/// Ambulatory-glucose-profile-style time-in-range statistics for a set of
/// readings restricted to a date interval.
public struct TIRResult: Sendable, Equatable {
    public var veryLowPercent: Double
    public var lowPercent: Double
    public var inRangePercent: Double
    public var highPercent: Double
    public var veryHighPercent: Double
    public var readingCount: Int
    public var expectedReadingCount: Int
    public var coveragePercent: Double

    public init(
        veryLowPercent: Double,
        lowPercent: Double,
        inRangePercent: Double,
        highPercent: Double,
        veryHighPercent: Double,
        readingCount: Int,
        expectedReadingCount: Int,
        coveragePercent: Double
    ) {
        self.veryLowPercent = veryLowPercent
        self.lowPercent = lowPercent
        self.inRangePercent = inRangePercent
        self.highPercent = highPercent
        self.veryHighPercent = veryHighPercent
        self.readingCount = readingCount
        self.expectedReadingCount = expectedReadingCount
        self.coveragePercent = coveragePercent
    }
}

public enum TimeInRangeCalculator {
    /// Fixed clinical extremes, independent of the user's configurable target range.
    private static let veryLowThreshold = 54.0
    private static let veryHighThreshold = 250.0
    private static let dexcomSampleIntervalSeconds = 5.0 * 60.0

    /// Computes standard AGP-style banded time-in-range percentages over
    /// `interval`, plus a coverage figure so sparse data (sensor gaps,
    /// missed uploads) isn't presented with false confidence.
    ///
    /// Bands, using the caller-supplied target range:
    /// very low (<54), low (54 up to targetLow), in range (targetLow...targetHigh),
    /// high (above targetHigh up to 250), very high (>250).
    public static func compute(
        readings: [GlucoseReading],
        targetLow: Double = 70,
        targetHigh: Double = 180,
        over interval: DateInterval
    ) -> TIRResult {
        let inWindow = readings.filter { interval.contains($0.timestamp) }
        let readingCount = inWindow.count

        var veryLowCount = 0
        var lowCount = 0
        var inRangeCount = 0
        var highCount = 0
        var veryHighCount = 0

        for reading in inWindow {
            let value = reading.mgdl
            if value < veryLowThreshold {
                veryLowCount += 1
            } else if value < targetLow {
                lowCount += 1
            } else if value <= targetHigh {
                inRangeCount += 1
            } else if value <= veryHighThreshold {
                highCount += 1
            } else {
                veryHighCount += 1
            }
        }

        func percent(_ count: Int) -> Double {
            readingCount > 0 ? (Double(count) / Double(readingCount)) * 100 : 0
        }

        let expectedReadingCount = max(0, Int((interval.duration / dexcomSampleIntervalSeconds).rounded()))
        let coveragePercent = expectedReadingCount > 0
            ? (Double(readingCount) / Double(expectedReadingCount)) * 100
            : 0

        return TIRResult(
            veryLowPercent: percent(veryLowCount),
            lowPercent: percent(lowCount),
            inRangePercent: percent(inRangeCount),
            highPercent: percent(highCount),
            veryHighPercent: percent(veryHighCount),
            readingCount: readingCount,
            expectedReadingCount: expectedReadingCount,
            coveragePercent: coveragePercent
        )
    }
}
