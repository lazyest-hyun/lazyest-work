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

        expectEqual(CalendarSelfResponseStatus.accepted.indicatorSemanticColor, .green, "accepted indicator is green")
        expectEqual(CalendarSelfResponseStatus.tentative.indicatorSemanticColor, .orange, "tentative indicator is orange")
        expectEqual(CalendarSelfResponseStatus.needsAction.indicatorSemanticColor, .gray, "needs-action indicator is gray")
        expectEqual(CalendarSelfResponseStatus.declined.indicatorSemanticColor, .red, "declined indicator is red")

        print("PASS: GWSMenuCore behavior")
    }
}
SWIFT

swiftc "$ROOT/macos/GWSMenuBar/Sources/GWSMenuCore/GWSMenuCore.swift" "$TMPDIR/TestGWSMenuCore.swift" -o "$TMPDIR/gws-menu-core-test"
"$TMPDIR/gws-menu-core-test"
