import SwiftUI
import SwiftData
import GlucoseCore

@main
struct GlucoseCompanionApp: App {
    let modelContainer: ModelContainer
    @State private var appContainer = AppContainer()

    init() {
        do {
            modelContainer = try ModelContainerFactory.makeLocalContainer()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appContainer)
                .task {
                    let context = modelContainer.mainContext
                    try? AppBootstrap.ensureSeeded(in: context)
                    appContainer.resumeDexcomPollingIfConnected(context: context)
                    try? await appContainer.startBackgroundDelivery(context: context)
                }
        }
        .modelContainer(modelContainer)
    }
}
