import SwiftUI
import SwiftData
import GlucoseCore
import BolusCalculator
import RatioLearning
import CorrectionLearning

struct BolusSuggestionView: View {
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var allReadings: [GlucoseReading]
    @Query private var settingsRows: [UserSettings]
    @Query private var profiles: [TimeOfDayProfile]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var allDoses: [InsulinDose]
    @Query private var carbEntries: [CarbEntry]
    @Query private var stepSamples: [StepSample]
    @Query private var workouts: [WorkoutSession]

    /// Wraps `BolusCalculationResult` with the one failure mode that isn't
    /// (and can't be) one of its cases: no glucose reading exists at all, so
    /// there's no `currentGlucoseMgdl`/`glucoseReadingTimestamp` to even call
    /// `BolusCalculator.calculate` with.
    private enum ViewResult {
        case calculation(BolusCalculationResult)
        case noGlucoseReading
    }

    @State private var carbsText: String = ""
    @State private var planningToBeActive: Bool = false
    @State private var viewResult: ViewResult?
    @State private var showingReview = false
    @State private var pendingSuggestionID: UUID?

    private var settings: UserSettings? { settingsRows.first }
    private var glucoseUnit: GlucoseUnit { settings?.glucoseUnit ?? .mgdl }
    private var latestReading: GlucoseReading? { allReadings.first }

    private var activeProfile: TimeOfDayProfile? {
        let hour = Calendar.current.component(.hour, from: Date())
        return profiles.first { $0.contains(hour: hour) }
    }

    private var carbsGrams: Double? { Double(carbsText) }

    private var canCalculate: Bool {
        guard let carbsGrams else { return false }
        return carbsGrams > 0
    }

