import Foundation
import GlucoseCore

/// A single glucose reading as returned by
/// `ReadPublisherLatestGlucoseValues`, before conversion to GlucoseCore's
/// `GlucoseReading`.
///
/// Dexcom's payload carries three timestamps that can legitimately differ:
/// - `wallTime` (`WT`): the receiver/phone's wall clock at the time of the
///   reading, which drifts if the device's clock has been changed.
/// - `systemTime` (`ST`): the sensor/transmitter's internal monotonic clock,
///   not tied to wall-clock time at all.
/// - `displayTime` (`DT`): Dexcom's own reconciliation of the above, adjusted
///   for the account's timezone. This is what the Dexcom apps show on
///   screen, and is the one this package prefers for storage/display so
///   readings line up with what the user sees in the Dexcom app itself.
public struct DexcomReading: Sendable, Equatable {
    public let wallTime: Date
    public let systemTime: Date
    public let displayTime: Date
    public let mgdl: Double
    public let trend: GlucoseTrend

    public init(wallTime: Date, systemTime: Date, displayTime: Date, mgdl: Double, trend: GlucoseTrend) {
        self.wallTime = wallTime
        self.systemTime = systemTime
        self.displayTime = displayTime
        self.mgdl = mgdl
        self.trend = trend
    }
}

public enum DexcomShareError: Error, Sendable {
    /// The underlying `URLSession` call failed (offline, timeout, DNS, etc).
    case networkFailure(underlying: Error)
    /// Dexcom accepted the request shape but rejected the account/password.
    case invalidCredentials
    /// A previously-valid session ID was rejected by the server; the caller
    /// should discard its cached session and log in again.
    case sessionExpired
    /// The response didn't parse as the JSON shape this client expects --
    /// most likely sign that Dexcom has changed the API shape.
    case unexpectedResponse(details: String)
}

/// HTTP client for Dexcom's unofficial Share/Follow API. See the header
/// comment in `DexcomEndpoints.swift` before changing anything here.
public struct DexcomShareClient: Sendable {
    private let applicationId: String
    private let session: URLSession

    public init(applicationId: String = DexcomEndpoints.defaultApplicationId, urlSession: URLSession = .shared) {
        self.applicationId = applicationId
        self.session = urlSession
    }

    // MARK: - Authentication

    /// Performs the two-step Dexcom Share login: exchange account
    /// name/password for an `accountId`, then exchange the `accountId` for a
    /// `sessionId`. Returns the session ID on success.
    public func authenticateAndLogin(credentials: DexcomCredentials) async throws -> String {
        let accountId = try await authenticatePublisherAccount(credentials: credentials)

        // Dexcom returns an all-zero GUID from either step to signal bad
        // credentials rather than an HTTP error status.
        guard !Self.isNilGUID(accountId) else {
            throw DexcomShareError.invalidCredentials
        }

        let sessionId = try await loginPublisherAccountById(accountId: accountId, credentials: credentials)

        guard !Self.isNilGUID(sessionId) else {
            throw DexcomShareError.invalidCredentials
        }

        return sessionId
    }

    private func authenticatePublisherAccount(credentials: DexcomCredentials) async throws -> String {
        let url = DexcomEndpoints.url(for: DexcomEndpoints.Path.authenticatePublisherAccount, region: credentials.region)
        let body: [String: String] = [
            "accountName": credentials.accountName,
            "password": credentials.password,
            "applicationId": applicationId
        ]
        return try await postExpectingBareString(url: url, jsonBody: body)
    }

    private func loginPublisherAccountById(accountId: String, credentials: DexcomCredentials) async throws -> String {
        let url = DexcomEndpoints.url(for: DexcomEndpoints.Path.loginPublisherAccountById, region: credentials.region)
        let body: [String: String] = [
            "accountId": accountId,
            "password": credentials.password,
            "applicationId": applicationId
        ]
        return try await postExpectingBareString(url: url, jsonBody: body)
    }

    // MARK: - Reading fetch

    /// Fetches the most recent glucose readings visible to this publisher
    /// session, most-recent-first (Dexcom's own ordering).
    public func fetchLatestReadings(
        sessionId: String,
        minutes: Int = 1440,
        maxCount: Int = 288,
        region: DexcomRegion = .us
    ) async throws -> [DexcomReading] {
        var components = URLComponents(
            url: DexcomEndpoints.url(for: DexcomEndpoints.Path.readPublisherLatestGlucoseValues, region: region),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "sessionID", value: sessionId),
            URLQueryItem(name: "minutes", value: String(minutes)),
            URLQueryItem(name: "maxCount", value: String(maxCount))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await performRequest(request)

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode >= 400 {
            throw Self.classifyErrorResponse(data: data, statusCode: statusCode)
        }

        return try Self.parseReadings(from: data)
    }

    public func toGlucoseReading(_ reading: DexcomReading) -> GlucoseReading {
        GlucoseReading(
            timestamp: reading.displayTime,
            mgdl: reading.mgdl,
            trend: reading.trend,
            source: .dexcomShare
        )
    }

    // MARK: - Low-level request helpers

    /// POSTs a JSON object and expects a response body that is itself a bare
    /// JSON string (e.g. `"1b2c3d4e-..."`), which is how
    /// `AuthenticatePublisherAccount` and `LoginPublisherAccountById` both
    /// return their GUIDs.
    private func postExpectingBareString(url: URL, jsonBody: [String: String]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)

