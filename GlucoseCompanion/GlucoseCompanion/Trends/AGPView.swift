import SwiftUI
import SwiftData
import Charts
import GlucoseCore
import GlucoseAnalytics

struct AGPView: View {
    @Query private var readings: [GlucoseReading]
    @Query private var settingsRows: [UserSettings]

    @State private var windowDays: Int = 14

    private var glucoseUnit: GlucoseUnit { settingsRows.first?.glucoseUnit ?? .mgdl }

    private var profile: AGPProfile {
        AGPAggregator.aggregate(readings: readings, windowDays: windowDays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Window", selection: $windowDays) {
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                    Text("90 Days").tag(90)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ambulatory Glucose Profile")
                        .font(.headline)
                    Text("Median (line), 25th-75th percentile (dark band), and 10th-90th percentile (light band) of glucose at each time of day, over the trailing \(windowDays) days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                chart
                    .frame(height: 280)
            }
            .padding()
        }
    }

    private var chart: some View {
        Chart {
            // Slots with no readings in the window carry `nil` percentiles;
            // skipping them here creates a visible gap in the band rather
            // than interpolating across missing data.
            ForEach(profile.slots, id: \.minuteOfDay) { slot in
                if let p10 = slot.p10, let p90 = slot.p90 {
                    AreaMark(
                        x: .value("Time", slot.minuteOfDay),
                        yStart: .value("P10", p10),
                        yEnd: .value("P90", p90)
                    )
                    .foregroundStyle(.blue.opacity(0.15))
                }
            }
            ForEach(profile.slots, id: \.minuteOfDay) { slot in
                if let p25 = slot.p25, let p75 = slot.p75 {
                    AreaMark(
                        x: .value("Time", slot.minuteOfDay),
                        yStart: .value("P25", p25),
                        yEnd: .value("P75", p75)
                    )
                    .foregroundStyle(.blue.opacity(0.32))
                }
            }
            ForEach(profile.slots, id: \.minuteOfDay) { slot in
                if let median = slot.median {
                    LineMark(
                        x: .value("Time", slot.minuteOfDay),
                        y: .value("Median", median)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartXScale(domain: 0...(24 * 60))
        .chartYScale(domain: 40...300)
        .chartXAxis {
            AxisMarks(values: .stride(by: 360)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let minute = value.as(Int.self) {
                        Text(timeLabel(minuteOfDay: minute))
                    }
                }
            }
        }
        .chartYAxis {
            // Underlying domain/data stays in mg/dL; only tick labels convert.
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

    private func timeLabel(minuteOfDay: Int) -> String {
        let normalized = ((minuteOfDay % 1440) + 1440) % 1440
        let hour24 = normalized / 60
        let period = hour24 < 12 ? "AM" : "PM"
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return "\(hour12) \(period)"
    }
}

#Preview {
    NavigationStack {
        AGPView()
    }
}
