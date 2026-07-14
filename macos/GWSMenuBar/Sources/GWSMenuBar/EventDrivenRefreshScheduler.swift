import AppKit
import Foundation
import GWSMenuCore

enum RemoteRefreshTrigger: String, Sendable {
    case popoverOpened
    case systemWake
    case sessionActive
    case clockChanged
    case timeZoneChanged
    case dayChanged
    case safetySync
}

enum LocalRefreshTrigger: String, Hashable, Sendable {
    case meetingBoundary
    case statusDisplay
    case teamsPresenceRefresh
}

@MainActor
final class EventDrivenRefreshScheduler {
    typealias RemoteRefreshHandler = @MainActor (RemoteRefreshTrigger) async -> Void
    typealias LocalRefreshHandler = @MainActor (Set<LocalRefreshTrigger>) -> Void
    typealias GmailRefreshHandler = @MainActor () async -> Int?

    private struct LocalCandidate {
        let date: Date
        let triggers: Set<LocalRefreshTrigger>
    }

    private let onRemoteRefresh: RemoteRefreshHandler
    private let onLocalRefresh: LocalRefreshHandler
    private let onGmailRefresh: GmailRefreshHandler
    private let calendarSafetyScheduler = NSBackgroundActivityScheduler(
        identifier: "io.github.gwsmenu.calendar-safety-sync"
    )
    private let gmailScheduler = NSBackgroundActivityScheduler(
        identifier: "io.github.gwsmenu.gmail-unread-sync"
    )

    private var localTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var meetings: [MeetingEvent] = []
    private var alertLeadMinutes = 10
    private var teamsPresenceEnabled = false
    private var nextTeamsPresenceRefreshDate: Date?
    private var gmailRefreshTask: (id: UUID, task: Task<Int?, Never>)?
    private var gmailReconciliationTask: Task<Void, Never>?
    private var gmailReconciliationGeneration = UUID()
    private var hasStarted = false

    init(
        onRemoteRefresh: @escaping RemoteRefreshHandler,
        onLocalRefresh: @escaping LocalRefreshHandler,
        onGmailRefresh: @escaping GmailRefreshHandler
    ) {
        self.onRemoteRefresh = onRemoteRefresh
        self.onLocalRefresh = onLocalRefresh
        self.onGmailRefresh = onGmailRefresh
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeSystemEvents()
        scheduleBackgroundActivities()
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        localTimer?.invalidate()
        localTimer = nil
        cancelGmailUnreadReconciliation()
        gmailRefreshTask?.task.cancel()
        gmailRefreshTask = nil
        calendarSafetyScheduler.invalidate()
        gmailScheduler.invalidate()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
    }

    func requestRemoteRefresh(_ trigger: RemoteRefreshTrigger) {
        guard hasStarted else { return }
        AppLog.lifecycle.info("Refresh event: \(trigger.rawValue, privacy: .public)")
        if trigger.refreshesGmail {
            requestGmailRefresh()
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.onRemoteRefresh(trigger)
        }
    }

    func requestGmailRefresh() {
        guard hasStarted else { return }
        Task { @MainActor [weak self] in
            _ = await self?.performGmailRefresh()
        }
    }

    func startGmailUnreadReconciliation(baselineCount: Int?) {
        guard hasStarted else { return }
        guard gmailReconciliationTask == nil else {
            AppLog.gmail.debug("Gmail unread reconciliation already active; coalescing open event")
            return
        }

        let generation = UUID()
        gmailReconciliationGeneration = generation
        var plan = GmailUnreadReconciliationPlan(baselineCount: baselineCount)
        gmailReconciliationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.gmailReconciliationGeneration == generation {
                    self.gmailReconciliationTask = nil
                }
            }

