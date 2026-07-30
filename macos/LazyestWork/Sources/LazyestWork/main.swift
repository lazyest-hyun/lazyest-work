import AppKit
import Combine
import Foundation
#if GWS_FILE_KEYCHAIN
import GTMAppAuth
#endif
import LazyestWorkCore
#if GWS_FILE_KEYCHAIN
import ObjectiveC
#endif
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import GoogleSignIn
@preconcurrency import UserNotifications

final class AppModel: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            AppLanguageSettings.save(language)
        }
    }
    @Published var events: [MeetingEvent] = []
    @Published var now = Date()
    @Published var connectionState = ConnectionState.loading
    @Published var lastError: String?
    @Published var lastErrorRecovery: ErrorRecoveryAction?
    @Published var gmailError: String?
    @Published var gmailErrorRecovery: ErrorRecoveryAction?
    @Published var isBusy = false
    @Published var workspaceApps = WorkspaceAppStore.load()
    @Published var gmailUnreadCount: Int?
    @Published var alertLeadMinutes: Int {
        didSet {
            AlertSettings.saveLeadMinutes(alertLeadMinutes)
        }
    }
    @Published var calendarNotificationsEnabled: Bool {
        didSet {
            AlertSettings.saveCalendarNotificationsEnabled(calendarNotificationsEnabled)
        }
    }
    @Published var meetingFocusEnabled: Bool {
        didSet {
            FocusSettings.saveMeetingFocusEnabled(meetingFocusEnabled)
        }
    }
    @Published var meetingFocusStatusText = ""
    @Published var meetingFocusHelperInstalled = false
    @Published var meetingFocusApprovalPending = false
    @Published var teamsPresenceEnabled: Bool {
        didSet {
            TeamsPresenceSettings.saveEnabled(teamsPresenceEnabled)
        }
    }
    @Published var teamsCallBlockEnabled: Bool {
        didSet {
            TeamsCallBlockSettings.saveEnabled(teamsCallBlockEnabled)
        }
    }
    @Published var teamsControlScrollBlockEnabled: Bool {
        didSet {
            TeamsCallBlockSettings.saveControlScrollEnabled(teamsControlScrollBlockEnabled)
        }
    }
    @Published var teamsCallBlockPermissionPending = TeamsCallBlockSettings.loadPendingEnableAfterPermission()
    @Published var teamsCallBlockStatusText = "Teams call block is off."
    @Published var teamsPresenceStatusText = "Connect Microsoft, then turn on Teams Busy for accepted meetings."
    @Published var teamsConnectionState = MicrosoftConnectionState.missingSetup
    @Published var teamsOperation = MicrosoftTeamsOperation.idle
    @Published var teamsSetupConfig = MicrosoftSetupSettings.load()
    @Published var mailBadgeEnabled: Bool {
        didSet {
            MailBadgeSettings.saveEnabled(mailBadgeEnabled)
        }
    }
    @Published var launchAtLoginEnabled: Bool
    @Published var setupChecklistDismissed: Bool {
        didSet {
            SetupChecklistSettings.saveDismissed(setupChecklistDismissed)
        }
    }

    init() {
        language = AppLanguageSettings.load()
        alertLeadMinutes = AlertSettings.loadLeadMinutes()
        calendarNotificationsEnabled = AlertSettings.loadCalendarNotificationsEnabled()
        meetingFocusEnabled = FocusSettings.loadMeetingFocusEnabled()
        teamsPresenceEnabled = TeamsPresenceSettings.loadEnabled()
        teamsCallBlockEnabled = TeamsCallBlockSettings.loadEnabled()
        teamsControlScrollBlockEnabled = TeamsCallBlockSettings.loadControlScrollEnabled()
        mailBadgeEnabled = MailBadgeSettings.loadEnabled()
        launchAtLoginEnabled = LaunchAtLoginSettings.isEnabled()
        setupChecklistDismissed = SetupChecklistSettings.loadDismissed()
    }
}

enum ErrorRecoveryAction: Equatable {
    case googleConnection
    case gmailPermission
    case notificationSettings
    case loginItemsSettings

    var buttonTitle: String {
        switch self {
        case .googleConnection:
            return "Connect"
        case .gmailPermission:
            return "Allow"
        case .notificationSettings, .loginItemsSettings:
            return "Settings"
        }
    }
}

enum UnreadCountFormatter {
    static func display(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

private final class LockedFormatter<Formatter>: @unchecked Sendable {
    private let formatter: Formatter
    private let lock = NSLock()

    init(_ makeFormatter: () -> Formatter) {
        formatter = makeFormatter()
    }

    func use<Result>(_ body: (Formatter) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(formatter)
    }
}

private enum AppDateFormatters {
    private static let iso8601 = LockedFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
    private static let fractionalISO8601 = LockedFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
    private static let shortTime = LockedFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
    private static let compactDate = LockedFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }
    private static let timeInterval = LockedFormatter {
        let formatter = DateIntervalFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
    private static let koreanWeekday = weekdayFormatter(localeIdentifier: "ko_KR")
    private static let englishWeekday = weekdayFormatter(localeIdentifier: "en_US_POSIX")

    static func iso8601String(from date: Date) -> String {
        iso8601.use { $0.string(from: date) }
    }

    static func parseISO8601(_ value: String) -> Date? {
        fractionalISO8601.use { $0.date(from: value) }
            ?? iso8601.use { $0.date(from: value) }
    }

    static func shortTimeString(from date: Date) -> String {
        shortTime.use { $0.string(from: date) }
    }

    static func compactDateString(from date: Date) -> String {
        compactDate.use { $0.string(from: date) }
    }

    static func timeIntervalString(from start: Date, to end: Date) -> String {
        timeInterval.use { $0.string(from: start, to: end) }
    }

    static func weekdayString(from date: Date, language: AppLanguage) -> String {
        let formatter = language == .korean ? koreanWeekday : englishWeekday
        return formatter.use { $0.string(from: date) }
    }

    private static func weekdayFormatter(localeIdentifier: String) -> LockedFormatter<DateFormatter> {
        LockedFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: localeIdentifier)
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "EEE"
            return formatter
        }
    }
}

@MainActor
enum AppImages {
    private static let googleBlue = NSColor(calibratedRed: 66.0 / 255.0, green: 133.0 / 255.0, blue: 244.0 / 255.0, alpha: 1)
    private static let googleRed = NSColor(calibratedRed: 219.0 / 255.0, green: 68.0 / 255.0, blue: 55.0 / 255.0, alpha: 1)
    private static let googleYellow = NSColor(calibratedRed: 244.0 / 255.0, green: 180.0 / 255.0, blue: 0, alpha: 1)
    private static let googleGreen = NSColor(calibratedRed: 15.0 / 255.0, green: 157.0 / 255.0, blue: 88.0 / 255.0, alpha: 1)
    private static let standardIcon = makeAppIcon(size: 18)

    static func menuBarIcon(unreadCount: Int? = nil) -> NSImage {
        guard let unreadCount, unreadCount > 0 else {
            return standardIcon
        }

        return badgedMenuBarIcon(countText: UnreadCountFormatter.display(unreadCount))
    }

    static func headerIcon() -> NSImage {
        standardIcon
    }

    private static func makeAppIcon(size: CGFloat) -> NSImage {
        if let icon = bundledAppIcon(size: size) {
            return icon
        }

        return googleWorkspaceIcon(size: size, dotSize: 4.2)
    }

    private static func badgedMenuBarIcon(countText: String) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        standardIcon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

        let badgeHeight: CGFloat = 9.5
        let badgeWidth = min(max(CGFloat(countText.count) * 4.3 + 6.0, badgeHeight), size - 1)
        let badgeRect = NSRect(
            x: size - badgeWidth,
            y: size - badgeHeight,
            width: badgeWidth,
            height: badgeHeight
        )

        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2).fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6.0, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        countText.draw(in: badgeRect.insetBy(dx: 1.0, dy: 1.1), withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func bundledAppIcon(size: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else {
            return nil
        }

        icon.size = NSSize(width: size, height: size)
        icon.isTemplate = false
        return icon
    }

    static func googleWorkspaceIcon(size: CGFloat, dotSize: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        let colors: [[NSColor]] = [
            [googleBlue, googleRed, googleYellow],
            [googleGreen, googleBlue, googleRed],
            [googleYellow, googleGreen, googleBlue]
        ]
        let gap = (size - dotSize * 3) / 4

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        for row in 0..<3 {
            for column in 0..<3 {
                colors[row][column].setFill()
                let x = gap + CGFloat(column) * (dotSize + gap)
                let y = gap + CGFloat(2 - row) * (dotSize + gap)
                let rect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
                NSBezierPath(roundedRect: rect, xRadius: dotSize * 0.35, yRadius: dotSize * 0.35).fill()
            }
        }
        image.unlockFocus()

        image.isTemplate = false
        return image
    }
}

private enum PopoverLayout {
    static let width: CGFloat = 420
    static let maximumHeight: CGFloat = 590
    static let minimumHomeHeight: CGFloat = 280
    static let settingsMinimumHeight: CGFloat = 420
    static let headerHeight: CGFloat = 52
    static let dividerHeight: CGFloat = 1
    static let homeChromeHeight = headerHeight + dividerHeight

    static func quantized(_ value: CGFloat) -> CGFloat {
        (value / 4).rounded(.up) * 4
    }
}

@MainActor
private enum SingleInstanceGuard {
    static func isPrimaryInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let instances = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .sorted { $0.processIdentifier < $1.processIdentifier }

