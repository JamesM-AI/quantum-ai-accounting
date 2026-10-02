import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static var schema: Schema {
        Schema([
            GlucoseReading.self,
            CarbEntry.self,
            InsulinDose.self,
            TimeOfDayProfile.self,
            UserSettings.self,
            WorkoutSession.self,
            StepSample.self
        ])
    }

    /// Local-only store. This is the default -- health data never leaves the
    /// device unless the user explicitly opts into the CloudKit backup
    /// configuration below.
    public static func makeLocalContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Opt-in encrypted iCloud backup via the app's private CloudKit database.
    /// Only construct this after the user has explicitly enabled it in
    /// Settings.
    public static func makeCloudBackedContainer(cloudKitContainerIdentifier: String) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
