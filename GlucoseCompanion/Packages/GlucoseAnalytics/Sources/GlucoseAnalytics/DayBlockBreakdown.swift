import Foundation
import GlucoseCore

/// Glycemic variability and time-in-range stats for a single day-block
/// (e.g. Breakfast, Lunch, Dinner, Overnight), over some analysis window.
public struct DayBlockStats: Sendable, Equatable {
    public var blockName: String
    public var averageMgdl: Double
    public var standardDeviation: Double
    public var coefficientOfVariationPercent: Double
    public var tir: TIRResult

    public init(
        blockName: String,
        averageMgdl: Double,
        standardDeviation: Double,
        coefficientOfVariationPercent: Double,
        tir: TIRResult
    ) {
        self.blockName = blockName
        self.averageMgdl = averageMgdl
        self.standardDeviation = standardDeviation
        self.coefficientOfVariationPercent = coefficientOfVariationPercent
        self.tir = tir
    }
}

public enum DayBlockBreakdown {
    /// Computes per-block glucose stats by filtering `readings` to each
    /// block's local-hour boundaries (via `TimeOfDayProfile.contains(hour:)`)
    /// and to `interval`, then reusing `TimeInRangeCalculator` for the banded
    /// percentages.
    ///
    /// Caveat on coverage: `TimeInRangeCalculator.compute`'s `expectedReadingCount`
    /// assumes continuous 5-minute-cadence coverage across the *entire* interval
    /// passed to it, which is correct for a full-day analysis but not for a
    /// block that only spans part of each day. Here we recompute the expected
    /// count scaled by the block's own hour-span (block hours / 24, times the
    /// number of days in `interval`) so `coveragePercent` reflects "how much of
    /// this block's own time was sampled," not "how much of the full interval."
    /// This is still an approximation at the edges of `interval` (a block that
    /// only partially overlaps the first/last day is not fractionally trimmed).
    public static func breakdown(
        readings: [GlucoseReading],
        blocks: [TimeOfDayProfile],
        targetLow: Double = 70,
        targetHigh: Double = 180,
        over interval: DateInterval
    ) -> [DayBlockStats] {
        let calendar = Calendar.current
        let inWindow = readings.filter { interval.contains($0.timestamp) }

        return blocks.map { block in
            let blockReadings = inWindow.filter { reading in
                let hour = calendar.component(.hour, from: reading.timestamp)
                return block.contains(hour: hour)
            }

            let values = blockReadings.map(\.mgdl)
            let average = mean(values)
            let stdDev = sampleStandardDeviation(values, mean: average)
            let cv = average > 0 ? (stdDev / average) * 100 : 0

            var tir = TimeInRangeCalculator.compute(
                readings: blockReadings,
                targetLow: targetLow,
                targetHigh: targetHigh,
                over: interval
            )
            tir.expectedReadingCount = expectedReadingCount(for: block, over: interval)
            tir.coveragePercent = tir.expectedReadingCount > 0
                ? (Double(tir.readingCount) / Double(tir.expectedReadingCount)) * 100
                : 0

            return DayBlockStats(
                blockName: block.blockName,
                averageMgdl: average,
                standardDeviation: stdDev,
                coefficientOfVariationPercent: cv,
                tir: tir
            )
        }
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func sampleStandardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sumOfSquaredDeviations = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let variance = sumOfSquaredDeviations / Double(values.count - 1)
        return variance.squareRoot()
    }

    private static func hourSpan(of block: TimeOfDayProfile) -> Int {
        if block.startHour <= block.endHour {
            return block.endHour - block.startHour
        } else {
            return (24 - block.startHour) + block.endHour
        }
    }

    private static func expectedReadingCount(for block: TimeOfDayProfile, over interval: DateInterval) -> Int {
        let dayCount = interval.duration / (24 * 60 * 60)
        let blockHours = Double(hourSpan(of: block))
        let expected = dayCount * blockHours * (60.0 / 5.0)
        return max(0, Int(expected.rounded()))
    }
}
