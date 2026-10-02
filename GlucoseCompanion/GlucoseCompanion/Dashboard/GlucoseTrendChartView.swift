import SwiftUI
import Charts
import GlucoseCore

/// Pure, data-in view: the caller decides which readings and target range to
/// show (recent window on the Dashboard, but reusable/previewable anywhere)
/// rather than this view querying SwiftData itself.
struct GlucoseTrendChartView: View {
    let readings: [GlucoseReading]
    let targetLow: Double
    let targetHigh: Double
    var unit: GlucoseUnit = .mgdl

    private var chronological: [GlucoseReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    private var yDomain: ClosedRange<Double> {
        let values = chronological.map(\.mgdl)
        let lowerBound = min(50, targetLow, values.min() ?? targetLow)
        let upperBound = max(220, targetHigh, values.max() ?? targetHigh)
        return lowerBound...upperBound
    }

    var body: some View {
        Chart {
            // Shaded target-range band. Omitting xStart/xEnd makes this span
            // the full plotted x-domain, which is how Swift Charts expects a
            // reference-range band to be drawn.
            RectangleMark(
                yStart: .value("Target Low", targetLow),
                yEnd: .value("Target High", targetHigh)
            )
            .foregroundStyle(.green.opacity(0.12))

            ForEach(chronological, id: \.id) { reading in
                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.mgdl)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            ForEach(chronological, id: \.id) { reading in
                PointMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.mgdl)
                )
                .foregroundStyle(colorFor(reading.mgdl))
                .symbolSize(20)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            // The chart's underlying data/domain always stays in mg/dL;
            // only the tick label text is converted for display.
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let mgdl = value.as(Double.self) {
                        Text(GlucoseFormatting.valueString(mgdl: mgdl, unit: unit))
                    }
                }
            }
        }
        .frame(height: 220)
    }

    /// Clinical extremes (<54 / >250 mg/dL) get a red highlight regardless of
    /// the user's configurable target range; mild out-of-range gets amber.
    private func colorFor(_ mgdl: Double) -> Color {
        if mgdl < 54 || mgdl > 250 {
            return .red
        }
        if mgdl < targetLow || mgdl > targetHigh {
            return .orange
        }
        return .blue
    }
}

#Preview {
    GlucoseTrendChartView(
        readings: [
            GlucoseReading(timestamp: .now.addingTimeInterval(-3600 * 3), mgdl: 110, source: .healthKit),
            GlucoseReading(timestamp: .now.addingTimeInterval(-3600 * 2), mgdl: 145, source: .healthKit),
            GlucoseReading(timestamp: .now.addingTimeInterval(-3600 * 1), mgdl: 210, source: .healthKit),
            GlucoseReading(timestamp: .now, mgdl: 165, source: .healthKit)
        ],
        targetLow: 70,
        targetHigh: 180
    )
    .padding()
}