        guard let primary = instances.first else {
            return true
        }
        return primary.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let authWindow = AuthWindow()
    private let model = AppModel()
    private lazy var authClient = GoogleSignInAuthClient(authWindow: authWindow)
    private lazy var calendarService = GoogleCalendarService(authClient: authClient)
    private lazy var gmailService = GoogleGmailService(authClient: authClient)
    private lazy var microsoftAuthClient = MicrosoftGraphAuthClient(authWindow: authWindow)
    private let microsoftCLIClient = Microsoft365CLIClient()
    private lazy var teamsPresenceService = MicrosoftTeamsPresenceService(authClient: microsoftAuthClient, cliClient: microsoftCLIClient)
    private let teamsCallBlocker = MicrosoftTeamsCallBlocker()
    private let meetingFocusBridge = MeetingFocusBridge()
    private lazy var popover: NSPopover = makePopover()
    private var pendingPopoverHeight: CGFloat?
    private var cancellables = Set<AnyCancellable>()
    private lazy var refreshScheduler = EventDrivenRefreshScheduler(
        onRemoteRefresh: { [weak self] _ in
            await self?.refreshEvents(showsActivity: false)
        },
        onLocalRefresh: { [weak self] triggers in
            self?.handleScheduledLocalRefresh(triggers)
        },
        onGmailRefresh: { [weak self] in
            guard let self else { return nil }
            return await self.refreshGmailUnread()
        }
    )
    private var meetingFocusApprovalTask: Task<Void, Never>?
    private var meetingFocusSyncTask: Task<Void, Never>?
    private var meetingFocusSyncGeneration = UUID()
    private var teamsPresenceTask: Task<Void, Never>?
    private var isRefreshingEvents = false
    private var isRefreshingGmail = false
    private var statusIconUnreadText: String?
    private var renderedStatusTitle: String?
    private var text: AppText {
        AppText(language: model.language)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstanceGuard.isPrimaryInstance() else {
            AppLog.lifecycle.notice("Lazyest Work duplicate launch ignored")
            NSApp.terminate(nil)
            return
        }

        AppLog.lifecycle.notice("Lazyest Work launched")
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        configureApplicationMenu()
        configureStatusItem()
        bindModel()
        teamsCallBlocker.configure(
            savedEnabled: model.teamsCallBlockEnabled,
            savedControlScrollBlockEnabled: model.teamsControlScrollBlockEnabled
        )
        refreshScheduler.start()
        let skipGoogleRestore = InstallLaunchSettings.consumeSkipGoogleRestoreOnce()

        Task {
            await restoreAndRefresh(skipGoogleRestore: skipGoogleRestore)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if microsoftAuthClient.handle(url: url) {
                continue
            }
            _ = authClient.handle(url: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !popover.isShown else { return true }
        DispatchQueue.main.async { [weak self] in
            self?.showPopover()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshTeamsCallBlockPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        meetingFocusApprovalTask?.cancel()
        meetingFocusSyncTask?.cancel()
        teamsPresenceTask?.cancel()
        refreshScheduler.stop()
        teamsCallBlocker.stop()
        turnOffManagedMeetingFocus()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = AppImages.menuBarIcon(unreadCount: menuBarUnreadCount())
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshUI()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        let maximumHeight = maximumPopoverHeight()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: PopoverLayout.width,
            height: min(maximumHeight, PopoverLayout.minimumHomeHeight)
        )
        let hostingController = NSHostingController(
            rootView: LazyestWorkPopover(
                model: model,
                maximumHeight: maximumHeight,
                onPreferredHeightChange: { [weak self] height in
                    self?.updatePopoverHeight(height)
                },
                onSignIn: { [weak self] in self?.signIn() },
                onRefresh: { [weak self] in self?.refreshFromMenu() },
                onSignOut: { [weak self] in self?.signOut() },
                onDismissSetupChecklist: { [weak self] in self?.dismissSetupChecklist() },
                onEnableCalendarAlerts: { [weak self] in self?.enableCalendarAlertsFromMenu() },
                onEnableGmailBadge: { [weak self] in self?.enableGmailBadgeFromMenu() },
                onEnableLaunchAtLogin: { [weak self] in self?.enableLaunchAtLoginFromMenu() },
                onUpdateLanguage: { [weak self] language in self?.updateLanguage(language) },
                onUpdateWorkspaceApps: { [weak self] apps in self?.updateWorkspaceApps(apps) },
                onUpdateAlertLeadMinutes: { [weak self] minutes in self?.updateAlertLeadMinutes(minutes) },
                onUpdateCalendarNotifications: { [weak self] isEnabled in self?.updateCalendarNotificationsEnabled(isEnabled) },
                onSendTestCalendarNotification: { [weak self] in self?.sendTestCalendarNotificationFromSettings() },
                onUpdateMeetingFocus: { [weak self] isEnabled in self?.updateMeetingFocusEnabled(isEnabled) ?? false },
                onApproveMeetingFocus: { [weak self] in self?.requestMeetingFocusApproval() },
                onInstallMicrosoftCLI: { [weak self] in self?.installMicrosoft365CLI() },
                onConnectMicrosoftTeams: { [weak self] in self?.connectMicrosoftTeams() },
                onSignOutMicrosoftTeams: { [weak self] in self?.signOutMicrosoftTeams() },
                onUpdateTeamsPresence: { [weak self] isEnabled in self?.updateTeamsPresenceEnabled(isEnabled) ?? false },
                onUpdateTeamsCallBlock: { [weak self] isEnabled in self?.updateTeamsCallBlockEnabled(isEnabled) ?? false },
                onUpdateTeamsControlScrollBlock: { [weak self] isEnabled in self?.updateTeamsControlScrollBlockEnabled(isEnabled) ?? false },
                onRefreshTeamsCallBlockPermissions: { [weak self] in self?.refreshTeamsCallBlockPermissions() },
                onUpdateMailBadge: { [weak self] isEnabled in self?.updateMailBadgeEnabled(isEnabled) },
                onUpdateLaunchAtLogin: { [weak self] isEnabled in self?.updateLaunchAtLoginEnabled(isEnabled) },
                onOpenURL: { [weak self] url in self?.openURLFromMenu(url) },
                onOpenWorkspaceURL: { [weak self] url in self?.openWorkspaceURLFromMenu(url) }
            )
        )
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController
        return popover
    }

    private func maximumPopoverHeight() -> CGFloat {
        let visibleHeight = statusItem.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 670
        return min(PopoverLayout.maximumHeight, max(PopoverLayout.minimumHomeHeight, visibleHeight - 80))
    }

    private func updatePopoverHeight(_ requestedHeight: CGFloat) {
        let height = min(
            maximumPopoverHeight(),
            max(PopoverLayout.minimumHomeHeight, PopoverLayout.quantized(requestedHeight))
        )
        pendingPopoverHeight = height
        DispatchQueue.main.async { [weak self] in
            guard let self, let pendingHeight = self.pendingPopoverHeight else { return }
            self.pendingPopoverHeight = nil
            guard abs(self.popover.contentSize.height - pendingHeight) >= 4 else { return }
            self.popover.contentSize = NSSize(width: PopoverLayout.width, height: pendingHeight)
        }
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Lazyest Work")
        appMenu.addItem(NSMenuItem(title: "Quit Lazyest Work", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func bindModel() {
        model.$alertLeadMinutes
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshUI()
            }
            .store(in: &cancellables)

        teamsCallBlocker.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if self.model.teamsCallBlockEnabled != isEnabled {
                    self.model.teamsCallBlockEnabled = isEnabled
                }
                self.refreshUI()
            }
            .store(in: &cancellables)

        teamsCallBlocker.$isControlScrollBlockEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if self.model.teamsControlScrollBlockEnabled != isEnabled {
                    self.model.teamsControlScrollBlockEnabled = isEnabled
                }
                self.refreshUI()
            }
            .store(in: &cancellables)

        teamsCallBlocker.$statusText
            .receive(on: RunLoop.main)
            .sink { [weak self] statusText in
                guard let self else { return }
                if self.model.teamsCallBlockStatusText != statusText {
                    self.model.teamsCallBlockStatusText = statusText
                }
                self.refreshUI()
            }
            .store(in: &cancellables)

        teamsCallBlocker.$isPendingEnableAfterPermission
            .receive(on: RunLoop.main)
            .sink { [weak self] isPending in
                guard let self else { return }
                if self.model.teamsCallBlockPermissionPending != isPending {
                    self.model.teamsCallBlockPermissionPending = isPending
                }
                self.refreshUI()
            }
            .store(in: &cancellables)
    }

    private func restoreAndRefresh(skipGoogleRestore: Bool = false) async {
        refreshLaunchAtLoginState()
        refreshMeetingFocusHelperStatus()
        refreshMicrosoftConnectionState()
        if skipGoogleRestore {
            model.connectionState = authClient.connectionState()
            refreshUI()
            return
        }
        do {
            try await authClient.restorePreviousSignIn()
            model.connectionState = authClient.connectionState()
            await refreshEvents()
            await refreshGmailUnread()
        } catch {
            AppLog.lifecycle.debug("Saved Google session was not restored")
            model.connectionState = authClient.connectionState()
            model.lastError = nil
            model.lastErrorRecovery = nil
            refreshUI()
            await syncCalendarNotifications()
            syncMeetingFocus()
            syncTeamsPresence()
        }
    }

    private func refreshEvents(showsActivity: Bool = true) async {
        guard !isRefreshingEvents else { return }
        isRefreshingEvents = true
        defer { isRefreshingEvents = false }

        updateNow()
        guard model.connectionState.isConnected else {
            if !model.events.isEmpty {
                model.events = []
            }
            refreshUI()
            cancelCalendarNotifications()
            syncMeetingFocus()
            syncTeamsPresence()
            updateScheduledMeetingRefreshes()
            return
        }

        if showsActivity {
            model.isBusy = true
            model.lastError = nil
            model.lastErrorRecovery = nil
            refreshUI()
        }

        var eventsChanged = false
        do {
            let loadedEvents = try await calendarService.loadUpcomingEvents()
            if model.events != loadedEvents {
                model.events = loadedEvents
                eventsChanged = true
            }
            let connectionState = authClient.connectionState()
            if model.connectionState != connectionState {
                model.connectionState = connectionState
            }
            if model.lastErrorRecovery == .googleConnection {
                model.lastError = nil
                model.lastErrorRecovery = nil
            }
        } catch let error where isExpectedCancellation(error) {
            AppLog.calendar.debug("Calendar refresh cancelled")
        } catch {
            AppLog.calendar.error("Calendar refresh failed: \(error.localizedDescription, privacy: .private)")
            let errorMessage = userFacingError(error)
            if model.lastError != errorMessage {
                model.lastError = errorMessage
            }
            model.lastErrorRecovery = googleRecoveryAction(for: error)
            let connectionState = authClient.connectionState()
            if model.connectionState != connectionState {
                model.connectionState = connectionState
            }
        }

        if showsActivity {
            model.isBusy = false
        }
        refreshUI()
        if eventsChanged {
            await syncCalendarNotifications()
        }
        syncMeetingFocus()
        syncTeamsPresence()
        updateScheduledMeetingRefreshes()
    }

    private func handleScheduledLocalRefresh(_ triggers: Set<LocalRefreshTrigger>) {
        updateNow()
        refreshUI()

        if triggers.contains(.meetingBoundary) {
            syncMeetingFocus()
            syncTeamsPresence()
        } else if triggers.contains(.teamsPresenceRefresh) {
            syncTeamsPresence()
        }
    }

    private func updateScheduledMeetingRefreshes() {
        refreshScheduler.updateMeetings(
            model.events,
            alertLeadMinutes: model.alertLeadMinutes,
            teamsPresenceEnabled: model.teamsPresenceEnabled
        )
    }

    private func refreshUI() {
        updateStatusIcon()
        updateTitle()
    }

    private func updateNow() {
        model.now = Date()
    }

    private func refreshLaunchAtLoginState() {
        model.launchAtLoginEnabled = LaunchAtLoginSettings.isEnabled()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let unreadText = menuBarUnreadText()
        guard statusIconUnreadText != unreadText || button.image == nil else { return }

        statusIconUnreadText = unreadText
        button.image = AppImages.menuBarIcon(unreadCount: menuBarUnreadCount())
    }

    private func updateTitle() {
        switch model.connectionState {
        case .loading:
            setStatusTitle("", toolTip: "Loading Lazyest Work")
        case .missingBundleConfig:
            setStatusTitle("", toolTip: "Google Sign-In is not configured")
        case .signedOut:
            setStatusTitle("", toolTip: "Sign in to Google Calendar")
        case .connected:
            let now = model.now
            if let active = model.events.first(where: {
                $0.selfResponseStatus != .declined && $0.start <= now && $0.end > now
            }) {
                setStatusTitle(
                    statusTitle(meetingText: "Now · \(active.menuBarTitle)"),
                    toolTip: statusToolTip(meetingToolTip: active.statusToolTip)
                )
                return
            }

            guard let next = model.events.first(where: {
                $0.selfResponseStatus != .declined && $0.start > now
            }) else {
                setStatusTitle(statusTitle(), toolTip: statusToolTip(meetingToolTip: "No upcoming meetings"))
                return
            }

            let secondsUntilStart = next.start.timeIntervalSince(now)
            let leadWindow = TimeInterval(model.alertLeadMinutes * 60)
            if secondsUntilStart <= leadWindow {
                let minutes = max(1, Int(ceil(secondsUntilStart / 60)))
                setStatusTitle(
                    statusTitle(meetingText: "\(minutes)m · \(next.menuBarTitle)"),
                    toolTip: statusToolTip(meetingToolTip: next.statusToolTip)
                )
            } else {
                setStatusTitle(
                    statusTitle(),
                    toolTip: statusToolTip(meetingToolTip: "\(next.title) at \(next.startTimeText)")
                )
            }
        }
    }

    private func statusTitle(meetingText: String? = nil) -> String {
        let parts = [meetingText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        guard !parts.isEmpty else { return "" }
        return " \(parts.joined(separator: " · "))"
    }

    private func statusToolTip(meetingToolTip: String?) -> String? {
        [gmailToolTipText(), meetingToolTip]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: "\n")
            .nilIfEmpty
    }

    private func menuBarUnreadCount() -> Int? {
        guard model.mailBadgeEnabled, let count = model.gmailUnreadCount, count > 0 else { return nil }
        return count
    }

    private func menuBarUnreadText() -> String? {
        guard let count = menuBarUnreadCount() else { return nil }
        return UnreadCountFormatter.display(count)
    }

    private func gmailToolTipText() -> String? {
        guard let count = menuBarUnreadCount() else { return nil }
        return "Gmail Inbox unread: \(UnreadCountFormatter.display(count))"
    }

    private func openURLFromMenu(_ url: URL) {
        if WorkspaceApp.isGmailURL(url),
           model.mailBadgeEnabled,
           model.connectionState.isConnected {
            refreshScheduler.startGmailUnreadReconciliation(
                baselineCount: model.gmailUnreadCount
            )
        }
        NSWorkspace.shared.open(url)
    }

    private func openWorkspaceURLFromMenu(_ url: URL) {
        // Opening a Google app hands focus to Chrome. Keep the menu-bar
        // interaction complete instead of leaving its popover floating above it.
        popover.performClose(nil)
        openURLFromMenu(url)
    }

    private func setStatusTitle(_ title: String, toolTip: String?) {
        guard let button = statusItem.button else { return }
        let imagePosition: NSControl.ImagePosition = title.isEmpty ? .imageOnly : .imageLeading
        if renderedStatusTitle != title {
            button.title = title
            renderedStatusTitle = title
        }
        if button.imagePosition != imagePosition {
            button.imagePosition = imagePosition
        }
        if button.toolTip != toolTip {
            button.toolTip = toolTip
        }
    }

    @objc private func signIn() {
        popover.performClose(nil)
        Task {
            model.isBusy = true
            model.lastError = nil
            model.lastErrorRecovery = nil
            model.gmailError = nil
            model.gmailErrorRecovery = nil
            refreshUI()

            do {
                let grant = try await authClient.signIn(
                    includeGmailLabels: model.mailBadgeEnabled
                )
                model.connectionState = authClient.connectionState()
                await refreshEvents()
                if model.mailBadgeEnabled {
                    if grant.gmailLabelsGranted {
                        await refreshGmailUnread()
                    } else {
                        model.mailBadgeEnabled = false
                        model.gmailUnreadCount = nil
                        model.gmailError = text.s(
                            "Gmail unread count was not allowed.",
                            "Gmail 안 읽은 개수 권한이 허용되지 않았습니다."
                        )
                        model.gmailErrorRecovery = .gmailPermission
                    }
                } else {
                    model.gmailUnreadCount = nil
                }
            } catch let error where isExpectedCancellation(error) {
                AppLog.lifecycle.debug("Scheduled refresh cancelled")
            } catch {
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = googleRecoveryAction(for: error)
                model.connectionState = authClient.connectionState()
            }

            model.isBusy = false
            refreshUI()
        }
    }

    @objc private func refreshFromMenu() {
        Task {
            updateNow()
            await refreshEvents()
            await refreshGmailUnread()
        }
    }

    @objc private func signOut() {
        authClient.signOut()
        refreshScheduler.cancelGmailUnreadReconciliation()
        model.events = []
        model.gmailUnreadCount = nil
        model.calendarNotificationsEnabled = false
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.gmailError = nil
        model.gmailErrorRecovery = nil
        model.connectionState = authClient.connectionState()
        cancelCalendarNotifications()
        turnOffManagedMeetingFocus()
        syncTeamsPresence()
        updateScheduledMeetingRefreshes()
        refreshUI()
    }

    private func updateWorkspaceApps(_ apps: [WorkspaceApp]) {
        guard model.workspaceApps != apps else { return }
        model.workspaceApps = apps
        WorkspaceAppStore.save(apps)
        refreshUI()
    }

    private func updateLanguage(_ language: AppLanguage) {
        guard model.language != language else { return }
        model.language = language
        if !model.meetingFocusStatusText.isEmpty {
            model.meetingFocusStatusText = text.dndPausedSubtitle
        }
        if model.teamsPresenceStatusText == AppText(language: .english).teamsManualPause ||
            model.teamsPresenceStatusText == AppText(language: .korean).teamsManualPause {
            model.teamsPresenceStatusText = text.teamsManualPause
        }
        refreshTeamsCallBlockPermissions()
        refreshUI()
    }

    private func updateAlertLeadMinutes(_ minutes: Int) {
        guard model.alertLeadMinutes != minutes else { return }
        model.alertLeadMinutes = minutes
        model.lastError = nil
        model.lastErrorRecovery = nil
        refreshUI()
        updateScheduledMeetingRefreshes()
        Task {
            await syncCalendarNotifications()
        }
    }

    private func updateCalendarNotificationsEnabled(_ isEnabled: Bool) {
        guard model.calendarNotificationsEnabled != isEnabled else { return }
        model.calendarNotificationsEnabled = isEnabled
        model.lastError = nil
        model.lastErrorRecovery = nil
        refreshUI()
        Task {
            await syncCalendarNotifications()
        }
    }

    private func updateMeetingFocusEnabled(_ isEnabled: Bool) -> Bool {
        if !isEnabled {
            cancelPendingMeetingFocusApproval()
            guard model.meetingFocusEnabled else { return false }
            model.meetingFocusEnabled = false
            model.lastError = nil
            model.lastErrorRecovery = nil
            refreshUI()
            syncMeetingFocus()
            return false
        }

        guard model.meetingFocusEnabled != isEnabled else { return model.meetingFocusEnabled }
        if isEnabled {
            do {
                guard try meetingFocusBridge.isHelperShortcutInstalled() else {
                    model.meetingFocusHelperInstalled = false
                    model.meetingFocusApprovalPending = true
                    model.meetingFocusEnabled = false
                    model.lastError = nil
                    model.lastErrorRecovery = nil
                    refreshUI()
                    return false
                }
                cancelPendingMeetingFocusApproval()
                model.meetingFocusHelperInstalled = true
            } catch {
                cancelPendingMeetingFocusApproval()
                model.meetingFocusEnabled = false
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = nil
                refreshUI()
                return false
            }
        }
        model.meetingFocusEnabled = isEnabled
        model.lastError = nil
        model.lastErrorRecovery = nil
        refreshUI()
        syncMeetingFocus()
        return model.meetingFocusEnabled
    }

    private func requestMeetingFocusApproval() {
        do {
            guard try meetingFocusBridge.isHelperShortcutInstalled() else {
                try meetingFocusBridge.openHelperInstaller()
                model.meetingFocusHelperInstalled = false
                model.meetingFocusApprovalPending = true
                model.lastError = "Click Add Shortcut once in macOS. Lazyest Work turns Do Not Disturb on automatically after approval."
                model.lastErrorRecovery = nil
                refreshUI()
                watchForMeetingFocusApproval()
                return
            }
            model.meetingFocusApprovalPending = true
            _ = enableMeetingFocusAfterHelperApproval()
        } catch {
            cancelPendingMeetingFocusApproval()
            model.meetingFocusEnabled = false
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = nil
            refreshUI()
        }
    }

    private func refreshMeetingFocusHelperStatus() {
        let bridge = meetingFocusBridge
        Task { @MainActor [weak self] in
            let isInstalled = await Task.detached(priority: .utility) {
                (try? bridge.isHelperShortcutInstalled()) ?? false
            }.value
            guard let self, !Task.isCancelled else { return }
            self.model.meetingFocusHelperInstalled = isInstalled
            if isInstalled, self.enableMeetingFocusAfterHelperApproval(isHelperInstalled: true) {
                return
            }
            if !isInstalled, self.model.meetingFocusEnabled {
                self.model.meetingFocusEnabled = false
            }
        }
    }

    private func watchForMeetingFocusApproval() {
        meetingFocusApprovalTask?.cancel()
        meetingFocusApprovalTask = Task { [weak self] in
            for _ in 0..<60 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard let bridge = self?.meetingFocusBridge else { return }
                let isInstalled = await Task.detached(priority: .utility) {
                    (try? bridge.isHelperShortcutInstalled()) == true
                }.value
                let didEnable = await MainActor.run {
                    self?.enableMeetingFocusAfterHelperApproval(isHelperInstalled: isInstalled) ?? false
                }
                if didEnable { return }
            }
            await MainActor.run {
                self?.finishMeetingFocusApprovalWatch()
            }
        }
    }

    private func enableMeetingFocusAfterHelperApproval(isHelperInstalled: Bool? = nil) -> Bool {
        guard model.meetingFocusApprovalPending else { return false }
        guard isHelperInstalled ?? ((try? meetingFocusBridge.isHelperShortcutInstalled()) == true) else { return false }
        meetingFocusApprovalTask?.cancel()
        meetingFocusApprovalTask = nil
        model.meetingFocusApprovalPending = false
        model.meetingFocusHelperInstalled = true
        model.meetingFocusEnabled = true
        model.lastError = nil
        model.lastErrorRecovery = nil
        refreshUI()
        syncMeetingFocus()
        return true
    }

    private func finishMeetingFocusApprovalWatch() {
        meetingFocusApprovalTask = nil
        guard model.meetingFocusApprovalPending else { return }
        model.meetingFocusApprovalPending = false
        model.lastError = "Do Not Disturb approval was not completed. Click Approve to retry."
        model.lastErrorRecovery = nil
        refreshUI()
    }

    private func cancelPendingMeetingFocusApproval() {
        meetingFocusApprovalTask?.cancel()
        meetingFocusApprovalTask = nil
        model.meetingFocusApprovalPending = false
    }

    private func refreshMicrosoftConnectionState() {
        model.teamsSetupConfig = MicrosoftSetupSettings.load()
        microsoftAuthClient.configure(model.teamsSetupConfig)
        if model.teamsSetupConfig.isComplete {
            model.teamsConnectionState = microsoftAuthClient.connectionState()
        } else {
            model.teamsConnectionState = microsoftCLIClient.isAvailable ? .signedOut : .missingSetup
        }
        normalizeTeamsPresenceAvailability()
    }

    private func normalizeTeamsPresenceAvailability() {
        guard model.teamsPresenceEnabled else { return }

        switch model.teamsConnectionState {
        case .connected:
            return
        case .missingSetup:
            model.teamsPresenceStatusText = "Off. Install Microsoft 365 CLI for one-time setup."
        case .signedOut:
            model.teamsPresenceStatusText = "Off. Complete Microsoft setup before turning on Teams Busy."
        case .failed:
            model.teamsPresenceStatusText = "Microsoft connection check failed."
        }
    }

    private func installMicrosoft365CLI() {
        guard model.teamsOperation == .idle, !microsoftCLIClient.isAvailable else { return }
        model.teamsOperation = .installingCLI
        model.lastError = nil
        model.lastErrorRecovery = nil
        refreshUI()

        Task {
            do {
                try await microsoftCLIClient.installIfNeeded()
                model.teamsConnectionState = .signedOut
                model.lastError = nil
                model.lastErrorRecovery = nil
            } catch {
                model.teamsConnectionState = .missingSetup
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = nil
            }
            model.teamsOperation = .idle
            refreshUI()
        }
    }

    private func connectMicrosoftTeams() {
        guard model.teamsOperation == .idle else { return }
        guard model.teamsSetupConfig.isComplete else {
            setUpMicrosoftTeams()
            return
        }

        do {
            let config = try model.teamsSetupConfig.normalized()
            model.teamsSetupConfig = config
            microsoftAuthClient.configure(config)
        } catch {
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = nil
            refreshUI()
            return
        }

        popover.performClose(nil)
        model.teamsOperation = .signingIn
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.teamsPresenceStatusText = "Opening Microsoft sign-in."
        refreshUI()

        Task {
            do {
                try? await teamsPresenceService.clearManagedPresenceIfNeeded()
                try await microsoftAuthClient.signIn(config: model.teamsSetupConfig)
                teamsPresenceService.clearLocalManagedState()
                refreshMicrosoftConnectionState()
                model.teamsPresenceStatusText = "Connected. Turn on Teams Busy for accepted meetings."
                syncTeamsPresence()
            } catch {
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = nil
                model.teamsPresenceStatusText = "Microsoft sign-in did not finish."
                if model.teamsSetupConfig.usesLoopbackRedirect,
                   error.localizedDescription.localizedCaseInsensitiveContains("aadsts700016") {
                    MicrosoftSetupSettings.clearPersonalApp()
                    try? microsoftAuthClient.signOut()
                }
                refreshMicrosoftConnectionState()
            }
            model.teamsOperation = .idle
            refreshUI()
        }
    }

    private func setUpMicrosoftTeams() {
        guard model.teamsOperation == .idle else { return }
        guard microsoftCLIClient.isAvailable else {
            model.lastError = "Install Microsoft 365 CLI first."
            model.lastErrorRecovery = nil
            refreshUI()
            return
        }
        model.teamsOperation = .settingUp
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.teamsPresenceStatusText = "Creating your Microsoft sign-in app for one-time setup."
        refreshUI()

        Task {
            do {
                let config = try await microsoftCLIClient.bootstrapPersonalApp()
                try MicrosoftSetupSettings.savePersonalApp(config)
                model.teamsSetupConfig = MicrosoftSetupSettings.load()
                microsoftAuthClient.configure(model.teamsSetupConfig)
                model.teamsOperation = .signingIn
                model.teamsPresenceStatusText = "Opening Microsoft sign-in."
                refreshUI()

                try await microsoftAuthClient.signIn(config: model.teamsSetupConfig)
                teamsPresenceService.clearLocalManagedState()
                refreshMicrosoftConnectionState()
                model.teamsPresenceStatusText = "Connected. Turn on Teams Busy for accepted meetings."
                syncTeamsPresence()
            } catch {
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = nil
                model.teamsPresenceStatusText = "Microsoft setup did not finish."
                refreshMicrosoftConnectionState()
            }
            model.teamsOperation = .idle
            refreshUI()
        }
    }

    private func signOutMicrosoftTeams() {
        guard model.teamsOperation == .idle else { return }
        model.teamsOperation = .signingOut
        model.teamsPresenceEnabled = false
        updateScheduledMeetingRefreshes()
        model.teamsPresenceStatusText = "Signing out of Microsoft."
        teamsPresenceTask?.cancel()
        teamsPresenceTask = Task {
            var presenceClearError: Error?
            do {
                try await teamsPresenceService.clearManagedPresenceIfNeeded()
            } catch {
                presenceClearError = error
            }

            do {
                try microsoftAuthClient.signOut()
                teamsPresenceService.clearLocalManagedState()
                refreshMicrosoftConnectionState()
                model.lastError = presenceClearError.map(userFacingError)
                model.lastErrorRecovery = nil
                model.teamsPresenceStatusText = presenceClearError == nil
                    ? "Signed out. Teams Busy is off."
                    : "Signed out. The previous Teams Busy status could not be cleared."
            } catch {
                teamsPresenceService.clearLocalManagedState()
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = nil
                model.teamsPresenceStatusText = "Microsoft sign-out did not finish."
            }
            model.teamsOperation = .idle
            refreshUI()
        }
    }

    private func updateTeamsPresenceEnabled(_ isEnabled: Bool) -> Bool {
        if !isEnabled {
            guard model.teamsPresenceEnabled else { return false }
            model.teamsPresenceEnabled = false
            model.lastError = nil
            model.lastErrorRecovery = nil
            model.teamsPresenceStatusText = "Off. Teams Busy automation is disabled."
            refreshUI()
            syncTeamsPresence()
            updateScheduledMeetingRefreshes()
            return false
        }

        if !model.teamsSetupConfig.isComplete {
            model.teamsPresenceEnabled = false
            model.teamsPresenceStatusText = "Complete Microsoft setup before turning on Teams Busy."
            model.lastError = microsoftCLIClient.isAvailable
                ? "Complete Microsoft setup first."
                : "Install Microsoft 365 CLI, then complete Microsoft setup."
            model.lastErrorRecovery = nil
            refreshUI()
            updateScheduledMeetingRefreshes()
            return false
        }

        refreshMicrosoftConnectionState()
        guard model.teamsConnectionState.isConnected else {
            model.teamsPresenceEnabled = false
            model.teamsPresenceStatusText = "Connect Microsoft before turning on Teams Busy."
            model.lastError = "Connect Microsoft once before enabling Teams Busy."
            model.lastErrorRecovery = nil
            refreshUI()
            updateScheduledMeetingRefreshes()
            return false
        }

        model.teamsPresenceEnabled = true
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.teamsPresenceStatusText = "Checking accepted meetings now."
        refreshUI()
        syncTeamsPresence()
        updateScheduledMeetingRefreshes()
        return true
    }

    private func updateTeamsCallBlockEnabled(_ isEnabled: Bool) -> Bool {
        model.lastError = nil
        model.lastErrorRecovery = nil

        if isEnabled, !requestTeamsAccessibilityPermissionIfNeeded() {
            refreshTeamsCallBlockPermissions()
            return false
        }

        let enabled = teamsCallBlocker.setEnabled(isEnabled)
        model.teamsCallBlockEnabled = enabled
        model.teamsCallBlockPermissionPending = teamsCallBlocker.isPendingEnableAfterPermission
        model.teamsCallBlockStatusText = teamsCallBlocker.statusText
        refreshUI()
        return enabled
    }

    private func updateTeamsControlScrollBlockEnabled(_ isEnabled: Bool) -> Bool {
        model.lastError = nil
        model.lastErrorRecovery = nil

        if isEnabled, !requestTeamsAccessibilityPermissionIfNeeded() {
            refreshTeamsCallBlockPermissions()
            return false
        }

        let enabled = teamsCallBlocker.setControlScrollBlockEnabled(isEnabled)
        model.teamsControlScrollBlockEnabled = enabled
        model.teamsCallBlockPermissionPending = teamsCallBlocker.isPendingEnableAfterPermission
        model.teamsCallBlockStatusText = teamsCallBlocker.statusText
        refreshUI()
        return enabled
    }

    private func requestTeamsAccessibilityPermissionIfNeeded() -> Bool {
        teamsCallBlocker.refreshPermissions()
        guard !teamsCallBlocker.permissionState.isReady else {
            return true
        }

        _ = TeamsCallBlockPermissionState.requestAccessibilityPermission()
        return false
    }

    private func refreshTeamsCallBlockPermissions() {
        teamsCallBlocker.refreshPermissions()
        model.teamsCallBlockEnabled = teamsCallBlocker.isEnabled
        model.teamsControlScrollBlockEnabled = teamsCallBlocker.isControlScrollBlockEnabled
        model.teamsCallBlockPermissionPending = teamsCallBlocker.isPendingEnableAfterPermission
        model.teamsCallBlockStatusText = teamsCallBlocker.statusText
        refreshUI()
    }

    private func syncTeamsPresence() {
        let automationEnabled = model.teamsPresenceEnabled
        let calendarConnected = model.connectionState.isConnected
        let teamsConnected = model.teamsConnectionState.isConnected

        guard teamsConnected else {
            refreshMicrosoftConnectionState()
            switch model.teamsConnectionState {
            case .missingSetup:
                model.teamsPresenceStatusText = "Off. Install Microsoft 365 CLI for one-time setup."
            case .signedOut:
                model.teamsPresenceStatusText = "Off. Complete Microsoft setup or connect Microsoft."
            case .failed:
                model.teamsPresenceStatusText = "Microsoft connection check failed."
            case .connected:
                break
            }
            refreshUI()
            return
        }

        let desiredState = TeamsPresencePolicy.desiredState(
            events: model.events,
            now: model.now,
            isEnabled: automationEnabled &&
                calendarConnected &&
                teamsConnected
        )
        teamsPresenceTask?.cancel()
        teamsPresenceTask = Task {
            do {
                let result = try await teamsPresenceService.apply(desiredState, now: model.now)
                model.teamsPresenceStatusText = teamsPresenceStatusText(
                    for: result,
                    desiredState: desiredState,
                    automationEnabled: automationEnabled,
                    calendarConnected: calendarConnected,
                    teamsConnected: teamsConnected
                )
                refreshMicrosoftConnectionState()
            } catch let error where isExpectedCancellation(error) {
                AppLog.teamsPresence.debug("Teams presence sync cancelled")
            } catch {
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = nil
                model.teamsPresenceStatusText = "Teams Busy could not be updated."
                refreshMicrosoftConnectionState()
            }
            refreshUI()
        }
    }

    private func teamsPresenceStatusText(
        for result: TeamsPresenceApplyResult,
        desiredState: MeetingFocusState,
        automationEnabled: Bool,
        calendarConnected: Bool,
        teamsConnected: Bool
    ) -> String {
        switch result {
        case .applied(let until):
            return "Teams preferred status set to Busy until \(shortPresenceTime(until)). Teams may take a few minutes to show it."
        case .alreadyActive(let until):
            return "Teams preferred status is already Busy until \(shortPresenceTime(until)). Teams may take a few minutes to show it."
        case .cleared:
            if !automationEnabled {
                return "Off. Cleared Teams preferred status."
            }
            return "No active accepted meeting now. Cleared Teams preferred status."
        case .pausedForManualOverride:
            return text.teamsManualPause
        case .idle:
            break
        }

        guard teamsConnected else {
            return "Connect Microsoft before turning on Teams Busy."
        }
        guard automationEnabled else {
            return "Off. Teams Busy automation is disabled."
        }
        guard calendarConnected else {
            return "Connect Google Calendar to use accepted meeting automation."
        }

        switch desiredState {
        case .active:
            return "Active accepted meeting found. Teams Busy will refresh before it expires."
        case .inactive:
            return "Watching accepted meetings. No active accepted meeting now."
        }
    }

    private func shortPresenceTime(_ date: Date) -> String {
        AppDateFormatters.shortTimeString(from: date)
    }

    private func updateMailBadgeEnabled(_ isEnabled: Bool) {
        guard model.mailBadgeEnabled != isEnabled else { return }
        model.mailBadgeEnabled = isEnabled
        model.gmailError = nil
        model.gmailErrorRecovery = nil
        refreshUI()

        Task {
            if isEnabled {
                await enableGmailUnreadBadge()
            } else {
                refreshScheduler.cancelGmailUnreadReconciliation()
                model.gmailUnreadCount = nil
                model.gmailError = nil
                model.gmailErrorRecovery = nil
                refreshUI()
            }
        }
    }

    private func updateLaunchAtLoginEnabled(_ isEnabled: Bool) {
        model.lastError = nil
        model.lastErrorRecovery = nil
        applyLaunchAtLoginSetting(isEnabled)
        refreshUI()
    }

    private func applyLaunchAtLoginSetting(_ isEnabled: Bool) {
        guard model.launchAtLoginEnabled != isEnabled else { return }
        do {
            try LaunchAtLoginSettings.setEnabled(isEnabled)
            model.launchAtLoginEnabled = LaunchAtLoginSettings.isEnabled()
            if isEnabled, LaunchAtLoginSettings.status == .requiresApproval {
                model.lastError = text.s(
                    "Allow Lazyest Work in Login Items.",
                    "로그인 항목에서 Lazyest Work를 허용하세요."
                )
                model.lastErrorRecovery = .loginItemsSettings
            }
        } catch {
            model.launchAtLoginEnabled = LaunchAtLoginSettings.isEnabled()
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = nil
        }
    }

    private func syncCalendarNotifications() async {
        guard model.calendarNotificationsEnabled, model.connectionState.isConnected else {
            cancelCalendarNotifications()
            return
        }

        do {
            try await ensureNotificationAuthorization()
            try await scheduleCalendarNotifications()
        } catch let error where isExpectedCancellation(error) {
            AppLog.calendar.debug("Calendar notification sync cancelled")
        } catch {
            model.calendarNotificationsEnabled = false
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = .notificationSettings
            cancelCalendarNotifications()
            refreshUI()
        }
    }

    private func scheduleCalendarNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let now = Date()
        let leadSeconds = TimeInterval(model.alertLeadMinutes * 60)
        for event in model.events {
            guard event.selfResponseStatus != .declined else { continue }
            let fireDate = event.start.addingTimeInterval(-leadSeconds)
            let identifier = event.notificationIdentifier(leadMinutes: model.alertLeadMinutes)
            guard fireDate > now.addingTimeInterval(3) else {
                continue
            }
            guard !shouldSuppressCalendarNotification(at: fireDate) else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.subtitle = model.alertLeadMinutes == 1 ? "Meeting in 1 minute" : "Meeting in \(model.alertLeadMinutes) minutes"
            content.body = [event.timeText, event.roomLine]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            content.sound = .default
            content.userInfo = [
                "type": "calendar",
                "url": (event.meetingURL ?? event.htmlLink ?? WorkspaceApp.calendarURL).absoluteString
            ]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try await addNotificationRequest(request)
        }
    }

