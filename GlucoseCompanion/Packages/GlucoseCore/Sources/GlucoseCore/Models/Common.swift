import Foundation

/// Where a record originated. Used to dedup against HealthKit re-observation
/// of samples the app itself wrote back to Health.
public enum EntrySource: String, Codable, Sendable {
    case healthKit
    case manualInApp
    case dexcomShare
}

public enum GlucoseTrend: String, Codable, Sendable {
    case rapidRise
    case rising
    case flat
    case falling
    case rapidFall
    case unknown
}

/// Mirrors HKInsulinDeliveryReason (bolus = 1, basal = 2 in HealthKit).
public enum InsulinDeliveryReason: String, Codable, Sendable {
    case bolus
    case basal
}

public enum ConfidenceLevel: String, Codable, Sendable {
    case insufficientData
    case low
    case medium
    case high
}

public enum IOBModelType: String, Codable, Sendable {
    case bilinear
    case exponential
}

public enum GlucoseUnit: String, Codable, Sendable {
    case mgdl
    case mmolL
}

public enum DexcomRegion: String, Codable, Sendable {
    case us
    case outsideUS
}
