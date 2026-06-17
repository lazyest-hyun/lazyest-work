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

public enum MeetingNotificationPolicy {
    public static func shouldSuppressNotifications<Event: FocusEventRepresentable>(
        events: [Event],
        at date: Date
    ) -> Bool {
        MeetingFocusPolicy.desiredState(
            events: events,
            now: date,
            isEnabled: true
        ) != .inactive
    }
}

public struct TeamsPresenceSetRequest: Equatable {
    public let sessionID: String
    public let availability: String
    public let activity: String
    public let expirationDuration: String
    public let expiresAt: Date
}

public struct TeamsManagedPresenceSession: Codable, Equatable {
    public let eventID: String
    public let sessionID: String
    public let userID: String
    public let expiresAt: Date

    public init(eventID: String, sessionID: String, userID: String, expiresAt: Date) {
        self.eventID = eventID
        self.sessionID = sessionID
        self.userID = userID
        self.expiresAt = expiresAt
    }
}

public enum TeamsPresencePolicy {
    public static let graphMinimumDurationMinutes = 5
    public static let graphMaximumDurationMinutes = 240

    public static func desiredState<Event: FocusEventRepresentable>(
        events: [Event],
        now: Date,
        isEnabled: Bool
    ) -> MeetingFocusState {
        MeetingFocusPolicy.desiredState(events: events, now: now, isEnabled: isEnabled)
    }

    public static func setPresenceRequest(
        sessionID: String,
        until end: Date,
        now: Date
    ) -> TeamsPresenceSetRequest {
        let remainingMinutes = Int(ceil(max(0, end.timeIntervalSince(now)) / 60))
        let clampedMinutes = min(
            max(remainingMinutes, graphMinimumDurationMinutes),
            graphMaximumDurationMinutes
        )
        return TeamsPresenceSetRequest(
            sessionID: sessionID,
            availability: "Busy",
            activity: "InAConferenceCall",
            expirationDuration: graphDuration(minutes: clampedMinutes),
            expiresAt: now.addingTimeInterval(TimeInterval(clampedMinutes * 60))
        )
    }

    public static func shouldRefreshManagedPresence(
        eventID: String,
        managedSession: TeamsManagedPresenceSession?,
        now: Date,
        refreshLeadSeconds: TimeInterval = 300
    ) -> Bool {
        guard let managedSession,
              managedSession.eventID == eventID else {
            return true
        }
        return managedSession.expiresAt.timeIntervalSince(now) <= refreshLeadSeconds
    }

    public static func managedSession(
        eventID: String,
        request: TeamsPresenceSetRequest,
        userID: String
    ) -> TeamsManagedPresenceSession {
        TeamsManagedPresenceSession(
            eventID: eventID,
            sessionID: request.sessionID,
            userID: userID,
            expiresAt: request.expiresAt
        )
    }

    private static func graphDuration(minutes: Int) -> String {
        if minutes == graphMaximumDurationMinutes {
            return "PT4H"
        }
        return "PT\(minutes)M"
    }
}

public enum FocusStatusParser {
    public static func parse(_ output: String) -> Bool? {
        let normalized = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty {
            return false
        }
        if normalized.contains("방해금지") {
            return true
        }
        if ["true", "on", "enabled", "active", "1", "yes"].contains(normalized) {
            return true
        }
        if ["false", "off", "disabled", "inactive", "0", "no"].contains(normalized) {
            return false
        }
        let tokens = Set(
            normalized.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        )
        let activeTokens: Set<String> = ["true", "on", "enabled", "active", "1", "yes"]
        let inactiveTokens: Set<String> = ["false", "off", "disabled", "inactive", "0", "no"]
        let hasActiveToken = !tokens.isDisjoint(with: activeTokens)
        let hasInactiveToken = !tokens.isDisjoint(with: inactiveTokens)
        if hasActiveToken != hasInactiveToken {
            return hasActiveToken
        }
        return nil
    }
}
