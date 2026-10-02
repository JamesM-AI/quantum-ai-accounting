import SwiftUI
import SwiftData
import GlucoseCore
import GlucoseAnalytics

struct DashboardView: View {
    // `@Query` can't easily express "readings from the last N hours" with a
    // `#Predicate` built against `Date()` (predicates are evaluated lazily/
    // repeatedly and a captured `Date()` would go stale), so we fetch sorted
    // descending and slice the recent window in computed properties instead.
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var allReadings: [GlucoseReading]
    @Query private var settingsRows: [UserSettings]

    private var settings: UserSettings? { settingsRows.first }
    private var targetLow: Double { settings?.targetRangeLowMgdl ?? 70 }
    private var targetHigh: Double { settings?.targetRangeHighMgdl ?? 180 }
    private var glucoseUnit: GlucoseUnit { settings?.glucoseUnit ?? .mgdl }

    private var latestReading: GlucoseReading? { allReadings.first }

    private var chartReadings: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-6 * 60 * 60)
        return allReadings.filter { $0.timestamp >= cutoff }
    }

    private var last24HoursTIR: TIRResult {
        let interval = DateInterval(start: Date().addingTimeInterval(-24 * 60 * 60), end: Date())
        return TimeInRangeCalculator.compute(
            readings: allReadings,
            targetLow: targetLow,
            targetHigh: targetHigh,
            over: interval
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentReadingSection

                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 6 Hours")
                        .font(.headline)
                    GlucoseTrendChartView(
                        readings: chartReadings,
                        targetLow: targetLow,
                        targetHigh: targetHigh,
                        unit: glucoseUnit
                    )
                }

                TimeInRangeCardView(tir: last24HoursTIR, title: "Last 24 Hours")
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    @ViewBuilder
    private var currentReadingSection: some View {
        if let reading = latestReading {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(GlucoseFormatting.valueString(mgdl: reading.mgdl, unit: glucoseUnit))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Image(systemName: trendSymbol(for: reading.trend))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(GlucoseFormatting.unitLabel(glucoseUnit))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text("Updated \(reading.timestamp.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No glucose readings yet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Readings will appear here once HealthKit or Dexcom sync completes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trendSymbol(for trend: GlucoseTrend?) -> String {
        switch trend {
        case .rapidRise: return "arrow.up"
        case .rising: return "arrow.up.right"
        case .flat: return "arrow.right"
        case .falling: return "arrow.down.right"
        case .rapidFall: return "arrow.down"
        case .unknown, .none: return "questionmark"
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
}
