#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/TestGWSMenuCore.swift" <<'SWIFT'
import Foundation

struct StubEvent: MenuEventRepresentable, FocusEventRepresentable {
    let id: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let hasMeetingSignal: Bool
    let selfResponseStatus: CalendarSelfResponseStatus
}

func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message)\nexpected: \(expected)\nactual: \(actual)\n", stderr)
        exit(1)
    }
}

@main
struct GWSMenuCoreBehaviorTest {
    static func main() {
        let ids = (1...9).map { "app-\($0)" }
        expectEqual(
            MenuSectionVisibility.visibleWorkspaceIDs(ids, isExpanded: false, columns: 4),
            ["app-1", "app-2", "app-3", "app-4"],
            "collapsed workspace shows one four-item row"
        )
        expectEqual(
            MenuSectionVisibility.visibleWorkspaceIDs(ids, isExpanded: true, columns: 4),
            ids,
            "expanded workspace shows all apps"
        )

        let now = date("2026-06-11T09:00:00Z")
        let today = StubEvent(id: "today", start: date("2026-06-11T10:00:00Z"), end: date("2026-06-11T10:30:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .accepted)
        let overnight = StubEvent(id: "overnight", start: date("2026-06-10T23:00:00Z"), end: date("2026-06-11T09:30:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .accepted)
        let tomorrow = StubEvent(id: "tomorrow", start: date("2026-06-12T10:00:00Z"), end: date("2026-06-12T10:30:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .accepted)
        let afterWindow = StubEvent(id: "after-window", start: date("2026-06-19T10:00:00Z"), end: date("2026-06-19T10:30:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .accepted)
        expectEqual(
            MenuSectionVisibility.visibleUpcomingEvents([today, overnight, tomorrow, afterWindow], now: now, isExpanded: false).map(\.id),
            ["overnight", "today"],
            "collapsed upcoming shows events that overlap today"
        )
        expectEqual(
            MenuSectionVisibility.visibleUpcomingEvents([today, overnight, tomorrow, afterWindow], now: now, isExpanded: true).map(\.id),
            ["overnight", "today", "tomorrow"],
            "expanded upcoming shows events within one week"
        )

        let focusNow = date("2026-06-11T09:15:00Z")
        let accepted = StubEvent(id: "accepted", start: date("2026-06-11T09:00:00Z"), end: date("2026-06-11T10:00:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .accepted)
        let needsAction = StubEvent(id: "needs", start: date("2026-06-11T09:00:00Z"), end: date("2026-06-11T10:00:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .needsAction)
        let declined = StubEvent(id: "declined", start: date("2026-06-11T09:00:00Z"), end: date("2026-06-11T10:00:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .declined)
        let allDay = StubEvent(id: "all-day", start: date("2026-06-11T00:00:00Z"), end: date("2026-06-12T00:00:00Z"), isAllDay: true, hasMeetingSignal: true, selfResponseStatus: .accepted)
        let future = StubEvent(id: "future", start: date("2026-06-11T11:00:00Z"), end: date("2026-06-11T12:00:00Z"), isAllDay: false, hasMeetingSignal: true, selfResponseStatus: .accepted)
        let noMeetingSignal = StubEvent(id: "focus-time", start: date("2026-06-11T09:00:00Z"), end: date("2026-06-11T10:00:00Z"), isAllDay: false, hasMeetingSignal: false, selfResponseStatus: .accepted)
        expectEqual(
            MeetingFocusPolicy.desiredState(events: [needsAction, declined], now: focusNow, isEnabled: true),
            .inactive,
            "needs-action and declined meetings do not enable DND"
        )
        expectEqual(
            MeetingFocusPolicy.desiredState(events: [needsAction, accepted, declined], now: focusNow, isEnabled: true),
            .active(until: accepted.end, eventID: "accepted"),
            "accepted current meeting enables DND until meeting end"
        )
        expectEqual(
            MeetingNotificationPolicy.shouldSuppressNotifications(events: [needsAction, accepted, declined], at: focusNow),
            true,
            "accepted current meeting suppresses GWS Menu notifications"
        )
        expectEqual(
            MeetingNotificationPolicy.shouldSuppressNotifications(events: [needsAction, declined], at: focusNow),
            false,
            "needs-action and declined meetings do not suppress GWS Menu notifications"
        )
        expectEqual(
            MeetingNotificationPolicy.shouldSuppressNotifications(events: [allDay, future, noMeetingSignal], at: focusNow),
            false,
            "all-day, future, and non-meeting focus blocks do not suppress GWS Menu notifications"
        )
        expectEqual(
            MeetingNotificationPolicy.shouldSuppressNotifications(events: [accepted], at: accepted.start),
            true,
            "suppression includes the meeting start instant"
        )
        expectEqual(
            MeetingNotificationPolicy.shouldSuppressNotifications(events: [accepted], at: accepted.end),
            false,
            "suppression stops at the meeting end instant"
        )

        expectEqual(CalendarSelfResponseStatus.accepted.indicatorSemanticColor, .green, "accepted indicator is green")
        expectEqual(CalendarSelfResponseStatus.tentative.indicatorSemanticColor, .orange, "tentative indicator is orange")
        expectEqual(CalendarSelfResponseStatus.needsAction.indicatorSemanticColor, .gray, "needs-action indicator is gray")
        expectEqual(CalendarSelfResponseStatus.declined.indicatorSemanticColor, .red, "declined indicator is red")

        expectEqual(FocusStatusParser.parse(""), false, "empty Korean Shortcuts status means DND is off")
        expectEqual(FocusStatusParser.parse("방해금지 모드"), true, "Korean DND status means DND is on")
        expectEqual(FocusStatusParser.parse("off"), false, "English off status means DND is off")
        expectEqual(FocusStatusParser.parse("enabled"), true, "English enabled status means DND is on")

        let remaining = date("2026-06-11T09:04:15Z")
        let shortPresence = TeamsPresencePolicy.setPresenceRequest(
            sessionID: "11111111-2222-3333-4444-555555555555",
            until: date("2026-06-11T09:06:00Z"),
            now: remaining
        )
        expectEqual(shortPresence.availability, "Busy", "Teams presence uses Busy availability")
        expectEqual(shortPresence.activity, "InAConferenceCall", "Teams presence uses conference call activity")
        expectEqual(shortPresence.expirationDuration, "PT5M", "Teams presence clamps short meetings to Graph minimum")
        let longPresence = TeamsPresencePolicy.setPresenceRequest(
            sessionID: "11111111-2222-3333-4444-555555555555",
            until: date("2026-06-11T15:30:00Z"),
            now: focusNow
        )
        expectEqual(longPresence.expirationDuration, "PT4H", "Teams presence clamps long meetings to Graph maximum")
        expectEqual(
            TeamsPresencePolicy.desiredState(events: [needsAction, accepted, declined], now: focusNow, isEnabled: true),
            .active(until: accepted.end, eventID: "accepted"),
            "accepted current meeting enables Teams Busy"
        )
        expectEqual(
            TeamsPresencePolicy.desiredState(events: [needsAction, declined, allDay, noMeetingSignal], now: focusNow, isEnabled: true),
            .inactive,
            "Teams Busy ignores declined, unanswered, all-day, and non-meeting focus blocks"
        )
        let managedSession = TeamsPresencePolicy.managedSession(
            eventID: "accepted",
            request: longPresence,
            userID: "graph-user-original"
        )
        expectEqual(managedSession.sessionID, "11111111-2222-3333-4444-555555555555", "managed session keeps the app session ID used for setPresence")
        expectEqual(managedSession.userID, "graph-user-original", "managed session keeps the Microsoft Graph user ID used for setPresence")
        expectEqual(
            TeamsPresencePolicy.shouldRefreshManagedPresence(eventID: "accepted", managedSession: managedSession, now: focusNow),
            false,
            "managed presence is not refreshed while the same meeting session is still fresh"
        )
        expectEqual(
            TeamsPresencePolicy.shouldRefreshManagedPresence(
                eventID: "accepted",
                managedSession: managedSession,
                now: date("2026-06-11T15:26:00Z")
            ),
            true,
            "managed presence refreshes before Graph expiration"
        )
        expectEqual(
            TeamsPresencePolicy.shouldRefreshManagedPresence(eventID: "different", managedSession: managedSession, now: focusNow),
            true,
            "managed presence refreshes when the active meeting changes"
        )

        print("PASS: GWSMenuCore behavior")
    }
}
SWIFT

swiftc "$ROOT/macos/GWSMenuBar/Sources/GWSMenuCore/GWSMenuCore.swift" "$TMPDIR/TestGWSMenuCore.swift" -o "$TMPDIR/gws-menu-core-test"
"$TMPDIR/gws-menu-core-test"
