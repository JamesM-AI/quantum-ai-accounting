import Foundation

/// A coarse activity-level bucket used to group meal/dose events by how much
/// the person was moving around them. See `ActivityContextBuilder` for the
/// (deliberately simple, heuristic) classification thresholds.
public enum ActivityBucket: String, Sendable, CaseIterable, Codable {
    case sedentary
    case lightlyActive
    case active

    public var displayName: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .lightlyActive: return "Lightly Active"
        case .active: return "Active"
        }
    }
}
