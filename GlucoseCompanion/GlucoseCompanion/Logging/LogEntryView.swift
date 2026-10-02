import SwiftUI
import SwiftData
import GlucoseCore

struct LogEntryView: View {
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbEntries: [CarbEntry]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulinDoses: [InsulinDose]

    @State private var showingCarbForm = false
    @State private var showingInsulinForm = false

    private enum RecentEntry: Identifiable {
        case carb(CarbEntry)
        case insulin(InsulinDose)

        var id: UUID {
            switch self {
            case .carb(let entry): return entry.id
            case .insulin(let dose): return dose.id
            }
        }

        var timestamp: Date {
            switch self {
            case .carb(let entry): return entry.timestamp
            case .insulin(let dose): return dose.timestamp
            }
        }
    }

    private var recentEntries: [RecentEntry] {
        let combined: [RecentEntry] = carbEntries.map(RecentEntry.carb) + insulinDoses.map(RecentEntry.insulin)
        return Array(combined.sorted { $0.timestamp > $1.timestamp }.prefix(15))
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingCarbForm = true
                } label: {
                    Label("Log Carbs", systemImage: "fork.knife")
                }
                Button {
                    showingInsulinForm = true
                } label: {
                    Label("Log Insulin", systemImage: "syringe")
                }
            }

            Section("Recent Entries") {
                if recentEntries.isEmpty {
                    Text("Nothing logged yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentEntries) { entry in
                        recentEntryRow(entry)
                    }
                }
            }
        }
        .navigationTitle("Log")
        .sheet(isPresented: $showingCarbForm) {
            CarbEntryForm()
        }
        .sheet(isPresented: $showingInsulinForm) {
            InsulinDoseForm()
        }
    }

    private func recentEntryRow(_ entry: RecentEntry) -> some View {
        HStack {
            switch entry {
            case .carb(let carbEntry):
                Image(systemName: "fork.knife")
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Int(carbEntry.grams.rounded())) g carbs")
                    if let note = carbEntry.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .insulin(let dose):
                Image(systemName: "syringe")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                Text("\(formattedUnits(dose.units)) u \(dose.reason == .bolus ? "bolus" : "basal")")
            }
            Spacer()
            Text(entry.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedUnits(_ units: Double) -> String {
        String(format: "%.1f", units)
    }
}

#Preview {
    NavigationStack {
        LogEntryView()
    }
}