        let (data, response) = try await performRequest(request)

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode >= 400 {
            throw Self.classifyErrorResponse(data: data, statusCode: statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            throw DexcomShareError.unexpectedResponse(
                details: "Expected a bare JSON string, got: \(String(data: data, encoding: .utf8) ?? "<binary>")"
            )
        }
        return decoded
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw DexcomShareError.networkFailure(underlying: error)
        }
    }

    /// Dexcom communicates auth/session problems both via HTTP status and
    /// via a JSON error body shaped like `{"Code": "...", "Message": "..."}`.
    /// This inspects both to decide whether the caller should treat it as an
    /// expired session (worth a transparent re-login) versus something else.
    private static func classifyErrorResponse(data: Data, statusCode: Int) -> DexcomShareError {
        struct DexcomErrorBody: Decodable {
            let code: String?
            let message: String?

            enum CodingKeys: String, CodingKey {
                case code = "Code"
                case message = "Message"
            }
        }

        let sessionExpiredCodes: Set<String> = [
            "SessionNotValid",
            "SessionIdNotFound",
            "SessionNotFound"
        ]
        let invalidCredentialCodes: Set<String> = [
            "AccountPasswordInvalid",
            "SSO_AuthenticateAccountNotFound",
            "AccountNotFound"
        ]

        if let body = try? JSONDecoder().decode(DexcomErrorBody.self, from: data), let code = body.code {
            if sessionExpiredCodes.contains(code) {
                return .sessionExpired
            }
            if invalidCredentialCodes.contains(code) {
                return .invalidCredentials
            }
            return .unexpectedResponse(details: "\(code): \(body.message ?? "no message")")
        }

        if statusCode == 401 || statusCode == 500 {
            // Dexcom has historically used a bare 500 for an expired
            // session on the polling endpoint even without a parseable body.
            return .sessionExpired
        }

        return .unexpectedResponse(details: "HTTP \(statusCode) with unparseable body")
    }

    private static func isNilGUID(_ guid: String) -> Bool {
        guid == "00000000-0000-0000-0000-000000000000"
    }

    // MARK: - Reading parsing

    static func parseReadings(from data: Data) throws -> [DexcomReading] {
        struct RawReading: Decodable {
            let wt: String
            let st: String
            let dt: String
            let value: Double
            let trend: String

            enum CodingKeys: String, CodingKey {
                case wt = "WT"
                case st = "ST"
                case dt = "DT"
                case value = "Value"
                case trend = "Trend"
            }
        }

        let rawReadings: [RawReading]
        do {
            rawReadings = try JSONDecoder().decode([RawReading].self, from: data)
        } catch {
            throw DexcomShareError.unexpectedResponse(
                details: "Could not decode glucose value array: \(error)"
            )
        }

        return try rawReadings.map { raw in
            guard
                let wallTime = Self.parseDexcomDate(raw.wt),
                let systemTime = Self.parseDexcomDate(raw.st),
                let displayTime = Self.parseDexcomDate(raw.dt)
            else {
                throw DexcomShareError.unexpectedResponse(
                    details: "Unparseable Dexcom /Date(...)/ timestamp in \(raw.wt), \(raw.st), \(raw.dt)"
                )
            }
            return DexcomReading(
                wallTime: wallTime,
                systemTime: systemTime,
                displayTime: displayTime,
                mgdl: raw.value,
                trend: Self.mapTrend(raw.trend)
            )
        }
    }

    /// Parses Dexcom's ASP.NET-style JSON date strings, e.g.
    /// `"/Date(1609459200000)/"` or `"/Date(1609459200000-0700)/"` (the
    /// optional trailing timezone offset, if present, is ignored since the
    /// millis are already UTC epoch millis). `JSONDecoder`'s built-in date
    /// strategies (`.iso8601`, `.secondsSince1970`, etc) don't understand
    /// this format, hence the manual parse.
    static func parseDexcomDate(_ value: String) -> Date? {
        guard let openParen = value.firstIndex(of: "("),
              let closeParen = value.firstIndex(of: ")") else {
            return nil
        }
        let inner = value[value.index(after: openParen)..<closeParen]

        // Strip an optional trailing "+HHMM"/"-HHMM" timezone suffix from
        // the millisecond digits.
        let millisString: Substring
        if let signIndex = inner.lastIndex(where: { $0 == "+" || $0 == "-" }), signIndex != inner.startIndex {
            millisString = inner[inner.startIndex..<signIndex]
        } else {
            millisString = inner
        }

        guard let millis = Double(millisString) else {
            return nil
        }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    /// Maps Dexcom's `Trend` string to GlucoseCore's `GlucoseTrend`.
    static func mapTrend(_ trend: String) -> GlucoseTrend {
        switch trend {
        case "DoubleUp":
            return .rapidRise
        case "SingleUp", "FortyFiveUp":
            return .rising
        case "Flat":
            return .flat
        case "FortyFiveDown", "SingleDown":
            return .falling
        case "DoubleDown":
            return .rapidFall
        case "None", "NotComputable", "RateOutOfRange":
            return .unknown
        default:
            return .unknown
        }
    }
}
