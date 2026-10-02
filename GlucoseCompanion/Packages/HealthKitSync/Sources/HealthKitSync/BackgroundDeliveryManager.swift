import Foundation
import HealthKit
import SwiftData

/// Registers `HKObserverQuery`s and enables background delivery so
/// incremental syncs keep running while the app isn't in the foreground.
/// Call `start` once, at app launch, after HealthKit authorization has
/// already been requested.
///
/// `@MainActor` because it owns an `AnchoredQuerySync` (itself `@MainActor`,
/// since it touches a SwiftData `ModelContext`) -- without this, even just
/// constructing `AnchoredQuerySync()` as a stored property default is a
/// compile error ("main actor-isolated initializer in a synchronous
/// nonisolated context"), since this type's own `init` would otherwise be
/// nonisolated.
@MainActor
public final class BackgroundDeliveryManager {
    private let sync = AnchoredQuerySync()

    /// Observer queries must be kept alive for as long as we want updates;
    /// dropping the last strong reference lets ARC tear them down.
    private var observerQueries: [HKObserverQuery] = []

    public init() {}

    public func start(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore
    ) async throws {
        try await enableBackgroundDelivery(healthStore: healthStore)
        registerObservers(healthStore: healthStore, context: context, anchorStore: anchorStore)
    }

    private func enableBackgroundDelivery(healthStore: HKHealthStore) async throws {
        let immediateTypes: [HKSampleType] = [
            HealthStoreManager.glucoseType,
            HealthStoreManager.insulinType
        ]
        let hourlyTypes: [HKSampleType] = [
            HealthStoreManager.carbType,
            HealthStoreManager.workoutType,
            HealthStoreManager.heartRateType,
            HealthStoreManager.stepCountType
        ]

        for type in immediateTypes {
            try await healthStore.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
        for type in hourlyTypes {
            try await healthStore.enableBackgroundDelivery(for: type, frequency: .hourly)
        }
    }

    private func registerObservers(
        healthStore: HKHealthStore,
        context: ModelContext,
        anchorStore: AnchorStore
    ) {
        let observedTypes = HealthStoreManager.readTypes.compactMap { $0 as? HKSampleType }

        for type in observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [sync] _, completionHandler, error in
                Task {
                    // HealthKit stops delivering further updates for this
                    // type until `completionHandler` is called -- always
                    // call it, on every path, even if the sync below throws.
                    defer { completionHandler() }
                    guard error == nil else { return }
                    try? await sync.runIncrementalSync(
                        healthStore: healthStore,
                        context: context,
                        anchorStore: anchorStore
                    )
                }
            }
            healthStore.execute(query)
            observerQueries.append(query)
        }
    }
}
