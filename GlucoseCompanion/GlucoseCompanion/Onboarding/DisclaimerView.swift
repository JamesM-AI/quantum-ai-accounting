import SwiftUI
import SwiftData
import GlucoseCore

/// Gates onboarding: `RootView` shows this until `hasAcceptedDisclaimer` is
/// true on the singleton `UserSettings` row. Also reused read-only (no
/// acceptance UI) from `SettingsView` so the same text stays reachable at
/// any time, not just on first launch.
struct DisclaimerView: View {
    /// When true, this is the read-only presentation from Settings: no
    /// checkbox/button, just the text.
    var isReadOnly: Bool = false
    /// Called after the disclaimer is accepted (onboarding advances the
    /// flow); unused in the read-only presentation.
    var onAccept: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [UserSettings]

    @State private var hasAgreed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Before You Continue")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 4)

                disclaimerBody

                if !isReadOnly {
                    Divider()
                        .padding(.vertical, 8)

                    Toggle(isOn: $hasAgreed) {
                        Text("I understand and agree")
                            .font(.headline)
                    }
                    .toggleStyle(.switch)

                    Button(action: accept) {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAgreed)
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle(isReadOnly ? "Disclaimer" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isReadOnly {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var disclaimerBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            disclaimerSection(
                icon: "stethoscope",
                title: "Not a Medical Device",
                body: "GlucoseCompanion is personal decision-support software. It is not a medical device, has not been reviewed or cleared by any regulator, and does not replace professional medical advice, diagnosis, or treatment. Always use your own judgment and consult your diabetes care team."
            )

            disclaimerSection(
                icon: "syringe",
                title: "Bolus Suggestions Are Informational Only",
                body: "Any insulin dose this app suggests is purely informational. Every suggestion must be reviewed by you before acting on it, and you can edit it before logging anything. GlucoseCompanion never delivers insulin automatically, has no integration with any insulin pump, and never will."
            )

            disclaimerSection(
                icon: "person.crop.circle.badge.checkmark",
                title: "Confirm Your Numbers With Your Care Team",
                body: "Before relying on anything this app suggests, confirm your target glucose range, maximum bolus dose, and carb ratios with your endocrinologist or diabetes care team. The values you enter here are only as safe as the numbers you and your care team agree on."
            )

            disclaimerSection(
                icon: "exclamationmark.triangle",
                title: "Use At Your Own Risk",
                body: "You are solely responsible for all treatment decisions, including any dose of insulin you take. In an emergency, or if you feel unwell, contact your care team or emergency services rather than relying on this app."
            )
        }
    }

    private func disclaimerSection(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func accept() {
        guard let settings = settingsRows.first else { return }
        settings.hasAcceptedDisclaimer = true
        settings.disclaimerAcceptedAt = Date()
        try? modelContext.save()
        onAccept?()
    }
}

#Preview {
    NavigationStack {
        DisclaimerView()
    }
    .modelContainer(for: UserSettings.self, inMemory: true)
}
