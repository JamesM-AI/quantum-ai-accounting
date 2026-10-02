import SwiftUI
import SwiftData
import GlucoseCore
import GlucoseAnalytics

struct DayBlockBreakdownView: View {
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var allReadings: [GlucoseReading]
    @Query private var blocks: [TimeOfDayProfile]
    @Query private var settingsRows: [UserSettings]

    private var settings: UserSettings? { settingsRows.first }
    private var glucoseUnit: GlucoseUnit { settings?.glucoseUnit ?? .mgdl }

    private static let analysisWindowDays = 14

    private var stats: [DayBlockStats] {
        let interval = DateInterval(
            start: Date().addingTimeInterval(-Double(Self.analysisWindowDays) * 24 * 60 * 60),
            end: Date()
        )
        return DayBlockBreakdown.breakdown(
            readings: allReadings,
            blocks: blocks,
            targetLow: settings?.targetRangeLowMgdl ?? 70,
            targetHigh: settings?.targetRangeHighMgdl ?? 180,
            over: interval
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day Block Breakdown")
                        .font(.headline)
                    Text("Trailing \(Self.analysisWindowDays) days, split by time-of-day block.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(stats, id: \.blockName) { block in
                    blockCard(block)
                }
            }
            .padding()
        }
    }

    private func blockCard(_ block: DayBlockStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(block.blockName)
                    .font(.title3.bold())
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Avg \(GlucoseFormatting.readingString(mgdl: block.averageMgdl, unit: glucoseUnit))")
                        .font(.subheadline)
                    Text("CV \(String(format: "%.0f", block.coefficientOfVariationPercent))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TimeInRangeCardView(tir: block.tir, title: "")
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        DayBlockBreakdownView()
    }
}
