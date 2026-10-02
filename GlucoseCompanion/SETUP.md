# GlucoseCompanion — Setup

This repo contains the Swift source for GlucoseCompanion, but **not** an `.xcodeproj` file. Xcode project files are a fragile, Xcode-version-specific binary-ish format that can't be reliably hand-authored or validated without Xcode itself (this was written in a Linux environment with no Xcode). Instead, all the Swift Packages and app-target source are provided, and you'll assemble them into a real Xcode project in a few minutes on your Mac. This also means: **nothing here has been compiled or run yet** — treat first build as the start of testing, not the end.

## Requirements

- A Mac with Xcode 15 or later (Xcode 16+ recommended)
- An Apple Developer account (free or paid) to enable the HealthKit capability and run on your iPhone
- iOS 17+ on your iPhone (for SwiftData + typed `HKInsulinDeliveryReason`)
- The Dexcom app installed and (ideally) already sharing your G7 data to Apple Health, plus your Dexcom Share/Follow account credentials if you want the backup sync path

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project → iOS → App**.
2. Product Name: `GlucoseCompanion`. Interface: **SwiftUI**. Storage: choose **SwiftData** (leave "Host in CloudKit" unchecked for now — this can be enabled later, see `ModelContainerFactory.makeCloudBackedContainer`). Language: Swift.
3. Save it as the `GlucoseCompanion/` directory in this repo, replacing the placeholder — or create it alongside and move files in; either way, the end state should match the layout below.
4. Set the deployment target to **iOS 17.0** in the project's build settings.

## 2. Add the local Swift Packages

For each of the eight packages under `GlucoseCompanion/Packages/`:

1. In Xcode: **File → Add Package Dependencies… → Add Local…**, and select each package folder (`Packages/GlucoseCore`, `Packages/HealthKitSync`, `Packages/DexcomShareClient`, `Packages/GlucoseAnalytics`, `Packages/RatioLearning`, `Packages/BolusCalculator`, `Packages/ActivityInsights`, `Packages/CorrectionLearning`).
2. Add all eight as dependencies of the `GlucoseCompanion` app target (Target → General → Frameworks, Libraries, and Embedded Content → +).

Each package's `Package.swift` already declares its local dependencies (e.g. `ActivityInsights` depends on both `GlucoseCore` and `RatioLearning`) via a relative local path, so Xcode should resolve the graph automatically once all seven are added.

## 3. Copy in the app-target source

Copy the contents of `GlucoseCompanion/GlucoseCompanion/` (the `App/`, `Onboarding/`, `Dashboard/`, `Trends/`, `Logging/`, `BolusSuggestion/`, `Insights/`, `Settings/` groups and `GlucoseCompanionApp.swift`) into your new Xcode project's `GlucoseCompanion` target, preserving the folder groups. Xcode will offer to copy items into the project — do that, or drag the folders in with "Create groups" selected.

Replace the auto-generated `ContentView.swift`/default `Info.plist` with the ones provided here:
- `GlucoseCompanion.entitlements` — add via Target → Signing & Capabilities → **+ Capability → HealthKit**, then check **Background Delivery**. Xcode manages the entitlements file's contents once the capability is added; cross-check it against the provided file.
- `Info.plist` — merge the `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `UIBackgroundModes`, and `BGTaskSchedulerPermittedIdentifiers` keys into your project's Info settings (Target → Info tab, or the physical Info.plist if you keep one).
- Also add Target → Signing & Capabilities → **+ Capability → Background Modes**, and check **Background fetch** and **Background processing**.

## 4. Wire up the app entry point

`GlucoseCompanionApp.swift` (provided) constructs the shared `ModelContainer` via `ModelContainerFactory.makeLocalContainer()`, runs `AppBootstrap.ensureSeeded`, and starts `HealthKitSync`'s background delivery + `DexcomShareClient`'s polling service once the user has connected them. Review it against your actual project structure once pasted in — dependency injection wiring (`AppContainer`/`AppState`) may need small adjustments depending on exactly how Xcode named things.

## 5. Build order (recommended)

Build and test incrementally rather than all at once — each milestone is independently verifiable on your device:

1. **M0**: Project builds, disclaimer/onboarding shell navigates, `ModelContainer` boots (check the Xcode console for SwiftData errors on first launch).
2. **M1**: Grant HealthKit permission on your device, confirm the Dashboard/Trends screens populate with your real glucose/carb/insulin history via `AnchoredQuerySync`.
3. **M2**: Log a carb/insulin entry manually, confirm it appears in Apple Health, and confirm it does **not** get duplicated when HealthKit later re-syncs it (the `healthKitUUID` dedup path).
4. **M3**: Once you have a few weeks of logged meals, open Insights and sanity-check the learned carb ratio/correction factor per time block against what you already know about your own dosing.
5. **M4**: Connect Dexcom Share credentials in Settings, confirm readings merge without duplicating HealthKit data. Try the Bolus suggestion screen — enter a test carb amount and **verify the math by hand** before trusting it, and confirm the low-glucose refusal and max-dose clamp actually trigger under the right conditions.

## Important safety note

The bolus suggestion feature is informational only — review every suggestion, confirm your target range / max dose / carb ratios with your endocrinologist or diabetes care team before relying on any number this app produces, and never let it replace your clinical judgment or your care team's guidance. This app has no pump integration and never will — it only helps you log what you decide to do.

## A known fragile piece: Dexcom Share

The Dexcom Share/Follow API used for the backup sync path is unofficial and reverse-engineered — Dexcom doesn't publish or support it, and it has changed before (endpoint hosts, the `applicationId` value, session behavior). If Dexcom Share login stops working after this was written, check `Packages/DexcomShareClient/Sources/DexcomShareClient/DexcomEndpoints.swift` first — the constants there are the most likely thing to need updating. HealthKit remains the primary, more durable data path regardless.
