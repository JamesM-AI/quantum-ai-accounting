import SwiftUI
import SwiftData
import GlucoseCore

/// Presented as a sheet from `LogEntryView`, so it wraps its own
/// `NavigationStack` (a modal presentation is a separate navigation context
/// from the tab's stack) to get a title and toolbar.
struct CarbEntryForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var gramsText: String = ""
    @State private var note: String = ""
    @State private var timestamp: Date = Date()

    private var grams: Double? { Double(gramsText) }

    private var canSave: Bool {
        guard let grams else { return false }
        return grams > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Carbs") {
                    HStack {
                        TextField("Grams", text: $gramsText)
                            .keyboardType(.decimalPad)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                    TextField("Note (optional)", text: $note)
                }

                Section("When") {
                    // Meals are logged after the fact; disallow future
                    // timestamps since this records something that happened.
                    DatePicker("Time", selection: $timestamp, in: ...Date())
                }
            }
            .navigationTitle("Log Carbs")
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
        guard let grams else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = CarbEntry(
            timestamp: timestamp,
            grams: grams,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            source: .manualInApp
        )
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CarbEntryForm()
}
