import Foundation
import GlucoseCore

/// One fixed time-of-day slot's distribution across every day in the
/// aggregation window (e.g. all "08:00-08:15" readings from the last 14 days
/// collapsed together, regardless of calendar date).
public struct AGPSlot: Sendable, Equatable {
    /// Minutes since local midnight at the start of this slot (e.g. 480 = 08:00).
    public var minuteOfDay: Int
    public var median: Double?
    public var p10: Double?
    public var p25: Double?
    public var p75: Double?
    public var p90: Double?

    public init(
        minuteOfDay: Int,
        median: Double?,
        p10: Double?,
        p25: Double?,
        p75: Double?,
        p90: Double?
    ) {
        self.minuteOfDay = minuteOfDay
        self.median = median
        self.p10 = p10
        self.p25 = p25
        self.p75 = p75
        self.p90 = p90
    }
}

public struct AGPProfile: Sendable, Equatable {
    public var slots: [AGPSlot]
    public var windowDays: Int
    public var generatedAt: Date

    public init(slots: [AGPSlot], windowDays: Int, generatedAt: Date) {
        self.slots = slots
        self.windowDays = windowDays
        self.generatedAt = generatedAt
    }
}

public enum AGPAggregator {
    private static let minutesPerDay = 24 * 60

    /// Buckets `readings` from the trailing `windowDays`-day window into
    /// fixed-width time-of-day slots (by local wall-clock time, independent
    /// of calendar date) and computes each slot's median and 10th/25th/75th/90th
    /// percentiles.
    public static func aggregate(
        readings: [GlucoseReading],
        windowDays: Int,
        slotMinutes: Int = 15,
        now: Date = Date()
    ) -> AGPProfile {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let inWindow = readings.filter { $0.timestamp >= windowStart && $0.timestamp <= now }

        let slotCount = (minutesPerDay + slotMinutes - 1) / slotMinutes
        var bucketed = [[Double]](repeating: [], count: slotCount)

        for reading in inWindow {
            let components = calendar.dateComponents([.hour, .minute], from: reading.timestamp)
            guard let hour = components.hour, let minute = components.minute else { continue }
            let minuteOfDay = hour * 60 + minute
            let slotIndex = min(minuteOfDay / slotMinutes, slotCount - 1)
            bucketed[slotIndex].append(reading.mgdl)
        }

        let slots = (0..<slotCount).map { index -> AGPSlot in
            let values = bucketed[index].sorted()
            return AGPSlot(
                minuteOfDay: index * slotMinutes,
                median: percentile(values, 50),
                p10: percentile(values, 10),
                p25: percentile(values, 25),
                p75: percentile(values, 75),
                p90: percentile(values, 90)
            )
        }

        return AGPProfile(slots: slots, windowDays: windowDays, generatedAt: now)
    }

    /// Linear-interpolation percentile over an already-sorted array (the
    /// common "linear" method: interpolates between the two closest ranks).
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        guard sorted.count > 1 else { return sorted[0] }

        let rank = (p / 100) * Double(sorted.count - 1)
        let lowerIndex = Int(rank.rounded(.down))
        let upperIndex = Int(rank.rounded(.up))
        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }
        let fraction = rank - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * fraction
    }
}
