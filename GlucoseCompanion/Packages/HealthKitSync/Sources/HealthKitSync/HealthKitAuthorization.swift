import Foundation
import HealthKit

/// Coarse status for a single Health data category. Note that HealthKit only
/// ever reveals *share* (write) authorization through `authorizationStatus(for:)`
/// -- for read-only requests it deliberately withholds whether the user
/// granted or denied access, so `.denied` below only ever shows up for the
/// types this app also asks to write (carbs, insulin).
public enum HealthKitAuthorizationStatus: String, Sendable {
    case notDetermined
    case denied
    case authorized

    init(_ status: HKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .sharingDenied: self = .denied
        case .sharingAuthorized: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
}

/// The Health data categories this app cares about, kept as a plain enum so
/// callers outside this package never need to import HealthKit just to ask
/// "is glucose authorized?".
public enum HealthDataCategory: String, CaseIterable, Sendable {
    case bloodGlucose
    case dietaryCarbohydrates
    case insulinDelivery
    case workouts
    case heartRate
    case stepCount

    var objectType: HKObjectType {
        switch self {
        case .bloodGlucose: return HealthStoreManager.glucoseType
        case .dietaryCarbohydrates: return HealthStoreManager.carbType
        case .insulinDelivery: return HealthStoreManager.insulinType
        case .workouts: return HealthStoreManager.workoutType
        case .heartRate: return HealthStoreManager.heartRateType
        case .stepCount: return HealthStoreManager.stepCountType
        }
    }
}

/// UI-friendly rollup of authorization state, safe to hand to a SwiftUI view
/// without that view needing to know HealthKit exists.
public struct AuthorizationSummary: Sendable, Equatable {
    public let granted: Bool
    public let deniedTypes: [String]

    public init(granted: Bool, deniedTypes: [String]) {
        self.granted = granted
        self.deniedTypes = deniedTypes
    }
}

public enum HealthKitAuthorization {
    /// Only the categories this app requests *share* access for (carbs,
    /// insulin) can meaningfully report `.denied` here -- see the caveat on
    /// `HealthKitAuthorizationStatus`.
    private static let shareCategories: [HealthDataCategory] = [.dietaryCarbohydrates, .insulinDelivery]

    public static func status(for category: HealthDataCategory, store: HealthStoreManager) -> HealthKitAuthorizationStatus {
        HealthKitAuthorizationStatus(store.healthStore.authorizationStatus(for: category.objectType))
    }

    public static func shareAuthorizationSummary(store: HealthStoreManager) -> AuthorizationSummary {
        let deniedTypes = shareCategories
            .filter { status(for: $0, store: store) == .denied }
            .map(\.rawValue)
        return AuthorizationSummary(granted: deniedTypes.isEmpty, deniedTypes: deniedTypes)
    }
}
