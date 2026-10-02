import SwiftUI
import SwiftData
import Charts
import GlucoseCore
import RatioLearning
import ActivityInsights

/// Shows how logged activity (steps) around meals relates to the glucose
/// response seen afterward.
///
/// Scope boundary: this view is informational/trend-only. It never feeds
/// into `BolusCalculator` and nothing here should read as dosing guidance --
/// the numbers shown are "here's what your data shows," not "here's what to
/// do about it."
struct ActivityTrendView: View {
    @Query private var carbEntries: [CarbEntry]
    @Query private var insulinDoses: [InsulinDose]
    @Query private var glucoseReadings: [GlucoseReading]
    @Query private var stepSamples: [StepSample]
    @Query private var workouts: [WorkoutSession]
    @Query private var settingsRows: [UserSettings]

    private var settings: UserSettings? { settingsRows.first }
    private var glucoseUnit: GlucoseUnit { settings?.glucoseUnit ?? .mgdl }

    @State private var chartPoints: [ActivityGlucosePoint] = []
    @State private var activityProfiles: [ActivityAdjustedProfile] = []

    /// A cheap proxy for "has the underlying data changed." Rebuilding
    /// `chartPoints`/`activityProfiles` means re-running meal-event matching
    /// -- an O(carbs x boluses) scan over the person's full history -- plus
    /// two regressions. Doing that as bare computed properties referenced
    /// from `body` re-ran the whole pipeline on every SwiftUI render,
    /// including ones triggered by completely unrelated state changes (e.g.
    /// a background HealthKit sync completing while this tab happened to be
    /// visible). `.task(id:)` below only recomputes when this fingerprint
    /// actually changes. Row counts are an imprecise signal -- an in-place
    /// edit with no count change wouldn't trigger a refresh -- but match
    /// this app's actual usage (almost all writes are appends) without
    /// needing a real versioning scheme.
    private var dataFingerprint: String {
        "\(carbEntries.count)-\(insulinDoses.count)-\(glucoseReadings.count)-\(stepSamples.count)-\(workouts.count)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity & Glucose Response")
                        .font(.headline)
                    Text("How does your activity relate to your glucose response? This is informational only -- it does not change your bolus suggestions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                chart
                    .frame(height: 260)

                Text("Faded points are excluded from any statistics -- they overlap a workout or other confounding event, so their glucose response can't be attributed to steps alone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("By Activity Level")
                        .font(.headline)
                    ForEach(ActivityBucket.allCases, id: \.self) { bucket in
                        bucketRow(bucket)
                    }
                }
            }
            .padding()
        }
        .task(id: dataFingerprint) {
            recompute()
        }
    }

    private func recompute() {
        let mealEvents = MealExcursionMatcher.extractEvents(
            carbEntries: carbEntries,
            insulinDoses: insulinDoses,
            glucoseReadings: glucoseReadings,
            excludeWindows: workouts.map(\.interval)
        )
        let contexts = ActivityContextBuilder.buildContexts(mealEvents: mealEvents, stepSamples: stepSamples)
        chartPoints = ActivityTrendBuilder.buildPoints(contexts: contexts).filter { $0.glucoseExcursionMgdl != nil }
        activityProfiles = ActivityAdjustedRatioEstimator.estimate(
            contexts: contexts,
            targetMidpointMgdl: settings?.targetMidpointMgdl ?? 125
        )
    }

    private var chart: some View {
        Chart {
            ForEach(Array(chartPoints.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Steps", point.combinedSteps),
                    y: .value("Glucose Rise", point.glucoseExcursionMgdl ?? 0)
                )
                .foregroundStyle(.blue)
                .opacity(point.isConfounded ? 0.3 : 1.0)
            }
        }
        .chartXAxisLabel("Steps around meal")
        .chartYAxisLabel("Glucose rise")
        .chartYAxis {
            // The underlying value is a glucose-rise delta in mg/dL; the same
            // mg/dL<->unit conversion used for absolute readings applies to a
            // delta just as well, so tick labels are formatted the same way.
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let mgdl = value.as(Double.self) {
                        Text(GlucoseFormatting.valueString(mgdl: mgdl, unit: glucoseUnit))
                    }
                }
            }
        }
    }

    private func bucketRow(_ bucket: ActivityBucket) -> some View {
        let profile = activityProfiles.first(where: { $0.bucket == bucket })

        return VStack(alignment: .leading, spacing: 4) {
            Text(bucket.displayName)
                .font(.subheadline.bold())

            if profile?.carbRatio == nil && profile?.correctionFactor == nil {
                Text("Not enough data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    if let carbRatio = profile?.carbRatio {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(String(format: "%.1f", carbRatio.value)) g/u")
                                .font(.subheadline)
                            Text("\(carbRatio.dataPointCount) meals \u{00B7} \(confidenceLabel(carbRatio.confidence))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let correctionFactor = profile?.correctionFactor {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(GlucoseFormatting.perUnitValueString(mgdlPerUnit: correctionFactor.value, unit: glucoseUnit)) \(GlucoseFormatting.perUnitLabel(glucoseUnit))")
                                .font(.subheadline)
                            Text("\(correctionFactor.dataPointCount) meals \u{00B7} \(confidenceLabel(correctionFactor.confidence))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func confidenceLabel(_ confidence: ConfidenceLevel) -> String {
        switch confidence {
        case .insufficientData: return "insufficient data"
        case .low: return "low confidence"
        case .medium: return "medium confidence"
        case .high: return "high confidence"
        }
    }
}

#Preview {
    NavigationStack {
        ActivityTrendView()
    }
}
