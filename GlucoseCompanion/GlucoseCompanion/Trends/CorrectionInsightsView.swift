import SwiftUI
import SwiftData
import GlucoseCore
import RatioLearning
import CorrectionLearning

/// Shows patterns in standalone correction doses (not tied to a meal) split
/// by whether activity followed, plus the learned activity-adjusted
/// correction sensitivity that feeds `BolusSuggestionView`'s "I plan to be
/// active after this" toggle.
///
/// Scope boundary: like `ActivityTrendView`, this is informational/trend-only
/// -- it never feeds back into `BolusCalculator` itself (the toggle on the
/// Bolus screen builds its own copy of this same pipeline). The safety
/// banner at the top is not a footnote: exercising soon after a correction
/// carries real risk (residual insulin on board, or exercising at a very
/// high glucose with ketones), so it's the first thing on screen, always
/// visible, never collapsed behind a disclosure or a scroll.
struct CorrectionInsightsView: View {
    @Query private var insulinDoses: [InsulinDose]
    @Query private var carbEntries: [CarbEntry]
    @Query private var glucoseReadings: [GlucoseReading]
    @Query private var stepSamples: [StepSample]
    @Query private var workouts: [WorkoutSession]
    @Query private var settingsRows: [UserSettings]

    private var settings: UserSettings? { settingsRows.first }
    private var glucoseUnit: GlucoseUnit { settings?.glucoseUnit ?? .mgdl }

    @State private var withActivityEvents: [CorrectionEvent] = []
    @State private var withoutActivityEvents: [CorrectionEvent] = []
    @State private var sensitivity = CorrectionSensitivityEstimate(withActivity: nil, withoutActivity: nil)
    @State private var activityTarget = ActivityTargetSuggestion(medianSuccessfulSteps: nil, sampleCount: 0)

