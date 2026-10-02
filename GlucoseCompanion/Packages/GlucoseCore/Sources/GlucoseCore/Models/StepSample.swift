import Foundation
import SwiftData

/// A step-count sample synced from HealthKit. HealthKit reports steps as a
/// series of `HKQuantitySample`s over variable-length windows (not one
/// continuous stream), so each row here mirrors exactly one such sample --
/// `stepCount` is the count for `[startDate, endDate)`, not a running total.
/// Read-only, same as `WorkoutSession`: this app never writes step data.
@Model
public final class StepSample {
    @Attribute(.unique) public var id: UUID
    public var startDate: Date
    public var endDate: Date
    public var stepCount: Int
    public var source: EntrySource
    public var healthKitUUID: UUID?

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        stepCount: Int,
        source: EntrySource = .healthKit,
        healthKitUUID: UUID? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.stepCount = stepCount
        self.source = source
        self.healthKitUUID = healthKitUUID
    }
}
