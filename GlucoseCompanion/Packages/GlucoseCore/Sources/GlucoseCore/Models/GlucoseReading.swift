import Foundation
import SwiftData

@Model
public final class GlucoseReading {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    /// Canonical storage unit is mg/dL regardless of display preference.
    public var mgdl: Double
    public var trend: GlucoseTrend?
    public var source: EntrySource
    /// Set when this reading was created from (or matched to) an HKObject,
    /// used as the dedup key against HealthKit re-observation.
    public var healthKitUUID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        mgdl: Double,
        trend: GlucoseTrend? = nil,
        source: EntrySource,
        healthKitUUID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mgdl = mgdl
        self.trend = trend
        self.source = source
        self.healthKitUUID = healthKitUUID
    }
}
