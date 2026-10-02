import Foundation
import Security
import GlucoseCore

/// A Dexcom Share account's login credentials plus which regional server
/// they authenticate against.
///
/// `password` is intentionally never surfaced by any logging-friendly
/// conformance. Do not add `CustomStringConvertible`/`CustomDebugStringConvertible`
/// without redacting it -- accidentally printing this struct (e.g. in a
/// crash log or `os_log`) would leak the user's Dexcom password.
public struct DexcomCredentials: Codable, Equatable, Sendable {
    public var accountName: String
    public var password: String
    public var region: DexcomRegion

    public init(accountName: String, password: String, region: DexcomRegion) {
        self.accountName = accountName
        self.password = password
        self.region = region
    }
}

/// Persists a single `DexcomCredentials` value in the Keychain.
///
/// Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so the credential
/// is readable by background polling (which can run before the user has
/// unlocked the device this boot cycle, but only after the *first* unlock)
/// while never syncing to iCloud Keychain or migrating to another device.
/// This is deliberately different -- and less restrictive -- than how the
/// app should treat actual health data, but appropriate for a third-party
/// login credential.
public struct KeychainCredentialStore {
    private let service: String
    private let account: String

    public init(
        service: String = "com.glucosecompanion.dexcomshare",
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func save(_ credentials: DexcomCredentials) throws {
        let data = try JSONEncoder().encode(credentials)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        // Try update first (the common case after initial setup); fall back
        // to add if nothing exists yet.
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unhandled(status: updateStatus)
        }
    }

    public func load() -> DexcomCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(DexcomCredentials.self, from: data)
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }
}

public enum KeychainError: Error {
    case unhandled(status: OSStatus)
}
