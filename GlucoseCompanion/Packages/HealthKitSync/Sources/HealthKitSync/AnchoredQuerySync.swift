import Foundation
import HealthKit
import SwiftData
import GlucoseCore

/// Seam for persisting `HKQueryAnchor` bookkeeping. Anchors are opaque and
/// not sensitive, so the app layer is free to back this with UserDefaults,
/// SwiftData, or anything else -- this package doesn't assume which.
public protocol AnchorStore {
    func anchorData(for key: String) -> Data?
    func setAnchorData(_ data: Data?, for key: String)
}

/// Convenience default backed by `UserDefaults`.
public final class UserDefaultsAnchorStore: AnchorStore {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "HealthKitSync.anchor.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func anchorData(for key: String) -> Data? {
        defaults.data(forKey: keyPrefix + key)
    }

    public func setAnchorData(_ data: Data?, for key: String) {
        defaults.set(data, forKey: keyPrefix + key)
    }
}

/// Syncs the GlucoseCore-backed Health categories (glucose, carbs, insulin,
/// workouts, steps) via `HKAnchoredObjectQuery`, deduping against records that
/// already exist locally -- whether they arrived from a previous HealthKit
/// sync or were logged directly in-app and already carry a `healthKitUUID`
/// from having been written back to Health.
///
/// Not an actor: callers are expected to invoke this against a `ModelContext`
/// they already own the isolation of (typically the app's main context).
/// Pinned to the main actor deliberately: every method here touches a
/// SwiftData `ModelContext`, which (like Core Data's `NSManagedObjectContext`)
/// is not safe to use from an arbitrary thread. `BackgroundDeliveryManager`
/// invokes this from an `HKObserverQuery` completion handler, which HealthKit
/// calls back on an unspecified (often background/concurrent) queue -- without
/// this isolation, that path crashes (SIGABRT) the first time it races the
/// main thread's own use of the same context. Marking the type `@MainActor`
/// makes every `await` call into it hop to the main actor automatically,
/// regardless of what thread the caller happens to be running on.
@MainActor
public final class AnchoredQuerySync {
    public init() {}

    private enum AnchorKey {
        static let glucose = "glucose"
        static let carbs = "carbs"
        static let insulin = "insulin"
        static let workouts = "workouts"
        static let steps = "steps"
    }

    /// `BackgroundDeliveryManager` registers one `HKObserverQuery` per
    /// observed type (glucose, carbs, insulin, workouts, heart rate, steps),
    /// and each independently triggers a full `runIncrementalSync` call.
    /// Being `@MainActor` prevents two calls from literally running at the
    /// same instant, but it does NOT prevent them from *interleaving* at
    /// `await` suspension points -- a second call can still read the "before"
    /// state, suspend, and resume after a first call already changed that
    /// same state, corrupting SwiftData's internal object registration. This
    /// flag makes overlapping sync requests coalesce (skip) instead of
    /// interleave: safe because a skipped request's changes will simply be
    /// picked up the next time any observer fires.
    private var isSyncing = false

