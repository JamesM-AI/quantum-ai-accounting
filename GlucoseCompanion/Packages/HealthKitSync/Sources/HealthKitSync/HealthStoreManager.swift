import Foundation
import HealthKit

/// Thin wrapper around `HKHealthStore` that centralizes the set of types this
/// app cares about and the units it stores them in. Nothing here touches
/// SwiftData -- that's `AnchoredQuerySync`'s job.
public final class HealthStoreManager {
    public static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public let healthStore = HKHealthStore()

    public init() {}

    // MARK: - Types

    public static let glucoseType = HKQuantityType(.bloodGlucose)
    public static let carbType = HKQuantityType(.dietaryCarbohydrates)
    public static let insulinType = HKQuantityType(.insulinDelivery)
    public static let workoutType = HKObjectType.workoutType()
    public static let heartRateType = HKQuantityType(.heartRate)
    public static let stepCountType = HKQuantityType(.stepCount)

    /// Everything this app reads from Health, spanning both the entries that
    /// map directly onto GlucoseCore models (glucose/carbs/insulin) and the
    /// contextual signals used elsewhere (workouts, heart rate, steps).
    public static var readTypes: Set<HKObjectType> {
        [glucoseType, carbType, insulinType, workoutType, heartRateType, stepCountType]
    }

    /// Only the entries the app itself can produce (manual carb/insulin log
    /// entries) get written back to Health, so Health stays the durable,
    /// cross-app source of truth for them. Glucose always comes from a CGM,
    /// never written by this app.
    public static var shareTypes: Set<HKSampleType> {
        [carbType, insulinType]
    }

    // MARK: - Units

    public static let glucoseUnit = HKUnit(from: "mg/dL")
    public static let carbUnit = HKUnit.gram()
    public static let insulinUnit = HKUnit.internationalUnit()

    // MARK: - Authorization

    public func requestAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }
}
