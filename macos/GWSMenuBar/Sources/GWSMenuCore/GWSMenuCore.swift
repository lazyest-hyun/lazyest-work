import Foundation

public enum CalendarStatusSemanticColor: Equatable {
    case green
    case orange
    case gray
    case red
}

public enum CalendarSelfResponseStatus: String, Equatable {
    case accepted
    case tentative
    case needsAction
    case declined
    case unknown

    public init(rawGoogleValue: String?) {
        switch rawGoogleValue {
        case "accepted":
            self = .accepted
        case "tentative":
            self = .tentative
        case "needsAction":
            self = .needsAction
        case "declined":
            self = .declined
        default:
            self = .unknown
        }
    }

    public var indicatorSemanticColor: CalendarStatusSemanticColor {
        switch self {
        case .accepted:
            return .green
        case .tentative:
            return .orange
        case .declined:
            return .red
        case .needsAction, .unknown:
            return .gray
        }
    }
}

public protocol MenuEventRepresentable {
    var id: String { get }
    var start: Date { get }
    var end: Date { get }
    var isAllDay: Bool { get }
}

public protocol FocusEventRepresentable: MenuEventRepresentable {
    var hasMeetingSignal: Bool { get }
    var selfResponseStatus: CalendarSelfResponseStatus { get }
}

public enum MenuSectionVisibility {
    public static let defaultWorkspaceColumns = 4
    public static let defaultUpcomingLimit = 8
    public static let defaultUpcomingWindowDays = 7

    public static func visibleWorkspaceIDs(
        _ ids: [String],
        isExpanded: Bool,
        columns: Int = defaultWorkspaceColumns
    ) -> [String] {
        guard !isExpanded else { return ids }
        return Array(ids.prefix(max(1, columns)))
    }

    public static func visibleUpcomingEvents<Event: MenuEventRepresentable>(
        _ events: [Event],
        now: Date,
        isExpanded: Bool,
        calendar: Calendar = .autoupdatingCurrent,
        limit: Int = defaultUpcomingLimit,
        windowDays: Int = defaultUpcomingWindowDays
    ) -> [Event] {
        let end = calendar.date(byAdding: .day, value: windowDays, to: now) ?? now.addingTimeInterval(TimeInterval(windowDays * 86_400))
        let today = calendar.dateInterval(of: .day, for: now)
        return events
            .filter { !$0.isAllDay && $0.end > now && $0.start < end }
            .filter { event in
                isExpanded || today.map { event.start < $0.end && event.end > $0.start } ?? calendar.isDate(event.start, inSameDayAs: now)
            }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }
}

public enum MeetingFocusState: Equatable {
    case inactive
    case active(until: Date, eventID: String)
}

public enum MeetingFocusPolicy {
    public static func desiredState<Event: FocusEventRepresentable>(
        events: [Event],
        now: Date,
        isEnabled: Bool
    ) -> MeetingFocusState {
        guard isEnabled else { return .inactive }
        let activeEvents = events
            .filter { !$0.isAllDay }
            .filter { $0.hasMeetingSignal }
            .filter { $0.selfResponseStatus == .accepted }
            .filter { $0.start <= now && $0.end > now }
            .sorted { lhs, rhs in
                if lhs.end == rhs.end {
                    return lhs.start < rhs.start
                }
                return lhs.end > rhs.end
            }

        guard let event = activeEvents.first else {
            return .inactive
        }
        return .active(until: event.end, eventID: event.id)
    }
}