    /// Same rationale as `ActivityTrendView.dataFingerprint`: this pipeline
    /// re-runs meal-event matching (O(carbs x boluses)) plus correction-event
    /// extraction and two more regressions -- expensive enough that it must
    /// only run when the underlying data actually changes, not on every
    /// SwiftUI render.
    private var dataFingerprint: String {
        "\(carbEntries.count)-\(insulinDoses.count)-\(glucoseReadings.count)-\(stepSamples.count)-\(workouts.count)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                safetyBanner

                VStack(alignment: .leading, spacing: 4) {
                    Text("Correction & Activity Insights")
                        .font(.headline)
                    Text("Patterns from your own standalone correction doses -- not tied to a meal. This is informational only; it does not tell you what to do.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                outcomesSection

                Divider()

                sensitivitySection

                Divider()

                activityTargetSection

                Divider()

                Text("This only reflects standalone corrections -- doses given without accompanying carbs. The Bolus screen's \"I plan to be active after this\" toggle uses the same learned \"with activity\" sensitivity shown above.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .task(id: dataFingerprint) {
            recompute()
        }
    }

    private func recompute() {
        guard let settings else {
            withActivityEvents = []
            withoutActivityEvents = []
            sensitivity = CorrectionSensitivityEstimate(withActivity: nil, withoutActivity: nil)
            activityTarget = ActivityTargetSuggestion(medianSuccessfulSteps: nil, sampleCount: 0)
            return
        }

        let mealEvents = MealExcursionMatcher.extractEvents(
            carbEntries: carbEntries,
            insulinDoses: insulinDoses,
            glucoseReadings: glucoseReadings
        )
        let correctionEvents = CorrectionEventExtractor.extractEvents(
            insulinDoses: insulinDoses,
            glucoseReadings: glucoseReadings,
            stepSamples: stepSamples,
            workouts: workouts,
            mealEvents: mealEvents,
            targetRangeLowMgdl: settings.targetRangeLowMgdl,
            targetRangeHighMgdl: settings.targetRangeHighMgdl,
            lowGlucoseSafetyFloorMgdl: settings.lowGlucoseSafetyFloorMgdl,
            insulinActionDurationMinutes: settings.insulinActionDurationMinutes
        )

        withActivityEvents = correctionEvents.filter { $0.stepsAfterWindow > 0 || $0.hadWorkoutAfter }
        withoutActivityEvents = correctionEvents.filter { !($0.stepsAfterWindow > 0 || $0.hadWorkoutAfter) }
        sensitivity = CorrectionSensitivityEstimator.estimate(
            events: correctionEvents,
            targetMidpointMgdl: settings.targetMidpointMgdl
        )
        activityTarget = ActivityTargetEstimator.suggest(events: correctionEvents)
    }

    // MARK: - Safety banner

    // Deliberately its own visually distinct, always-on section at the very
    // top -- not a caption under a chart, not something a disclosure can
    // hide. See the type-level doc comment for why.
    private var safetyBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before being active after a correction")
                    .font(.subheadline.bold())
                Text("Do not exercise if your glucose is very high and you have ketones, or if you feel unwell -- this can be dangerous. Check ketones if your glucose is very high, and follow your care team's guidance on when it's safe to be active after a high. This screen shows patterns from your own data; it is not medical advice.")
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.red.opacity(0.4), lineWidth: 1)
        )
        .foregroundStyle(.primary)
    }

    // MARK: - Outcomes

    private var outcomesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Correction Outcomes")
                .font(.headline)
            outcomeGroup(title: "With activity after", events: withActivityEvents)
            outcomeGroup(title: "Without activity after", events: withoutActivityEvents)
        }
    }

    private func outcomeGroup(title: String, events: [CorrectionEvent]) -> some View {
        let counts = OutcomeCounts(events: events)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            if events.isEmpty {
                Text("Not enough data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                outcomeBar(counts: counts)
                Text(counts.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outcomeBar(counts: OutcomeCounts) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(counts.segments.enumerated()), id: \.offset) { _, segment in
                    segment.color
                        .frame(width: geometry.size.width * segment.fraction)
                }
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Sensitivity

    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Learned Correction Sensitivity")
                .font(.headline)
            sensitivityRow(title: "With activity after", estimate: sensitivity.withActivity)
            sensitivityRow(title: "Without activity after", estimate: sensitivity.withoutActivity)
        }
    }

    private func sensitivityRow(title: String, estimate: RatioEstimate?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
            if let estimate {
                Text("\(GlucoseFormatting.perUnitValueString(mgdlPerUnit: estimate.value, unit: glucoseUnit)) \(GlucoseFormatting.perUnitLabel(glucoseUnit))")
                    .font(.subheadline.bold())
                Text("\(estimate.dataPointCount) corrections \u{00B7} \(confidenceLabel(estimate.confidence)) confidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not enough data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Activity target

    // Framed descriptively ("has tended to"), not prescriptively -- this is
    // a pattern observed in the person's own past data, not a suggested
    // workout plan. Deliberately avoids "should"/"recommended".
    private var activityTargetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity Pattern")
                .font(.headline)
            if let medianSteps = activityTarget.medianSuccessfulSteps {
                Text("Based on \(activityTarget.sampleCount) of your own corrections, about \(medianSteps) steps of activity afterward has tended to bring you back into range without going low.")
                    .font(.caption)
            } else {
                Text("Only \(activityTarget.sampleCount) data point(s) so far -- keep logging corrections and any activity afterward to build this up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
}

/// Tally of `CorrectionOutcome` values for one group of events (with/without
/// activity), plus the proportional bar segments to render it. Kept as a
/// plain local helper (not part of `CorrectionLearning`) since it's purely a
/// display concern over that package's data.
private struct OutcomeCounts {
    let successful: Int
    let overcorrected: Int
    let undercorrected: Int
    let indeterminate: Int

    init(events: [CorrectionEvent]) {
        successful = events.filter { $0.outcome == .successful }.count
        overcorrected = events.filter { $0.outcome == .overcorrected }.count
        undercorrected = events.filter { $0.outcome == .undercorrected }.count
        indeterminate = events.filter { $0.outcome == .indeterminate }.count
    }

    var total: Int { successful + overcorrected + undercorrected + indeterminate }

    struct Segment {
        let fraction: Double
        let color: Color
    }

    var segments: [Segment] {
        guard total > 0 else { return [] }
        let denominator = Double(total)
        return [
            Segment(fraction: Double(successful) / denominator, color: .green),
            Segment(fraction: Double(undercorrected) / denominator, color: .orange),
            Segment(fraction: Double(overcorrected) / denominator, color: .red),
            Segment(fraction: Double(indeterminate) / denominator, color: .gray)
        ]
    }

    var summaryText: String {
        var parts: [String] = []
        if successful > 0 { parts.append("\(successful) successful") }
        if overcorrected > 0 { parts.append("\(overcorrected) overcorrected") }
        if undercorrected > 0 { parts.append("\(undercorrected) undercorrected") }
        if indeterminate > 0 { parts.append("\(indeterminate) indeterminate") }
        return "\(parts.joined(separator: ", ")), out of \(total)"
    }
}

#Preview {
    NavigationStack {
        CorrectionInsightsView()
    }
}
