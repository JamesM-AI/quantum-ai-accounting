import SwiftUI
import SwiftData
import GlucoseCore

/// Steps a first-run user through disclaimer -> HealthKit permission ->
/// target range setup -> optional baseline carb ratios -> optional Dexcom
/// connect.
///
/// This view does not dismiss itself: `RootView` watches
/// `hasAcceptedDisclaimer && hasCompletedOnboarding` on the singleton
/// `UserSettings` row via `@Query` and switches to `MainTabView` once both
/// are true. Note this is deliberately NOT `isConfigured` -- that flag flips
/// true right after the target-range step (so the bolus calculator can be
/// used) but onboarding must keep going past that point, so
/// `hasCompletedOnboarding` is only set at the very end of this flow
/// (`finishOnboarding()`). The baseline-ratios and Dexcom steps are both
/// purely optional/skippable.
struct OnboardingFlow: View {
    private enum Step {
        case disclaimer
        case healthKit
        case targetRange
        case baselineRatios
        case dexcom
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [UserSettings]

    @State private var step: Step = .disclaimer

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .disclaimer:
                    DisclaimerView(onAccept: { step = .healthKit })

                case .healthKit:
                    HealthKitPermissionView(onContinue: { step = .targetRange })

                case .targetRange:
                    if let settings = settingsRows.first {
                        // `TargetRangeSettingsView`'s body is bare `Section`s
                        // (see its doc comment) so it can also be folded
                        // directly into `SettingsView`'s own `Form` --
                        // standalone here, it needs this `Form` wrapper.
                        Form {
                            TargetRangeSettingsView(settings: settings, onSave: {
                                step = .baselineRatios
                            })
                        }
                    } else {
                        ProgressView()
                    }

                case .baselineRatios:
                    BaselineRatiosView(onContinue: { step = .dexcom })

                case .dexcom:
                    DexcomLoginView(onSkip: finishOnboarding)
                }
            }
            .navigationTitle(title(for: step))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func title(for step: Step) -> String {
        switch step {
        case .disclaimer: return ""
        case .healthKit: return "Health Access"
        case .targetRange: return "Target Range"
        case .baselineRatios: return "Baseline Ratios"
        case .dexcom: return "Connect Dexcom"
        }
    }

    private func finishOnboarding() {
        guard let settings = settingsRows.first else { return }
        settings.hasCompletedOnboarding = true
        try? modelContext.save()
    }
}

#Preview {
    OnboardingFlow()
        .modelContainer(for: UserSettings.self, inMemory: true)
        .environment(AppContainer())
}
