import SwiftUI
import GlucoseAnalytics

/// Compact time-in-range summary. Takes a plain `TIRResult` so it can be
/// reused anywhere a banded breakdown is needed (Dashboard, per-block trends).
struct TimeInRangeCardView: View {
    let tir: TIRResult
    var title: String = "Time in Range"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(percentString(tir.inRangePercent))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("% in range")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            stackedBar

            HStack(spacing: 4) {
                bandLabel("Very Low", tir.veryLowPercent, .red)
                bandLabel("Low", tir.lowPercent, .orange)
                bandLabel("In Range", tir.inRangePercent, .green)
                bandLabel("High", tir.highPercent, .orange)
                bandLabel("Very High", tir.veryHighPercent, .red)
            }

            // Sparse sensor data should never look as authoritative as a
            // full day of readings, so coverage is always shown alongside
            // the percentages, not hidden behind a tap or tooltip.
            Text("\(percentString(tir.coveragePercent))% sensor coverage (\(tir.readingCount) of \(tir.expectedReadingCount) expected readings)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var stackedBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                segment(tir.veryLowPercent, color: .red.opacity(0.85), width: proxy.size.width)
                segment(tir.lowPercent, color: .orange.opacity(0.6), width: proxy.size.width)
                segment(tir.inRangePercent, color: .green, width: proxy.size.width)
                segment(tir.highPercent, color: .orange.opacity(0.6), width: proxy.size.width)
                segment(tir.veryHighPercent, color: .red.opacity(0.85), width: proxy.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 14)
    }

    private func segment(_ percent: Double, color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width * CGFloat(percent) / 100))
    }

    private func bandLabel(_ name: String, _ percent: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(percentString(percent))
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

#Preview {
    TimeInRangeCardView(
        tir: TIRResult(
            veryLowPercent: 2,
            lowPercent: 6,
            inRangePercent: 68,
            highPercent: 20,
            veryHighPercent: 4,
            readingCount: 250,
            expectedReadingCount: 288,
            coveragePercent: 87
        )
    )
    .padding()
}