    private func cancelCalendarNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func sendTestCalendarNotificationFromSettings() {
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.isBusy = true
        refreshUI()

        Task {
            await sendTestCalendarNotification()
            model.isBusy = false
            refreshUI()
        }
    }

    private func sendTestCalendarNotification() async {
        do {
            try await ensureNotificationAuthorization()

            let content = UNMutableNotificationContent()
            content.title = "Lazyest Work"
            content.subtitle = "Test meeting alert"
            content.body = "Meeting notifications are working."
            content.sound = .default
            content.userInfo = [
                "type": "calendar-test",
                "url": WorkspaceApp.calendarURL.absoluteString
            ]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "lazyest-work-test-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )
            try await addNotificationRequest(request)
        } catch {
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = .notificationSettings
        }
    }

    private func shouldSuppressCalendarNotification(at date: Date = Date()) -> Bool {
        return MeetingNotificationPolicy.shouldSuppressNotifications(
            events: model.events,
            at: date
        )
    }

    private func syncMeetingFocus() {
        let desiredState = MeetingFocusPolicy.desiredState(
            events: model.events,
            now: model.now,
            isEnabled: model.meetingFocusEnabled && model.connectionState.isConnected
        )
        meetingFocusSyncTask?.cancel()
        let generation = UUID()
        meetingFocusSyncGeneration = generation
        let bridge = meetingFocusBridge
        meetingFocusSyncTask = Task { @MainActor [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                do {
                    return Result<MeetingFocusApplyResult, AppError>.success(try bridge.apply(desiredState))
                } catch {
                    return Result<MeetingFocusApplyResult, AppError>.failure(.api(error.localizedDescription))
                }
            }.value

            guard let self,
                  !Task.isCancelled,
                  self.meetingFocusSyncGeneration == generation else {
                return
            }
            switch outcome {
            case .success(let result):
                AppLog.meetingFocus.debug("Meeting Focus sync completed")
                self.model.meetingFocusStatusText = self.meetingFocusStatusText(for: result)
            case .failure(let error):
                AppLog.meetingFocus.error("Meeting Focus sync failed: \(error.localizedDescription, privacy: .private)")
                self.model.lastError = self.userFacingError(error)
                self.model.lastErrorRecovery = nil
            }
            self.meetingFocusSyncTask = nil
            self.refreshUI()
        }
    }

    private func turnOffManagedMeetingFocus() {
        do {
            _ = try meetingFocusBridge.apply(.inactive)
            model.meetingFocusStatusText = ""
        } catch {
            AppLog.meetingFocus.error("Failed to turn off managed Meeting Focus: \(error.localizedDescription, privacy: .private)")
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = nil
        }
    }

    private func meetingFocusStatusText(for result: MeetingFocusApplyResult) -> String {
        switch result {
        case .pausedForManualOverride:
            return text.dndPausedSubtitle
        case .idle, .activated, .alreadyActive, .cleared:
            return ""
        }
    }

    private func enableGmailUnreadBadge() async {
        do {
            if model.connectionState.isConnected {
                try await authClient.ensureGmailLabelsScope()
                model.gmailError = nil
                model.gmailErrorRecovery = nil
                await refreshGmailUnread()
            }
        } catch {
            model.gmailUnreadCount = nil
            model.mailBadgeEnabled = false
            model.gmailError = gmailUserFacingError(error)
            model.gmailErrorRecovery = gmailRecoveryAction(for: error)
            refreshUI()
        }
    }

    @discardableResult
    private func refreshGmailUnread() async -> Int? {
        // Only a newly completed request is valid evidence for unread
        // reconciliation. Returning the cached count here could make a failed
        // request look like a stable result.
        guard !isRefreshingGmail else { return nil }
        isRefreshingGmail = true
        defer { isRefreshingGmail = false }

        guard model.mailBadgeEnabled, model.connectionState.isConnected else {
            model.gmailUnreadCount = nil
            return nil
        }

        do {
            let unreadCount = try await gmailService.loadInboxUnreadCount()
            model.gmailUnreadCount = unreadCount
            model.gmailError = nil
            model.gmailErrorRecovery = nil
            refreshUI()
            return unreadCount
        } catch let error where isExpectedCancellation(error) {
            AppLog.gmail.debug("Gmail unread refresh cancelled")
            return nil
        } catch {
            AppLog.gmail.error("Gmail unread refresh failed: \(error.localizedDescription, privacy: .private)")
            let recovery = gmailRecoveryAction(for: error)
            model.gmailError = gmailUserFacingError(error)
            model.gmailErrorRecovery = recovery
            if recovery == .gmailPermission {
                model.mailBadgeEnabled = false
                model.gmailUnreadCount = nil
                refreshScheduler.cancelGmailUnreadReconciliation()
            }
            refreshUI()
            return nil
        }
    }

    private func enableGmailBadgeFromMenu() {
        guard model.connectionState.isConnected else { return }
        popover.performClose(nil)
        model.mailBadgeEnabled = true
        model.gmailError = nil
        model.gmailErrorRecovery = nil
        model.isBusy = true
        refreshUI()

        Task {
            await enableGmailUnreadBadge()
            model.isBusy = false
            refreshUI()
        }
    }

    private func enableCalendarAlertsFromMenu() {
        guard model.connectionState.isConnected else { return }
        model.calendarNotificationsEnabled = true
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.isBusy = true
        refreshUI()

        Task {
            await syncCalendarNotifications()
            model.isBusy = false
            refreshUI()
        }
    }

    private func enableLaunchAtLoginFromMenu() {
        model.lastError = nil
        model.lastErrorRecovery = nil
        applyLaunchAtLoginSetting(true)
        refreshUI()
    }

    private func dismissSetupChecklist() {
        model.setupChecklistDismissed = true
        refreshUI()
    }

    private func ensureNotificationAuthorization() async throws {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = try await requestNotificationAuthorization()
            if !granted {
                throw AppError.notificationPermissionDenied
            }
        case .denied:
            throw AppError.notificationPermissionDenied
        @unknown default:
            throw AppError.notificationPermissionDenied
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await UNUserNotificationCenter.current().notificationSettings()
    }

    private func requestNotificationAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let urlString = response.notification.request.content.userInfo["url"] as? String
        if let urlString, let url = URL(string: urlString) {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(anchor: button)
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        updateNow()
        refreshLaunchAtLoginState()
        refreshMeetingFocusHelperStatus()
        refreshMicrosoftConnectionState()
        refreshTeamsCallBlockPermissions()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        refreshScheduler.requestRemoteRefresh(.popoverOpened)
    }

    private func showStatusMenu(anchor: NSStatusBarButton) {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit Lazyest Work", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func userFacingError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if let apiError = error as? GoogleAPIError {
            if apiError.service == .gmail {
                return gmailUserFacingError(apiError)
            }
            if apiError.isUnavailableInBuild {
                return text.s(
                    "Calendar is unavailable in this build.",
                    "이 빌드에서는 캘린더를 사용할 수 없습니다."
                )
            }
            if apiError.requiresReconnect {
                return text.s(
                    "Google connection expired. Connect again.",
                    "Google 연결이 만료되었습니다. 다시 연결하세요."
                )
            }
            if apiError.isTransient {
                return text.s(
                    "Calendar refresh will retry shortly.",
                    "캘린더를 잠시 후 다시 확인합니다."
                )
            }
        }
        if case AppError.gmailScopeNotGranted = error {
            return gmailUserFacingError(error)
        }
        if !lowercased.contains("microsoft"),
           lowercased.contains("client_secret") || lowercased.contains("invalid_client") {
            return text.s(
                "Google connection is unavailable in this build.",
                "이 빌드에서는 Google에 연결할 수 없습니다."
            )
        }
        if !lowercased.contains("microsoft"),
           lowercased.contains("redirect_uri_mismatch") || lowercased.contains("url scheme") {
            return text.s(
                "Google could not return to Lazyest Work. Install the latest build.",
                "Google이 Lazyest Work로 돌아오지 못했습니다. 최신 빌드를 설치하세요."
            )
        }
        if lowercased.contains("homebrew") {
            return text.s(
                "Homebrew is required to install Microsoft 365 CLI.",
                "Microsoft 365 CLI 설치에 Homebrew가 필요합니다."
            )
        }
        if (lowercased.contains("microsoft 365 cli") || lowercased.contains("m365")) &&
            (lowercased.contains("install") || lowercased.contains("npm") || lowercased.contains("node.js")) {
            return text.s(
                "Microsoft 365 CLI installation failed. Check Homebrew/Node.js, then retry.",
                "Microsoft 365 CLI 설치에 실패했습니다. Homebrew와 Node.js를 확인한 뒤 다시 시도하세요."
            )
        }
        if lowercased.contains("microsoft one-time setup could not create") {
            if lowercased.contains("403") ||
                lowercased.contains("insufficient privileges") ||
                lowercased.contains("authorization_requestdenied") {
                return text.s(
                    "Your organization does not allow this account to create its personal Microsoft sign-in app.",
                    "조직에서 이 계정의 개인 Microsoft 로그인 앱 생성을 허용하지 않습니다."
                )
            }
            return text.s(
                "The Microsoft sign-in app could not be created during one-time setup. Try again.",
                "Microsoft 1회 설정용 로그인 앱을 만들지 못했습니다. 다시 시도하세요."
            )
        }
        if lowercased.contains("microsoft one-time setup sign-in failed") {
            return text.s(
                "Microsoft one-time setup sign-in was denied or did not finish.",
                "Microsoft 1회 설정 로그인이 거부되었거나 완료되지 않았습니다."
            )
        }
        if lowercased.contains("microsoft") || lowercased.contains("graph") || lowercased.contains("teams") ||
            lowercased.contains("presencereadwrite") || lowercased.contains("presence.readwrite") {
            if lowercased.contains("keychain") {
                return "Teams status could not read or save credentials in Keychain. Try Connect Microsoft again."
            }
            if lowercased.contains("redirect_uri_mismatch") {
                return text.s(
                    "The personal Microsoft sign-in app has an invalid callback. Run Microsoft setup again.",
                    "개인 Microsoft 로그인 앱의 콜백 설정이 올바르지 않습니다. Microsoft 설정을 다시 진행하세요."
                )
            }
            if lowercased.contains("access_denied") {
                return text.s(
                    "Microsoft sign-in was denied. Allow profile and Teams presence access, then try again.",
                    "Microsoft 로그인이 거부되었습니다. 프로필과 Teams 상태 권한을 허용한 뒤 다시 시도하세요."
                )
            }
            if lowercased.contains("aadsts700016") {
                return text.s(
                    "Your personal Microsoft sign-in app no longer exists. Click Sign in again to recreate it.",
                    "개인 Microsoft 로그인 앱이 더 이상 없습니다. 로그인을 다시 눌러 재생성하세요."
                )
            }
            if lowercased.contains("aadsts65001") || lowercased.contains("admin") || lowercased.contains("consent") {
                return "Teams status needs permission approval from your Microsoft account or organization."
            }
            if lowercased.contains("not configured") {
                return "Teams status is not available in this build."
            }
            if lowercased.contains("not connected") || lowercased.contains("sign-in") || lowercased.contains("sign in") {
                return "Connect Microsoft once before enabling Teams Busy."
            }
            return "Teams status could not be updated."
        }
        if lowercased.contains("keychain") {
            return text.s(
                "Google credentials could not be read from Keychain. Connect again.",
                "Keychain에서 Google 로그인을 읽지 못했습니다. 다시 연결하세요."
            )
        }
        if lowercased.contains("gmail") || lowercased.contains("mail") {
            return gmailUserFacingError(error)
        }
        if lowercased.contains("notification") {
            return "macOS notification permission is off. Meeting alerts cannot be scheduled."
        }
        if lowercased.contains("focus shortcut") || lowercased.contains("shortcuts") {
            return "Do Not Disturb during meetings needs one-time macOS approval. Click Approve, then Add Shortcut when macOS asks."
        }
        if lowercased.contains("login item") || lowercased.contains("launch") {
            return "Open at login could not be changed."
        }
        if lowercased.contains("access_denied") || lowercased.contains("permission") {
            return "Calendar permission was not granted. Try Sign in again and allow read-only Google Calendar access."
        }
        return message
    }

    private func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func googleRecoveryAction(for error: Error) -> ErrorRecoveryAction? {
        if let apiError = error as? GoogleAPIError {
            return apiError.requiresReconnect ? .googleConnection : nil
        }
        switch error {
        case AppError.notSignedIn, AppError.calendarScopeNotGranted:
            return .googleConnection
        default:
            let message = error.localizedDescription.lowercased()
            return message.contains("access_denied") || message.contains("invalid_grant")
                ? .googleConnection
                : nil
        }
    }

    private func gmailRecoveryAction(for error: Error) -> ErrorRecoveryAction? {
        if let apiError = error as? GoogleAPIError {
            if apiError.requiresReconnect {
                return .googleConnection
            }
            return apiError.requiresAdditionalScope ? .gmailPermission : nil
        }
        if case AppError.notSignedIn = error {
            return .googleConnection
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("invalid_grant") ||
            message.contains("not signed in") ||
            message.contains("keychain") {
            return .googleConnection
        }
        return isGmailPermissionError(error) ? .gmailPermission : nil
    }

    private func gmailUserFacingError(_ error: Error) -> String {
        if let apiError = error as? GoogleAPIError {
            if apiError.isUnavailableInBuild {
                return text.s(
                    "Gmail unread count is unavailable in this build.",
                    "이 빌드에서는 Gmail 안 읽은 개수를 사용할 수 없습니다."
                )
            }
            if apiError.requiresReconnect {
                return text.s(
                    "Google connection expired. Connect again.",
                    "Google 연결이 만료되었습니다. 다시 연결하세요."
                )
            }
            if apiError.requiresAdditionalScope {
                return text.s(
                    "Allow Gmail unread-count access.",
                    "Gmail 안 읽은 개수 접근을 허용하세요."
                )
            }
            if apiError.isTransient {
                return text.s(
                    "Gmail unread count will retry shortly.",
                    "Gmail 안 읽은 개수를 잠시 후 다시 확인합니다."
                )
            }
        }
        if gmailRecoveryAction(for: error) == .googleConnection {
            return text.s(
                "Google connection expired. Connect again.",
                "Google 연결이 만료되었습니다. 다시 연결하세요."
            )
        }
        if isGmailPermissionError(error) {
            return text.s(
                "Allow Gmail unread-count access.",
                "Gmail 안 읽은 개수 접근을 허용하세요."
            )
        }
        return text.s(
            "Gmail unread count could not refresh.",
            "Gmail 안 읽은 개수를 갱신하지 못했습니다."
        )
    }

    private func isGmailPermissionError(_ error: Error) -> Bool {
        if case AppError.gmailScopeNotGranted = error {
            return true
        }
        let message = error.localizedDescription
        return message.localizedCaseInsensitiveContains("gmail unread-count permission") ||
            message.localizedCaseInsensitiveContains("access_denied") ||
            message.localizedCaseInsensitiveContains("scope") ||
            message.localizedCaseInsensitiveContains("cancel")
    }

}

