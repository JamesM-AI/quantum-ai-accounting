import Foundation
import SwiftData

@Model
public final class InsulinDose {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var units: Double
    public var reason: InsulinDeliveryReason
    /// Optional link to the meal this bolus was intended to cover.
    public var linkedCarbEntryID: UUID?
    /// If this dose was logged from a BolusSuggestion, keep the audit trail
    /// purely for the user's own history -- never used to trigger anything.
    public var linkedSuggestionID: UUID?
    public var source: EntrySource
    public var healthKitUUID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        units: Double,
        reason: InsulinDeliveryReason,
        linkedCarbEntryID: UUID? = nil,
        linkedSuggestionID: UUID? = nil,
        source: EntrySource,
        healthKitUUID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.units = units
        self.reason = reason
        self.linkedCarbEntryID = linkedCarbEntryID
        self.linkedSuggestionID = linkedSuggestionID
        self.source = source
        self.healthKitUUID = healthKitUUID
    }
}
