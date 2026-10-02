import Foundation
import SwiftData

/// A workout synced from HealthKit (Apple Health / Apple Watch / any app that
/// writes `HKWorkout` samples). Read-only from this app's perspective -- it
/// never creates workouts, only mirrors what Health already has, so every
/// row's `source` is `.healthKit` and `healthKitUUID` is always set.
@Model
public final class WorkoutSession {
    @Attribute(.unique) public var id: UUID
    public var startDate: Date
    public var endDate: Date
    /// Human-readable label derived from `HKWorkoutActivityType` (e.g.
    /// "Walking", "Running", "Cycling") -- kept as a plain string here so
    /// this package has no HealthKit dependency; the mapping lives in
    /// HealthKitSync.
    public var activityType: String
    public var totalEnergyBurnedKcal: Double?
    public var totalDistanceMeters: Double?
    public var source: EntrySource
    public var healthKitUUID: UUID?

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        activityType: String,
        totalEnergyBurnedKcal: Double? = nil,
        totalDistanceMeters: Double? = nil,
        source: EntrySource = .healthKit,
        healthKitUUID: UUID? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activityType = activityType
        self.totalEnergyBurnedKcal = totalEnergyBurnedKcal
        self.totalDistanceMeters = totalDistanceMeters
        self.source = source
        self.healthKitUUID = healthKitUUID
    }

    public var interval: DateInterval {
        DateInterval(start: startDate, end: max(startDate, endDate))
    }
}