enum PopoverScreen {
    case home
    case appSettings
    case workspaceSettings
}

private struct HomeContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct LazyestWorkPopover: View {
    @ObservedObject var model: AppModel
    @State private var screen = PopoverScreen.home
    @State private var editorID = UUID()
    @State private var isWorkspaceExpanded = false
    @State private var isUpcomingExpanded = false
    @State private var homeContentHeight = PopoverLayout.minimumHomeHeight - PopoverLayout.homeChromeHeight
    @State private var settingsSessionHeight: CGFloat?
    let maximumHeight: CGFloat
    let onPreferredHeightChange: (CGFloat) -> Void
    let onSignIn: () -> Void
    let onRefresh: () -> Void
    let onSignOut: () -> Void
    let onDismissSetupChecklist: () -> Void
    let onEnableCalendarAlerts: () -> Void
    let onEnableGmailBadge: () -> Void
    let onEnableLaunchAtLogin: () -> Void
    let onUpdateLanguage: (AppLanguage) -> Void
    let onUpdateWorkspaceApps: ([WorkspaceApp]) -> Void
    let onUpdateAlertLeadMinutes: (Int) -> Void
    let onUpdateCalendarNotifications: (Bool) -> Void
    let onSendTestCalendarNotification: () -> Void
    let onUpdateMeetingFocus: (Bool) -> Bool
    let onApproveMeetingFocus: () -> Void
    let onInstallMicrosoftCLI: () -> Void
    let onConnectMicrosoftTeams: () -> Void
    let onSignOutMicrosoftTeams: () -> Void
    let onUpdateTeamsPresence: (Bool) -> Bool
    let onUpdateTeamsCallBlock: (Bool) -> Bool
    let onUpdateTeamsControlScrollBlock: (Bool) -> Bool
    let onRefreshTeamsCallBlockPermissions: () -> Void
    let onUpdateMailBadge: (Bool) -> Void
    let onUpdateLaunchAtLogin: (Bool) -> Void
    let onOpenURL: (URL) -> Void
    let onOpenWorkspaceURL: (URL) -> Void

    var body: some View {
        Group {
            switch screen {
            case .home:
                homeView
            case .appSettings:
                AppSettingsView(
                    connectionState: model.connectionState,
                    isBusy: model.isBusy,
                    errorMessage: presentedLastError,
                    errorRecovery: model.lastErrorRecovery,
                    gmailErrorMessage: presentedGmailError,
                    gmailErrorRecovery: model.gmailErrorRecovery,
                    initialAlertLeadMinutes: model.alertLeadMinutes,
                    initialCalendarNotificationsEnabled: model.calendarNotificationsEnabled,
                    currentCalendarNotificationsEnabled: model.calendarNotificationsEnabled,
                    initialLanguage: model.language,
                    currentLanguage: model.language,
                    initialMeetingFocusEnabled: model.meetingFocusEnabled,
                    currentMeetingFocusEnabled: model.meetingFocusEnabled,
                    meetingFocusApprovalPending: model.meetingFocusApprovalPending,
                    meetingFocusStatusText: model.meetingFocusStatusText,
                    initialTeamsPresenceEnabled: model.teamsPresenceEnabled,
                    currentTeamsPresenceEnabled: model.teamsPresenceEnabled,
                    initialTeamsCallBlockEnabled: model.teamsCallBlockEnabled,
                    currentTeamsCallBlockEnabled: model.teamsCallBlockEnabled,
                    initialTeamsControlScrollBlockEnabled: model.teamsControlScrollBlockEnabled,
                    currentTeamsControlScrollBlockEnabled: model.teamsControlScrollBlockEnabled,
                    teamsCallBlockPermissionPending: model.teamsCallBlockPermissionPending,
                    teamsCallBlockStatusText: model.teamsCallBlockStatusText,
                    teamsPresenceStatusText: model.teamsPresenceStatusText,
                    microsoftConnectionState: model.teamsConnectionState,
                    microsoftSetupConfig: model.teamsSetupConfig,
                    microsoftTeamsOperation: model.teamsOperation,
                    initialMailBadgeEnabled: model.mailBadgeEnabled,
                    currentMailBadgeEnabled: model.mailBadgeEnabled,
                    initialLaunchAtLoginEnabled: model.launchAtLoginEnabled,
                    currentLaunchAtLoginEnabled: model.launchAtLoginEnabled,
                    onDone: showHome,
                    onRecoverError: recoverFromError,
                    onSignIn: onSignIn,
                    onSignOut: onSignOut,
                    onOpenNotificationSettings: openNotificationSettings,
                    onOpenGitHub: openGitHub,
                    onUpdateLanguage: onUpdateLanguage,
                    onUpdateAlertLeadMinutes: onUpdateAlertLeadMinutes,
                    onUpdateCalendarNotifications: onUpdateCalendarNotifications,
                    onSendTestCalendarNotification: onSendTestCalendarNotification,
                    onUpdateMeetingFocus: onUpdateMeetingFocus,
                    onApproveMeetingFocus: onApproveMeetingFocus,
                    onInstallMicrosoftCLI: onInstallMicrosoftCLI,
                    onConnectMicrosoftTeams: onConnectMicrosoftTeams,
                    onSignOutMicrosoftTeams: onSignOutMicrosoftTeams,
                    onUpdateTeamsPresence: onUpdateTeamsPresence,
                    onUpdateTeamsCallBlock: onUpdateTeamsCallBlock,
                    onUpdateTeamsControlScrollBlock: onUpdateTeamsControlScrollBlock,
                    onRefreshTeamsCallBlockPermissions: onRefreshTeamsCallBlockPermissions,
                    onUpdateMailBadge: onUpdateMailBadge,
                    onUpdateLaunchAtLogin: onUpdateLaunchAtLogin
                )
                .id(editorID)
            case .workspaceSettings:
                WorkspaceAppsEditor(
                    initialApps: model.workspaceApps,
                    onDone: showHome,
                    onUpdateApps: onUpdateWorkspaceApps
                )
                .id(editorID)
            }
        }
        .frame(width: PopoverLayout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .popoverSurface()
        .onAppear {
            onPreferredHeightChange(preferredHeight)
        }
        .onChange(of: preferredHeight) { _, height in
            onPreferredHeightChange(height)
        }
    }

    private var preferredHeight: CGFloat {
        switch screen {
        case .home:
            return homePreferredHeight
        case .appSettings:
            return settingsSessionHeight
                ?? min(maximumHeight, max(homePreferredHeight, PopoverLayout.settingsMinimumHeight))
        case .workspaceSettings:
            return maximumHeight
        }
    }

    private var homePreferredHeight: CGFloat {
        min(
            maximumHeight,
            max(
                PopoverLayout.minimumHomeHeight,
                PopoverLayout.quantized(homeContentHeight + PopoverLayout.homeChromeHeight)
            )
        )
    }

    private var homeView: some View {
        VStack(spacing: 0) {
            HeaderView(
                connectionState: model.connectionState,
                language: model.language,
                isBusy: model.isBusy,
                onRefresh: onRefresh,
                onOpenSettings: openAppSettings
            )

            MenuDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WorkspaceGrid(
                        apps: model.workspaceApps.filter(\.isEnabled),
                        language: model.language,
                        gmailUnreadCount: model.mailBadgeEnabled ? model.gmailUnreadCount : nil,
                        isExpanded: isWorkspaceExpanded,
                        onToggleExpanded: { isWorkspaceExpanded.toggle() },
                        onManageApps: openWorkspaceSettings,
                        onOpenURL: onOpenWorkspaceURL
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    MenuDivider()

                    VStack(alignment: .leading, spacing: 14) {
                    if let lastError = presentedLastError ?? presentedGmailError {
                        let recovery = presentedLastError == nil
                            ? model.gmailErrorRecovery
                            : model.lastErrorRecovery
                        ErrorBanner(
                            message: lastError,
                            actionTitle: recovery?.buttonTitle,
                            action: recovery.map { recovery in
                                { recoverFromError(recovery) }
                            }
                        )
                    }

                    if !model.connectionState.isConnected || model.events.isEmpty {
                        PrimaryCalendarCard(
                            connectionState: model.connectionState,
                            language: model.language,
                            isBusy: model.isBusy,
                            includesGmail: model.mailBadgeEnabled,
                            onSignIn: onSignIn
                        )
                    }

                    if shouldShowSetupChecklist {
                        FinishSetupCard(
                            isGoogleConnected: model.connectionState.isConnected,
                            alertLeadMinutes: model.alertLeadMinutes,
                            calendarNotificationsEnabled: model.calendarNotificationsEnabled,
                            mailBadgeEnabled: model.mailBadgeEnabled,
                            teamsCallBlockEnabled: model.teamsCallBlockEnabled,
                            teamsCallBlockPermissionPending: model.teamsCallBlockPermissionPending,
                            launchAtLoginEnabled: model.launchAtLoginEnabled,
                            isBusy: model.isBusy,
                            onEnableCalendarAlerts: onEnableCalendarAlerts,
                            onEnableGmailBadge: onEnableGmailBadge,
                            onEnableTeamsCallBlock: { _ = onUpdateTeamsCallBlock(true) },
                            onEnableLaunchAtLogin: onEnableLaunchAtLogin,
                            onDismiss: onDismissSetupChecklist
                        )
                    }

                    UpcomingEventsView(
                        events: model.events,
                        language: model.language,
                        now: model.now,
                        isExpanded: isUpcomingExpanded,
                        onToggleExpanded: { isUpcomingExpanded.toggle() },
                        onOpenURL: onOpenWorkspaceURL
                    )
                    }
                    .padding(16)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HomeContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onPreferenceChange(HomeContentHeightPreferenceKey.self) { height in
                let measuredHeight = PopoverLayout.quantized(height)
                guard measuredHeight > 0, abs(homeContentHeight - measuredHeight) >= 4 else { return }
                homeContentHeight = measuredHeight
            }

        }
    }

    private var shouldShowSetupChecklist: Bool {
        guard !model.setupChecklistDismissed else { return false }

        let missingGoogleOptions = model.connectionState.isConnected &&
            (!model.calendarNotificationsEnabled || !model.mailBadgeEnabled)
        let missingLocalOptions = !model.teamsCallBlockEnabled ||
            model.teamsCallBlockPermissionPending ||
            !model.launchAtLoginEnabled

        return missingGoogleOptions || missingLocalOptions
    }

    private var presentedLastError: String? {
        presentableError(model.lastError)
    }

    private var presentedGmailError: String? {
        presentableError(model.gmailError)
    }

    private func presentableError(_ message: String?) -> String? {
        guard let message else { return nil }
        let normalized = message.lowercased()
        guard !normalized.contains("cancellationerror"),
              !normalized.contains("cancelled"),
              !normalized.contains("canceled") else {
            return nil
        }
        return message
    }

    private func openAppSettings() {
        editorID = UUID()
        settingsSessionHeight = min(
            maximumHeight,
            max(homePreferredHeight, PopoverLayout.settingsMinimumHeight)
        )
        setScreen(.appSettings)
    }

    private func openWorkspaceSettings() {
        editorID = UUID()
        setScreen(.workspaceSettings)
    }

    private func showHome() {
        settingsSessionHeight = nil
        setScreen(.home)
    }

    private func setScreen(_ newScreen: PopoverScreen) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            screen = newScreen
        }
    }

    private func recoverFromError(_ recovery: ErrorRecoveryAction) {
        switch recovery {
        case .googleConnection:
            onSignIn()
        case .gmailPermission:
            onEnableGmailBadge()
        case .notificationSettings:
            openNotificationSettings()
        case .loginItemsSettings:
            openLoginItemsSettings()
        }
    }

    private func openNotificationSettings() {
        guard let url = Self.notificationSettingsURL() else { return }
        onOpenURL(url)
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/lazyest-hyun/lazyest-work") else { return }
        onOpenURL(url)
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        onOpenURL(url)
    }

    static func notificationSettingsURL() -> URL? {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lazyest.work"
        return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)")
            ?? URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }
}

enum MenuSurfaceStyle {
    case card
    case inset
    case tile
}

enum MenuAppearance {
    static func surfaceFill(
        _ style: MenuSurfaceStyle,
        colorScheme _: ColorScheme,
        isDragging: Bool = false
    ) -> Color {
        let opacityMultiplier = isDragging ? 0.58 : 1

        switch style {
        case .card, .tile:
            return Color(nsColor: .controlBackgroundColor).opacity(opacityMultiplier)
        case .inset:
            return Color(nsColor: .windowBackgroundColor).opacity(opacityMultiplier)
        }
    }

    static func dividerColor(for _: ColorScheme) -> Color {
        Color(nsColor: .separatorColor).opacity(0.70)
    }

    static func semanticFill(_ color: Color, colorScheme: ColorScheme) -> Color {
        color.opacity(colorScheme == .dark ? 0.16 : 0.12)
    }

    static func semanticStroke(_ color: Color, colorScheme: ColorScheme) -> Color {
        color.opacity(colorScheme == .dark ? 0.28 : 0.18)
    }
}

struct PopoverSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

struct MenuSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let style: MenuSurfaceStyle
    let cornerRadius: CGFloat
    let isDragging: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                MenuAppearance.surfaceFill(style, colorScheme: colorScheme, isDragging: isDragging),
                in: shape
            )
    }
}

extension View {
    func popoverSurface() -> some View {
        modifier(PopoverSurfaceModifier())
    }

    func menuSurface(
        _ style: MenuSurfaceStyle = .card,
        cornerRadius: CGFloat = 8,
        isDragging: Bool = false
    ) -> some View {
        modifier(MenuSurfaceModifier(style: style, cornerRadius: cornerRadius, isDragging: isDragging))
    }
}

struct MenuDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(MenuAppearance.dividerColor(for: colorScheme))
            .frame(height: 1)
    }
}

struct HeaderView: View {
    let connectionState: ConnectionState
    let language: AppLanguage
    let isBusy: Bool
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppImages.headerIcon())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)

            Text("Lazyest Work")
                .font(.system(size: 13, weight: .semibold))

            Text(text.googleAccountLine(connectionState))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            }

            IconButton(symbolName: "arrow.clockwise", title: text.s("Refresh", "새로고침"), action: onRefresh)
                .disabled(!connectionState.isConnected || isBusy)
            IconButton(symbolName: "gearshape", title: text.settings, action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .frame(height: PopoverLayout.headerHeight)
    }

    private var text: AppText { AppText(language: language) }
}

struct PrimaryCalendarCard: View {
    let connectionState: ConnectionState
    let language: AppLanguage
    let isBusy: Bool
    let includesGmail: Bool
    let onSignIn: () -> Void
    private var text: AppText { AppText(language: language) }

    var body: some View {
        switch connectionState {
        case .loading:
            StatusCard(symbolName: "hourglass", title: text.s("Loading calendar", "캘린더 확인 중"), message: text.s("Checking saved sign-in.", "저장된 로그인을 확인합니다."), actionTitle: nil, action: nil)
        case .missingBundleConfig:
            StatusCard(
                symbolName: "exclamationmark.triangle",
                title: text.s("Google unavailable", "Google 연결 불가"),
                message: text.s(
                    "This build is missing its Google connection.",
                    "이 빌드에 Google 연결 정보가 없습니다."
                ),
                actionTitle: nil,
                action: nil
            )
        case .signedOut:
            AuthStatusCard(
                symbolName: "person.crop.circle.badge.plus",
                title: text.s("Connect Google", "Google 연결"),
                message: isBusy
                    ? text.s("Waiting for Google.", "Google 로그인 대기 중…")
                    : includesGmail
                        ? text.s("Calendar events and Gmail unread count.", "캘린더 일정과 Gmail 안 읽은 개수를 확인합니다.")
                        : text.s("Calendar events for the next 7 days.", "앞으로 7일의 캘린더 일정을 확인합니다."),
                primaryTitle: isBusy ? text.s("Connecting", "연결 중…") : text.s("Connect", "연결"),
                primarySystemImage: "person.crop.circle.badge.plus",
                primaryAction: onSignIn,
                isPrimaryDisabled: isBusy,
                footnote: includesGmail
                    ? text.s("No mail content", "메일 내용 미사용")
                    : text.s("Read only", "읽기 전용")
            )
        case .connected:
            StatusCard(symbolName: "checkmark.circle", title: text.s("No upcoming meetings", "예정된 회의 없음"), message: isBusy ? text.s("Refreshing calendar.", "캘린더 새로고침 중…") : text.s("Nothing scheduled for 7 days.", "7일 내 일정이 없습니다."), actionTitle: nil, action: nil)
        }
    }
}

struct AuthStatusCard: View {
    let symbolName: String
    let title: String
    let message: String
    let primaryTitle: String
    let primarySystemImage: String
    let primaryAction: () -> Void
    let isPrimaryDisabled: Bool
    let footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Button {
                    primaryAction()
                } label: {
                    Label(primaryTitle, systemImage: primarySystemImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrimaryDisabled)

                Spacer()

                if let footnote {
                    Text(footnote)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .menuSurface()
    }
}

struct FinishSetupCard: View {
    let isGoogleConnected: Bool
    let alertLeadMinutes: Int
    let calendarNotificationsEnabled: Bool
    let mailBadgeEnabled: Bool
    let teamsCallBlockEnabled: Bool
    let teamsCallBlockPermissionPending: Bool
    let launchAtLoginEnabled: Bool
    let isBusy: Bool
    let onEnableCalendarAlerts: () -> Void
    let onEnableGmailBadge: () -> Void
    let onEnableTeamsCallBlock: () -> Void
    let onEnableLaunchAtLogin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish setup")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Optional settings that make the menu app feel alive.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                IconButton(symbolName: "xmark", title: "Hide setup checklist", action: onDismiss)
            }

