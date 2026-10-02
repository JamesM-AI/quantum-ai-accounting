import SwiftUI
import SwiftData
import GlucoseCore

struct SettingsView: View {
    @Environment(AppContainer.self) private var appContainer
    @Query private var settingsRows: [UserSettings]

    @State private var showingDexcomSheet = false

    var body: some View {
        Group {
            if let settings = settingsRows.first {
                Form {
                    // `TargetRangeSettingsView` contributes its own several
                    // top-level `Section`s (target range, safety floor, max
                    // dose, insulin action) directly here rather than being
                    // nested inside one more `Section` -- same validation and
                    // save behavior as onboarding, just folded into this form.
                    TargetRangeSettingsView(settings: settings)

                    Section("Dexcom Share") {
                        dexcomRow
                    }

                    Section {
                        NavigationLink {
                            DisclaimerView(isReadOnly: true)
                        } label: {
                            Label("About & Disclaimer", systemImage: "info.circle")
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingDexcomSheet) {
            NavigationStack {
                DexcomLoginView()
            }
        }
    }

    private var dexcomRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if appContainer.isDexcomConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not Connected", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let error = appContainer.dexcomLastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if appContainer.isDexcomConnected {
                Button("Disconnect", role: .destructive) {
                    appContainer.disconnectDexcom()
                }
            } else {
                Button("Connect Dexcom Account") {
                    showingDexcomSheet = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: UserSettings.self, inMemory: true)
    .environment(AppContainer())
}
