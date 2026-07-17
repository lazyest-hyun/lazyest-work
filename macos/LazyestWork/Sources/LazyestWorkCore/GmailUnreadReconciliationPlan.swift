import Foundation

public struct GmailUnreadReconciliationPlan: Sendable {
    public enum Step: Equatable, Sendable {
        case wait(TimeInterval)
        case stopBecauseCountSettled
        case stopBecauseWindowEnded
    }

    public static let defaultObservationRetryDelays: [TimeInterval] = [2, 4, 8, 16]
    public static let defaultSettleDelay: TimeInterval = 5
    public static let defaultRequiredStableChecks = 2
    public static let defaultMaximumFollowUpChecks = 6

    private var baselineCount: Int?
    private let observationRetryDelays: [TimeInterval]
    private let settleDelay: TimeInterval
    private let requiredStableChecks: Int
    private let maximumFollowUpChecks: Int
    private var nextObservationDelayIndex = 0
    private var scheduledFollowUpChecks = 0
    private var hasObservedChange = false
    private var lastObservedCount: Int?
    private var consecutiveStableChecks = 0

    public init(
        baselineCount: Int?,
        observationRetryDelays: [TimeInterval] = defaultObservationRetryDelays,
        settleDelay: TimeInterval = defaultSettleDelay,
        requiredStableChecks: Int = defaultRequiredStableChecks,
        maximumFollowUpChecks: Int = defaultMaximumFollowUpChecks
    ) {
        self.baselineCount = baselineCount
        self.observationRetryDelays = observationRetryDelays.filter { $0 > 0 }
        self.settleDelay = max(0.1, settleDelay)
        self.requiredStableChecks = max(1, requiredStableChecks)
        self.maximumFollowUpChecks = max(1, maximumFollowUpChecks)
    }

    public mutating func nextStep(observedCount: Int?) -> Step {
        if hasObservedChange {
            guard let observedCount else {
                return scheduleFollowUp(after: settleDelay)
            }
            if observedCount == lastObservedCount {
                consecutiveStableChecks += 1
                if consecutiveStableChecks >= requiredStableChecks {
                    return .stopBecauseCountSettled
                }
            } else {
                lastObservedCount = observedCount
                consecutiveStableChecks = 0
            }
            return scheduleFollowUp(after: settleDelay)
        }

        guard let observedCount else {
            return scheduleNextObservation()
        }

        // A Gmail open can happen before the app has ever loaded a count. The
        // first successful response becomes the baseline; subsequent checks
        // still use the same bounded request budget.
        guard let baselineCount else {
            self.baselineCount = observedCount
            return scheduleNextObservation()
        }

        if observedCount != baselineCount {
            hasObservedChange = true
            lastObservedCount = observedCount
            consecutiveStableChecks = 0
            return scheduleFollowUp(after: settleDelay)
        }

        return scheduleNextObservation()
    }

    private mutating func scheduleNextObservation() -> Step {
        guard nextObservationDelayIndex < observationRetryDelays.count else {
            return .stopBecauseWindowEnded
        }
        // Keep enough of the existing seven-call budget for two settle checks
        // even when the first change arrives at the last observation attempt.
        let remainingFollowUpChecks = maximumFollowUpChecks - scheduledFollowUpChecks
        guard remainingFollowUpChecks > requiredStableChecks else {
            return .stopBecauseWindowEnded
        }

        let delay = observationRetryDelays[nextObservationDelayIndex]
        nextObservationDelayIndex += 1
        return scheduleFollowUp(after: delay)
    }

    private mutating func scheduleFollowUp(after delay: TimeInterval) -> Step {
        guard scheduledFollowUpChecks < maximumFollowUpChecks else {
            return .stopBecauseWindowEnded
        }
        scheduledFollowUpChecks += 1
        return .wait(delay)
    }
}
