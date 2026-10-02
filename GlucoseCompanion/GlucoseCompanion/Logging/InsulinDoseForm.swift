import SwiftUI
import SwiftData
import GlucoseCore

/// Presented as a sheet from `LogEntryView`; see `CarbEntryForm` for why this
/// wraps its own `NavigationStack`.
struct InsulinDoseForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var unitsText: String = ""
    // Defaults to bolus: that's what a person manually logs most often
    // (basal is usually a fixed daily/pump-managed dose).
    @State private var reason: InsulinDeliveryReason = .bolus
    @State private var timestamp: Date = Date()

    private var units: Double? { Double(unitsText) }

    private var canSave: Bool {
        guard let units else { return false }
        return units > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Insulin") {
                    HStack {
                        TextField("Units", text: $unitsText)
                            .keyboardType(.decimalPad)
                        Text("u")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Reason", selection: $reason) {
                        Text("Bolus").tag(InsulinDeliveryReason.bolus)
                        Text("Basal").tag(InsulinDeliveryReason.basal)
                    }
                    .pickerStyle(.segmented)
                }

                Section("When") {
                    DatePicker("Time", selection: $timestamp, in: ...Date())
                }
            }
            .navigationTitle("Log Insulin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let units else { return }
        let dose = InsulinDose(
            timestamp: timestamp,
            units: units,
            reason: reason,
            source: .manualInApp
        )
        modelContext.insert(dose)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    InsulinDoseForm()
}