            VStack(spacing: 7) {
                FinishSetupOptionRow(
                    title: "Teams call block",
                    subtitle: teamsCallBlockPermissionPending
                        ? "Waiting for macOS permission. Open Settings to finish approval."
                        : "Ask before outgoing Teams call buttons. Microsoft sign-in is not needed.",
                    systemImage: "phone.badge.checkmark",
                    isEnabled: teamsCallBlockEnabled,
                    isPending: teamsCallBlockPermissionPending,
                    isBusy: false,
                    action: onEnableTeamsCallBlock
                )
                FinishSetupOptionRow(
                    title: "Open at login",
                    subtitle: "Start Lazyest Work when you sign in to macOS.",
                    systemImage: "power",
                    isEnabled: launchAtLoginEnabled,
                    isBusy: false,
                    action: onEnableLaunchAtLogin
                )
                if isGoogleConnected {
                    FinishSetupOptionRow(
                        title: "Meeting alerts",
                        subtitle: "Desktop notification \(alertLeadMinutes)m before meetings. Requires macOS Notifications.",
                        systemImage: "bell.badge",
                        isEnabled: calendarNotificationsEnabled,
                        isBusy: isBusy,
                        action: onEnableCalendarAlerts
                    )
                    FinishSetupOptionRow(
                        title: "Gmail badge",
                        subtitle: "Inbox unread count. Rechecks briefly after opening Gmail.",
                        systemImage: "envelope.badge",
                        isEnabled: mailBadgeEnabled,
                        isBusy: isBusy,
                        action: onEnableGmailBadge
                    )
                }
            }
        }
        .padding(12)
        .menuSurface()
    }
}

struct FinishSetupOptionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    var isPending = false
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEnabled ? .green : Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isEnabled {
                Label("On", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            } else if isPending {
                Label("Waiting", systemImage: "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                Button("Enable", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .menuSurface(.inset, cornerRadius: 7)
    }
}

struct AlertLeadSettingRow: View {
    @Binding var selectedMinutes: Int
    let language: AppLanguage
    private let options = AlertSettings.allowedLeadMinutes
    private var text: AppText { AppText(language: language) }

    var body: some View {
        HStack(spacing: 10) {
            Label(text.meetingAlert, systemImage: "bell")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Menu {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        selectedMinutes = minutes
                    } label: {
                        if selectedMinutes == minutes {
                            Label(optionTitle(minutes), systemImage: "checkmark")
                        } else {
                            Text(optionTitle(minutes))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(text.shortMinutesBefore(selectedMinutes))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .menuSurface(.inset)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .menuSurface()
    }

    private func optionTitle(_ minutes: Int) -> String {
        text.minutesBefore(minutes)
    }
}

struct LanguagePickerRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Picker("", selection: $selection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 116)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .menuSurface()
    }
}

struct NotificationToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .menuSurface()
    }
}

struct MeetingFocusToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isApprovalPending: Bool
    @Binding var isOn: Bool
    let approveTitle: String
    let approveHelp: String
    let onApprove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isApprovalPending, !isOn {
                Button(approveTitle, action: onApprove)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(approveHelp)
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .menuSurface()
    }
}

struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let buttonTitle: String
    let buttonRole: ButtonRole?
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(role: buttonRole, action: action) {
                Text(buttonTitle)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .menuSurface()
    }
}

struct UpcomingEventsView: View {
    let events: [MeetingEvent]
    let language: AppLanguage
    let now: Date
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onOpenURL: (URL) -> Void
    private var text: AppText { AppText(language: language) }

    private var visibleEvents: [MeetingEvent] {
        MenuSectionVisibility.visibleUpcomingEvents(events, now: now, isExpanded: isExpanded)
    }

