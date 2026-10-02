import Foundation
import GlucoseCore

/// Caches the current Dexcom Share session ID and serializes login attempts.
///
/// Dexcom Share sessions are opaque -- there's no documented expiry duration
/// returned alongside the sessionId, so this tracks an estimated expiry and
/// otherwise relies on the caller reacting to `DexcomShareError.sessionExpired`
/// from a poll to invalidate the cache early. Being an actor means two
/// concurrent callers (e.g. an overlapping background poll and a
/// user-triggered manual refresh) that both find the cache stale will not
/// both fire redundant login requests -- the second caller's `validSessionId`
/// call awaits the first's in-flight login and reuses its result.
public actor DexcomSession {
    /// Community reporting suggests Dexcom Share sessions commonly last on
    /// the order of hours, but since this isn't documented, this value is
    /// deliberately conservative and secondary to reacting to
    /// `.sessionExpired` from an actual request.
    public static let assumedLifetime: TimeInterval = 60 * 60

    private var cachedSessionId: String?
    private var expiresAt: Date?
    private var inFlightLogin: Task<String, Error>?

    public init() {}

    /// Returns a session ID guaranteed (as best this client can tell) to
    /// still be valid, performing a fresh two-step login if the cache is
    /// empty, expired, or was invalidated by `invalidate()`.
    public func validSessionId(credentials: DexcomCredentials, client: DexcomShareClient) async throws -> String {
        if let sessionId = cachedSessionId, let expiresAt, expiresAt > Date() {
            return sessionId
        }

        if let inFlightLogin {
            return try await inFlightLogin.value
        }

        let loginTask = Task { () throws -> String in
            try await client.authenticateAndLogin(credentials: credentials)
        }
        inFlightLogin = loginTask

        defer { inFlightLogin = nil }

        let sessionId = try await loginTask.value
        cachedSessionId = sessionId
        expiresAt = Date().addingTimeInterval(Self.assumedLifetime)
        return sessionId
    }

    /// Discards the cached session, forcing the next `validSessionId` call
    /// to log in again. Call this after receiving `.sessionExpired` from a
    /// poll so the retry doesn't reuse the same dead session ID.
    public func invalidate() {
        cachedSessionId = nil
        expiresAt = nil
    }
}
