import Foundation
import GlucoseCore

// MARK: - IMPORTANT: unofficial, reverse-engineered API
//
// Everything in this file targets Dexcom's Share/Follow web service, which is
// what the Dexcom Follow mobile app uses to fetch a publisher's glucose data.
// Dexcom has never published or supported this API for third-party use: it
// has no versioning guarantees, no changelog, and its hosts, paths, request
// shape, and `applicationId` have all changed in the past without notice.
//
// Treat every constant below as a "known to have worked as of some point in
// the community reverse-engineering effort" value, not a documented contract.
// If login or polling starts failing, this file -- and `defaultApplicationId`
// in particular -- is the first thing to re-verify against current behavior
// (e.g. by inspecting network traffic from an up-to-date Dexcom Follow app).
//
// This is a backup data path only: HealthKit is the primary source of
// glucose data, and this client exists solely to fill gaps when HealthKit
// hasn't synced yet.
public enum DexcomEndpoints {

    /// The Dexcom Share "application ID" that identifies the calling client
    /// to Dexcom's backend. This is not a secret -- it's a fixed GUID baked
    /// into the Dexcom Follow app itself and long shared across community
    /// reverse-engineering projects (e.g. nightscout's share2nightscout,
    /// xDrip). It is the single most likely value to go stale: if
    /// authentication starts failing with otherwise-correct credentials,
    /// check whether this GUID needs to be replaced first.
    public static let defaultApplicationId = "d8665ade-9673-4e27-9ff6-92db4ce13d13"

    /// Base host for each Dexcom Share region. Selectable via `DexcomRegion`
    /// from GlucoseCore.
    public static func baseURL(for region: DexcomRegion) -> URL {
        switch region {
        case .us:
            return URL(string: "https://share2.dexcom.com/ShareWebServices/Services")!
        case .outsideUS:
            return URL(string: "https://shareous1.dexcom.com/ShareWebServices/Services")!
        }
    }

    public enum Path {
        public static let authenticatePublisherAccount = "/General/AuthenticatePublisherAccount"
        public static let loginPublisherAccountById = "/General/LoginPublisherAccountById"
        public static let readPublisherLatestGlucoseValues = "/Publisher/ReadPublisherLatestGlucoseValues"
    }

    /// Builds the full URL for a given path against a region's base host.
    /// Kept in one place so request-building code never string-concatenates
    /// hosts and paths itself.
    public static func url(for path: String, region: DexcomRegion) -> URL {
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        return URL(string: baseURL(for: region).absoluteString + normalizedPath)!
    }
}