    var body: some View {
        Form {
            Section {
                disclaimerBanner
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Meal") {
                HStack {
                    TextField("Carb grams", text: $carbsText)
                        .keyboardType(.decimalPad)
                    Text("g")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("I plan to be active after this", isOn: $planningToBeActive)
                    Text("If checked and you have enough correction history, the correction dose may be reduced -- see below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let latestReading {
                    HStack {
                        Text("Current glucose")
                        Spacer()
                        Text(GlucoseFormatting.readingString(mgdl: latestReading.mgdl, unit: glucoseUnit))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No recent glucose reading available")
                        .foregroundStyle(.secondary)
                }

                Button("Calculate", action: calculate)
                    .disabled(!canCalculate)
            }

            if let viewResult {
                resultSection(viewResult)
            }
        }
        .navigationTitle("Bolus")
        .sheet(isPresented: $showingReview) {
            if
                case .calculation(.suggestion(let suggestion)) = viewResult,
                let carbsGrams,
                let pendingSuggestionID
            {
                BolusReviewSheet(
                    suggestion: suggestion,
                    carbsGrams: carbsGrams,
                    suggestionID: pendingSuggestionID
                )
            }
        }
    }

    // Shown above every result, every time -- not a one-time acknowledgement
    // and not a toast that can be dismissed and forgotten.
    private var disclaimerBanner: some View {
        Label {
            Text("Informational only -- not medical advice. Review every suggestion and confirm with your care team.")
                .font(.caption)
        } icon: {
            Image(systemName: "exclamationmark.shield.fill")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func resultSection(_ viewResult: ViewResult) -> some View {
        switch viewResult {
        case .noGlucoseReading:
            Section("Can't Calculate") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No glucose reading is available yet.")
                    Text("Wait for HealthKit or Dexcom sync to bring in a recent reading before calculating a dose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .calculation(let result):
            calculationResultSection(result)
        }
    }

    @ViewBuilder
    private func calculationResultSection(_ result: BolusCalculationResult) -> some View {
        switch result {
        case .suggestion(let suggestion):
            Section("Suggested Dose") {
                Text("\(formattedUnits(suggestion.suggestedUnits)) units")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                breakdownRow("Carbs", suggestion.carbComponentUnits)
                breakdownRow("Correction", suggestion.correctionComponentUnits)
                breakdownRow("Insulin on board (subtracted)", -suggestion.insulinOnBoardUnits)

                Text("\(suggestion.usedProfile.blockName) \u{00B7} based on \(suggestion.usedProfile.dataPointCount) meals \u{00B7} \(confidenceLabel(suggestion.usedProfile.confidence)) confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !suggestion.warnings.isEmpty {
                Section("Warnings") {
                    ForEach(Array(suggestion.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warningText(warning), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button("Review & Log") {
                    pendingSuggestionID = UUID()
                    showingReview = true
                }
            }

        case .refusedNotConfigured:
            Section("Can't Calculate") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bolus suggestions aren't set up yet.")
                    Text("Go to Settings to set your target glucose range and maximum bolus dose before using this feature.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .refusedGlucoseTooLow(let currentMgdl):
            Section("Can't Calculate") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Glucose is too low to suggest a dose (\(GlucoseFormatting.readingString(mgdl: currentMgdl, unit: glucoseUnit))).")
                        .foregroundStyle(.red)
                    Text("Treat the low first. Do not take insulin right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .refusedStaleGlucose(let readingAgeMinutes):
            Section("Can't Calculate") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your most recent glucose reading is \(Int(readingAgeMinutes)) minutes old.")
                    Text("Wait for a fresh CGM reading before calculating a dose -- an old reading may no longer reflect where you are now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .refusedProfileNotReady:
            Section("Can't Calculate") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This time of day doesn't have a usable carb ratio or correction factor yet.")
                    Text("Log more meals so ratios can be learned, or set one directly in Insights with your care team's numbers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func breakdownRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value >= 0 ? "" : "-")\(formattedUnits(abs(value))) u")
                .foregroundStyle(.secondary)
        }
    }

    private func confidenceLabel(_ confidence: ConfidenceLevel) -> String {
        switch confidence {
        case .insufficientData: return "insufficient data"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    private func warningText(_ warning: BolusWarning) -> String {
        switch warning {
        case .exceedsMaxDose(let clampedFrom):
            return "Raw calculation was \(formattedUnits(clampedFrom))u, capped to your configured max dose."
        case .unusuallyHighVersusHistory(let recentAverage):
            return "Unusually high vs. your recent average of \(formattedUnits(recentAverage))u."
        case .lowConfidenceProfile(let confidence):
            return "This time block's ratios are \(confidenceLabel(confidence)) confidence."
        case .activityAdjustedCorrectionApplied(let baseline, let adjusted, let confidence, let dataPointCount):
            return "Correction reduced for planned activity: \(GlucoseFormatting.perUnitValueString(mgdlPerUnit: adjusted, unit: glucoseUnit))/u instead of your usual \(GlucoseFormatting.perUnitValueString(mgdlPerUnit: baseline, unit: glucoseUnit))/u, based on \(dataPointCount) past corrections followed by activity (\(confidenceLabel(confidence)) confidence)."
        }
    }

    private func formattedUnits(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func calculate() {
        guard let carbsGrams, carbsGrams > 0 else { return }

        guard let latestReading else {
            viewResult = .noGlucoseReading
            return
        }

        // Defensive only: the singleton `UserSettings` row and the four
        // default day blocks are always seeded at launch, so these should
        // never actually be nil. If they somehow were, `.refusedNotConfigured`
        // is the accurate user-facing message either way ("finish setup").
        guard let settings, let activeProfile else {
            viewResult = .calculation(.refusedNotConfigured)
            return
        }

        let now = Date()
        // Plenty of headroom over any realistic insulin action duration
        // (IOB window) and over the sample size `unusuallyHigh` needs
        // (recent-history window) without pulling the entire dose history.
        let iobLookback = now.addingTimeInterval(-48 * 60 * 60)
        let recentHistoryLookback = now.addingTimeInterval(-60 * 24 * 60 * 60)

        let bolusDoses = allDoses.filter { $0.reason == .bolus }
        let recentBolusDoses = bolusDoses.filter { $0.timestamp >= recentHistoryLookback && $0.timestamp <= now }
        let allBolusDosesForIOB = bolusDoses.filter { $0.timestamp >= iobLookback && $0.timestamp <= now }

        // Only bother building the correction-learning pipeline when the
        // toggle is on -- when it's off, `nil` preserves the exact baseline
        // behavior `BolusCalculator.calculate` already had.
        var activityAdjustedFactor: ActivityAdjustedCorrectionFactor?
        if planningToBeActive {
            let mealEvents = MealExcursionMatcher.extractEvents(
                carbEntries: carbEntries,
                insulinDoses: allDoses,
                glucoseReadings: allReadings
            )
            let correctionEvents = CorrectionEventExtractor.extractEvents(
                insulinDoses: allDoses,
                glucoseReadings: allReadings,
                stepSamples: stepSamples,
                workouts: workouts,
                mealEvents: mealEvents,
                targetRangeLowMgdl: settings.targetRangeLowMgdl,
                targetRangeHighMgdl: settings.targetRangeHighMgdl,
                lowGlucoseSafetyFloorMgdl: settings.lowGlucoseSafetyFloorMgdl,
                insulinActionDurationMinutes: settings.insulinActionDurationMinutes
            )
            let sensitivity = CorrectionSensitivityEstimator.estimate(
                events: correctionEvents,
                targetMidpointMgdl: settings.targetMidpointMgdl
            )
            if let withActivity = sensitivity.withActivity {
                activityAdjustedFactor = ActivityAdjustedCorrectionFactor(
                    mgdlPerUnit: withActivity.value,
                    confidence: withActivity.confidence,
                    dataPointCount: withActivity.dataPointCount
                )
            }
        }

        let result = BolusCalculator.calculate(
            carbsGrams: carbsGrams,
            currentGlucoseMgdl: latestReading.mgdl,
            glucoseReadingTimestamp: latestReading.timestamp,
            now: now,
            settings: settings,
            profile: activeProfile,
            recentBolusDoses: recentBolusDoses,
            allBolusDosesForIOB: allBolusDosesForIOB,
            activityAdjustedCorrectionFactor: activityAdjustedFactor
        )
        viewResult = .calculation(result)
    }
}

#Preview {
    NavigationStack {
        BolusSuggestionView()
    }
}
