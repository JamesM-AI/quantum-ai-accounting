import Foundation
import RatioLearning

/// Pairs a `MealEvent` (from `RatioLearning`) with the step-count activity
/// surrounding it, so it can be grouped by `ActivityBucket` for trend display.
///
/// This type carries no glucose-affecting logic of its own -- it is purely a
/// join of "what happened with this meal/dose" (`mealEvent`) and "how much
/// was the person moving around it" (the step totals below). See
/// `ActivityContextBuilder` for how these are computed.
public struct MealActivityContext: Sendable {
    public let mealEvent: MealEvent

    /// Steps in the window immediately before the meal/dose (default 2h).
    public let stepsBeforeWindow: Int

    /// Steps in the window immediately after (default 2h) -- this is the
    /// window most directly relevant to how activity affects glucose
    /// absorption/insulin action in the following hours.
    public let stepsAfterWindow: Int

    /// Total steps for the full calendar day the event falls on -- a
    /// coarser "how active was this whole day" signal, shown for context
    /// but NOT used to classify `bucket` (see `ActivityContextBuilder`).
    public let stepsBackgroundDaily: Int

    public let bucket: ActivityBucket

    public init(
        mealEvent: MealEvent,
        stepsBeforeWindow: Int,
        stepsAfterWindow: Int,
        stepsBackgroundDaily: Int,
        bucket: ActivityBucket
    ) {
        self.mealEvent = mealEvent
        self.stepsBeforeWindow = stepsBeforeWindow
        self.stepsAfterWindow = stepsAfterWindow
        self.stepsBackgroundDaily = stepsBackgroundDaily
        self.bucket = bucket
    }
}
