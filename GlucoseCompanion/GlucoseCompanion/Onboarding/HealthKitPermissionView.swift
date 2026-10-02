import SwiftUI
import SwiftData
import GlucoseCore
import HealthKitSync

/// Explains and requests HealthKit access during onboarding. Denial or
/// partial denial is never allowed to block the rest of onboarding -- the
/// user can revisit this from Settings later, and the app degrades to
/// Dexcom Share / manual logging without it.
struct HealthKitPermissionView: View {
    var onContinue: () -> Void

    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext

    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var hasRequested = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connect to Apple Health")
                    .font(.largeTitle.bold())

                Text("GlucoseCompanion uses Apple Health as the shared source of truth for your data.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    permissionRow(icon: "drop.fill", text: "Reads your blood glucose readings, so your CGM data shows up here alongside everything else.")
                    permissionRow(icon: "fork.knife", text: "Reads and writes the carbohydrate entries you log, so meals stay in sync with other apps.")
                    permissionRow(icon: "syringe", text: "Reads and writes the insulin doses you log, for the same reason.")
                    permissionRow(icon: "figure.run", text: "Reads workouts and heart rate, which help explain glucose swings around exercise.")
                }
                .padding(.vertical, 4)

                Text("You can change any of these permissions at any time from the iOS Settings app, under Health > Data Access & Devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if let summary = appContainer.healthKitShareAuthorization {
                    if summary.granted {
                        Label("Access granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Some permissions were denied (\(summary.deniedTypes.joined(separator: ", "))). You can grant them later in iOS Settings.", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Button(action: requestAccess) {
                    if isRequesting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(hasRequested ? "Try Again" : "Grant Access")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)
                .padding(.top, 8)

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func permissionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.subheadline)
        }
    }

    private func requestAccess() {
        errorMessage = nil
        isRequesting = true
        Task {
            defer { isRequesting = false }
            do {
                try await appContainer.requestHealthKitAuthorization()
                hasRequested = true
                do {
                    try await appContainer.runInitialHealthKitSync(context: modelContext)
                } catch {
                    // Authorization succeeded even if the first sync failed;
                    // surface the sync error but don't treat it as a reason
                    // to block onboarding.
                    errorMessage = "Connected, but the initial sync failed: \(error.localizedDescription)"
                }
            } catch {
                hasRequested = true
                errorMessage = "Couldn't get HealthKit access: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        HealthKitPermissionView(onContinue: {})
    }
    .modelContainer(for: UserSettings.self, inMemory: true)
    .environment(AppContainer())
}
