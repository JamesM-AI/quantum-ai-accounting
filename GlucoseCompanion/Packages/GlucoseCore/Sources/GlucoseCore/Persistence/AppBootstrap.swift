import Foundation
import SwiftData

/// First-run seeding: ensures exactly one UserSettings row and the default
/// time-of-day blocks exist. Safe to call on every launch.
public enum AppBootstrap {
    @MainActor
    public static func ensureSeeded(in context: ModelContext) throws {
        var settingsDescriptor = FetchDescriptor<UserSettings>()
        settingsDescriptor.fetchLimit = 1
        let existingSettings = try context.fetch(settingsDescriptor)
        if let settings = existingSettings.first {
            // Migration bridge: `hasCompletedOnboarding` was added after
            // `isConfigured` already existed as the sole completion gate.
            // An install that reached `isConfigured` under the old logic
            // was, in every practical sense, already done with onboarding --
            // without this, every such install gets sent back through the
            // full onboarding flow the first time it launches post-update,
            // since the new field defaults to `false` for existing rows.
            if settings.isConfigured && !settings.hasCompletedOnboarding {
                settings.hasCompletedOnboarding = true
            }
        } else {
            context.insert(UserSettings())
        }

        let profileDescriptor = FetchDescriptor<TimeOfDayProfile>()
        if try context.fetch(profileDescriptor).isEmpty {
            for block in TimeOfDayProfile.defaultBlocks() {
                context.insert(block)
            }
        }

        try context.save()
    }
}
