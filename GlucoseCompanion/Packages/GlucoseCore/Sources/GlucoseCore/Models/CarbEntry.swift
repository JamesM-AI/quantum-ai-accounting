import Foundation
import SwiftData

@Model
public final class CarbEntry {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var grams: Double
    public var note: String?
    public var source: EntrySource
    public var healthKitUUID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        grams: Double,
        note: String? = nil,
        source: EntrySource,
        healthKitUUID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.grams = grams
        self.note = note
        self.source = source
        self.healthKitUUID = healthKitUUID
    }
}
