import Foundation

/// How a standalone correction dose actually played out, classified from
/// the glucose trajectory that followed it.
public enum CorrectionOutcome: String, Sendable, Codable {
    /// Returned to target range without going below the safety floor.
    case successful
    /// Glucose fell below the low safety floor at some point during the
    /// insulin action window -- the correction (with whatever activity
    /// followed) was too aggressive for this occasion.
    case overcorrected
    /// Glucose was still above the target range at the end of the action
    /// window -- the correction (with whatever activity followed) wasn't
    /// enough.
    case undercorrected
    /// Not enough follow-up glucose data to classify either way.
    case indeterminate
}