            AppLog.gmail.debug("Gmail unread reconciliation started")
            var observedCount = await self.performGmailRefresh()
            while !Task.isCancelled {
                switch plan.nextStep(observedCount: observedCount) {
                case .stopBecauseCountSettled:
                    AppLog.gmail.debug("Gmail unread reconciliation stopped after count settled")
                    return
                case .stopBecauseWindowEnded:
                    AppLog.gmail.debug("Gmail unread reconciliation window ended")
                    return
                case .wait(let delay):
                    let nanoseconds = UInt64(delay * 1_000_000_000)
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    observedCount = await self.performGmailRefresh()
                }
            }
        }
    }

    func cancelGmailUnreadReconciliation() {
        gmailReconciliationGeneration = UUID()
        gmailReconciliationTask?.cancel()
        gmailReconciliationTask = nil
    }

    func updateMeetings(
        _ meetings: [MeetingEvent],
        alertLeadMinutes: Int,
        teamsPresenceEnabled: Bool
    ) {
        self.meetings = meetings
        self.alertLeadMinutes = alertLeadMinutes
        self.teamsPresenceEnabled = teamsPresenceEnabled
        updateTeamsPresenceRefreshDate(after: Date(), resetWhenActive: true)
        armNextLocalTimer()
    }

    private func observeSystemEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.requestRemoteRefresh(.systemWake)
                }
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.requestRemoteRefresh(.sessionActive)
                }
            }
        )

        observeNotification(.NSSystemClockDidChange, trigger: .clockChanged)
        observeNotification(.NSSystemTimeZoneDidChange, trigger: .timeZoneChanged)
        observeNotification(.NSCalendarDayChanged, trigger: .dayChanged)
    }

    private func observeNotification(
        _ name: Notification.Name,
        trigger: RemoteRefreshTrigger
    ) {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.requestRemoteRefresh(trigger)
                }
            }
        )
    }

    private func scheduleBackgroundActivities() {
        calendarSafetyScheduler.repeats = true
        calendarSafetyScheduler.interval = 15 * 60
        calendarSafetyScheduler.tolerance = 5 * 60
        calendarSafetyScheduler.qualityOfService = .utility
        calendarSafetyScheduler.schedule { [weak self] completion in
            Task { @MainActor in
                guard let self, self.hasStarted else {
                    completion(.deferred)
                    return
                }
                AppLog.lifecycle.info("Refresh event: \(RemoteRefreshTrigger.safetySync.rawValue, privacy: .public)")
                await self.onRemoteRefresh(.safetySync)
                completion(.finished)
            }
        }

        gmailScheduler.repeats = true
        gmailScheduler.interval = 5 * 60
        gmailScheduler.tolerance = 30
        gmailScheduler.qualityOfService = .utility
        gmailScheduler.schedule { [weak self] completion in
            Task { @MainActor in
                guard let self, self.hasStarted else {
                    completion(.deferred)
                    return
                }
                AppLog.lifecycle.info("Refresh event: gmailSafetySync")
                _ = await self.performGmailRefresh()
                completion(.finished)
            }
        }
    }

    private func performGmailRefresh() async -> Int? {
        if let gmailRefreshTask {
            return await gmailRefreshTask.task.value
        }

        let id = UUID()
        let handler = onGmailRefresh
        let task = Task { @MainActor in
            await handler()
        }
        gmailRefreshTask = (id, task)
        let unreadCount = await task.value
        if gmailRefreshTask?.id == id {
            gmailRefreshTask = nil
        }
        return unreadCount
    }

    private func armNextLocalTimer() {
        localTimer?.invalidate()
        localTimer = nil
        guard hasStarted, let candidate = nextLocalCandidate(after: Date()) else { return }

        let timer = Timer(fire: candidate.date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.hasStarted else { return }
                self.localTimer = nil
                let reasons = candidate.triggers.map(\.rawValue).sorted().joined(separator: ",")
                AppLog.lifecycle.debug("Local refresh event: \(reasons, privacy: .public)")
                self.onLocalRefresh(candidate.triggers)
                self.updateTeamsPresenceRefreshDate(
                    after: Date(),
                    resetWhenActive: candidate.triggers.contains(.teamsPresenceRefresh)
                )
                self.armNextLocalTimer()
            }
        }
        timer.tolerance = candidate.triggers == [.statusDisplay] ? 0.5 : 0.1
        RunLoop.main.add(timer, forMode: .common)
        localTimer = timer
    }

    private func nextLocalCandidate(after now: Date) -> LocalCandidate? {
        let minimumFireDate = now.addingTimeInterval(0.05)
        var candidates: [LocalCandidate] = []
        let visibleMeetings = meetings.filter { $0.selfResponseStatus != .declined }

        for meeting in visibleMeetings {
            if meeting.start > minimumFireDate {
                candidates.append(LocalCandidate(date: meeting.start, triggers: [.meetingBoundary]))
            }
            if meeting.end > minimumFireDate {
                candidates.append(LocalCandidate(date: meeting.end, triggers: [.meetingBoundary]))
            }
        }

        if let nextMeeting = visibleMeetings
            .filter({ $0.start > now })
            .min(by: { $0.start < $1.start }) {
            let leadStart = nextMeeting.start.addingTimeInterval(-TimeInterval(alertLeadMinutes * 60))
            if leadStart > minimumFireDate {
                candidates.append(LocalCandidate(date: leadStart, triggers: [.statusDisplay]))
            } else {
                let secondsUntilStart = nextMeeting.start.timeIntervalSince(now)
                let displayedMinutes = Int(ceil(secondsUntilStart / 60))
                if displayedMinutes > 1 {
                    let nextMinute = nextMeeting.start.addingTimeInterval(
                        -TimeInterval((displayedMinutes - 1) * 60)
                    )
                    if nextMinute > minimumFireDate {
                        candidates.append(LocalCandidate(date: nextMinute, triggers: [.statusDisplay]))
                    }
                }
            }
        }

        if let nextTeamsPresenceRefreshDate,
           nextTeamsPresenceRefreshDate > minimumFireDate {
            candidates.append(
                LocalCandidate(
                    date: nextTeamsPresenceRefreshDate,
                    triggers: [.teamsPresenceRefresh]
                )
            )
        }

        guard let earliestDate = candidates.map(\.date).min() else { return nil }
        let combinedTriggers = candidates
            .filter { abs($0.date.timeIntervalSince(earliestDate)) < 0.25 }
            .reduce(into: Set<LocalRefreshTrigger>()) { result, candidate in
                result.formUnion(candidate.triggers)
        }
        return LocalCandidate(date: earliestDate, triggers: combinedTriggers)
    }

    private func updateTeamsPresenceRefreshDate(after now: Date, resetWhenActive: Bool) {
        let hasActiveTeamsMeeting = teamsPresenceEnabled && meetings.contains(where: {
            !$0.isAllDay &&
                $0.hasMeetingSignal &&
                $0.selfResponseStatus == .accepted &&
                $0.start <= now &&
                $0.end > now
        })
        guard hasActiveTeamsMeeting else {
            nextTeamsPresenceRefreshDate = nil
            return
        }
        if resetWhenActive || nextTeamsPresenceRefreshDate == nil {
            nextTeamsPresenceRefreshDate = now.addingTimeInterval(5 * 60)
        }
    }
}

private extension RemoteRefreshTrigger {
    var refreshesGmail: Bool {
        switch self {
        case .popoverOpened, .systemWake, .sessionActive:
            return true
        case .clockChanged, .timeZoneChanged, .dayChanged, .safetySync:
            return false
        }
    }
}