    private var visibleEventGroups: [EventDayGroup] {
        let calendar = Calendar.autoupdatingCurrent
        var groups: [EventDayGroup] = []
        for event in visibleEvents {
            let day = calendar.startOfDay(for: event.start)
            if groups.last?.id == day {
                groups[groups.count - 1].events.append(event)
            } else {
                groups.append(EventDayGroup(id: day, events: [event]))
            }
        }
        return groups
    }

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SectionTitle(text.s("Upcoming", "다가오는 일정"))
                    Spacer()
                    IconButton(
                        symbolName: isExpanded ? "chevron.up" : "chevron.down",
                        title: isExpanded ? text.s("Show today only", "오늘만 보기") : text.s("Show this week", "이번 주 보기"),
                        action: onToggleExpanded
                    )
                    .frame(width: 24, height: 24)
                }

                if visibleEvents.isEmpty {
                    Text(isExpanded ? text.s("No meetings this week", "이번 주 회의 없음") : text.s("No meetings today", "오늘 회의 없음"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .menuSurface(.inset)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(visibleEventGroups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                if let firstEvent = group.events.first {
                                    HStack(spacing: 4) {
                                        Text(firstEvent.dayText(relativeTo: now, language: language))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                        Text("· \(AppDateFormatters.compactDateString(from: group.id))")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(.secondary)
                                    }
                                        .padding(.leading, 2)
                                }

                                ForEach(group.events, id: \.id) { event in
                                    EventRow(event: event, language: language, onOpenURL: onOpenURL)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}

private struct EventDayGroup: Identifiable {
    let id: Date
    var events: [MeetingEvent]
}

private enum EventRowMetrics {
    static let primaryFont = Font.system(size: 12, weight: .semibold)
    static let secondaryFont = Font.system(size: 11, weight: .regular)
    static let primaryHeight: CGFloat = 18
    static let secondaryHeight: CGFloat = 16
    static let lineSpacing: CGFloat = 2
    static let contentHeight = primaryHeight + lineSpacing + secondaryHeight
}

struct EventRow: View {
    let event: MeetingEvent
    let language: AppLanguage
    let onOpenURL: (URL) -> Void
    private var text: AppText { AppText(language: language) }
    @State private var isShowingParticipants = false

    private var secondaryText: String? {
        if let room = event.roomLine {
            return room
        }
        if let calendarName = event.calendarName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return calendarName
        }
        return nil
    }

    var body: some View {
        rowContent
            .contextMenu {
                if let meetingURL = event.meetingURL {
                    Button(text.s("Join meeting", "회의 입장")) { onOpenURL(meetingURL) }
                }
                if let htmlLink = event.htmlLink, htmlLink != event.meetingURL {
                    Button(text.s("Open event", "일정 열기")) { onOpenURL(htmlLink) }
                }
            }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 7) {
            EventTimeColumn(event: event)

            Capsule()
                .fill(event.selfResponseStatus.indicatorColor)
                .frame(width: 3, height: EventRowMetrics.contentHeight)
                .help(event.selfResponseStatus.helpText)

            VStack(alignment: .leading, spacing: EventRowMetrics.lineSpacing) {
                HStack(spacing: 5) {
                    Text(event.title)
                        .font(EventRowMetrics.primaryFont)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .help(event.title)

                    Spacer(minLength: 6)

                    if let meetingURL = event.meetingURL {
                        EventIconButton(
                            symbolName: "video.fill",
                            title: text.s("Join meeting", "회의 입장"),
                            action: { onOpenURL(meetingURL) }
                        )
                    }

                    if let htmlLink = event.htmlLink {
                        EventIconButton(
                            symbolName: "info.circle",
                            title: text.s("Open event", "일정 열기"),
                            action: { onOpenURL(htmlLink) }
                        )
                    }
                }
                .frame(height: EventRowMetrics.primaryHeight)

                HStack(spacing: 7) {
                    if let secondaryText {
                        Text(secondaryText)
                            .font(EventRowMetrics.secondaryFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                            .help(secondaryText)
                    }

                    if let participantText = event.participantCompactText {
                        if secondaryText != nil {
                            Divider()
                                .frame(height: 12)
                        }

                        Button {
                            isShowingParticipants.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "person.2")
                                Text(participantText)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .font(EventRowMetrics.secondaryFont)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(event.participantToolTip(text: text))
                        .popover(
                            isPresented: $isShowingParticipants,
                            attachmentAnchor: .point(.top),
                            arrowEdge: .bottom
                        ) {
                            ParticipantPopover(event: event, language: language)
                        }
                    }
                }
                .frame(height: EventRowMetrics.secondaryHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .menuSurface()
    }
}

struct EventTimeColumn: View {
    let event: MeetingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: EventRowMetrics.lineSpacing) {
            Text(event.startTimeText)
                .font(EventRowMetrics.primaryFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(height: EventRowMetrics.primaryHeight)
            Text("- \(event.endTimeText)")
                .font(EventRowMetrics.secondaryFont)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(height: EventRowMetrics.secondaryHeight)
        }
        .frame(height: EventRowMetrics.contentHeight, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: false)
        .help(event.timeText)
    }
}

struct EventIconButton: View {
    let symbolName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(title))
        .help(title)
    }
}

struct ParticipantPopover: View {
    let event: MeetingEvent
    let language: AppLanguage

    private var text: AppText { AppText(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(text.participants)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(event.participantCompactText ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                ParticipantList(participants: event.participants, language: language)
            }
            .frame(maxHeight: 280)
        }
        .padding(10)
        .frame(width: 260)
    }
}

struct ParticipantList: View {
    let participants: [MeetingParticipant]
    let language: AppLanguage

    private var text: AppText { AppText(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(participants) { participant in
                HStack(spacing: 6) {
                    Image(systemName: participant.statusSymbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(participant.statusColor)
                        .frame(width: 12)

                    Text(participant.label)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .help(participant.helpText(text: text))

                    Spacer(minLength: 6)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .menuSurface(.inset, cornerRadius: 7)
    }
}

struct WorkspaceGrid: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    let apps: [WorkspaceApp]
    let language: AppLanguage
    let gmailUnreadCount: Int?
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onManageApps: () -> Void
    let onOpenURL: (URL) -> Void
    private var text: AppText { AppText(language: language) }

    private var visibleApps: [WorkspaceApp] {
        let visibleIDs = Set(MenuSectionVisibility.visibleWorkspaceIDs(
            apps.map(\.id),
            isExpanded: isExpanded,
            columns: MenuSectionVisibility.defaultWorkspaceColumns
        ))
        return apps.filter { visibleIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionTitle(text.s("Workspace", "워크스페이스"))
                Spacer()
                if apps.count > MenuSectionVisibility.defaultWorkspaceColumns {
                    IconButton(
                        symbolName: isExpanded ? "chevron.up" : "chevron.down",
                        title: isExpanded ? text.s("Collapse apps", "앱 접기") : text.s("Show all apps", "모든 앱 보기"),
                        action: onToggleExpanded
                    )
                    .frame(width: 24, height: 24)
                }
                IconButton(symbolName: "slider.horizontal.3", title: text.s("Manage apps", "앱 관리"), action: onManageApps)
                    .frame(width: 24, height: 24)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visibleApps) { app in
                    Button {
                        if let url = app.url {
                            onOpenURL(url)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                WorkspaceProductIcon(app: app)
                                    .frame(width: 24, height: 24)
                                if app.id == "gmail", let gmailUnreadCount, gmailUnreadCount > 0 {
                                    GmailUnreadBadge(count: gmailUnreadCount)
                                        .offset(x: 9, y: -7)
                                }
                            }
                            .frame(width: 36, height: 26)
                            Text(app.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(app.url == nil)
                    .menuSurface(.tile)
                }
            }
        }
    }
}

struct GmailUnreadBadge: View {
    let count: Int

    private var displayCount: String {
        UnreadCountFormatter.display(count)
    }

    var body: some View {
        Text(displayCount)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Color.red, in: Capsule())
    }
}

struct WorkspaceProductIcon: View {
    let app: WorkspaceApp

    var body: some View {
        if let image = app.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: app.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private enum AppSettingsSection: String, CaseIterable, Identifiable {
    case general
    case notifications
    case teams
    case account

    var id: String { rawValue }

    func title(_ text: AppText) -> String {
        switch self {
        case .general: return text.general
        case .notifications: return text.notifications
        case .teams: return text.teams
        case .account: return text.account
        }
    }
}

struct AppSettingsView: View {
    let connectionState: ConnectionState
    let isBusy: Bool
    let errorMessage: String?
    let errorRecovery: ErrorRecoveryAction?
    let gmailErrorMessage: String?
    let gmailErrorRecovery: ErrorRecoveryAction?
    let currentLanguage: AppLanguage
    let currentCalendarNotificationsEnabled: Bool
    let currentMeetingFocusEnabled: Bool
    let meetingFocusApprovalPending: Bool
    let meetingFocusStatusText: String
    let currentTeamsPresenceEnabled: Bool
    let currentTeamsCallBlockEnabled: Bool
    let currentTeamsControlScrollBlockEnabled: Bool
    let teamsCallBlockPermissionPending: Bool
    let teamsCallBlockStatusText: String
    let teamsPresenceStatusText: String
    let microsoftConnectionState: MicrosoftConnectionState
    let microsoftSetupConfig: MicrosoftSetupConfig
    let microsoftTeamsOperation: MicrosoftTeamsOperation
    let currentMailBadgeEnabled: Bool
    let currentLaunchAtLoginEnabled: Bool
    @State private var draftAlertLeadMinutes: Int
    @State private var draftCalendarNotificationsEnabled: Bool
    @State private var draftLanguage: AppLanguage
    @State private var draftMeetingFocusEnabled: Bool
    @State private var draftTeamsPresenceEnabled: Bool
    @State private var draftTeamsCallBlockEnabled: Bool
    @State private var draftTeamsControlScrollBlockEnabled: Bool
    @State private var draftMailBadgeEnabled: Bool
    @State private var draftLaunchAtLoginEnabled: Bool
    @State private var selectedSection = AppSettingsSection.general
    let onDone: () -> Void
    let onRecoverError: (ErrorRecoveryAction) -> Void
    let onSignIn: () -> Void
    let onSignOut: () -> Void
    let onOpenNotificationSettings: () -> Void
    let onOpenGitHub: () -> Void
    let onUpdateLanguage: (AppLanguage) -> Void
    let onUpdateAlertLeadMinutes: (Int) -> Void
    let onUpdateCalendarNotifications: (Bool) -> Void
    let onSendTestCalendarNotification: () -> Void
    let onUpdateMeetingFocus: (Bool) -> Bool
    let onApproveMeetingFocus: () -> Void
    let onInstallMicrosoftCLI: () -> Void
    let onConnectMicrosoftTeams: () -> Void
    let onSignOutMicrosoftTeams: () -> Void
    let onUpdateTeamsPresence: (Bool) -> Bool
    let onUpdateTeamsCallBlock: (Bool) -> Bool
    let onUpdateTeamsControlScrollBlock: (Bool) -> Bool
    let onRefreshTeamsCallBlockPermissions: () -> Void
    let onUpdateMailBadge: (Bool) -> Void
    let onUpdateLaunchAtLogin: (Bool) -> Void

    init(
        connectionState: ConnectionState,
        isBusy: Bool,
        errorMessage: String?,
        errorRecovery: ErrorRecoveryAction?,
        gmailErrorMessage: String?,
        gmailErrorRecovery: ErrorRecoveryAction?,
        initialAlertLeadMinutes: Int,
        initialCalendarNotificationsEnabled: Bool,
        currentCalendarNotificationsEnabled: Bool,
        initialLanguage: AppLanguage,
        currentLanguage: AppLanguage,
        initialMeetingFocusEnabled: Bool,
        currentMeetingFocusEnabled: Bool,
        meetingFocusApprovalPending: Bool,
        meetingFocusStatusText: String,
        initialTeamsPresenceEnabled: Bool,
        currentTeamsPresenceEnabled: Bool,
        initialTeamsCallBlockEnabled: Bool,
        currentTeamsCallBlockEnabled: Bool,
        initialTeamsControlScrollBlockEnabled: Bool,
        currentTeamsControlScrollBlockEnabled: Bool,
        teamsCallBlockPermissionPending: Bool,
        teamsCallBlockStatusText: String,
        teamsPresenceStatusText: String,
        microsoftConnectionState: MicrosoftConnectionState,
        microsoftSetupConfig: MicrosoftSetupConfig,
        microsoftTeamsOperation: MicrosoftTeamsOperation,
        initialMailBadgeEnabled: Bool,
        currentMailBadgeEnabled: Bool,
        initialLaunchAtLoginEnabled: Bool,
        currentLaunchAtLoginEnabled: Bool,
        onDone: @escaping () -> Void,
        onRecoverError: @escaping (ErrorRecoveryAction) -> Void,
        onSignIn: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onOpenNotificationSettings: @escaping () -> Void,
        onOpenGitHub: @escaping () -> Void,
        onUpdateLanguage: @escaping (AppLanguage) -> Void,
        onUpdateAlertLeadMinutes: @escaping (Int) -> Void,
        onUpdateCalendarNotifications: @escaping (Bool) -> Void,
        onSendTestCalendarNotification: @escaping () -> Void,
        onUpdateMeetingFocus: @escaping (Bool) -> Bool,
        onApproveMeetingFocus: @escaping () -> Void,
        onInstallMicrosoftCLI: @escaping () -> Void,
        onConnectMicrosoftTeams: @escaping () -> Void,
        onSignOutMicrosoftTeams: @escaping () -> Void,
        onUpdateTeamsPresence: @escaping (Bool) -> Bool,
        onUpdateTeamsCallBlock: @escaping (Bool) -> Bool,
        onUpdateTeamsControlScrollBlock: @escaping (Bool) -> Bool,
        onRefreshTeamsCallBlockPermissions: @escaping () -> Void,
        onUpdateMailBadge: @escaping (Bool) -> Void,
        onUpdateLaunchAtLogin: @escaping (Bool) -> Void
    ) {
        _draftAlertLeadMinutes = State(initialValue: initialAlertLeadMinutes)
        _draftCalendarNotificationsEnabled = State(initialValue: initialCalendarNotificationsEnabled)
        _draftLanguage = State(initialValue: initialLanguage)
        _draftMeetingFocusEnabled = State(initialValue: initialMeetingFocusEnabled)
        _draftTeamsPresenceEnabled = State(initialValue: initialTeamsPresenceEnabled)
        _draftTeamsCallBlockEnabled = State(initialValue: initialTeamsCallBlockEnabled)
        _draftTeamsControlScrollBlockEnabled = State(initialValue: initialTeamsControlScrollBlockEnabled)
        _draftMailBadgeEnabled = State(initialValue: initialMailBadgeEnabled)
        _draftLaunchAtLoginEnabled = State(initialValue: initialLaunchAtLoginEnabled)
        self.connectionState = connectionState
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.errorRecovery = errorRecovery
        self.gmailErrorMessage = gmailErrorMessage
        self.gmailErrorRecovery = gmailErrorRecovery
        self.currentCalendarNotificationsEnabled = currentCalendarNotificationsEnabled
        self.currentLanguage = currentLanguage
        self.currentMeetingFocusEnabled = currentMeetingFocusEnabled
        self.meetingFocusApprovalPending = meetingFocusApprovalPending
        self.meetingFocusStatusText = meetingFocusStatusText
        self.currentTeamsPresenceEnabled = currentTeamsPresenceEnabled
        self.currentTeamsCallBlockEnabled = currentTeamsCallBlockEnabled
        self.currentTeamsControlScrollBlockEnabled = currentTeamsControlScrollBlockEnabled
        self.teamsCallBlockPermissionPending = teamsCallBlockPermissionPending
        self.teamsCallBlockStatusText = teamsCallBlockStatusText
        self.teamsPresenceStatusText = teamsPresenceStatusText
        self.microsoftConnectionState = microsoftConnectionState
        self.microsoftSetupConfig = microsoftSetupConfig
        self.microsoftTeamsOperation = microsoftTeamsOperation
        self.currentMailBadgeEnabled = currentMailBadgeEnabled
        self.currentLaunchAtLoginEnabled = currentLaunchAtLoginEnabled
        self.onDone = onDone
        self.onRecoverError = onRecoverError
        self.onSignIn = onSignIn
        self.onSignOut = onSignOut
        self.onOpenNotificationSettings = onOpenNotificationSettings
        self.onOpenGitHub = onOpenGitHub
        self.onUpdateLanguage = onUpdateLanguage
        self.onUpdateAlertLeadMinutes = onUpdateAlertLeadMinutes
        self.onUpdateCalendarNotifications = onUpdateCalendarNotifications
        self.onSendTestCalendarNotification = onSendTestCalendarNotification
        self.onUpdateMeetingFocus = onUpdateMeetingFocus
        self.onApproveMeetingFocus = onApproveMeetingFocus
        self.onInstallMicrosoftCLI = onInstallMicrosoftCLI
        self.onConnectMicrosoftTeams = onConnectMicrosoftTeams
        self.onSignOutMicrosoftTeams = onSignOutMicrosoftTeams
        self.onUpdateTeamsPresence = onUpdateTeamsPresence
        self.onUpdateTeamsCallBlock = onUpdateTeamsCallBlock
        self.onUpdateTeamsControlScrollBlock = onUpdateTeamsControlScrollBlock
        self.onRefreshTeamsCallBlockPermissions = onRefreshTeamsCallBlockPermissions
        self.onUpdateMailBadge = onUpdateMailBadge
        self.onUpdateLaunchAtLogin = onUpdateLaunchAtLogin
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IconButton(symbolName: "chevron.left", title: text.back, action: onDone)

                Text(text.settings)
                    .font(.system(size: 17, weight: .semibold))

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: PopoverLayout.headerHeight)

            MenuDivider()

            Picker("", selection: $selectedSection) {
                ForEach(AppSettingsSection.allCases) { section in
                    Text(section.title(text)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let (message, recovery) = activeError {
                        ErrorBanner(
                            message: message,
                            actionTitle: recovery?.buttonTitle,
                            action: recovery.map { recovery in
                                { onRecoverError(recovery) }
                            }
                        )
                    }

                    switch selectedSection {
                    case .general:
                        LanguagePickerRow(
                            title: text.languageLabel,
                            subtitle: text.languageSubtitle,
                            selection: languageBinding
                        )
                        NotificationToggleRow(
                            title: text.openAtLogin,
                            subtitle: text.openAtLoginSubtitle,
                            systemImage: "power",
                            isOn: launchAtLoginBinding
                        )
                    case .notifications:
                        NotificationToggleRow(
                            title: text.desktopAlerts,
                            subtitle: text.desktopAlertsSubtitle,
                            systemImage: "bell.badge",
                            isOn: calendarNotificationsBinding
                        )
                        AlertLeadSettingRow(selectedMinutes: alertLeadMinutesBinding, language: currentLanguage)
                        SettingsActionRow(
                            title: text.testAlert,
                            subtitle: text.testAlertSubtitle,
                            systemImage: "bell.badge.waveform",
                            buttonTitle: text.send,
                            buttonRole: nil,
                            isDisabled: isBusy,
                            action: onSendTestCalendarNotification
                        )
                        MeetingFocusToggleRow(
                            title: text.doNotDisturbDuringMeetings,
                            subtitle: meetingFocusSubtitle,
                            systemImage: "moon.zzz",
                            isApprovalPending: meetingFocusApprovalPending,
                            isOn: meetingFocusBinding,
                            approveTitle: text.approve,
                            approveHelp: text.approveHelp,
                            onApprove: onApproveMeetingFocus
                        )
                        NotificationToggleRow(
                            title: text.inboxUnreadBadge,
                            subtitle: text.inboxUnreadBadgeSubtitle,
                            systemImage: "envelope.badge",
                            isOn: mailBadgeBinding
                        )
                        SettingsActionRow(
                            title: text.notificationSettings,
                            subtitle: text.notificationSettingsSubtitle,
                            systemImage: "bell.and.waves.left.and.right",
                            buttonTitle: text.open,
                            buttonRole: nil,
                            isDisabled: false,
                            action: onOpenNotificationSettings
                        )
                    case .teams:
                        MicrosoftTeamsCallProtectionSettingsCard(
                            language: currentLanguage,
                            isEnabled: teamsCallBlockBinding,
                            statusText: teamsCallBlockStatusText
                        )
                        MicrosoftTeamsControlScrollBlockSettingsCard(
                            language: currentLanguage,
                            isEnabled: teamsControlScrollBlockBinding,
                            statusText: teamsCallBlockStatusText
                        )
                        MicrosoftTeamsSettingsCard(
                            language: currentLanguage,
                            connectionState: microsoftConnectionState,
                            isCalendarConnected: connectionState.isConnected,
                            usesNativeAuth: microsoftSetupConfig.isComplete,
                            isCLIInstalled: Microsoft365CLIClient.isAvailable,
                            operation: microsoftTeamsOperation,
                            presenceStatusText: teamsPresenceStatusText,
                            isPresenceEnabled: teamsPresenceBinding,
                            onInstallCLI: onInstallMicrosoftCLI,
                            onConnect: onConnectMicrosoftTeams,
                            onSignOut: onSignOutMicrosoftTeams
                        )
                    case .account:
                        SettingsActionRow(
                            title: text.googleAccount,
                            subtitle: connectionState.accountLine,
                            systemImage: "person.crop.circle",
                            buttonTitle: connectionState.isConnected
                                ? text.signOut
                                : text.s("Connect", "연결"),
                            buttonRole: nil,
                            isDisabled: isGoogleAccountActionDisabled,
                            action: performGoogleAccountAction
                        )
                        SettingsActionRow(
                            title: text.githubRepository,
                            subtitle: text.githubRepositorySubtitle,
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            buttonTitle: text.open,
                            buttonRole: nil,
                            isDisabled: false,
                            action: onOpenGitHub
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .id(selectedSection)

        }
        .onChange(of: currentLanguage) { _, newValue in
            draftLanguage = newValue
        }
        .onChange(of: currentCalendarNotificationsEnabled) { _, newValue in
            draftCalendarNotificationsEnabled = newValue
        }
        .onChange(of: currentMeetingFocusEnabled) { _, newValue in
            draftMeetingFocusEnabled = newValue
        }
        .onChange(of: currentTeamsPresenceEnabled) { _, newValue in
            draftTeamsPresenceEnabled = newValue
        }
        .onChange(of: currentTeamsCallBlockEnabled) { _, newValue in
            draftTeamsCallBlockEnabled = newValue
        }
        .onChange(of: currentMailBadgeEnabled) { _, newValue in
            draftMailBadgeEnabled = newValue
        }
        .onChange(of: currentLaunchAtLoginEnabled) { _, newValue in
            draftLaunchAtLoginEnabled = newValue
        }
        .onAppear(perform: onRefreshTeamsCallBlockPermissions)
    }

    private var activeError: (String, ErrorRecoveryAction?)? {
        if selectedSection == .notifications, let gmailErrorMessage {
            return (gmailErrorMessage, gmailErrorRecovery)
        }
        if let errorMessage {
            return (errorMessage, errorRecovery)
        }
        return nil
    }

    private var isGoogleAccountActionDisabled: Bool {
        if isBusy { return true }
        switch connectionState {
        case .loading, .missingBundleConfig:
            return true
        case .signedOut, .connected:
            return false
        }
    }

    private func performGoogleAccountAction() {
        if connectionState.isConnected {
            onSignOut()
        } else {
            onSignIn()
        }
    }

    private var alertLeadMinutesBinding: Binding<Int> {
        Binding(
            get: { draftAlertLeadMinutes },
            set: { newValue in
                draftAlertLeadMinutes = newValue
                onUpdateAlertLeadMinutes(newValue)
            }
        )
    }

    private var text: AppText {
        AppText(language: currentLanguage)
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { draftLanguage },
            set: { newValue in
                draftLanguage = newValue
                onUpdateLanguage(newValue)
            }
        )
    }

    private var calendarNotificationsBinding: Binding<Bool> {
        Binding(
            get: { draftCalendarNotificationsEnabled },
            set: { newValue in
                draftCalendarNotificationsEnabled = newValue
                onUpdateCalendarNotifications(newValue)
            }
        )
    }

    private var meetingFocusBinding: Binding<Bool> {
        Binding(
            get: { draftMeetingFocusEnabled },
            set: { newValue in
                draftMeetingFocusEnabled = onUpdateMeetingFocus(newValue)
            }
        )
    }

    private var meetingFocusSubtitle: String {
        if meetingFocusApprovalPending {
            return text.dndApprovalNeeded
        }
        if !meetingFocusStatusText.isEmpty {
            return meetingFocusStatusText
        }
        return text.dndSubtitle
    }

    private var teamsPresenceBinding: Binding<Bool> {
        Binding(
            get: { draftTeamsPresenceEnabled },
            set: { newValue in
                draftTeamsPresenceEnabled = onUpdateTeamsPresence(newValue)
            }
        )
    }

    private var teamsCallBlockBinding: Binding<Bool> {
        Binding(
            get: { draftTeamsCallBlockEnabled },
            set: { newValue in
                draftTeamsCallBlockEnabled = onUpdateTeamsCallBlock(newValue)
            }
        )
    }

    private var teamsControlScrollBlockBinding: Binding<Bool> {
        Binding(
            get: { draftTeamsControlScrollBlockEnabled },
            set: { newValue in
                draftTeamsControlScrollBlockEnabled = onUpdateTeamsControlScrollBlock(newValue)
            }
        )
    }

    private var mailBadgeBinding: Binding<Bool> {
        Binding(
            get: { draftMailBadgeEnabled },
            set: { newValue in
                draftMailBadgeEnabled = newValue
                onUpdateMailBadge(newValue)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { draftLaunchAtLoginEnabled },
            set: { newValue in
                draftLaunchAtLoginEnabled = newValue
                onUpdateLaunchAtLogin(newValue)
            }
        )
    }
}

struct WorkspaceAppsEditor: View {
    @State private var draftApps: [WorkspaceApp]
    @State private var selectedAppID: String?
    @State private var draggingAppID: String?
    @State private var lastAutoScrollAt = Date.distantPast
    private let initialApps: [WorkspaceApp]
    let onDone: () -> Void
    let onUpdateApps: ([WorkspaceApp]) -> Void

    init(
        initialApps: [WorkspaceApp],
        onDone: @escaping () -> Void,
        onUpdateApps: @escaping ([WorkspaceApp]) -> Void
    ) {
        _draftApps = State(initialValue: initialApps)
        _selectedAppID = State(initialValue: initialApps.first?.id)
        self.initialApps = initialApps
        self.onDone = onDone
        self.onUpdateApps = onUpdateApps
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IconButton(symbolName: "xmark", title: "Cancel", action: onDone)

                Text("Workspace")
                    .font(.system(size: 17, weight: .semibold))

                Text("\(draftApps.filter(\.isEnabled).count) visible")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                IconButton(symbolName: "plus", title: "Add app", action: addCustomApp)
                IconButton(symbolName: "arrow.counterclockwise", title: "Reset apps", action: resetDefaults)
                Button("Save", action: saveAndDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draftApps == initialApps)
            }
            .padding(.horizontal, 14)
            .frame(height: PopoverLayout.headerHeight)

            MenuDivider()

            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Workspace Apps")

                            if let selectedIndex {
                                WorkspaceAppDetailEditor(
                                    app: appBinding(selectedIndex),
                                    canDelete: !draftApps[selectedIndex].isBuiltIn,
                                    canMoveUp: selectedIndex > 0,
                                    canMoveDown: selectedIndex < draftApps.count - 1,
                                    onMoveToTop: { moveToTop(index: selectedIndex) },
                                    onMoveUp: { move(index: selectedIndex, offset: -1) },
                                    onMoveDown: { move(index: selectedIndex, offset: 1) },
                                    onMoveToBottom: { moveToBottom(index: selectedIndex) },
                                    onDelete: { delete(index: selectedIndex) }
                                )
                            }

                            WorkspaceAppsGridEditor(
                                apps: $draftApps,
                                selectedAppID: $selectedAppID,
                                draggingAppID: $draggingAppID
                            )
                        }
                        .padding(10)
                    }

                    VStack(spacing: 0) {
                        WorkspaceAppAutoScrollDropZone(
                            edge: .top,
                            apps: $draftApps,
                            draggingID: $draggingAppID,
                            lastAutoScrollAt: $lastAutoScrollAt,
                            scrollProxy: proxy
                        )

                        Spacer()

                        WorkspaceAppAutoScrollDropZone(
                            edge: .bottom,
                            apps: $draftApps,
                            draggingID: $draggingAppID,
                            lastAutoScrollAt: $lastAutoScrollAt,
                            scrollProxy: proxy
                        )
                    }
                    .allowsHitTesting(draggingAppID != nil)
                }
                .onChange(of: draggingAppID) { _, newValue in
                    if newValue == nil {
                        lastAutoScrollAt = .distantPast
                    }
                }
            }
            .onChange(of: draftApps) { _, newValue in
                if !newValue.contains(where: { $0.id == selectedAppID }) {
                    selectedAppID = newValue.first?.id
                }
            }

        }
    }

    private var selectedIndex: Int? {
        guard let selectedAppID else { return nil }
        return draftApps.firstIndex(where: { $0.id == selectedAppID })
    }

    private func saveAndDone() {
        onUpdateApps(draftApps)
        onDone()
    }

    private func appBinding(_ index: Int) -> Binding<WorkspaceApp> {
        Binding(
            get: { draftApps[index] },
            set: { newValue in
                draftApps[index] = newValue
            }
        )
    }

    private func addCustomApp() {
        let app = WorkspaceApp.custom()
        draftApps.append(app)
        selectedAppID = app.id
    }

    private func resetDefaults() {
        draftApps = WorkspaceApp.defaultApps
        selectedAppID = draftApps.first?.id
    }

    private func move(index: Int, offset: Int) {
        let target = index + offset
        guard draftApps.indices.contains(index),
              draftApps.indices.contains(target) else {
            return
        }
        draftApps.swapAt(index, target)
        selectedAppID = draftApps[target].id
    }

    private func moveToTop(index: Int) {
        guard draftApps.indices.contains(index), index > 0 else {
            return
        }
        let app = draftApps.remove(at: index)
        draftApps.insert(app, at: 0)
        selectedAppID = app.id
    }

    private func moveToBottom(index: Int) {
        guard draftApps.indices.contains(index), index < draftApps.count - 1 else {
            return
        }
        let app = draftApps.remove(at: index)
        draftApps.append(app)
        selectedAppID = app.id
    }

    private func delete(index: Int) {
        guard draftApps.indices.contains(index),
              !draftApps[index].isBuiltIn else {
            return
        }
        draftApps.remove(at: index)
        selectedAppID = draftApps.indices.contains(index) ? draftApps[index].id : draftApps.last?.id
    }
}

struct WorkspaceAppsGridEditor: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    @Binding var apps: [WorkspaceApp]
    @Binding var selectedAppID: String?
    @Binding var draggingAppID: String?

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(apps) { listedApp in
                if let index = apps.firstIndex(where: { $0.id == listedApp.id }) {
                    WorkspaceAppEditorTile(
                        app: apps[index],
                        isSelected: selectedAppID == listedApp.id,
                        isDragging: draggingAppID == listedApp.id,
                        canDelete: !apps[index].isBuiltIn,
                        onSelect: { selectedAppID = listedApp.id },
                        onToggleEnabled: {
                            selectedAppID = listedApp.id
                            apps[index].isEnabled.toggle()
                        },
                        onDelete: {
                            delete(index: index)
                        },
                        onDrag: {
                            selectedAppID = listedApp.id
                            draggingAppID = listedApp.id
                            return NSItemProvider(object: listedApp.id as NSString)
                        }
                    )
                    .id(listedApp.id)
                    .onDrop(
                        of: [UTType.text],
                        delegate: WorkspaceAppReorderDropDelegate(
                            targetID: listedApp.id,
                            apps: $apps,
                            draggingID: $draggingAppID
                        )
                    )
                }
            }
        }
    }

    private func delete(index: Int) {
        guard apps.indices.contains(index), !apps[index].isBuiltIn else { return }
        apps.remove(at: index)
        selectedAppID = apps.indices.contains(index) ? apps[index].id : apps.last?.id
    }
}

struct WorkspaceAppEditorTile: View {
    let app: WorkspaceApp
    let isSelected: Bool
    let isDragging: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onToggleEnabled: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider

    var body: some View {
        VStack(spacing: 6) {
            WorkspaceProductIcon(app: app)
                .frame(width: 24, height: 24)
                .frame(width: 36, height: 28)

            Text(app.title.nilIfBlank ?? "Untitled")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .opacity(app.isEnabled ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .onDrag(onDrag)
        .menuSurface(.tile, isDragging: isDragging)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topLeading) {
            Button(action: onToggleEnabled) {
                Image(systemName: app.isEnabled ? "eye.fill" : "eye.slash")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(app.isEnabled ? "Hide app" : "Show app")
        }
        .overlay(alignment: .topTrailing) {
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Delete custom app")
            }
        }
        .help("Click to edit. Drag to reorder.")
    }
}

struct WorkspaceAppDetailEditor: View {
    @Binding var app: WorkspaceApp
    let canDelete: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveToTop: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToBottom: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                WorkspaceProductIcon(app: app)
                    .frame(width: 24, height: 24)
                    .frame(width: 32, height: 32)
                    .menuSurface(.inset)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.title.nilIfBlank ?? "Untitled")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(app.urlString.nilIfBlank ?? "No URL")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Toggle("Visible", isOn: binding(\.isEnabled))
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.switch)
            }

            TextField("Name", text: binding(\.title))
                .textFieldStyle(.roundedBorder)

            TextField("URL", text: binding(\.urlString))
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 4) {
                IconButton(symbolName: "arrow.up.to.line", title: "Move to top", action: onMoveToTop)
                    .disabled(!canMoveUp)
                IconButton(symbolName: "chevron.up", title: "Move up", action: onMoveUp)
                    .disabled(!canMoveUp)
                IconButton(symbolName: "chevron.down", title: "Move down", action: onMoveDown)
                    .disabled(!canMoveDown)
                IconButton(symbolName: "arrow.down.to.line", title: "Move to bottom", action: onMoveToBottom)
                    .disabled(!canMoveDown)

                Spacer()

                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .menuSurface()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WorkspaceApp, Value>) -> Binding<Value> {
        Binding(
            get: { app[keyPath: keyPath] },
            set: { newValue in
                app[keyPath: keyPath] = newValue
            }
        )
    }
}

struct WorkspaceAppReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var apps: [WorkspaceApp]
    @Binding var draggingID: String?

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != targetID,
              let fromIndex = apps.firstIndex(where: { $0.id == draggingID }),
              let targetIndex = apps.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            apps.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: targetIndex > fromIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

enum WorkspaceAppAutoScrollEdge {
    case top
    case bottom

    var step: Int {
        self == .top ? -1 : 1
    }

    var anchor: UnitPoint {
        self == .top ? .top : .bottom
    }

    var gradient: LinearGradient {
        switch self {
        case .top:
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        case .bottom:
            return LinearGradient(
                colors: [Color.clear, Color.accentColor.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct WorkspaceAppAutoScrollDropZone: View {
    let edge: WorkspaceAppAutoScrollEdge
    @Binding var apps: [WorkspaceApp]
    @Binding var draggingID: String?
    @Binding var lastAutoScrollAt: Date
    let scrollProxy: ScrollViewProxy

    var body: some View {
        Rectangle()
            .fill(draggingID == nil ? LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom) : edge.gradient)
            .frame(height: 44)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                delegate: WorkspaceAppAutoScrollDropDelegate(
                    edge: edge,
                    apps: $apps,
                    draggingID: $draggingID,
                    lastAutoScrollAt: $lastAutoScrollAt,
                    scrollProxy: scrollProxy
                )
            )
    }
}

struct WorkspaceAppAutoScrollDropDelegate: DropDelegate {
    let edge: WorkspaceAppAutoScrollEdge
    @Binding var apps: [WorkspaceApp]
    @Binding var draggingID: String?
    @Binding var lastAutoScrollAt: Date
    let scrollProxy: ScrollViewProxy

    func dropEntered(info: DropInfo) {
        autoScroll()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        autoScroll()
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    private func autoScroll() {
        guard let draggingID,
              let currentIndex = apps.firstIndex(where: { $0.id == draggingID }) else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastAutoScrollAt) > 0.16 else {
            return
        }

        let targetIndex = min(max(currentIndex + edge.step, 0), apps.count - 1)
        lastAutoScrollAt = now

        guard targetIndex != currentIndex else {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.12)) {
                    scrollProxy.scrollTo(draggingID, anchor: edge.anchor)
                }
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            apps.move(
                fromOffsets: IndexSet(integer: currentIndex),
                toOffset: edge == .bottom ? targetIndex + 1 : targetIndex
            )
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.12)) {
                scrollProxy.scrollTo(draggingID, anchor: edge.anchor)
            }
        }
    }
}

