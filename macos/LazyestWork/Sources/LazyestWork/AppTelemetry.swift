import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.lazyest.work"

    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let calendar = Logger(subsystem: subsystem, category: "CalendarSync")
    static let gmail = Logger(subsystem: subsystem, category: "GmailBadge")
    static let meetingFocus = Logger(subsystem: subsystem, category: "MeetingFocus")
    static let teamsCLI = Logger(subsystem: subsystem, category: "TeamsCLI")
    static let teamsPresence = Logger(subsystem: subsystem, category: "TeamsPresence")
    static let teamsGuard = Logger(subsystem: subsystem, category: "TeamsGuard")
    static let signing = Logger(subsystem: subsystem, category: "Signing")
}
