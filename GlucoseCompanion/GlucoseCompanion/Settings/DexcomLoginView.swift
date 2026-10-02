import SwiftUI
import SwiftData
import GlucoseCore
import DexcomShareClient

/// Dexcom Share credential entry. Used two ways:
/// - Standalone from `SettingsView`, presented in a sheet, with a plain
///   "Cancel" dismiss.
/// - Embedded as the last (optional) step of `OnboardingFlow`, where
///   `onSkip` is supplied so the user can defer setup entirely -- Dexcom
///   Share is only a backup data path to HealthKit, never a requirement.
struct DexcomLoginView: View {
    var onSkip: (() -> Void)? = nil

    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var accountName = ""
    @State private var password = ""
    @State private var region: DexcomRegion = .us
    @State private var isConnecting = false

    var body: some View {
        Form {
            Section {
                Text("Sign in with your Dexcom Share (Follow) account -- the same account name and password you use in the Dexcom app. This is a backup data path; Apple Health remains the primary source once connected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Dexcom Account") {
                TextField("Account name", text: $accountName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }

            Section("Region") {
                Picker("Region", selection: $region) {
                    Text("United States").tag(DexcomRegion.us)
                    Text("Outside United States").tag(DexcomRegion.outsideUS)
                }
                .pickerStyle(.segmented)
            }

            if let error = appContainer.dexcomLastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect || isConnecting)
            }

            if let onSkip {
                Section {
                    Button("Skip for now", role: .cancel) {
                        onSkip()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar {
            if onSkip == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var canConnect: Bool {
        !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func connect() {
        isConnecting = true
        let credentials = DexcomCredentials(accountName: accountName, password: password, region: region)
        appContainer.connectDexcom(credentials: credentials, context: modelContext)
        isConnecting = false

        if appContainer.isDexcomConnected {
            if let onSkip {
                // Onboarding's Dexcom step is done either way; reuse the
                // same "advance" closure whether the user connected or
                // skipped.
                onSkip()
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        DexcomLoginView()
    }
    .environment(AppContainer())
}
