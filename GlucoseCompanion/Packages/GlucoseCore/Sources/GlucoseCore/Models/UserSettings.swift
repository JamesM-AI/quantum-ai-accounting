import Foundation
import SwiftData

/// Singleton settings row. `isConfigured` gates the bolus suggestion feature
/// -- the numeric fields carry schema-level defaults (required for future
/// CloudKit compatibility) but must never be treated as meaningful values
/// until the user has explicitly set them.
@Model
public final class UserSettings {
    public var targetRangeLowMgdl: Double
    public var targetRangeHighMgdl: Double
    public var maxBolusUnits: Double
    public var insulinActionDurationMinutes: Int
    public var iobModel: IOBModelType
    public var glucoseUnit: GlucoseUnit
    public var dexcomRegion: DexcomRegion?
    public var hasAcceptedDisclaimer: Bool
    public var disclaimerAcceptedAt: Date?
    /// True only once the user has explicitly walked through target range +
    /// max dose setup. The bolus calculator must refuse to run while false.
    public var isConfigured: Bool
    /// Absolute floor below which the bolus calculator always refuses to
    /// suggest a dose, regardless of target range (see SafetyGuardrails).
    public var lowGlucoseSafetyFloorMgdl: Double
    /// Set only at the very end of `OnboardingFlow`, deliberately separate
    /// from `isConfigured` -- `isConfigured` flips true partway through the
    /// flow (as soon as target range/max dose are saved) so the bolus
    /// calculator can be used, but `RootView` must keep showing the rest of
    /// onboarding (baseline ratios, optional Dexcom connect) until this flag
    /// is true, not just `isConfigured`. Inline default (rather than only an
    /// init default) so SwiftData can lightweight-migrate existing installs
    /// that predate this field.
    public var hasCompletedOnboarding: Bool = false

    public init(
        targetRangeLowMgdl: Double = 70,
        targetRangeHighMgdl: Double = 180,
        maxBolusUnits: Double = 0,
        insulinActionDurationMinutes: Int = 240,
        iobModel: IOBModelType = .exponential,
        glucoseUnit: GlucoseUnit = .mgdl,
        dexcomRegion: DexcomRegion? = nil,
        hasAcceptedDisclaimer: Bool = false,
        disclaimerAcceptedAt: Date? = nil,
        isConfigured: Bool = false,
        lowGlucoseSafetyFloorMgdl: Double = 80,
        hasCompletedOnboarding: Bool = false
    ) {
        self.targetRangeLowMgdl = targetRangeLowMgdl
        self.targetRangeHighMgdl = targetRangeHighMgdl
        self.maxBolusUnits = maxBolusUnits
        self.insulinActionDurationMinutes = insulinActionDurationMinutes
        self.iobModel = iobModel
        self.glucoseUnit = glucoseUnit
        self.dexcomRegion = dexcomRegion
        self.hasAcceptedDisclaimer = hasAcceptedDisclaimer
        self.disclaimerAcceptedAt = disclaimerAcceptedAt
        self.isConfigured = isConfigured
        self.lowGlucoseSafetyFloorMgdl = lowGlucoseSafetyFloorMgdl
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public var targetMidpointMgdl: Double {
        (targetRangeLowMgdl + targetRangeHighMgdl) / 2
    }
}
