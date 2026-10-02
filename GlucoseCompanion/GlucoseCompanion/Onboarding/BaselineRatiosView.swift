import SwiftUI
import SwiftData
import GlucoseCore

/// Optional onboarding step: lets a user who already knows their carb ratios
/// and correction factors (from their endocrinologist or diabetes care team)
/// seed them as `userOverride*` values on each `TimeOfDayProfile` block,
/// before any meals have been logged for `RatioLearning` to learn from.
///
/// Every field here is optional and the "Continue" button is always enabled
/// -- nothing in this step is required, since GlucoseCompanion will learn
/// these values from logged meals over time regardless.
struct BaselineRatiosView: View {
    var onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TimeOfDayProfile.startHour) private var profiles: [TimeOfDayProfile]
    @Query private var settingsRows: [UserSettings]

    /// One text-field pair per block, keyed by the block's `id`.
    @State private var carbRatioText: [UUID: String] = [:]
    @State private var correctionFactorText: [UUID: String] = [:]

    private var glucoseUnit: GlucoseUnit { settingsRows.first?.glucoseUnit ?? .mgdl }

    var body: some View {
        Form {
            Section {
                Text("If you already know your carb ratios from your endocrinologist or diabetes care team, enter them below. This is entirely optional -- leave any field blank and GlucoseCompanion will learn it from your logged meals over time instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(profiles, id: \.id) { profile in
                Section(profile.blockName) {
                    Text("\(hourLabel(profile.startHour)) - \(hourLabel(profile.endHour))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Carb ratio (g/u)") {
                        TextField("Optional", text: carbRatioBinding(for: profile))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Correction factor (\(GlucoseFormatting.perUnitLabel(glucoseUnit)))") {
                        TextField("Optional", text: correctionFactorBinding(for: profile))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                Button(action: save) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func carbRatioBinding(for profile: TimeOfDayProfile) -> Binding<String> {
        Binding(
            get: { carbRatioText[profile.id] ?? "" },
            set: { carbRatioText[profile.id] = $0 }
        )
    }

    private func correctionFactorBinding(for profile: TimeOfDayProfile) -> Binding<String> {
        Binding(
            get: { correctionFactorText[profile.id] ?? "" },
            set: { correctionFactorText[profile.id] = $0 }
        )
    }

    /// For every block with at least one filled-in field, sets the
    /// corresponding `userOverride*` value(s) -- converting the correction
    /// factor from the displayed unit to mg/dL first, mirroring
    /// `LearnedRatiosView`'s `applyCorrectionOverride`. Blank fields are left
    /// untouched (they're always `nil` at this point in onboarding anyway).
    private func save() {
        for profile in profiles {
            if let text = carbRatioText[profile.id], let value = Double(text), value > 0 {
                profile.userOverrideCarbRatio = value
            }
            if let text = correctionFactorText[profile.id], let value = Double(text), value > 0 {
                let mgdlPerUnit = glucoseUnit == .mmolL ? value * GlucoseFormatting.mgdlPerMmol : value
                profile.userOverrideCorrectionFactor = mgdlPerUnit
            }
        }

        try? modelContext.save()
        onContinue()
    }

    private func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let period = normalized < 12 ? "AM" : "PM"
        var hour12 = normalized % 12
        if hour12 == 0 { hour12 = 12 }
        return "\(hour12) \(period)"
    }
}

#Preview {
    NavigationStack {
        BaselineRatiosView(onContinue: {})
    }
    .modelContainer(for: [TimeOfDayProfile.self, UserSettings.self], inMemory: true)
}
