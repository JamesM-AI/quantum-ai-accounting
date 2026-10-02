import SwiftUI
import GlucoseCore

/// Editor for the numeric fields that drive both display (target range) and
/// dosing safety (max bolus, DIA, IOB model, low-glucose floor). Reused both
/// as an onboarding step and embedded directly in `SettingsView` -- callers
/// pass the `UserSettings` row to edit and, optionally, a completion closure.
///
/// Body is a bare sequence of `Section`s rather than its own `Form` (SwiftUI's
/// `View.body` is an implicit `@ViewBuilder`, so multiple top-level `Section`s
/// are legal and flatten correctly into whichever `Form`/`List` the caller
/// provides) -- that lets `SettingsView` fold these sections directly into
/// its own `Form` instead of nesting one `Form` inside another. Full-screen
/// callers (onboarding) wrap it in their own `Form`.
///
/// `isConfigured` is only ever set `true` here, and only once this view's own
/// validation passes -- it is the single gate the bolus calculator checks
/// before it will produce a suggestion, so it must never flip true on
/// unvalidated or default (zeroed) values.
struct TargetRangeSettingsView: View {
    @Bindable var settings: UserSettings
    var onSave: (() -> Void)? = nil

    @State private var lowText: String = ""
    @State private var highText: String = ""
    @State private var maxBolusText: String = ""
    @State private var diaText: String = ""
    @State private var floorText: String = ""
    @State private var iobModel: IOBModelType = .exponential
    @State private var didLoad = false

    var body: some View {
        Group {
            Section {
                Text("These values are used to size bolus suggestions and to flag out-of-range readings. Confirm them with your endocrinologist or diabetes care team before relying on them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Display Unit") {
                Picker("Glucose unit", selection: $settings.glucoseUnit) {
                    Text("mg/dL").tag(GlucoseUnit.mgdl)
                    Text("mmol/L").tag(GlucoseUnit.mmolL)
                }
                .pickerStyle(.segmented)
                Text("Changes how glucose values are displayed throughout the app. The values you enter below stay in mg/dL regardless of this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Target Glucose Range (mg/dL)") {
                LabeledContent("Low") {
                    TextField("70", text: $lowText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("High") {
                    TextField("180", text: $highText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                if let message = rangeValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Low Glucose Safety Floor (mg/dL)") {
                TextField("80", text: $floorText)
                    .keyboardType(.numberPad)
                if let message = floorValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("The bolus calculator always refuses to suggest a dose at or below this floor, regardless of your target range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Maximum Bolus Dose") {
                LabeledContent("Units") {
                    TextField("e.g. 10", text: $maxBolusText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                if let message = maxBolusValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("A hard ceiling: no suggestion will ever exceed this, no matter what the calculation produces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Insulin Action") {
                LabeledContent("Duration (minutes)") {
                    TextField("240", text: $diaText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                if let message = diaValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Insulin-on-board model", selection: $iobModel) {
                    Text("Bilinear").tag(IOBModelType.bilinear)
                    Text("Exponential").tag(IOBModelType.exponential)
                }
            }

            Section {
                Button(action: save) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        lowText = Self.format(settings.targetRangeLowMgdl)
        highText = Self.format(settings.targetRangeHighMgdl)
        maxBolusText = settings.maxBolusUnits > 0 ? Self.format(settings.maxBolusUnits) : ""
        diaText = String(settings.insulinActionDurationMinutes)
        floorText = Self.format(settings.lowGlucoseSafetyFloorMgdl)
        iobModel = settings.iobModel
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }

    // MARK: - Parsed values

    private var low: Double? { Double(lowText) }
    private var high: Double? { Double(highText) }
    private var maxBolus: Double? { Double(maxBolusText) }
    private var dia: Int? { Int(diaText) }
    private var floor: Double? { Double(floorText) }

    // MARK: - Validation

    private var rangeValidationMessage: String? {
        guard let low, let high else { return "Enter both a low and a high value." }
        guard low < high else { return "The low value must be less than the high value." }
        return nil
    }

    private var floorValidationMessage: String? {
        guard let floor else { return "Enter a low glucose safety floor." }
        guard let low else { return nil }
        guard floor <= low else { return "The safety floor must be at or below your target range low." }
        return nil
    }

    private var maxBolusValidationMessage: String? {
        guard let maxBolus else { return "Enter a maximum bolus dose." }
        guard maxBolus > 0 else { return "The maximum bolus dose must be greater than zero." }
        return nil
    }

    private var diaValidationMessage: String? {
        guard let dia else { return "Enter an insulin action duration." }
        guard dia > 0 else { return "Insulin action duration must be greater than zero." }
        return nil
    }

    private var isValid: Bool {
        rangeValidationMessage == nil
            && floorValidationMessage == nil
            && maxBolusValidationMessage == nil
            && diaValidationMessage == nil
    }

    // MARK: - Save

    private func save() {
        guard isValid,
              let low, let high, let maxBolus, let dia, let floor else { return }

        settings.targetRangeLowMgdl = low
        settings.targetRangeHighMgdl = high
        settings.maxBolusUnits = maxBolus
        settings.insulinActionDurationMinutes = dia
        settings.lowGlucoseSafetyFloorMgdl = floor
        settings.iobModel = iobModel
        settings.isConfigured = true

        onSave?()
    }
}
