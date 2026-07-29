#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/TestLazyestWorkCore.swift" <<'SWIFT'
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
struct LazyestWorkCoreBehaviorTest {
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
            "accepted current meeting suppresses Lazyest Work notifications"
        )
        expectEqual(
            MeetingNotificationPolicy.shouldSuppressNotifications(events: [needsAction, declined], at: focusNow),
            false,
            "needs-action and declined meetings do not suppress Lazyest Work notifications"
        )
        expectEqual(
            MeetingNotificationPolicy.shouldSuppressNotifications(events: [allDay, future, noMeetingSignal], at: focusNow),
            false,
            "all-day, future, and non-meeting focus blocks do not suppress Lazyest Work notifications"
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

        expectEqual(
            TeamsInputProtectionPolicy.permissionState(
                accessibilityGranted: true
            ),
            .ready,
            "Teams input protection is ready with Accessibility permission"
        )
        expectEqual(
            TeamsInputProtectionPolicy.permissionState(
                accessibilityGranted: false
            ),
            .missingAccessibility,
            "Teams input protection requires Accessibility permission"
        )
        expectEqual(
            TeamsInputProtectionPolicy.shouldBlockControlScroll(
                isEnabled: true,
                controlKeyIsDown: true,
                isTeamsFrontmost: true,
                isInsideTeamsWindow: true
            ),
            true,
            "Control-scroll is blocked inside the frontmost Teams window"
        )
        expectEqual(
            TeamsInputProtectionPolicy.shouldBlockControlScroll(
                isEnabled: true,
                controlKeyIsDown: true,
                isTeamsFrontmost: false,
                isInsideTeamsWindow: true
            ),
            false,
            "Control-scroll stays transparent outside frontmost Teams"
        )

        let remaining = date("2026-06-11T09:04:15Z")
        let shortPresence = TeamsPresencePolicy.preferredPresenceRequest(
            until: date("2026-06-11T09:06:00Z"),
            now: remaining
        )
        expectEqual(shortPresence.availability, "Busy", "Teams presence uses Busy availability")
        expectEqual(shortPresence.activity, "Busy", "Teams preferred presence uses Busy activity")
        expectEqual(shortPresence.expirationDuration, "PT2M", "Teams preferred presence can expire at the meeting end")
        let longPresence = TeamsPresencePolicy.preferredPresenceRequest(
            until: date("2026-06-11T15:30:00Z"),
            now: focusNow
        )
        expectEqual(longPresence.expirationDuration, "PT375M", "Teams preferred presence can span long meetings")
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
        expectEqual(managedSession.sessionID, nil, "managed session does not use an app session ID for user preferred presence")
        expectEqual(managedSession.userID, "graph-user-original", "managed session keeps the Microsoft Graph user ID used for preferred presence")
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

        var gmailPlan = GmailUnreadReconciliationPlan(
            baselineCount: 4,
            observationRetryDelays: [2, 4, 8]
        )
        expectEqual(gmailPlan.nextStep(observedCount: nil), .wait(2), "unknown Gmail count is not treated as a read change")
        expectEqual(gmailPlan.nextStep(observedCount: 4), .wait(4), "unchanged Gmail count backs off")
        expectEqual(gmailPlan.nextStep(observedCount: 3), .wait(5), "changed Gmail count enters settle checks")
        expectEqual(gmailPlan.nextStep(observedCount: nil), .wait(5), "failed Gmail settle check is retried")
        expectEqual(gmailPlan.nextStep(observedCount: 3), .wait(5), "first stable Gmail count keeps settling")
        expectEqual(gmailPlan.nextStep(observedCount: 3), .stopBecauseCountSettled, "two stable Gmail counts stop reconciliation")

        var unknownBaselineGmailPlan = GmailUnreadReconciliationPlan(
            baselineCount: nil,
            observationRetryDelays: [2, 4, 8]
        )
        expectEqual(unknownBaselineGmailPlan.nextStep(observedCount: nil), .wait(2), "missing Gmail baseline retries")
        expectEqual(unknownBaselineGmailPlan.nextStep(observedCount: 5), .wait(4), "first Gmail result establishes a baseline")
        expectEqual(unknownBaselineGmailPlan.nextStep(observedCount: 4), .wait(5), "a later Gmail change still enters settle checks")
        expectEqual(unknownBaselineGmailPlan.nextStep(observedCount: 4), .wait(5), "unknown-baseline Gmail result starts settling")
        expectEqual(unknownBaselineGmailPlan.nextStep(observedCount: 4), .stopBecauseCountSettled, "unknown-baseline Gmail result settles cleanly")

        var changingGmailPlan = GmailUnreadReconciliationPlan(
            baselineCount: 4,
            observationRetryDelays: [2],
            maximumFollowUpChecks: 5
        )
        expectEqual(changingGmailPlan.nextStep(observedCount: 3), .wait(5), "first Gmail read starts settling")
        expectEqual(changingGmailPlan.nextStep(observedCount: 3), .wait(5), "stable Gmail count is observed again")
        expectEqual(changingGmailPlan.nextStep(observedCount: 2), .wait(5), "another Gmail read resets settling")
        expectEqual(changingGmailPlan.nextStep(observedCount: 2), .wait(5), "new Gmail count starts a fresh stable window")
        expectEqual(changingGmailPlan.nextStep(observedCount: 2), .stopBecauseCountSettled, "new Gmail count settles cleanly")

        print("PASS: LazyestWorkCore behavior")
    }
}
SWIFT

swiftc \
  "$ROOT/macos/LazyestWork/Sources/LazyestWorkCore/LazyestWorkCore.swift" \
  "$ROOT/macos/LazyestWork/Sources/LazyestWorkCore/GmailUnreadReconciliationPlan.swift" \
  "$ROOT/macos/LazyestWork/Sources/LazyestWorkCore/TeamsInputProtectionPolicy.swift" \
  "$TMPDIR/TestLazyestWorkCore.swift" \
  -o "$TMPDIR/lazyest-work-core-test"
"$TMPDIR/lazyest-work-core-test"