struct StatusCard: View {
    let symbolName: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .menuSurface()
    }
}

struct ErrorBanner: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    init(message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .lineLimit(4)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(MenuAppearance.semanticFill(.orange, colorScheme: colorScheme), in: shape)
        .overlay {
            shape.stroke(MenuAppearance.semanticStroke(.orange, colorScheme: colorScheme), lineWidth: 1)
        }
    }
}

struct IconButton: View {
    let symbolName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(title))
        .help(title)
    }
}

struct SectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

struct WorkspaceApp: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var urlString: String
    var iconName: String
    var symbolName: String
    var isEnabled: Bool
    var isBuiltIn: Bool

    var url: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme) else {
            return nil
        }
        return url
    }

    static func isGmailURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "mail.google.com" || host.hasSuffix(".mail.google.com")
    }

    var image: NSImage? {
        let url = Self.workspaceIconURL(named: iconName)
        return url.flatMap(NSImage.init(contentsOf:))
    }

    private static func workspaceIconURL(named iconName: String) -> URL? {
        for bundleURL in workspaceResourceBundleCandidates() {
            if let bundle = Bundle(url: bundleURL) {
                if let url = bundle.url(forResource: iconName, withExtension: "png", subdirectory: "WorkspaceIcons")
                    ?? bundle.url(forResource: iconName, withExtension: "png") {
                    return url
                }
            }

            let directURL = bundleURL.appendingPathComponent("\(iconName).png")
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }
        }

        return nil
    }

    private static func workspaceResourceBundleCandidates() -> [URL] {
        let bundleName = "LazyestWork_LazyestWork.bundle"
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true))
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName, isDirectory: true))

        return candidates
    }

    static let calendarURL = URL(string: "https://calendar.google.com/calendar/u/0/r")!
    static let gmailURL = URL(string: "https://mail.google.com/mail/u/0/#inbox")!

    static func builtIn(
        _ id: String,
        _ title: String,
        _ urlString: String,
        iconName: String,
        symbolName: String,
        isEnabled: Bool
    ) -> WorkspaceApp {
        WorkspaceApp(
            id: id,
            title: title,
            urlString: urlString,
            iconName: iconName,
            symbolName: symbolName,
            isEnabled: isEnabled,
            isBuiltIn: true
        )
    }

    static func custom() -> WorkspaceApp {
        WorkspaceApp(
            id: "custom-\(UUID().uuidString)",
            title: "New App",
            urlString: "https://",
            iconName: "custom",
            symbolName: "app",
            isEnabled: true,
            isBuiltIn: false
        )
    }

    static let defaultApps: [WorkspaceApp] = [
        builtIn("gmail", "Gmail", "https://mail.google.com/mail/u/0/#inbox", iconName: "gmail", symbolName: "envelope", isEnabled: true),
        builtIn("calendar", "Calendar", "https://calendar.google.com/calendar/u/0/r", iconName: "calendar", symbolName: "calendar", isEnabled: true),
        builtIn("meet", "Meet", "https://meet.google.com/", iconName: "meet", symbolName: "video", isEnabled: true),
        builtIn("chat", "Chat", "https://chat.google.com/", iconName: "chat", symbolName: "message", isEnabled: true),
        builtIn("drive", "Drive", "https://drive.google.com/drive/u/0/my-drive", iconName: "drive", symbolName: "externaldrive", isEnabled: true),
        builtIn("docs", "Docs", "https://docs.google.com/document/u/0/", iconName: "docs", symbolName: "doc.text", isEnabled: true),
        builtIn("sheets", "Sheets", "https://docs.google.com/spreadsheets/u/0/", iconName: "sheets", symbolName: "tablecells", isEnabled: true),
        builtIn("slides", "Slides", "https://docs.google.com/presentation/u/0/", iconName: "slides", symbolName: "rectangle.on.rectangle", isEnabled: true),
        builtIn("analytics", "Analytics", "https://analytics.google.com/", iconName: "analytics", symbolName: "chart.bar", isEnabled: true),
        builtIn("search-console", "Search Console", "https://search.google.com/search-console", iconName: "search-console", symbolName: "magnifyingglass", isEnabled: true),
        builtIn("gemini", "Gemini", "https://gemini.google.com/", iconName: "gemini", symbolName: "sparkles", isEnabled: true),
        builtIn("notebooklm", "NotebookLM", "https://notebooklm.google.com/", iconName: "notebooklm", symbolName: "book.closed", isEnabled: true),
        builtIn("tag-manager", "Tag Manager", "https://tagmanager.google.com/", iconName: "tag-manager", symbolName: "tag", isEnabled: false),
        builtIn("forms", "Forms", "https://docs.google.com/forms/u/0/", iconName: "forms", symbolName: "list.clipboard", isEnabled: false),
        builtIn("sites", "Sites", "https://sites.google.com/u/0/", iconName: "sites", symbolName: "globe", isEnabled: false),
        builtIn("keep", "Keep", "https://keep.google.com/", iconName: "keep", symbolName: "note.text", isEnabled: false),
        builtIn("tasks", "Tasks", "https://tasks.google.com/", iconName: "tasks", symbolName: "checklist", isEnabled: false),
        builtIn("contacts", "Contacts", "https://contacts.google.com/", iconName: "contacts", symbolName: "person.2", isEnabled: false),
        builtIn("admin", "Admin", "https://admin.google.com/", iconName: "admin", symbolName: "person.badge.key", isEnabled: false),
        builtIn("groups", "Groups", "https://groups.google.com/", iconName: "groups", symbolName: "person.3", isEnabled: false),
        builtIn("apps-script", "Apps Script", "https://script.google.com/home", iconName: "apps-script", symbolName: "curlybraces", isEnabled: false),
        builtIn("cloud-search", "Cloud Search", "https://cloudsearch.google.com/", iconName: "cloud-search", symbolName: "magnifyingglass", isEnabled: false),
        builtIn("vault", "Vault", "https://vault.google.com/", iconName: "vault", symbolName: "archivebox", isEnabled: false),
        builtIn("voice", "Voice", "https://voice.google.com/", iconName: "voice", symbolName: "phone", isEnabled: false),
        builtIn("classroom", "Classroom", "https://classroom.google.com/", iconName: "classroom", symbolName: "person.2.rectangle.stack", isEnabled: false),
        builtIn("search", "Search", "https://www.google.com/", iconName: "search", symbolName: "magnifyingglass", isEnabled: false),
        builtIn("account", "Account", "https://myaccount.google.com/", iconName: "account", symbolName: "person.crop.circle", isEnabled: false),
        builtIn("maps", "Maps", "https://maps.google.com/", iconName: "maps", symbolName: "map", isEnabled: false),
        builtIn("youtube", "YouTube", "https://www.youtube.com/", iconName: "youtube", symbolName: "play.rectangle", isEnabled: false),
        builtIn("photos", "Photos", "https://photos.google.com/", iconName: "photos", symbolName: "photo", isEnabled: false),
        builtIn("translate", "Translate", "https://translate.google.com/", iconName: "translate", symbolName: "character.bubble", isEnabled: false),
        builtIn("news", "News", "https://news.google.com/", iconName: "news", symbolName: "newspaper", isEnabled: false),
        builtIn("finance", "Finance", "https://www.google.com/finance/", iconName: "finance", symbolName: "chart.line.uptrend.xyaxis", isEnabled: false),
        builtIn("ads", "Ads", "https://ads.google.com/", iconName: "ads", symbolName: "megaphone", isEnabled: false),
        builtIn("cloud-console", "Cloud", "https://console.cloud.google.com/", iconName: "cloud-console", symbolName: "cloud", isEnabled: false),
        builtIn("colab", "Colab", "https://colab.research.google.com/", iconName: "colab", symbolName: "terminal", isEnabled: false)
    ]
}

enum WorkspaceAppStore {
    static var configURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let current = base.appendingPathComponent("Lazyest Work", isDirectory: true).appendingPathComponent("workspace-apps.json")
        let legacy = base.appendingPathComponent("GWS Menu", isDirectory: true).appendingPathComponent("workspace-apps.json")
        if !FileManager.default.fileExists(atPath: current.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.createDirectory(
                at: current.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.copyItem(at: legacy, to: current)
        }
        return current
    }

    static func load() -> [WorkspaceApp] {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode([WorkspaceApp].self, from: data) else {
            return WorkspaceApp.defaultApps
        }
        return reconcile(decoded)
    }

    static func save(_ apps: [WorkspaceApp]) {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(apps)
            try data.write(to: configURL, options: [.atomic])
        } catch {
            NSLog("Failed to save workspace apps: \(error.localizedDescription)")
        }
    }

    private static func reconcile(_ storedApps: [WorkspaceApp]) -> [WorkspaceApp] {
        var defaultByID = Dictionary(uniqueKeysWithValues: WorkspaceApp.defaultApps.map { ($0.id, $0) })
        var merged: [WorkspaceApp] = []

        for stored in storedApps {
            if let defaultApp = defaultByID.removeValue(forKey: stored.id) {
                var app = stored
                app.iconName = defaultApp.iconName
                app.symbolName = defaultApp.symbolName
                app.isBuiltIn = true
                if app.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    app.title = defaultApp.title
                }
                if app.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    app.urlString = defaultApp.urlString
                }
                merged.append(app)
            } else {
                merged.append(stored)
            }
        }

        for defaultApp in WorkspaceApp.defaultApps where defaultByID[defaultApp.id] != nil {
            merged.append(defaultApp)
        }

        return merged
    }
}

enum AlertSettings {
    static let allowedLeadMinutes = [1, 5, 10, 15]
    private static let leadMinutesKey = "calendarAlertLeadMinutes"
    private static let calendarNotificationsEnabledKey = "calendarNotificationsEnabled"

    static func loadLeadMinutes() -> Int {
        let stored = UserDefaults.standard.integer(forKey: leadMinutesKey)
        return allowedLeadMinutes.contains(stored) ? stored : 10
    }

    static func saveLeadMinutes(_ minutes: Int) {
        let normalized = allowedLeadMinutes.contains(minutes) ? minutes : 10
        UserDefaults.standard.set(normalized, forKey: leadMinutesKey)
    }

    static func loadCalendarNotificationsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: calendarNotificationsEnabledKey)
    }

    static func saveCalendarNotificationsEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: calendarNotificationsEnabledKey)
    }
}

enum FocusSettings {
    private static let meetingFocusEnabledKey = "meetingFocusEnabled"

    static func loadMeetingFocusEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: meetingFocusEnabledKey)
    }

    static func saveMeetingFocusEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: meetingFocusEnabledKey)
    }
}

enum InstallLaunchSettings {
    private static let skipGoogleRestoreOnceKey = "gwsSkipGoogleRestoreOnce"

    static func consumeSkipGoogleRestoreOnce() -> Bool {
        let shouldSkip = UserDefaults.standard.bool(forKey: skipGoogleRestoreOnceKey)
        if shouldSkip {
            UserDefaults.standard.removeObject(forKey: skipGoogleRestoreOnceKey)
        }
        return shouldSkip
    }
}

enum AppResourceLocator {
    private static let resourceBundleName = "LazyestWork_LazyestWork.bundle"

    static func url(named name: String, extension fileExtension: String, subdirectory: String? = nil) -> URL? {
        for bundleURL in resourceBundleCandidates() {
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory) {
                return url
            }
            if subdirectory != nil,
               let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: name, withExtension: fileExtension) {
                return url
            }

            var directURL = bundleURL
            if let subdirectory {
                directURL.appendPathComponent(subdirectory, isDirectory: true)
            }
            directURL.appendPathComponent("\(name).\(fileExtension)")
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }
            if subdirectory != nil {
                let rootURL = bundleURL.appendingPathComponent("\(name).\(fileExtension)")
                if FileManager.default.fileExists(atPath: rootURL.path) {
                    return rootURL
                }
            }
        }
        return nil
    }

    private static func resourceBundleCandidates() -> [URL] {
        guard let resourceURL = Bundle.main.resourceURL else {
            return []
        }
        return [
            resourceURL.appendingPathComponent(resourceBundleName, isDirectory: true),
            resourceURL
        ]
    }
}

enum SystemOpener {
    static func openFile(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw AppError.focusShortcutFailed(name: url.lastPathComponent, detail: "open exited with status \(process.terminationStatus)")
        }
    }
}

enum MailBadgeSettings {
    private static let enabledKey = "mailUnreadBadgeEnabled"
    private static let legacyEnabledKey = "mailNotificationsEnabled"

    static func loadEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: enabledKey) != nil {
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        if UserDefaults.standard.object(forKey: legacyEnabledKey) != nil {
            return UserDefaults.standard.bool(forKey: legacyEnabledKey)
        }
        return true
    }

    static func saveEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: legacyEnabledKey)
    }
}

enum LaunchAtLoginSettings {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func isEnabled() -> Bool {
        status == .enabled
    }

    static func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}

enum SetupChecklistSettings {
    private static let dismissedKey = "setupChecklistDismissed"

    static func loadDismissed() -> Bool {
        UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func saveDismissed(_ isDismissed: Bool) {
        UserDefaults.standard.set(isDismissed, forKey: dismissedKey)
    }
}

enum NotificationNamespaces {
    static let calendar = "gws.calendar."
}

enum ConnectionState: Equatable {
    case loading
    case missingBundleConfig
    case signedOut
    case connected(name: String?, email: String?)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var menuTitle: String {
        switch self {
        case .loading:
            return "Google: Loading"
        case .missingBundleConfig:
            return "Google: Unavailable"
        case .signedOut:
            return "Google: Not connected"
        case .connected:
            return "Google: \(accountDisplayLabel ?? "Connected")"
        }
    }

    var accountDisplayLabel: String? {
        guard case .connected(let name, let email) = self else {
            return nil
        }
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cleanEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if let cleanName, let cleanEmail,
           cleanName.caseInsensitiveCompare(cleanEmail) != .orderedSame {
            return "\(cleanName) (\(cleanEmail))"
        }
        return cleanName ?? cleanEmail
    }

    var accountLine: String {
        switch self {
        case .loading:
            return "Checking Google"
        case .missingBundleConfig:
            return "Unavailable in this build"
        case .signedOut:
            return "Not connected"
        case .connected:
            return accountDisplayLabel ?? "Connected"
        }
    }
}

struct GoogleOAuthConfiguration {
    let clientID: String?
    let callbackScheme: String?

    var isComplete: Bool {
        clientID != nil && callbackScheme != nil
    }

    static var current: GoogleOAuthConfiguration {
        GoogleOAuthConfiguration(
            clientID: Bundle.main.googleClientID,
            callbackScheme: Bundle.main.googleReversedClientID
        )
    }
}

struct GoogleSignInGrant {
    let gmailLabelsGranted: Bool
}

@MainActor
final class GoogleSignInAuthClient {
    private let authWindow: AuthWindow
    private let calendarScope = "https://www.googleapis.com/auth/calendar.events.readonly"
    private let legacyCalendarScope = "https://www.googleapis.com/auth/calendar.readonly"
    private let gmailLabelsScope = "https://www.googleapis.com/auth/gmail.labels"
    private let signIn: GIDSignIn

    init(authWindow: AuthWindow) {
        self.authWindow = authWindow
        self.signIn = GoogleSignInFactory.makeSignIn()
    }

    func connectionState() -> ConnectionState {
        configureIfPossible()
        guard GoogleOAuthConfiguration.current.isComplete else {
            return .missingBundleConfig
        }
        guard let user = signIn.currentUser else {
            return .signedOut
        }
        return .connected(
            name: user.profile?.name,
            email: user.profile?.email
        )
    }

    func configure(clientID: String) {
        signIn.configuration = GIDConfiguration(clientID: clientID)
    }

    func handle(url: URL) -> Bool {
        signIn.handle(url)
    }

    func restorePreviousSignIn() async throws {
        configureIfPossible()
        guard GoogleOAuthConfiguration.current.isComplete else {
            throw AppError.missingBundleConfig
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            signIn.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if user != nil {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: AppError.notSignedIn)
                }
            }
        }
    }

    func signIn(includeGmailLabels: Bool = false) async throws -> GoogleSignInGrant {
        configureIfPossible()
        guard GoogleOAuthConfiguration.current.isComplete else {
            throw AppError.missingBundleConfig
        }
        GoogleSignInFactory.removeUnreadableFileKeychainSessionBeforeInteractiveSignIn()
        let window = authWindow.present(
            message: includeGmailLabels
                ? "Connect Calendar and Gmail unread count."
                : "Connect Google Calendar."
        )
        defer { authWindow.hide() }
        var scopes = [calendarScope]
        if includeGmailLabels {
            scopes.append(gmailLabelsScope)
        }

        let result = try await signIn.signIn(
            withPresenting: window,
            hint: nil,
            additionalScopes: scopes
        )
        if !hasCalendarScope(result.user) {
            throw AppError.calendarScopeNotGranted
        }
        return GoogleSignInGrant(
            gmailLabelsGranted: hasGmailLabelsScope(result.user)
        )
    }

    func calendarAccessToken() async throws -> String {
        let user = try await currentUserWithUsableAccessToken()
        if !hasCalendarScope(user) {
            throw AppError.calendarScopeNotGranted
        }
        return user.accessToken.tokenString
    }

    func gmailLabelsAccessToken() async throws -> String {
        let user = try await currentUserWithUsableAccessToken()
        if !hasGmailLabelsScope(user) {
            throw AppError.gmailScopeNotGranted
        }
        return user.accessToken.tokenString
    }

    func ensureGmailLabelsScope() async throws {
        configureIfPossible()
        guard GoogleOAuthConfiguration.current.isComplete else {
            throw AppError.missingBundleConfig
        }
        guard let user = signIn.currentUser else {
            throw AppError.notSignedIn
        }
        if hasGmailLabelsScope(user) {
            return
        }

        let window = authWindow.present(message: "Allow Gmail unread badge access.")
        defer { authWindow.hide() }
        let result: GIDSignInResult
        if GoogleSignInFactory.supportsPublicIncrementalScopes {
            result = try await addGmailLabelsScope(to: user, presenting: window)
        } else {
            result = try await signIn.signIn(
                withPresenting: window,
                hint: user.profile?.email,
                additionalScopes: [gmailLabelsScope]
            )
        }
        if !hasGmailLabelsScope(result.user) {
            throw AppError.gmailScopeNotGranted
        }
    }

    private func currentUserWithUsableAccessToken() async throws -> GIDGoogleUser {
        guard let user = signIn.currentUser else {
            throw AppError.notSignedIn
        }
        if let expirationDate = user.accessToken.expirationDate,
           expirationDate.timeIntervalSinceNow > 120 {
            return user
        }
        return try await refreshedCurrentUser()
    }

    private func refreshedCurrentUser() async throws -> GIDGoogleUser {
        guard let user = signIn.currentUser else {
            throw AppError.notSignedIn
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
            user.refreshTokensIfNeeded { user, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: AppError.notSignedIn)
                }
            }
        }
    }

    private func hasCalendarScope(_ user: GIDGoogleUser) -> Bool {
        let scopes = user.grantedScopes ?? []
        return scopes.contains(calendarScope) || scopes.contains(legacyCalendarScope)
    }

    private func hasGmailLabelsScope(_ user: GIDGoogleUser) -> Bool {
        user.grantedScopes?.contains(gmailLabelsScope) == true
    }

    func signOut() {
        signIn.signOut()
    }

    private func addGmailLabelsScope(
        to user: GIDGoogleUser,
        presenting window: NSWindow
    ) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            user.addScopes([gmailLabelsScope], presenting: window) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AppError.gmailScopeNotGranted)
                }
            }
        }
    }

    private func configureIfPossible() {
        guard signIn.configuration == nil,
              let clientID = GoogleOAuthConfiguration.current.clientID else {
            return
        }
        configure(clientID: clientID)
    }
}

