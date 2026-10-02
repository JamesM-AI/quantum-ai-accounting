import Foundation
import GlucoseCore

/// Drives repeated polling of Dexcom Share for new readings while the app is
/// foregrounded (or during the brief window iOS grants a background task).
///
/// This is an `actor` rather than `@MainActor`: polling itself is pure
/// networking/decoding work with no UI dependency, and callers deliver
/// results via the `onNewReadings`/`onError` closures, which they can hop
/// back to the main actor from if they need to touch UI or a SwiftData
/// `ModelContext`. Keeping this off the main actor means a slow network call
/// never blocks UI work.
public actor DexcomPollingService {
    private let client: DexcomShareClient
    private let session: DexcomSession

    public init(client: DexcomShareClient = DexcomShareClient(), session: DexcomSession = DexcomSession()) {
        self.client = client
        self.session = session
    }

    /// Starts an unstructured polling loop and returns its `Task` so the
    /// caller can cancel it (e.g. when the app is backgrounded or the user
    /// disconnects their Dexcom account). The loop fetches immediately, then
    /// again every `intervalSeconds`.
    ///
    /// On `.sessionExpired`, the cached session is discarded and the fetch is
    /// retried exactly once with a fresh login before that cycle's error (if
    /// the retry also fails) is surfaced via `onError`; this keeps a single
    /// stale session from permanently wedging the poll loop while still
    /// avoiding a retry storm against Dexcom's servers.
    public func startPolling(
        credentials: DexcomCredentials,
        intervalSeconds: TimeInterval = 300,
        onNewReadings: @escaping ([GlucoseReading]) -> Void,
        onError: ((Error) -> Void)? = nil
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                await self.pollOnce(credentials: credentials, onNewReadings: onNewReadings, onError: onError)

                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }
    }

    private func pollOnce(
        credentials: DexcomCredentials,
        onNewReadings: @escaping ([GlucoseReading]) -> Void,
        onError: ((Error) -> Void)?
    ) async {
        do {
            let readings = try await fetchAndConvert(credentials: credentials)
            onNewReadings(readings)
        } catch DexcomShareError.sessionExpired {
            await session.invalidate()
            do {
                let readings = try await fetchAndConvert(credentials: credentials)
                onNewReadings(readings)
            } catch {
                onError?(error)
            }
        } catch {
            onError?(error)
        }
    }

    private func fetchAndConvert(credentials: DexcomCredentials) async throws -> [GlucoseReading] {
        let sessionId = try await session.validSessionId(credentials: credentials, client: client)
        let readings = try await client.fetchLatestReadings(sessionId: sessionId, region: credentials.region)
        return readings.map(client.toGlucoseReading)
    }

    // MARK: - Background refresh (app-target responsibility)
    //
    // TODO: This package cannot itself register a `BGAppRefreshTask` --
    // that requires an entry in the app target's Info.plist
    // (`BGTaskSchedulerPermittedIdentifiers`) and a submission/handler pair
    // wired up in the app's `AppDelegate`/`App` startup path, neither of
    // which a Swift Package can own. The intended integration is for the app
    // target to call `BGTaskScheduler.shared.register(forTaskWithIdentifier:)`
    // with a matching identifier and, inside that handler, run one
    // `pollOnce`-equivalent fetch (a single fetch, not `startPolling`'s
    // indefinite loop, since a background refresh task has only seconds
    // before iOS kills it). iOS decides if/when that task actually runs; this
    // service can only make the best-effort request for a background slot,
    // never guarantee polling cadence while backgrounded.
    public func registerBackgroundRefresh(taskIdentifier: String) {
        // Intentionally a no-op placeholder -- see TODO above.
    }
}
