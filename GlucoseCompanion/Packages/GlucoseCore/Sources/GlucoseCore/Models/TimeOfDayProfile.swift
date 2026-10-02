import Foundation
import SwiftData

/// One row per user-defined day-block (e.g. Breakfast/Lunch/Dinner/Overnight).
/// `learned*` fields are written only by the RatioLearning package's batch
/// job; `userOverride*` fields are set by the person and always take
/// precedence over the learned values wherever a dose is calculated.
@Model
public final class TimeOfDayProfile {
    @Attribute(.unique) public var id: UUID
    public var blockName: String
    /// Local-time hour boundaries, user-editable. `startHour` may be greater
    /// than `endHour` for a block that wraps past midnight (e.g. Overnight).
    public var startHour: Int
    public var endHour: Int

    public var learnedCarbRatio: Double?
    public var learnedCorrectionFactor: Double?
    public var dataPointCount: Int
    public var confidence: ConfidenceLevel
    public var lastComputedAt: Date?

    public var userOverrideCarbRatio: Double?
    public var userOverrideCorrectionFactor: Double?

    public init(
        id: UUID = UUID(),
        blockName: String,
        startHour: Int,
        endHour: Int,
        learnedCarbRatio: Double? = nil,
        learnedCorrectionFactor: Double? = nil,
        dataPointCount: Int = 0,
        confidence: ConfidenceLevel = .insufficientData,
        lastComputedAt: Date? = nil,
        userOverrideCarbRatio: Double? = nil,
        userOverrideCorrectionFactor: Double? = nil
    ) {
        self.id = id
        self.blockName = blockName
        self.startHour = startHour
        self.endHour = endHour
        self.learnedCarbRatio = learnedCarbRatio
        self.learnedCorrectionFactor = learnedCorrectionFactor
        self.dataPointCount = dataPointCount
        self.confidence = confidence
        self.lastComputedAt = lastComputedAt
        self.userOverrideCarbRatio = userOverrideCarbRatio
        self.userOverrideCorrectionFactor = userOverrideCorrectionFactor
    }

    /// The value the bolus calculator should actually use: user override wins.
    public var effectiveCarbRatio: Double? {
        userOverrideCarbRatio ?? learnedCarbRatio
    }

    public var effectiveCorrectionFactor: Double? {
        userOverrideCorrectionFactor ?? learnedCorrectionFactor
    }

    /// Whether `hour` (0-23, local time) falls in this block, handling
    /// blocks that wrap past midnight.
    public func contains(hour: Int) -> Bool {
        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            return hour >= startHour || hour < endHour
        }
    }

    public static func defaultBlocks() -> [TimeOfDayProfile] {
        [
            TimeOfDayProfile(blockName: "Breakfast", startHour: 5, endHour: 11),
            TimeOfDayProfile(blockName: "Lunch", startHour: 11, endHour: 16),
            TimeOfDayProfile(blockName: "Dinner", startHour: 16, endHour: 22),
            TimeOfDayProfile(blockName: "Overnight", startHour: 22, endHour: 5)
        ]
    }
}
