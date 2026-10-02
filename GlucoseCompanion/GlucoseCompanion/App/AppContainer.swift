import Foundation
import SwiftData
import HealthKitSync
import DexcomShareClient
import GlucoseCore

/// Composition root for every non-SwiftData service the app needs: HealthKit
/// access/sync, and the Dexcom Share backup path. Handed into the view tree
/// once via `.environment(_:)`. SwiftData access itself goes through the
/// standard `@Environment(\.modelContext)` / `@Query` mechanisms in each
/// view -- this container deliberately does not duplicate that.
@Observable
@MainActor
final class AppContainer {
    let healthStore = HealthStoreManager()
    let anchoredSync = AnchoredQuerySync()
    let backgroundDelivery = BackgroundDeliveryManager()
    let anchorStore = UserDefaultsAnchorStore()

    let dexcomKeychain = KeychainCredentialStore()
    let dexcomClient = DexcomShareClient()
    let dexcomPollingService = DexcomPollingService()

    var healthKitShareAuthorization: AuthorizationSummary?
    var isDexcomConnected: Bool = false
    var dexcomLastError: String?

    private var dexcomPollingTask: Task<Void, Never>?

    init() {
        isDexcomConnected = dexcomKeychain.load() != nil
    }

    // MARK: - HealthKit

    func requestHealthKitAuthorization() async throws {
        try await healthStore.requestAuthorization()
        healthKitShareAuthorization = HealthKitAuthorization.shareAuthorizationSummary(store: healthStore)
    }

    /// Call once, right after authorization is granted (typically at the end
    /// of onboarding). Bounded to the last 90 days by default.
    func runInitialHealthKitSync(context: ModelContext) async throws {
        try await anchoredSync.runInitialSync(
            healthStore: healthStore.healthStore,
            context: context,
            anchorStore: anchorStore
        )
    }

    /// Call once at every app launch (including the first) so incremental
    /// syncs keep running while backgrounded.
    func startBackgroundDelivery(context: ModelContext) async throws {
        try await backgroundDelivery.start(
            healthStore: healthStore.healthStore,
            context: context,
            anchorStore: anchorStore
        )
    }

    // MARK: - Dexcom Share (backup path)

    func connectDexcom(credentials: DexcomCredentials, context: ModelContext) {
        do {
            try dexcomKeychain.save(credentials)
        } catch {
            dexcomLastError = "Couldn't save Dexcom credentials: \(error.localizedDescription)"
            return
        }
        isDexcomConnected = true
        dexcomLastError = nil
        startDexcomPolling(credentials: credentials, context: context)
    }

    func disconnectDexcom() {
        dexcomPollingTask?.cancel()
        dexcomPollingTask = nil
        try? dexcomKeychain.clear()
        isDexcomConnected = false
    }

    /// Resumes polling using a previously-saved credential; call at launch
    /// if `isDexcomConnected` is already true.
    func resumeDexcomPollingIfConnected(context: ModelContext) {
        guard let credentials = dexcomKeychain.load() else {
            isDexcomConnected = false
            return
        }
        startDexcomPolling(credentials: credentials, context: context)
    }

    private func startDexcomPolling(credentials: DexcomCredentials, context: ModelContext) {
        dexcomPollingTask?.cancel()
        dexcomPollingTask = Task {
            await dexcomPollingService.startPolling(
                credentials: credentials,
                onNewReadings: { [weak self] readings in
                    Task { @MainActor in
                        self?.mergeDexcomReadings(readings, context: context)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.dexcomLastError = error.localizedDescription
                    }
                }
            )
        }
    }

    /// Dedups new Dexcom Share readings against existing readings (from
    /// either source) by timestamp proximity + value, per the reconciliation
    /// rule: HealthKit is canonical, Dexcom Share only fills gaps.
    private func mergeDexcomReadings(_ readings: [GlucoseReading], context: ModelContext) {
        guard !readings.isEmpty else { return }

        let existing = (try? context.fetch(FetchDescriptor<GlucoseReading>())) ?? []

        for reading in readings {
            let isDuplicate = existing.contains { candidate in
                abs(candidate.timestamp.timeIntervalSince(reading.timestamp)) <= 60
                    && abs(candidate.mgdl - reading.mgdl) < 1
            }
            guard !isDuplicate else { continue }
            context.insert(reading)
        }
        try? context.save()
    }
}
