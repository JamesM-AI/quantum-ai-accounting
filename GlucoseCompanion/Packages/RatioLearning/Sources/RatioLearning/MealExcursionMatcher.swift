import Foundation
import GlucoseCore

/// Reconstructs `MealEvent`s from raw logged data.
///
/// The three source arrays (`CarbEntry`, `InsulinDose`, `GlucoseReading`) are
/// independent logs -- there is no stored link guaranteeing a given carb
/// entry was covered by a given bolus, or that a glucose excursion wasn't
/// caused by something else entirely (a second snack, a correction, a
/// workout). This matcher's job is purely to *pair up* plausible meal events
/// and *flag* the ones where we can't be confident the excursion reflects
/// that meal alone. It never guesses; ambiguous cases are marked
/// `isConfounded` rather than resolved one way or another.
public enum MealExcursionMatcher {

    /// How far before/after the exact 3-hour mark we'll still accept a
    /// reading as "the 3-hour reading". CGM readings land every ~5 minutes,
    /// but sensor gaps happen, so we allow some slack rather than requiring
    /// an exact hit.
    private static let threeHourToleranceSeconds: TimeInterval = 20 * 60

    private static let preWindowMinutes: TimeInterval = 15

    public static func extractEvents(
        carbEntries: [CarbEntry],
        insulinDoses: [InsulinDose],
        glucoseReadings: [GlucoseReading],
        matchWindowMinutes: Int = 20,
        postMealWindowHours: Double = 3.0,
        excludeWindows: [DateInterval] = []
    ) -> [MealEvent] {
        let boluses = insulinDoses.filter { $0.reason == .bolus }
        let pairs = matchCarbEntriesToBoluses(
            carbEntries: carbEntries,
            boluses: boluses,
            matchWindowMinutes: matchWindowMinutes
        )

        let preWindowSeconds = preWindowMinutes * 60
        let postWindowSeconds = postMealWindowHours * 3600

        return pairs.map { pair in
            let (carbEntry, bolusDose) = pair
            let eventStart = min(carbEntry.timestamp, bolusDose.timestamp)
            let preWindowStart = eventStart.addingTimeInterval(-preWindowSeconds)
            let postWindowEnd = eventStart.addingTimeInterval(postWindowSeconds)
            let analysisWindow = DateInterval(start: preWindowStart, end: postWindowEnd)

            let preGlucose = mostRecentReading(
                glucoseReadings,
                atOrBefore: eventStart,
                notBefore: preWindowStart
            )

            let postReadings = glucoseReadings.filter {
                $0.timestamp > eventStart && $0.timestamp <= postWindowEnd
            }
            let postPeak = postReadings.map(\.mgdl).max()

            let threeHourTarget = eventStart.addingTimeInterval(3 * 3600)
            let postAt3h = closestReading(
                glucoseReadings,
                to: threeHourTarget,
                tolerance: threeHourToleranceSeconds
            )

            var reasons: [String] = []

            // Rule 1: we can't learn anything without the glucose data that
            // brackets the meal -- no pre reading, or no readings at all in
            // the post-meal window, means there's nothing to regress on.
            if preGlucose == nil {
                reasons.append("No glucose reading within \(Int(preWindowMinutes)) minutes before the event")
            }
            if postPeak == nil {
                reasons.append("No glucose readings in the \(postMealWindowHours)-hour post-meal window")
            }

            // Rule 2: another carb entry or bolus landing inside this
            // event's own analysis window means the excursion can't be
            // attributed to this meal alone.
            let otherCarbIntrudes = carbEntries.contains { other in
                other.id != carbEntry.id && analysisWindow.contains(other.timestamp)
            }
            let otherBolusIntrudes = boluses.contains { other in
                other.id != bolusDose.id && analysisWindow.contains(other.timestamp)
            }
            if otherCarbIntrudes || otherBolusIntrudes {
                reasons.append("Another carb entry or bolus dose falls inside this event's analysis window")
            }

            // Rule 3: caller-supplied windows to exclude (e.g. exercise
            // derived from HealthKit workouts by the app layer -- this
            // package has no workout data of its own).
            let overlapsExcluded = excludeWindows.contains { window in
                window.intersects(analysisWindow)
            }
            if overlapsExcluded {
                reasons.append("Overlaps an excluded time window (e.g. exercise)")
            }

            return MealEvent(
                carbEntry: carbEntry,
                bolusDose: bolusDose,
                preGlucoseMgdl: preGlucose,
                postGlucosePeakMgdl: postPeak,
                postGlucoseAt3hMgdl: postAt3h,
                isConfounded: !reasons.isEmpty,
                confoundedReason: reasons.isEmpty ? nil : reasons.joined(separator: "; ")
            )
        }
    }

    /// Greedy nearest-neighbor pairing: each carb entry is matched to the
    /// closest-in-time bolus within the match window, and each bolus can be
    /// used at most once. Without the one-bolus-per-meal constraint, a
    /// single dose could get "credited" to two separate carb entries, which
    /// would double-count that dose's units as evidence in the regression.
    /// Carb entries with no bolus in range are dropped -- not every carb
    /// entry has a matched dose (e.g. a snack covered by an earlier
    /// correction bolus, or an untreated small snack).
    private static func matchCarbEntriesToBoluses(
        carbEntries: [CarbEntry],
        boluses: [InsulinDose],
        matchWindowMinutes: Int
    ) -> [(CarbEntry, InsulinDose)] {
        let windowSeconds = TimeInterval(matchWindowMinutes) * 60

        struct Candidate {
            let carbEntry: CarbEntry
            let bolus: InsulinDose
            let delta: TimeInterval
        }

        var candidates: [Candidate] = []
        for carbEntry in carbEntries {
            for bolus in boluses {
                let delta = abs(bolus.timestamp.timeIntervalSince(carbEntry.timestamp))
                if delta <= windowSeconds {
                    candidates.append(Candidate(carbEntry: carbEntry, bolus: bolus, delta: delta))
                }
            }
        }
        candidates.sort { $0.delta < $1.delta }

        var usedCarbEntryIDs = Set<UUID>()
        var usedBolusIDs = Set<UUID>()
        var result: [(CarbEntry, InsulinDose)] = []

        for candidate in candidates {
            guard !usedCarbEntryIDs.contains(candidate.carbEntry.id),
                  !usedBolusIDs.contains(candidate.bolus.id) else { continue }
            usedCarbEntryIDs.insert(candidate.carbEntry.id)
            usedBolusIDs.insert(candidate.bolus.id)
            result.append((candidate.carbEntry, candidate.bolus))
        }

        return result
    }

    private static func mostRecentReading(
        _ readings: [GlucoseReading],
        atOrBefore: Date,
        notBefore: Date
    ) -> Double? {
        readings
            .filter { $0.timestamp <= atOrBefore && $0.timestamp >= notBefore }
            .max(by: { $0.timestamp < $1.timestamp })
            .map(\.mgdl)
    }

    private static func closestReading(
        _ readings: [GlucoseReading],
        to target: Date,
        tolerance: TimeInterval
    ) -> Double? {
        readings
            .filter { abs($0.timestamp.timeIntervalSince(target)) <= tolerance }
            .min(by: { abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target)) })
            .map(\.mgdl)
    }
}
