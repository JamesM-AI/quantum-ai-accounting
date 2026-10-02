import SwiftUI

struct MainTabView: View {
    @State private var showingSettings = false

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Dashboard", systemImage: "waveform.path.ecg") }

            NavigationStack {
                TrendsView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }

            NavigationStack {
                LogEntryView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Log", systemImage: "plus.circle") }

            NavigationStack {
                BolusSuggestionView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Bolus", systemImage: "syringe") }

            NavigationStack {
                LearnedRatiosView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Insights", systemImage: "brain.head.profile") }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}