enum GoogleSignInFactory {
    private static let authItemName = "auth"

    static var supportsPublicIncrementalScopes: Bool {
        #if GWS_FILE_KEYCHAIN
        false
        #else
        true
        #endif
    }

    @MainActor
    static func makeSignIn() -> GIDSignIn {
        #if GWS_FILE_KEYCHAIN
        if let fileKeychainSignIn = makeMacFileKeychainSignIn() {
            return fileKeychainSignIn
        }
        #endif
        return GIDSignIn.sharedInstance
    }

    static func removeUnreadableFileKeychainSessionBeforeInteractiveSignIn() {
        #if GWS_FILE_KEYCHAIN
        let store = makeFileKeychainStore()
        do {
            _ = try store.retrieveAuthSession()
        } catch {
            do {
                try store.removeAuthSession()
                AppLog.lifecycle.notice("Removed an unreadable legacy Google Keychain session before reconnecting")
            } catch {
                // A missing or locked item needs no destructive fallback here.
                // Google Sign-In will report the actionable error to the user.
            }
        }
        #endif
    }

    #if GWS_FILE_KEYCHAIN
    private static func makeFileKeychainStore() -> KeychainStore {
        KeychainStore(
            itemName: authItemName,
            keychainAttributes: [KeychainAttribute.useFileBasedKeychain]
        )
    }

    @MainActor
    private static func makeMacFileKeychainSignIn() -> GIDSignIn? {
        let store = makeFileKeychainStore()
        guard let migrationClass = objc_getClass("GIDAuthStateMigration") as? AnyObject,
              let migrationAllocated = migrationClass.perform(NSSelectorFromString("alloc"))?.takeRetainedValue(),
              let migration = migrationAllocated
                .perform(NSSelectorFromString("initWithKeychainStore:"), with: store)?
                .takeUnretainedValue(),
              let signInClass = GIDSignIn.self as AnyObject?,
              let signInAllocated = signInClass.perform(NSSelectorFromString("alloc"))?.takeRetainedValue(),
              let signIn = signInAllocated
                .perform(NSSelectorFromString("initWithKeychainStore:authStateMigrationService:"), with: store, with: migration)?
                .takeUnretainedValue() as? GIDSignIn else {
            return nil
        }
        return signIn
    }
    #endif
}

@MainActor
final class AuthWindow {
    // GoogleSignIn needs a live NSWindow as the ASWebAuthenticationSession
    // presentation anchor on macOS. Keep that technical anchor invisible: the
    // user should see the Google authentication sheet, not an extra Lazyest
    // Work window between the menu-bar action and Google.
    private lazy var window: NSWindow = {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 2, height: 2),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        return window
    }()

    func present(message _: String) -> NSWindow {
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    func hide() {
        window.orderOut(nil)
    }
}

enum GoogleAPIService: String, Sendable {
    case calendar
    case gmail
}

struct GoogleAPIError: LocalizedError, Sendable {
    let service: GoogleAPIService
    let statusCode: Int
    let reason: String?
    let message: String

    var errorDescription: String? { message }

    var requiresReconnect: Bool {
        guard statusCode == 401 || statusCode == 403 else { return false }
        let normalizedReason = reason?.lowercased() ?? ""
        return statusCode == 401 || [
            "autherror",
            "invalidcredentials",
            "invalid_grant",
            "unauthorized"
        ].contains(normalizedReason)
    }

    var isUnavailableInBuild: Bool {
        let normalizedReason = reason?.lowercased() ?? ""
        let normalizedMessage = message.lowercased()
        return ["accessnotconfigured", "servicedisabled", "service_disabled"].contains(normalizedReason) ||
            normalizedMessage.contains("api has not been used") ||
            normalizedMessage.contains("service disabled")
    }

    var requiresAdditionalScope: Bool {
        guard statusCode == 403 else { return false }
        let normalizedReason = reason?.lowercased() ?? ""
        let normalizedMessage = message.lowercased()
        return ["insufficientpermissions", "insufficient_permissions"].contains(normalizedReason) ||
            normalizedMessage.contains("insufficient authentication scope")
    }

    var isTransient: Bool {
        if statusCode == 408 || statusCode == 429 || statusCode >= 500 {
            return true
        }
        let normalizedReason = reason?.lowercased() ?? ""
        return [
            "backenderror",
            "dailylimitexceeded",
            "ratelimitexceeded",
            "userratelimitexceeded"
        ].contains(normalizedReason)
    }

    static func decode(
        service: GoogleAPIService,
        statusCode: Int,
        data: Data
    ) -> GoogleAPIError {
        let envelope = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data)
        let fallback = String(data: data, encoding: .utf8)?.nilIfBlank
            ?? "HTTP \(statusCode)"
        return GoogleAPIError(
            service: service,
            statusCode: statusCode,
            reason: envelope?.error.errors?.first?.reason ?? envelope?.error.status,
            message: envelope?.error.message ?? fallback
        )
    }
}

private struct GoogleErrorEnvelope: Decodable {
    let error: Payload

    struct Payload: Decodable {
        let message: String?
        let status: String?
        let errors: [Detail]?
    }

    struct Detail: Decodable {
        let reason: String?
    }
}

@MainActor
final class GoogleCalendarService {
    private let authClient: GoogleSignInAuthClient

    init(authClient: GoogleSignInAuthClient) {
        self.authClient = authClient
    }

    func loadUpcomingEvents() async throws -> [MeetingEvent] {
        let token = try await authClient.calendarAccessToken()
        let now = Date()
        let end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(604_800)

        return try await listPrimaryEvents(token: token, start: now, end: end)
            .filter { !$0.isAllDay && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    private func listPrimaryEvents(token: String, start: Date, end: Date) async throws -> [MeetingEvent] {
        let encodedCalendarId = "primary".pathSegmentEncoded
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarId)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: AppDateFormatters.iso8601String(from: start)),
            URLQueryItem(name: "timeMax", value: AppDateFormatters.iso8601String(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "timeZone", value: TimeZone.autoupdatingCurrent.identifier),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(
                name: "fields",
                value: "items(id,summary,description,location,htmlLink,hangoutLink,status,eventType,transparency,creator(email,displayName,self),organizer(email,displayName,self),attendees(email,displayName,resource,self,responseStatus),start(dateTime,date),end(dateTime,date))"
            )
        ]

        let response: GoogleEventsResponse = try await get(components.url!, token: token)
        let events = (response.items ?? []).filter(\.belongsOnMyCalendar)
        return events.compactMap {
            MeetingEvent(event: $0, calendarName: nil)
        }
    }

    private func get<T: Decodable>(
        _ url: URL,
        token: String,
        service: GoogleAPIService = .calendar
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleAPIError.decode(
                service: service,
                statusCode: http.statusCode,
                data: data
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

}

@MainActor
final class GoogleGmailService {
    private let authClient: GoogleSignInAuthClient

    init(authClient: GoogleSignInAuthClient) {
        self.authClient = authClient
    }

    func loadInboxUnreadCount() async throws -> Int {
        let token = try await authClient.gmailLabelsAccessToken()
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "messagesUnread")
        ]

        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleAPIError.decode(
                service: .gmail,
                statusCode: http.statusCode,
                data: data
            )
        }

        let decoded = try JSONDecoder().decode(GmailLabelResponse.self, from: data)
        return decoded.messagesUnread ?? 0
    }
}

struct GmailLabelResponse: Decodable {
    let messagesUnread: Int?
}

struct GoogleEventsResponse: Decodable {
    let items: [GoogleEvent]?
}

struct GoogleEvent: Decodable {
    let id: String
    let summary: String?
    let description: String?
    let location: String?
    let htmlLink: String?
    let hangoutLink: String?
    let status: String?
    let eventType: String?
    let transparency: String?
    let creator: GoogleEventPerson?
    let organizer: GoogleEventPerson?
    let attendees: [GoogleEventAttendee]?
    let start: GoogleEventDate
    let end: GoogleEventDate
}

struct GoogleEventPerson: Decodable {
    let email: String?
    let displayName: String?
    let selfPerson: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName
        case selfPerson = "self"
    }

    var label: String? {
        CalendarPersonLabel.displayName(
            displayName,
            email: email
        )
    }
}

struct MeetingParticipant: Identifiable, Equatable {
    let id: String
    let label: String
    let email: String?
    let role: String?
    let responseStatus: String?

    var statusSymbolName: String {
        switch responseStatus {
        case "accepted":
            return "checkmark.circle.fill"
        case "tentative":
            return "questionmark.circle.fill"
        case "declined":
            return "xmark.circle.fill"
        case "needsAction", nil:
            return "circle"
        default:
            return "circle.dotted"
        }
    }

    var statusColor: Color {
        switch responseStatus {
        case "accepted":
            return .green
        case "tentative":
            return .orange
        case "declined":
            return .red
        default:
            return .secondary
        }
    }

    func helpText(text: AppText) -> String {
        let localizedRole = role == "Host" ? text.host : role?.nilIfBlank
        return [label, email, localizedRole, text.participantResponse(responseStatus)]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: "\n")
    }
}

struct GoogleEventAttendee: Decodable {
    let email: String?
    let displayName: String?
    let resource: Bool?
    let selfAttendee: Bool?
    let responseStatus: String?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName
        case resource
        case selfAttendee = "self"
        case responseStatus
    }

    var roomLabel: String? {
        guard resource == true else {
            return nil
        }
        return displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var guestLabel: String? {
        guard resource != true else {
            return nil
        }
        return CalendarPersonLabel.displayName(
            displayName,
            email: email
        )
    }
}

enum CalendarPersonLabel {
    static func displayName(
        _ displayName: String?,
        email: String?
    ) -> String? {
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           !name.contains("@") {
            return name
        }

        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        return email
    }
}

extension GoogleEvent {
    var belongsOnMyCalendar: Bool {
        if status == "cancelled" {
            return false
        }
        if let eventType, eventType != "default" {
            return false
        }
        if transparency == "transparent" {
            return false
        }
        return true
    }
}

struct GoogleEventDate: Decodable {
    let dateTime: String?
    let date: String?
}

struct MeetingEvent: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let notes: String
    let location: String
    let room: String
    let htmlLink: URL?
    let hangoutLink: URL?
    let calendarName: String?
    let isAllDay: Bool
    let organizerName: String?
    let guestCount: Int
    let participants: [MeetingParticipant]
    let selfResponseStatus: CalendarSelfResponseStatus

    init?(event: GoogleEvent, calendarName: String?) {
        func parseDateTime(_ value: String?) -> Date? {
            value.flatMap(AppDateFormatters.parseISO8601)
        }

        let allDay = event.start.dateTime == nil || event.end.dateTime == nil
        guard let start = parseDateTime(event.start.dateTime),
              let end = parseDateTime(event.end.dateTime) else {
            return nil
        }

        self.id = event.id
        self.title = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "(No title)"
        self.start = start
        self.end = end
        self.notes = event.description ?? ""
        self.location = event.location ?? ""
        self.room = event.attendees?
            .compactMap(\.roomLabel)
            .joined(separator: ", ")
            .nilIfBlank ?? self.location
        self.htmlLink = event.htmlLink.flatMap(URL.init(string:))
        self.hangoutLink = event.hangoutLink.flatMap(URL.init(string:))
        self.calendarName = calendarName
        self.isAllDay = allDay
        self.organizerName = event.organizer?.label
            ?? event.creator?.label
        self.guestCount = MeetingEvent.guestCount(from: event)
        self.participants = MeetingEvent.participants(from: event)
        self.selfResponseStatus = MeetingEvent.selfResponseStatus(from: event)
    }

    var meetingURL: URL? {
        if let hangoutLink {
            return hangoutLink
        }
        if let htmlLink, MeetingLinkDetector.isMeetingURL(htmlLink) {
            return htmlLink
        }
        return MeetingLinkDetector.firstMeetingURL(in: [location, notes].joined(separator: "\n"))
    }

    var hasMeetingSignal: Bool {
        meetingURL != nil || guestCount > 0
    }

    var timeText: String {
        AppDateFormatters.timeIntervalString(from: start, to: end)
    }

    var countdownText: String {
        let now = Date()
        if start <= now && end > now {
            return "Now"
        }

        let minutes = max(0, Int(ceil(start.timeIntervalSince(now) / 60)))
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    func dayText(
        relativeTo now: Date,
        language: AppLanguage = AppLanguageSettings.load(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        if calendar.isDate(start, inSameDayAs: now) {
            return language == .korean ? "오늘" : "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(start, inSameDayAs: tomorrow) {
            return language == .korean ? "내일" : "Tomorrow"
        }

        let weekday = weekdayText(for: start, language: language)
        if isNextWeek(start, relativeTo: now, calendar: calendar) {
            return language == .korean ? "다음 \(weekday)" : "Next \(weekday)"
        }
        return weekday
    }

    private func isNextWeek(_ date: Date, relativeTo now: Date, calendar: Calendar) -> Bool {
        guard
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
            let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek.start),
            let nextWeekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: nextWeekStart)
        else {
            return false
        }

        return date >= nextWeekStart && date < nextWeekEnd
    }

    private func weekdayText(for date: Date, language: AppLanguage) -> String {
        AppDateFormatters.weekdayString(from: date, language: language)
    }

    var startTimeText: String {
        AppDateFormatters.shortTimeString(from: start)
    }

    var endTimeText: String {
        AppDateFormatters.shortTimeString(from: end)
    }

    var detailLine: String {
        [timeText, roomLine, calendarName]
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            .joined(separator: " · ")
    }

    var roomLine: String? {
        room.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var participantSummary: String? {
        let guestText = guestCount > 0 ? "+\(guestCount)" : nil
        let hostText = organizerName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map { "by \($0.truncated(maxLength: 18))" }
        return [hostText, guestText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }

    var participantCompactText: String? {
        let hostText = organizerName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map { $0.truncated(maxLength: 14) }
        let guestText = guestCount > 0 ? "+\(guestCount)" : nil
        return [hostText, guestText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }

    func participantToolTip(text: AppText) -> String {
        let host = organizerName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map { "\(text.host): \($0)" }
        let guests = text.participantCount(guestCount)
        return [host, guests]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private static func guestCount(from event: GoogleEvent) -> Int {
        let organizerEmail = event.organizer?.email?.lowercased()
        return event.attendees?
            .filter { $0.resource != true }
            .filter { $0.responseStatus != "declined" }
            .filter { attendee in
                guard let organizerEmail,
                      let attendeeEmail = attendee.email?.lowercased() else {
                    return true
                }
                return attendeeEmail != organizerEmail
            }
            .count ?? 0
    }

    private static func participants(from event: GoogleEvent) -> [MeetingParticipant] {
        let organizerEmail = event.organizer?.email?.lowercased()
        var participants: [MeetingParticipant] = []

        if let organizer = event.organizer ?? event.creator,
           let label = organizer.label?.nilIfBlank {
            participants.append(MeetingParticipant(
                id: "organizer-\(organizer.email ?? label)",
                label: label,
                email: organizer.email,
                role: "Host",
                responseStatus: nil
            ))
        }

        let guests = event.attendees?
            .filter { $0.resource != true }
            .filter { attendee in
                guard let organizerEmail,
                      let attendeeEmail = attendee.email?.lowercased() else {
                    return true
                }
                return attendeeEmail != organizerEmail
            }
            .compactMap { attendee -> MeetingParticipant? in
                guard let label = attendee.guestLabel?.nilIfBlank else {
                    return nil
                }
                let email = attendee.email?.nilIfBlank
                return MeetingParticipant(
                    id: email ?? "\(label)-\(attendee.responseStatus ?? "unknown")",
                    label: label,
                    email: email,
                    role: nil,
                    responseStatus: attendee.responseStatus
                )
            } ?? []

        participants.append(contentsOf: guests)
        return participants
    }

    private static func selfResponseStatus(from event: GoogleEvent) -> CalendarSelfResponseStatus {
        if event.organizer?.selfPerson == true || event.creator?.selfPerson == true {
            return .accepted
        }
        if let responseStatus = event.attendees?.first(where: { $0.selfAttendee == true })?.responseStatus {
            return CalendarSelfResponseStatus(rawGoogleValue: responseStatus)
        }
        return .accepted
    }

    var menuBarTitle: String {
        title.truncatedForMenuBar(maxLength: 28)
    }

    var statusToolTip: String {
        "\(title)\n\(timeText)"
    }

    func notificationIdentifier(leadMinutes: Int) -> String {
        let rawID = id.replacingOccurrences(of: #"[^A-Za-z0-9_-]"#, with: "-", options: .regularExpression)
        return "\(NotificationNamespaces.calendar)\(rawID)-\(Int(start.timeIntervalSince1970))-\(leadMinutes)"
    }
}

extension MeetingEvent: MenuEventRepresentable, FocusEventRepresentable {}

extension CalendarSelfResponseStatus {
    var indicatorColor: Color {
        switch indicatorSemanticColor {
        case .green:
            return .green
        case .orange:
            return .orange
        case .gray:
            return .secondary
        case .red:
            return .red
        }
    }

    var helpText: String {
        switch self {
        case .accepted:
            return "Accepted"
        case .tentative:
            return "Tentative"
        case .needsAction:
            return "No response"
        case .declined:
            return "Declined"
        case .unknown:
            return "Unknown response"
        }
    }
}

enum MeetingLinkDetector {
    private static let providers = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com"
    ]

    static func isMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return providers.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func firstMeetingURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.compactMap(\.url).first(where: isMeetingURL)
    }
}

enum AppError: LocalizedError, Sendable {
    case missingBundleConfig
    case invalidResponse
    case notSignedIn
    case calendarScopeNotGranted
    case gmailScopeNotGranted
    case notificationPermissionDenied
    case focusShortcutFailed(name: String, detail: String)
    case microsoftNotSignedIn
    case keychain(String, OSStatus)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleConfig:
            return "Google client ID and URL scheme are missing from the app bundle"
        case .invalidResponse:
            return "Invalid response"
        case .notSignedIn:
            return "Not signed in"
        case .calendarScopeNotGranted:
            return "Google Calendar permission was not granted"
        case .gmailScopeNotGranted:
            return "Gmail unread-count permission was not granted"
        case .notificationPermissionDenied:
            return "macOS notification permission was not granted"
        case .focusShortcutFailed(let name, let detail):
            return "Focus shortcut '\(name)' failed: \(detail)"
        case .microsoftNotSignedIn:
            return "Microsoft Teams is not connected"
        case .keychain(let action, let status):
            return "Keychain could not \(action) (status \(status))"
        case .api(let message):
            return message
        }
    }
}

extension Bundle {
    var googleClientID: String? {
        guard let value = object(forInfoDictionaryKey: "GIDClientID") as? String,
              value.nilIfBlank != nil,
              !value.contains("YOUR_GOOGLE_CLIENT_ID") else {
            return nil
        }
        return value
    }

    var googleReversedClientID: String? {
        guard let urlTypes = object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return nil
        }

        for urlType in urlTypes {
            guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else {
                continue
            }
            if let scheme = schemes.first(where: { value in
                value.hasPrefix("com.googleusercontent.apps.") &&
                    value.nilIfBlank != nil &&
                    !value.contains("YOUR_GOOGLE_CLIENT_ID")
            }) {
                return scheme
            }
        }

        return nil
    }

}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var pathSegmentEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    func truncatedForMenuBar(maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }
        return String(prefix(max(0, maxLength - 3))) + "..."
    }

    func truncated(maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }
        return String(prefix(max(0, maxLength - 3))) + "..."
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