    /// Bounded first-run sync covering the last `sinceDays` days. Intended to
    /// be called once, right after authorization is granted.
    public func runInitialSync(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore,
        sinceDays: Int = 90
    ) async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let startDate = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        try await syncGlucose(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: predicate)
        try await syncCarbs(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: predicate)
        try await syncInsulin(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: predicate)
        try await syncWorkouts(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: predicate)
        try await syncSteps(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: predicate)
    }

    /// Fetches only what changed since the anchor each category persisted
    /// last time. If no anchor exists yet (i.e. `runInitialSync` was never
    /// called) this behaves like an unbounded full sync, since an anchored
    /// query with a nil anchor and nil predicate returns everything.
    public func runIncrementalSync(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore
    ) async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        try await syncGlucose(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: nil)
        try await syncCarbs(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: nil)
        try await syncInsulin(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: nil)
        try await syncWorkouts(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: nil)
        try await syncSteps(healthStore: healthStore, context: context, anchorStore: anchorStore, predicate: nil)
    }

    // MARK: - Per-category sync

    private func syncGlucose(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore,
        predicate: NSPredicate?
    ) async throws {
        let key = AnchorKey.glucose
        let anchor = Self.loadAnchor(anchorStore: anchorStore, key: key)
        let result = try await Self.runAnchoredQuery(
            healthStore: healthStore,
            sampleType: HealthStoreManager.glucoseType,
            anchor: anchor,
            predicate: predicate
        )

        var existingUUIDs = try Self.existingHealthKitUUIDs(GlucoseReading.self, in: context)
        for case let sample as HKQuantitySample in result.samples where !existingUUIDs.contains(sample.uuid) {
            context.insert(Self.glucoseReading(from: sample))
            existingUUIDs.insert(sample.uuid)
        }
        Self.deleteRecords(GlucoseReading.self, matchingHealthKitUUIDs: result.deletedUUIDs, in: context)

        try context.save()
        Self.saveAnchor(result.newAnchor, anchorStore: anchorStore, key: key)
    }

    private func syncCarbs(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore,
        predicate: NSPredicate?
    ) async throws {
        let key = AnchorKey.carbs
        let anchor = Self.loadAnchor(anchorStore: anchorStore, key: key)
        let result = try await Self.runAnchoredQuery(
            healthStore: healthStore,
            sampleType: HealthStoreManager.carbType,
            anchor: anchor,
            predicate: predicate
        )

        var existingUUIDs = try Self.existingHealthKitUUIDs(CarbEntry.self, in: context)
        for case let sample as HKQuantitySample in result.samples where !existingUUIDs.contains(sample.uuid) {
            context.insert(Self.carbEntry(from: sample))
            existingUUIDs.insert(sample.uuid)
        }
        Self.deleteRecords(CarbEntry.self, matchingHealthKitUUIDs: result.deletedUUIDs, in: context)

        try context.save()
        Self.saveAnchor(result.newAnchor, anchorStore: anchorStore, key: key)
    }

    private func syncInsulin(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore,
        predicate: NSPredicate?
    ) async throws {
        let key = AnchorKey.insulin
        let anchor = Self.loadAnchor(anchorStore: anchorStore, key: key)
        let result = try await Self.runAnchoredQuery(
            healthStore: healthStore,
            sampleType: HealthStoreManager.insulinType,
            anchor: anchor,
            predicate: predicate
        )

        var existingUUIDs = try Self.existingHealthKitUUIDs(InsulinDose.self, in: context)
        for case let sample as HKQuantitySample in result.samples where !existingUUIDs.contains(sample.uuid) {
            context.insert(Self.insulinDose(from: sample))
            existingUUIDs.insert(sample.uuid)
        }
        Self.deleteRecords(InsulinDose.self, matchingHealthKitUUIDs: result.deletedUUIDs, in: context)

        try context.save()
        Self.saveAnchor(result.newAnchor, anchorStore: anchorStore, key: key)
    }

    private func syncWorkouts(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore,
        predicate: NSPredicate?
    ) async throws {
        let key = AnchorKey.workouts
        let anchor = Self.loadAnchor(anchorStore: anchorStore, key: key)
        let result = try await Self.runAnchoredQuery(
            healthStore: healthStore,
            sampleType: HealthStoreManager.workoutType,
            anchor: anchor,
            predicate: predicate
        )

        var existingUUIDs = try Self.existingHealthKitUUIDs(WorkoutSession.self, in: context)
        for case let sample as HKWorkout in result.samples where !existingUUIDs.contains(sample.uuid) {
            context.insert(Self.workoutSession(from: sample))
            existingUUIDs.insert(sample.uuid)
        }
        Self.deleteRecords(WorkoutSession.self, matchingHealthKitUUIDs: result.deletedUUIDs, in: context)

        try context.save()
        Self.saveAnchor(result.newAnchor, anchorStore: anchorStore, key: key)
    }

    private func syncSteps(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore,
        predicate: NSPredicate?
    ) async throws {
        let key = AnchorKey.steps
        let anchor = Self.loadAnchor(anchorStore: anchorStore, key: key)
        let result = try await Self.runAnchoredQuery(
            healthStore: healthStore,
            sampleType: HealthStoreManager.stepCountType,
            anchor: anchor,
            predicate: predicate
        )

        var existingUUIDs = try Self.existingHealthKitUUIDs(StepSample.self, in: context)
        for case let sample as HKQuantitySample in result.samples where !existingUUIDs.contains(sample.uuid) {
            context.insert(Self.stepSample(from: sample))
            existingUUIDs.insert(sample.uuid)
        }
        Self.deleteRecords(StepSample.self, matchingHealthKitUUIDs: result.deletedUUIDs, in: context)

        try context.save()
        Self.saveAnchor(result.newAnchor, anchorStore: anchorStore, key: key)
    }

    // MARK: - Anchored query plumbing

    private struct AnchoredQueryResult {
        let samples: [HKSample]
        let deletedUUIDs: Set<UUID>
        let newAnchor: HKQueryAnchor?
    }

    private static func runAnchoredQuery(
        healthStore: HKHealthStore,
        sampleType: HKSampleType,
        anchor: HKQueryAnchor?,
        predicate: NSPredicate?
    ) async throws -> AnchoredQueryResult {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samplesOrNil, deletedOrNil, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: AnchoredQueryResult(
                    samples: samplesOrNil ?? [],
                    deletedUUIDs: Set((deletedOrNil ?? []).map(\.uuid)),
                    newAnchor: newAnchor
                ))
            }
            healthStore.execute(query)
        }
    }

    private static func loadAnchor(anchorStore: AnchorStore, key: String) -> HKQueryAnchor? {
        guard let data = anchorStore.anchorData(for: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func saveAnchor(_ anchor: HKQueryAnchor?, anchorStore: AnchorStore, key: String) {
        guard let anchor else { return }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        anchorStore.setAnchorData(data, for: key)
    }

    // MARK: - HealthKit sample -> GlucoseCore model

    private static func glucoseReading(from sample: HKQuantitySample) -> GlucoseReading {
        GlucoseReading(
            timestamp: sample.startDate,
            mgdl: sample.quantity.doubleValue(for: HealthStoreManager.glucoseUnit),
            // Glucose samples written to Health by third-party CGM apps don't
            // reliably carry a trend-arrow metadata key, so we leave this nil
            // here; this app's own live trend comes from the Dexcom Share
            // sync path instead, not from HealthKit.
            trend: nil,
            source: .healthKit,
            healthKitUUID: sample.uuid
        )
    }

    private static func carbEntry(from sample: HKQuantitySample) -> CarbEntry {
        CarbEntry(
            timestamp: sample.startDate,
            grams: sample.quantity.doubleValue(for: HealthStoreManager.carbUnit),
            source: .healthKit,
            healthKitUUID: sample.uuid
        )
    }

    private static func insulinDose(from sample: HKQuantitySample) -> InsulinDose {
        InsulinDose(
            timestamp: sample.startDate,
            units: sample.quantity.doubleValue(for: HealthStoreManager.insulinUnit),
            reason: insulinDeliveryReason(from: sample),
            source: .healthKit,
            healthKitUUID: sample.uuid
        )
    }

    private static func insulinDeliveryReason(from sample: HKQuantitySample) -> InsulinDeliveryReason {
        guard
            let rawReason = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? NSNumber,
            let hkReason = HKInsulinDeliveryReason(rawValue: rawReason.intValue)
        else {
            // TODO: revisit -- defaulting missing/unrecognized delivery-reason
            // metadata to `.bolus` is a convenience guess so we never silently
            // drop a dose, not a claim that untagged doses are actually boluses.
            return .bolus
        }
        switch hkReason {
        case .basal: return .basal
        case .bolus: return .bolus
        @unknown default: return .bolus
        }
    }

    private static func workoutSession(from workout: HKWorkout) -> WorkoutSession {
        // TODO: Apple's newer API is `workout.statistics(for:)`, which reports
        // per-quantity-type totals and supersedes these convenience
        // properties -- worth migrating to eventually, but `totalEnergyBurned`
        // / `totalDistance` are still present and functional today.
        let energyKcal = workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie())
        let distanceMeters = workout.totalDistance?.doubleValue(for: HKUnit.meter())
        return WorkoutSession(
            startDate: workout.startDate,
            endDate: workout.endDate,
            activityType: activityTypeLabel(for: workout.workoutActivityType),
            totalEnergyBurnedKcal: energyKcal,
            totalDistanceMeters: distanceMeters,
            source: .healthKit,
            healthKitUUID: workout.uuid
        )
    }

    /// Human-readable label for the common activity types this app is
    /// confident about; HealthKit has ~80 `HKWorkoutActivityType` cases in
    /// total, so everything else falls back to a generic "Workout" label
    /// rather than guessing at an exhaustive mapping.
    private static func activityTypeLabel(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .walking: return "Walking"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Strength Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .highIntensityIntervalTraining: return "HIIT"
        case .other: return "Workout"
        default: return "Workout"
        }
    }

    private static func stepSample(from sample: HKQuantitySample) -> StepSample {
        StepSample(
            startDate: sample.startDate,
            endDate: sample.endDate,
            stepCount: Int(sample.quantity.doubleValue(for: HKUnit.count()).rounded()),
            source: .healthKit,
            healthKitUUID: sample.uuid
        )
    }

    // MARK: - Dedup / delete helpers

    // Deliberately no `#Predicate` filtering on `healthKitUUID != nil` here --
    // comparing an optional UUID to `nil` inside `#Predicate` is a known
    // SwiftData crash (SIGABRT) on some OS versions. Fetching everything and
    // filtering with plain `compactMap`/`if let` in Swift is slightly less
    // efficient but unconditionally safe, and these tables are small enough
    // (a personal health app's own history) for that not to matter.

    private static func existingHealthKitUUIDs(_ type: GlucoseReading.Type, in context: ModelContext) throws -> Set<UUID> {
        let descriptor = FetchDescriptor<GlucoseReading>()
        return Set(try context.fetch(descriptor).compactMap(\.healthKitUUID))
    }

    private static func existingHealthKitUUIDs(_ type: CarbEntry.Type, in context: ModelContext) throws -> Set<UUID> {
        let descriptor = FetchDescriptor<CarbEntry>()
        return Set(try context.fetch(descriptor).compactMap(\.healthKitUUID))
    }

    private static func existingHealthKitUUIDs(_ type: InsulinDose.Type, in context: ModelContext) throws -> Set<UUID> {
        let descriptor = FetchDescriptor<InsulinDose>()
        return Set(try context.fetch(descriptor).compactMap(\.healthKitUUID))
    }

    private static func existingHealthKitUUIDs(_ type: WorkoutSession.Type, in context: ModelContext) throws -> Set<UUID> {
        let descriptor = FetchDescriptor<WorkoutSession>()
        return Set(try context.fetch(descriptor).compactMap(\.healthKitUUID))
    }

    private static func existingHealthKitUUIDs(_ type: StepSample.Type, in context: ModelContext) throws -> Set<UUID> {
        let descriptor = FetchDescriptor<StepSample>()
        return Set(try context.fetch(descriptor).compactMap(\.healthKitUUID))
    }

    private static func deleteRecords(
        _ type: GlucoseReading.Type,
        matchingHealthKitUUIDs uuids: Set<UUID>,
        in context: ModelContext
    ) {
        guard !uuids.isEmpty else { return }
        let descriptor = FetchDescriptor<GlucoseReading>()
        guard let candidates = try? context.fetch(descriptor) else { return }
        for record in candidates {
            if let uuid = record.healthKitUUID, uuids.contains(uuid) {
                context.delete(record)
            }
        }
    }

    private static func deleteRecords(
        _ type: CarbEntry.Type,
        matchingHealthKitUUIDs uuids: Set<UUID>,
        in context: ModelContext
    ) {
        guard !uuids.isEmpty else { return }
        let descriptor = FetchDescriptor<CarbEntry>()
        guard let candidates = try? context.fetch(descriptor) else { return }
        for record in candidates {
            if let uuid = record.healthKitUUID, uuids.contains(uuid) {
                context.delete(record)
            }
        }
    }

    private static func deleteRecords(
        _ type: InsulinDose.Type,
        matchingHealthKitUUIDs uuids: Set<UUID>,
        in context: ModelContext
    ) {
        guard !uuids.isEmpty else { return }
        let descriptor = FetchDescriptor<InsulinDose>()
        guard let candidates = try? context.fetch(descriptor) else { return }
        for record in candidates {
            if let uuid = record.healthKitUUID, uuids.contains(uuid) {
                context.delete(record)
            }
        }
    }

    private static func deleteRecords(
        _ type: WorkoutSession.Type,
        matchingHealthKitUUIDs uuids: Set<UUID>,
        in context: ModelContext
    ) {
        guard !uuids.isEmpty else { return }
        let descriptor = FetchDescriptor<WorkoutSession>()
        guard let candidates = try? context.fetch(descriptor) else { return }
        for record in candidates {
            if let uuid = record.healthKitUUID, uuids.contains(uuid) {
                context.delete(record)
            }
        }
    }

    private static func deleteRecords(
        _ type: StepSample.Type,
        matchingHealthKitUUIDs uuids: Set<UUID>,
        in context: ModelContext
    ) {
        guard !uuids.isEmpty else { return }
        let descriptor = FetchDescriptor<StepSample>()
        guard let candidates = try? context.fetch(descriptor) else { return }
        for record in candidates {
            if let uuid = record.healthKitUUID, uuids.contains(uuid) {
                context.delete(record)
            }
        }
    }
}
