import Foundation
import GlucoseCore

/// Display-only conversion between the app's canonical storage unit (mg/dL,
/// used by every model and by BolusCalculator's math) and whatever unit the
/// user has chosen to see in `UserSettings.glucoseUnit`. Nothing is ever
/// stored in mmol/L -- this only formats numbers for reading.
enum GlucoseFormatting {
    static let mgdlPerMmol = 18.0182

    static func mmol(fromMgdl mgdl: Double) -> Double {
        mgdl / mgdlPerMmol
    }

    /// A glucose reading with its unit suffix, e.g. "142 mg/dL" or "7.9 mmol/L".
    static func readingString(mgdl: Double, unit: GlucoseUnit) -> String {
        "\(valueString(mgdl: mgdl, unit: unit)) \(unitLabel(unit))"
    }

    /// Just the number, no suffix -- for callers that lay out the unit label separately.
    static func valueString(mgdl: Double, unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdl:
            return "\(Int(mgdl.rounded()))"
        case .mmolL:
            return String(format: "%.1f", mmol(fromMgdl: mgdl))
        }
    }

    static func unitLabel(_ unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdl: return "mg/dL"
        case .mmolL: return "mmol/L"
        }
    }

    /// For rate-style values like the correction factor (glucose drop per
    /// insulin unit) -- same underlying conversion, different label/precision.
    static func perUnitLabel(_ unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdl: return "mg/dL per u"
        case .mmolL: return "mmol/L per u"
        }
    }

    static func perUnitValueString(mgdlPerUnit: Double, unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdl:
            return String(format: "%.1f", mgdlPerUnit)
        case .mmolL:
            return String(format: "%.2f", mmol(fromMgdl: mgdlPerUnit))
        }
    }
}
