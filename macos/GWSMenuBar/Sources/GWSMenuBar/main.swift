import AppKit
import Combine
import Foundation
import GTMAppAuth
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import GoogleSignIn
@preconcurrency import UserNotifications

final class AppModel: ObservableObject {
    @Published var events: [MeetingEvent] = []
    @Published var now = Date()
    @Published var connectionState = ConnectionState.loading
    @Published var lastError: String?
    @Published var lastErrorRecovery: ErrorRecoveryAction?
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
    @Published var mailBadgeEnabled: Bool {
        didSet {
            MailBadgeSettings.saveEnabled(mailBadgeEnabled)
        }
    }

    init() {
        alertLeadMinutes = AlertSettings.loadLeadMinutes()
        calendarNotificationsEnabled = AlertSettings.loadCalendarNotificationsEnabled()
        mailBadgeEnabled = MailBadgeSettings.loadEnabled()
    }
}

enum ErrorRecoveryAction {
    case googleSetup
    case gmailPermission

    var buttonTitle: String {
        switch self {
        case .googleSetup:
            return "Setup"
        case .gmailPermission:
            return "Allow"
        }
    }
}

enum UnreadCountFormatter {
    static func display(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

enum AppImages {
    private static let googleBlue = NSColor(calibratedRed: 66.0 / 255.0, green: 133.0 / 255.0, blue: 244.0 / 255.0, alpha: 1)
    private static let googleRed = NSColor(calibratedRed: 219.0 / 255.0, green: 68.0 / 255.0, blue: 55.0 / 255.0, alpha: 1)
    private static let googleYellow = NSColor(calibratedRed: 244.0 / 255.0, green: 180.0 / 255.0, blue: 0, alpha: 1)
    private static let googleGreen = NSColor(calibratedRed: 15.0 / 255.0, green: 157.0 / 255.0, blue: 88.0 / 255.0, alpha: 1)

    static func menuBarIcon(unreadCount: Int? = nil) -> NSImage {
        guard let unreadCount, unreadCount > 0 else {
            return appIcon(size: 18)
        }

        return badgedMenuBarIcon(countText: UnreadCountFormatter.display(unreadCount))
    }

    static func headerIcon() -> NSImage {
        appIcon(size: 18)
    }

    private static func appIcon(size: CGFloat) -> NSImage {
        if let icon = bundledAppIcon(size: size) {
            return icon
        }

        return googleWorkspaceIcon(size: size, dotSize: 4.2)
    }

    private static func badgedMenuBarIcon(countText: String) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        appIcon(size: size).draw(in: NSRect(x: 0, y: 0, width: size, height: size))

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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let authWindow = AuthWindow()
    private let model = AppModel()
    private lazy var authClient = GoogleSignInAuthClient(authWindow: authWindow)
    private lazy var calendarService = GoogleCalendarService(authClient: authClient)
    private lazy var gmailService = GoogleGmailService(authClient: authClient)
    private lazy var popover: NSPopover = makePopover()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var statusIconUnreadText: String?
    private var renderedStatusTitle: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        configureApplicationMenu()
        configureStatusItem()
        bindModel()

        Task {
            await restoreAndRefresh()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateNow()
                await self?.refreshEvents()
                await self?.refreshGmailUnread()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = authClient.handle(url: url)
        }
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
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 590)
        popover.contentViewController = NSHostingController(
            rootView: GWSMenuPopover(
                model: model,
                onSignIn: { [weak self] in self?.signIn() },
                onRefresh: { [weak self] in self?.refreshFromMenu() },
                onSignOut: { [weak self] in self?.signOut() },
                onResetGoogleSetup: { [weak self] in self?.resetGoogleSetup() },
                onEnableGmailBadge: { [weak self] in self?.enableGmailBadgeFromMenu() },
                onApplyGoogleSetup: { [weak self] config in
                    self?.applyGoogleSetup(config) ?? .failure("App is not ready to apply setup.")
                },
                onApplySettings: { [weak self] apps, alertLeadMinutes, calendarNotificationsEnabled, mailBadgeEnabled in
                    self?.applyAppSettings(
                        apps: apps,
                        alertLeadMinutes: alertLeadMinutes,
                        calendarNotificationsEnabled: calendarNotificationsEnabled,
                        mailBadgeEnabled: mailBadgeEnabled
                    )
                },
                onOpenURL: { url in NSWorkspace.shared.open(url) }
            )
        )
        return popover
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "GWS Menu")
        appMenu.addItem(NSMenuItem(title: "Quit GWS Menu", action: #selector(quit), keyEquivalent: "q"))
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
    }

    private func restoreAndRefresh() async {
        do {
            try await authClient.restorePreviousSignIn()
            model.connectionState = authClient.connectionState()
            await refreshEvents()
            await refreshGmailUnread()
        } catch {
            model.connectionState = authClient.connectionState()
            model.lastError = nil
            model.lastErrorRecovery = nil
            refreshUI()
            await syncCalendarNotifications()
        }
    }

    private func refreshEvents() async {
        updateNow()
        guard model.connectionState.isConnected else {
            model.events = []
            refreshUI()
            cancelCalendarNotifications()
            return
        }

        model.isBusy = true
        model.lastError = nil
        model.lastErrorRecovery = nil
        refreshUI()

        do {
            model.events = try await calendarService.loadUpcomingEvents()
            model.connectionState = authClient.connectionState()
        } catch {
            model.events = []
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = .googleSetup
            model.connectionState = authClient.connectionState()
        }

        model.isBusy = false
        refreshUI()
        await syncCalendarNotifications()
    }

    private func refreshUI() {
        updateStatusIcon()
        updateTitle()
    }

    private func updateNow() {
        model.now = Date()
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
            setStatusTitle("", toolTip: "Loading GWS Menu")
        case .missingBundleConfig:
            setStatusTitle("", toolTip: "Google Sign-In is not configured")
        case .signedOut:
            setStatusTitle("", toolTip: "Sign in to Google Calendar")
        case .connected:
            let now = model.now
            if let active = model.events.first(where: { $0.start <= now && $0.end > now }) {
                setStatusTitle(
                    statusTitle(meetingText: "Now · \(active.menuBarTitle)"),
                    toolTip: statusToolTip(meetingToolTip: active.statusToolTip)
                )
                return
            }

            guard let next = model.events.first(where: { $0.start > now }) else {
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
            refreshUI()

            do {
                try await authClient.signIn()
                model.connectionState = authClient.connectionState()
                await refreshEvents()
                if model.mailBadgeEnabled {
                    await enableGmailUnreadBadge()
                } else {
                    model.gmailUnreadCount = nil
                }
            } catch {
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = .googleSetup
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
        model.events = []
        model.gmailUnreadCount = nil
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.connectionState = authClient.connectionState()
        cancelCalendarNotifications()
        refreshUI()
    }

    private func resetGoogleSetup() {
        guard !model.isBusy else { return }
        model.isBusy = true
        model.lastError = nil
        model.lastErrorRecovery = nil
        refreshUI()

        Task {
            do {
                await authClient.clearSavedUserGrant()
                try GoogleAppBundleSetup.reset()
                model.events = []
                model.gmailUnreadCount = nil
                model.connectionState = .missingBundleConfig
                cancelCalendarNotifications()
                refreshUI()
                relaunchApp()
            } catch {
                model.lastError = userFacingError(error)
                model.lastErrorRecovery = .googleSetup
                model.connectionState = authClient.connectionState()
                model.isBusy = false
                refreshUI()
            }
        }
    }

    private func applyAppSettings(
        apps: [WorkspaceApp],
        alertLeadMinutes: Int,
        calendarNotificationsEnabled: Bool,
        mailBadgeEnabled: Bool
    ) {
        model.workspaceApps = apps
        model.alertLeadMinutes = alertLeadMinutes
        model.calendarNotificationsEnabled = calendarNotificationsEnabled
        model.mailBadgeEnabled = mailBadgeEnabled
        model.lastError = nil
        model.lastErrorRecovery = nil
        WorkspaceAppStore.save(apps)
        refreshUI()

        Task {
            await syncCalendarNotifications()
            if mailBadgeEnabled {
                await enableGmailUnreadBadge()
            } else {
                model.gmailUnreadCount = nil
            }
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
        } catch {
            model.calendarNotificationsEnabled = false
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = .googleSetup
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
            let fireDate = event.start.addingTimeInterval(-leadSeconds)
            let identifier = event.notificationIdentifier(leadMinutes: model.alertLeadMinutes)
            guard fireDate > now.addingTimeInterval(3) else {
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
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func enableGmailUnreadBadge() async {
        do {
            if model.connectionState.isConnected {
                try await authClient.ensureGmailLabelsScope()
                await refreshGmailUnread()
            }
        } catch {
            model.gmailUnreadCount = nil
            model.mailBadgeEnabled = true
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = gmailRecoveryAction(for: error)
            refreshUI()
        }
    }

    private func refreshGmailUnread() async {
        guard model.mailBadgeEnabled, model.connectionState.isConnected else {
            model.gmailUnreadCount = nil
            return
        }

        do {
            let unreadCount = try await gmailService.loadInboxUnreadCount()
            model.gmailUnreadCount = unreadCount
            model.lastError = nil
            model.lastErrorRecovery = nil
            refreshUI()
        } catch {
            model.lastError = userFacingError(error)
            model.lastErrorRecovery = gmailRecoveryAction(for: error)
            refreshUI()
        }
    }

    private func enableGmailBadgeFromMenu() {
        guard model.connectionState.isConnected else { return }
        popover.performClose(nil)
        model.mailBadgeEnabled = true
        model.lastError = nil
        model.lastErrorRecovery = nil
        model.isBusy = true
        refreshUI()

        Task {
            await enableGmailUnreadBadge()
            model.isBusy = false
            refreshUI()
        }
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
            updateNow()
            refreshUI()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showStatusMenu(anchor: NSStatusBarButton) {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit GWS Menu", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func applyGoogleSetup(_ config: GoogleSetupConfig) -> GoogleSetupResult {
        do {
            let normalized = try GoogleSetupConfig.normalized(
                clientID: config.clientID,
                reversedClientID: config.reversedClientID
            )
            let current = GoogleSetupConfig.current
            if current.clientID == normalized.clientID,
               current.resolvedReversedClientID == normalized.resolvedReversedClientID {
                authClient.configure(clientID: normalized.clientID)
                model.connectionState = authClient.connectionState()
                refreshUI()
                return .success("Setup is already saved. You can sign in now.")
            }
            try GoogleAppBundleSetup.apply(config: normalized)
            authClient.configure(clientID: normalized.clientID)
            model.connectionState = authClient.connectionState()
            refreshUI()
            relaunchApp()
            return .success("Saved setup. GWS Menu will restart now.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func userFacingError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if isGmailSetupError(error) {
            return "Gmail unread badge could not be enabled. Enable Gmail API in Google Cloud, then try again."
        }
        if isGmailPermissionError(error) {
            return "Gmail unread badge needs permission. Click Allow, then approve Gmail unread-count access."
        }
        if lowercased.contains("client_secret") || lowercased.contains("invalid_client") {
            let bundleID = Bundle.main.bundleIdentifier ?? "io.github.gwsmenu.app"
            return "This looks like a Web application OAuth client. Create an OAuth client for Apple's native app type in Google Cloud, use bundle ID \(bundleID), then paste that Client ID in Open Setup. GWS Menu does not use a client secret."
        }
        if lowercased.contains("redirect_uri_mismatch") || lowercased.contains("url scheme") {
            return "Google could not return to GWS Menu. Open Setup and save the generated URL scheme, then try signing in again."
        }
        if lowercased.contains("keychain") {
            return "Google Sign-In could not read or save credentials. Open Setup, save the current Client ID once, then try Sign in again."
        }
        if lowercased.contains("gmail") || lowercased.contains("mail") {
            return "Gmail unread badge could not be enabled. Enable Gmail API in Google Cloud, then try the Inbox unread badge setting again."
        }
        if lowercased.contains("notification") {
            return "macOS notification permission is off. Turn it on in System Settings, then enable the alert again."
        }
        if lowercased.contains("access_denied") || lowercased.contains("permission") {
            return "Calendar permission was not granted. Try Sign in again and allow read-only Google Calendar access."
        }
        return message
    }

    private func gmailRecoveryAction(for error: Error) -> ErrorRecoveryAction {
        isGmailSetupError(error) ? .googleSetup : .gmailPermission
    }

    private func isGmailSetupError(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.localizedCaseInsensitiveContains("accessNotConfigured") ||
            message.localizedCaseInsensitiveContains("api has not been used") ||
            message.localizedCaseInsensitiveContains("service_disabled") ||
            message.localizedCaseInsensitiveContains("gmail api") && message.localizedCaseInsensitiveContains("disabled")
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

    private func relaunchApp() {
        let bundlePath = Bundle.main.bundleURL.path.shellQuoted
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \(bundlePath)"]
        try? task.run()
        NSApp.terminate(nil)
    }
}

enum PopoverScreen {
    case home
    case appSettings
    case googleSetup
}

struct GWSMenuPopover: View {
    @ObservedObject var model: AppModel
    @State private var screen = PopoverScreen.home
    @State private var editorID = UUID()
    let onSignIn: () -> Void
    let onRefresh: () -> Void
    let onSignOut: () -> Void
    let onResetGoogleSetup: () -> Void
    let onEnableGmailBadge: () -> Void
    let onApplyGoogleSetup: (GoogleSetupConfig) -> GoogleSetupResult
    let onApplySettings: ([WorkspaceApp], Int, Bool, Bool) -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        Group {
            switch screen {
            case .home:
                homeView
            case .appSettings:
                WorkspaceAppsEditor(
                    initialApps: model.workspaceApps,
                    initialAlertLeadMinutes: model.alertLeadMinutes,
                    initialCalendarNotificationsEnabled: model.calendarNotificationsEnabled,
                    initialMailBadgeEnabled: model.mailBadgeEnabled,
                    onCancel: { screen = .home },
                    onResetGoogleSetup: onResetGoogleSetup,
                    onApply: { apps, alertLeadMinutes, calendarNotificationsEnabled, mailBadgeEnabled in
                        onApplySettings(apps, alertLeadMinutes, calendarNotificationsEnabled, mailBadgeEnabled)
                        screen = .home
                    }
                )
                .id(editorID)
            case .googleSetup:
                GoogleSetupView(
                    initialConfig: GoogleSetupConfig.current,
                    onCancel: { screen = .home },
                    onApply: onApplyGoogleSetup,
                    onOpenURL: onOpenURL
                )
            }
        }
        .frame(width: 420, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var homeView: some View {
        VStack(spacing: 0) {
            HeaderView(
                connectionState: model.connectionState,
                isBusy: model.isBusy,
                onRefresh: onRefresh
            )

            Divider()

            WorkspaceGrid(
                apps: model.workspaceApps.filter(\.isEnabled),
                gmailUnreadCount: model.gmailUnreadCount,
                onOpenURL: onOpenURL
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let lastError = model.lastError {
                        let recovery = model.lastErrorRecovery ?? .googleSetup
                        ErrorBanner(
                            message: lastError,
                            actionTitle: recovery.buttonTitle,
                            action: { recoverFromError(recovery) }
                        )
                    }

                    if !model.connectionState.isConnected || model.events.isEmpty {
                        PrimaryCalendarCard(
                            connectionState: model.connectionState,
                            isBusy: model.isBusy,
                            onSignIn: onSignIn,
                            onShowSetup: openGoogleSetup
                        )
                    }

                    UpcomingEventsView(events: Array(model.events.prefix(8)), now: model.now, onOpenURL: onOpenURL)
                }
                .padding(16)
            }

            Divider()

            FooterView(
                connectionState: model.connectionState,
                onSignOut: onSignOut,
                onManageApps: openAppSettings
            )
        }
    }

    private func openAppSettings() {
        editorID = UUID()
        screen = .appSettings
    }

    private func openGoogleSetup() {
        screen = .googleSetup
    }

    private func recoverFromError(_ recovery: ErrorRecoveryAction) {
        switch recovery {
        case .googleSetup:
            openGoogleSetup()
        case .gmailPermission:
            onEnableGmailBadge()
        }
    }
}

struct HeaderView: View {
    let connectionState: ConnectionState
    let isBusy: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppImages.headerIcon())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)

            Text("GWS Menu")
                .font(.system(size: 13, weight: .semibold))

            Text(connectionState.accountLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            }

            IconButton(symbolName: "arrow.clockwise", title: "Refresh", action: onRefresh)
                .disabled(!connectionState.isConnected || isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

struct PrimaryCalendarCard: View {
    let connectionState: ConnectionState
    let isBusy: Bool
    let onSignIn: () -> Void
    let onShowSetup: () -> Void

    var body: some View {
        switch connectionState {
        case .loading:
            StatusCard(symbolName: "hourglass", title: "Loading Calendar", message: "Checking saved Google sign-in.", actionTitle: nil, action: nil)
        case .missingBundleConfig:
            AuthStatusCard(
                symbolName: "wrench.and.screwdriver",
                title: "Google setup needed",
                message: "Open Setup, copy this app's Bundle ID into Google Cloud, then paste the Client ID back here.",
                primaryTitle: "Open Setup",
                primarySystemImage: "slider.horizontal.3",
                primaryAction: onShowSetup,
                isPrimaryDisabled: false,
                secondaryTitle: nil,
                secondarySystemImage: nil,
                secondaryAction: nil,
                footnote: "No client secret is used or stored."
            )
        case .signedOut:
            AuthStatusCard(
                symbolName: "person.crop.circle.badge.plus",
                title: "Connect Google Calendar",
                message: isBusy ? "Waiting for Google sign-in to finish." : "Sign in to read your primary calendar. You can repair setup if Google rejects the client.",
                primaryTitle: isBusy ? "Signing in" : "Sign in",
                primarySystemImage: "person.crop.circle.badge.plus",
                primaryAction: onSignIn,
                isPrimaryDisabled: isBusy,
                secondaryTitle: "Setup",
                secondarySystemImage: "gearshape",
                secondaryAction: onShowSetup,
                footnote: "Read-only calendar access."
            )
        case .connected:
            StatusCard(symbolName: "checkmark.circle", title: "No Upcoming Meetings", message: isBusy ? "Refreshing your calendar." : "Your calendar is clear for the next 7 days.", actionTitle: nil, action: nil)
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
    let secondaryTitle: String?
    let secondarySystemImage: String?
    let secondaryAction: (() -> Void)?
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

                if let secondaryTitle, let secondarySystemImage, let secondaryAction {
                    Button {
                        secondaryAction()
                    } label: {
                        Label(secondaryTitle, systemImage: secondarySystemImage)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let footnote {
                    Text(footnote)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AlertLeadSettingRow: View {
    @Binding var selectedMinutes: Int
    private let options = AlertSettings.allowedLeadMinutes

    var body: some View {
        HStack(spacing: 10) {
            Label("Meeting alert", systemImage: "bell")
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
                    Text("\(selectedMinutes)m before")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func optionTitle(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute before" : "\(minutes) minutes before"
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct UpcomingEventsView: View {
    let events: [MeetingEvent]
    let now: Date
    let onOpenURL: (URL) -> Void

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Upcoming")
                VStack(spacing: 8) {
                    ForEach(events, id: \.id) { event in
                        EventRow(event: event, now: now, onOpenURL: onOpenURL)
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: MeetingEvent
    let now: Date
    let onOpenURL: (URL) -> Void
    @State private var isShowingParticipants = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(event.startTimeText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                Text(event.dayText(relativeTo: now))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, height: 44)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .help(event.title)

                    if let participantSummary = event.participantSummary {
                        Button {
                            isShowingParticipants.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Text(participantSummary)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(event.participantToolTip)
                        .popover(
                            isPresented: $isShowingParticipants,
                            attachmentAnchor: .point(.top),
                            arrowEdge: .bottom
                        ) {
                            ParticipantPopover(event: event)
                        }
                    }
                }
                Text(event.detailLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(event.detailLine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let meetingURL = event.meetingURL {
                    IconButton(symbolName: "video.fill", title: "Join", action: { onOpenURL(meetingURL) })
                }

                if let htmlLink = event.htmlLink {
                    IconButton(symbolName: "info.circle", title: "Details", action: { onOpenURL(htmlLink) })
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ParticipantPopover: View {
    let event: MeetingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Participants")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(event.participantSummary ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ParticipantList(participants: event.participants)
        }
        .padding(10)
        .frame(width: 260)
    }
}

struct ParticipantList: View {
    let participants: [MeetingParticipant]

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
                        .help(participant.helpText)

                    Spacer(minLength: 6)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct WorkspaceGrid: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    let apps: [WorkspaceApp]
    let gmailUnreadCount: Int?
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Workspace")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(apps) { app in
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
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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

struct GoogleSetupView: View {
    @State private var clientID: String
    @State private var reversedClientID: String
    @State private var feedback: GoogleSetupResult?
    @State private var isNormalizingClientID = false
    let onCancel: () -> Void
    let onApply: (GoogleSetupConfig) -> GoogleSetupResult
    let onOpenURL: (URL) -> Void

    init(
        initialConfig: GoogleSetupConfig,
        onCancel: @escaping () -> Void,
        onApply: @escaping (GoogleSetupConfig) -> GoogleSetupResult,
        onOpenURL: @escaping (URL) -> Void
    ) {
        _clientID = State(initialValue: initialConfig.clientID)
        _reversedClientID = State(initialValue: initialConfig.reversedClientID)
        self.onCancel = onCancel
        self.onApply = onApply
        self.onOpenURL = onOpenURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IconButton(symbolName: "chevron.left", title: "Back", action: onCancel)
                Text("Google Setup")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                IconButton(symbolName: "questionmark.circle", title: "Open setup guide") {
                    if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
                        onOpenURL(url)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connect Google Calendar")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Follow the buttons in order. GWS Menu only needs an Apple native OAuth Client ID; it never asks for or stores a client secret.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SetupActionStep(
                            number: "1",
                            title: "Enable Calendar API",
                            text: "Open the API page, choose your Google Cloud project, then click Enable if it is not already enabled.",
                            buttonTitle: "Open API",
                            systemImage: "checkmark.shield"
                        ) {
                            openSetupURL("https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")
                        }

                        SetupActionStep(
                            number: "2",
                            title: "Gmail API for unread badge",
                            text: "Optional. Enable this only if you want an unread Inbox count on the Gmail tile.",
                            buttonTitle: "Open Gmail API",
                            systemImage: "envelope.badge"
                        ) {
                            openSetupURL("https://console.cloud.google.com/apis/library/gmail.googleapis.com")
                        }

                        SetupActionStep(
                            number: "3",
                            title: "Create Apple app credential",
                            text: "Open OAuth client creation. In Google Cloud, choose application type iOS; that is Google's Apple native app type for this macOS sign-in flow.",
                            buttonTitle: "Open OAuth Client",
                            systemImage: "key"
                        ) {
                            openSetupURL("https://console.cloud.google.com/apis/credentials/oauthclient")
                        }

                        SetupActionStep(
                            number: "4",
                            title: "Consent screen if asked",
                            text: "If Google blocks OAuth creation, open the consent screen, choose Internal for your Workspace org or Testing for personal use, then add yourself as a test user.",
                            buttonTitle: "Open Consent",
                            systemImage: "person.badge.shield.checkmark"
                        ) {
                            openSetupURL("https://console.cloud.google.com/apis/credentials/consent")
                        }
                    }

                    CopyableSetupInfoRow(
                        label: "App Bundle ID",
                        value: bundleID,
                        detail: "Paste this into Google Cloud's Bundle ID field."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client ID")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            TextField("1234567890-abc.apps.googleusercontent.com or credential JSON", text: $clientID)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: clientID) { _, newValue in
                                    if isNormalizingClientID {
                                        isNormalizingClientID = false
                                        updateURLScheme(from: newValue, replacingExisting: true)
                                        return
                                    }
                                    handleClientIDChange(newValue)
                                }
                            Button {
                                pasteClientID()
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                        }
                    }

                    CopyableSetupInfoRow(
                        label: "URL scheme",
                        value: urlSchemePreview,
                        detail: "Generated automatically from the Client ID. Save Setup writes it into this app bundle."
                    )

                    if let setupIssue {
                        SetupFeedbackView(result: .failure(setupIssue))
                    }

                    if let feedback {
                        SetupFeedbackView(result: feedback)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SetupStep(number: "5", text: "Copy the Client ID from Google Cloud, or download the credential file and paste its contents here.")
                        SetupStep(number: "6", text: "Click Save Setup. GWS Menu updates this app, registers the URL scheme, restarts, then you can click Sign in.")
                        SetupStep(number: "!", text: "If Google gives you a client secret, you created a Web application credential. Delete that and create the Apple/iOS client instead.")
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(14)
            }

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button {
                    saveSetup()
                } label: {
                    Text("Save Setup")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "io.github.gwsmenu.app"
    }

    private var urlSchemePreview: String {
        clientIDCandidate.flatMap { GoogleSetupConfig.reversedClientID(from: $0) }
            ?? reversedClientID.nilIfBlank
            ?? "Generated from Client ID"
    }

    private var urlSchemeForApply: String {
        clientIDCandidate.flatMap { GoogleSetupConfig.reversedClientID(from: $0) } ?? reversedClientID
    }

    private var clientIDCandidate: String? {
        GoogleSetupConfig.extractedClientID(from: clientID)
    }

    private var setupIssue: String? {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if GoogleSetupConfig.containsClientSecret(in: trimmed) {
            return "This looks like a Web application credential because it contains a client secret. Create an Apple/iOS OAuth client instead."
        }
        if clientIDCandidate == nil {
            return "Could not find a Google OAuth Client ID ending in .apps.googleusercontent.com."
        }
        return nil
    }

    private var canSave: Bool {
        clientIDCandidate != nil && setupIssue == nil
    }

    private func pasteClientID() {
        guard let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.isEmpty else {
            return
        }
        ingestClientIDInput(pasted, fromPasteButton: true)
    }

    private func handleClientIDChange(_ newValue: String) {
        feedback = nil
        if GoogleSetupConfig.looksLikeCredentialDocument(newValue) {
            ingestClientIDInput(newValue, fromPasteButton: false)
            return
        }
        updateURLScheme(from: newValue, replacingExisting: false)
    }

    private func ingestClientIDInput(_ input: String, fromPasteButton: Bool) {
        guard !GoogleSetupConfig.containsClientSecret(in: input) else {
            feedback = .failure("This looks like a Web application credential. GWS Menu ignored the client secret. Create an Apple/iOS OAuth client and paste that Client ID.")
            if !fromPasteButton {
                replaceClientID("")
            }
            return
        }
        guard let extracted = GoogleSetupConfig.extractedClientID(from: input) else {
            feedback = .failure(fromPasteButton ? "Could not find a Google OAuth Client ID in the clipboard." : "Could not find a Google OAuth Client ID in that credential text.")
            return
        }
        replaceClientID(extracted)
        updateURLScheme(from: extracted, replacingExisting: true)
        if fromPasteButton || input != extracted {
            feedback = .success("Client ID extracted. Review the URL scheme, then save setup.")
        }
    }

    private func replaceClientID(_ value: String) {
        if clientID != value {
            isNormalizingClientID = true
            clientID = value
        } else {
            updateURLScheme(from: value, replacingExisting: true)
        }
    }

    private func saveSetup() {
        guard let clientIDCandidate else {
            feedback = .failure("Paste a Google OAuth Client ID first.")
            return
        }
        feedback = onApply(GoogleSetupConfig(clientID: clientIDCandidate, reversedClientID: urlSchemeForApply))
    }

    private func openSetupURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            onOpenURL(url)
        }
    }

    private func updateURLScheme(from clientID: String, replacingExisting: Bool) {
        guard replacingExisting || reversedClientID.nilIfBlank == nil || GoogleSetupConfig.reversedClientID(from: reversedClientID) == nil,
              let generated = GoogleSetupConfig.reversedClientID(from: clientID) else {
            return
        }
        reversedClientID = generated
    }
}

struct SetupInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CopyableSetupInfoRow: View {
    let label: String
    let value: String
    let detail: String?
    @State private var didCopy = false

    init(label: String, value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                didCopy = true
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Copy \(label)")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: value) { _, _ in
            didCopy = false
        }
    }
}

struct SetupActionStep: View {
    let number: String
    let title: String
    let text: String
    let buttonTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Label(buttonTitle, systemImage: systemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(buttonTitle)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SetupStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SetupFeedbackView: View {
    let result: GoogleSetupResult

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.isSuccess ? .green : .orange)
            Text(result.message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background((result.isSuccess ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkspaceAppsEditor: View {
    @State private var draftApps: [WorkspaceApp]
    @State private var draftAlertLeadMinutes: Int
    @State private var draftCalendarNotificationsEnabled: Bool
    @State private var draftMailBadgeEnabled: Bool
    @State private var draggingAppID: String?
    @State private var lastAutoScrollAt = Date.distantPast
    @State private var showsResetGoogleSetupConfirmation = false
    let onCancel: () -> Void
    let onResetGoogleSetup: () -> Void
    let onApply: ([WorkspaceApp], Int, Bool, Bool) -> Void

    init(
        initialApps: [WorkspaceApp],
        initialAlertLeadMinutes: Int,
        initialCalendarNotificationsEnabled: Bool,
        initialMailBadgeEnabled: Bool,
        onCancel: @escaping () -> Void,
        onResetGoogleSetup: @escaping () -> Void,
        onApply: @escaping ([WorkspaceApp], Int, Bool, Bool) -> Void
    ) {
        _draftApps = State(initialValue: initialApps)
        _draftAlertLeadMinutes = State(initialValue: initialAlertLeadMinutes)
        _draftCalendarNotificationsEnabled = State(initialValue: initialCalendarNotificationsEnabled)
        _draftMailBadgeEnabled = State(initialValue: initialMailBadgeEnabled)
        self.onCancel = onCancel
        self.onResetGoogleSetup = onResetGoogleSetup
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IconButton(symbolName: "chevron.left", title: "Back", action: onCancel)

                Text("Settings")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                IconButton(
                    symbolName: "key.slash",
                    title: "Reset Google setup",
                    action: { showsResetGoogleSetupConfirmation = true }
                )
                IconButton(symbolName: "plus", title: "Add app", action: addCustomApp)
                IconButton(symbolName: "arrow.counterclockwise", title: "Reset apps", action: resetDefaults)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Calendar")
                            NotificationToggleRow(
                                title: "Desktop alerts",
                                subtitle: "Use macOS notifications for meeting reminders.",
                                systemImage: "bell.badge",
                                isOn: $draftCalendarNotificationsEnabled
                            )
                            AlertLeadSettingRow(selectedMinutes: $draftAlertLeadMinutes)

                            SectionTitle("Mail")
                            NotificationToggleRow(
                                title: "Inbox unread badge",
                                subtitle: "Shows unread count on Gmail. No desktop mail alerts.",
                                systemImage: "envelope.badge",
                                isOn: $draftMailBadgeEnabled
                            )

                            SectionTitle("Workspace Apps")

                            ForEach(draftApps) { listedApp in
                                if let index = draftApps.firstIndex(where: { $0.id == listedApp.id }) {
                                    WorkspaceAppEditorRow(
                                        app: appBinding(index),
                                        isDragging: draggingAppID == listedApp.id,
                                        canMoveUp: index > 0,
                                        canMoveDown: index < draftApps.count - 1,
                                        canDelete: !draftApps[index].isBuiltIn,
                                        onMoveUp: { move(index: index, offset: -1) },
                                        onMoveDown: { move(index: index, offset: 1) },
                                        onMoveToTop: { moveToTop(index: index) },
                                        onMoveToBottom: { moveToBottom(index: index) },
                                        onDelete: { delete(index: index) },
                                        onDrag: {
                                            draggingAppID = listedApp.id
                                            return NSItemProvider(object: listedApp.id as NSString)
                                        }
                                    )
                                    .id(listedApp.id)
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: WorkspaceAppReorderDropDelegate(
                                            targetID: listedApp.id,
                                            apps: $draftApps,
                                            draggingID: $draggingAppID
                                        )
                                    )
                                }
                            }
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

            Divider()

            VStack(spacing: 8) {
                HStack {
                    Text(WorkspaceAppStore.configURL.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }

                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()

                    Text("\(draftApps.filter(\.isEnabled).count) visible")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        onApply(draftApps, draftAlertLeadMinutes, draftCalendarNotificationsEnabled, draftMailBadgeEnabled)
                    } label: {
                        Text("Apply")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .confirmationDialog(
            "Reset Google setup?",
            isPresented: $showsResetGoogleSetupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Google Setup", role: .destructive, action: onResetGoogleSetup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs out, revokes the saved Google grant if possible, removes the Client ID and URL scheme from this app, then restarts GWS Menu. You will need Open Setup again.")
        }
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
        draftApps.append(WorkspaceApp.custom())
    }

    private func resetDefaults() {
        draftApps = WorkspaceApp.defaultApps
    }

    private func move(index: Int, offset: Int) {
        let target = index + offset
        guard draftApps.indices.contains(index),
              draftApps.indices.contains(target) else {
            return
        }
        draftApps.swapAt(index, target)
    }

    private func moveToTop(index: Int) {
        guard draftApps.indices.contains(index), index > 0 else {
            return
        }
        let app = draftApps.remove(at: index)
        draftApps.insert(app, at: 0)
    }

    private func moveToBottom(index: Int) {
        guard draftApps.indices.contains(index), index < draftApps.count - 1 else {
            return
        }
        let app = draftApps.remove(at: index)
        draftApps.append(app)
    }

    private func delete(index: Int) {
        guard draftApps.indices.contains(index),
              !draftApps[index].isBuiltIn else {
            return
        }
        draftApps.remove(at: index)
    }
}

struct WorkspaceAppEditorRow: View {
    @Binding var app: WorkspaceApp
    let isDragging: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToTop: () -> Void
    let onMoveToBottom: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 32)
                    .contentShape(Rectangle())
                    .onDrag(onDrag)
                    .help("Drag to reorder")

                Toggle("", isOn: binding(\.isEnabled))
                    .labelsHidden()

                WorkspaceProductIcon(app: app)
                    .frame(width: 24, height: 24)
                    .frame(width: 32, height: 32)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                TextField("Name", text: binding(\.title))
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 2) {
                    Menu {
                        Button(action: onMoveToTop) {
                            Label("Move to Top", systemImage: "arrow.up.to.line")
                        }
                        .disabled(!canMoveUp)

                        Button(action: onMoveUp) {
                            Label("Move Up", systemImage: "chevron.up")
                        }
                        .disabled(!canMoveUp)

                        Button(action: onMoveDown) {
                            Label("Move Down", systemImage: "chevron.down")
                        }
                        .disabled(!canMoveDown)

                        Button(action: onMoveToBottom) {
                            Label("Move to Bottom", systemImage: "arrow.down.to.line")
                        }
                        .disabled(!canMoveDown)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .help("Move")

                    IconButton(symbolName: "trash", title: "Delete custom app", action: onDelete)
                        .disabled(!canDelete)
                }
                .frame(width: 60)
            }

            TextField("URL", text: binding(\.urlString))
                .textFieldStyle(.roundedBorder)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(isDragging ? 0.62 : 1), in: RoundedRectangle(cornerRadius: 8))
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

struct FooterView: View {
    let connectionState: ConnectionState
    let onSignOut: () -> Void
    let onManageApps: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onManageApps) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)

            Spacer()

            if connectionState.isConnected {
                Button("Sign Out", action: onSignOut)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ErrorBanner: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
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
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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
        let bundleName = "GWSMenuBar_GWSMenuBar.bundle"
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
        return base.appendingPathComponent("GWS Menu", isDirectory: true).appendingPathComponent("workspace-apps.json")
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

enum MailBadgeSettings {
    private static let enabledKey = "mailUnreadBadgeEnabled"
    private static let legacyEnabledKey = "mailNotificationsEnabled"

    static func loadEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: enabledKey) != nil {
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        return UserDefaults.standard.bool(forKey: legacyEnabledKey)
    }

    static func saveEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: legacyEnabledKey)
    }
}

enum NotificationNamespaces {
    static let calendar = "gws.calendar."
}

enum ConnectionState {
    case loading
    case missingBundleConfig
    case signedOut
    case connected(email: String?)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var menuTitle: String {
        switch self {
        case .loading:
            return "Google Calendar: Loading"
        case .missingBundleConfig:
            return "Google Calendar: Bundle config missing"
        case .signedOut:
            return "Google Calendar: Not signed in"
        case .connected(let email):
            return "Google Calendar: \(email ?? "Connected")"
        }
    }

    var accountLine: String {
        switch self {
        case .loading:
            return "Loading Calendar"
        case .missingBundleConfig:
            return "Setup required"
        case .signedOut:
            return "Not signed in"
        case .connected(let email):
            return email ?? "Connected"
        }
    }
}

@MainActor
final class GoogleSignInAuthClient {
    private let authWindow: AuthWindow
    private let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
    private let gmailLabelsScope = "https://www.googleapis.com/auth/gmail.labels"
    private let signIn: GIDSignIn

    init(authWindow: AuthWindow) {
        self.authWindow = authWindow
        self.signIn = GoogleSignInFactory.makeSignIn()
    }

    func connectionState() -> ConnectionState {
        configureIfPossible()
        guard GoogleSetupConfig.current.isComplete else {
            return .missingBundleConfig
        }
        guard let user = signIn.currentUser else {
            return .signedOut
        }
        return .connected(email: user.profile?.email)
    }

    func configure(clientID: String) {
        signIn.configuration = GIDConfiguration(clientID: clientID)
    }

    func handle(url: URL) -> Bool {
        signIn.handle(url)
    }

    func restorePreviousSignIn() async throws {
        configureIfPossible()
        guard GoogleSetupConfig.current.isComplete else {
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

    func signIn(includeGmailLabels: Bool = false) async throws {
        configureIfPossible()
        guard GoogleSetupConfig.current.isComplete else {
            throw AppError.missingBundleConfig
        }
        let window = authWindow.present(message: "Sign in with Google to connect Calendar.")
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
        if includeGmailLabels, !hasGmailLabelsScope(result.user) {
            throw AppError.gmailScopeNotGranted
        }
    }

    func calendarAccessToken() async throws -> String {
        let user = try await refreshedCurrentUser()
        if !hasCalendarScope(user) {
            throw AppError.calendarScopeNotGranted
        }
        return user.accessToken.tokenString
    }

    func gmailLabelsAccessToken() async throws -> String {
        let user = try await refreshedCurrentUser()
        if !hasGmailLabelsScope(user) {
            throw AppError.gmailScopeNotGranted
        }
        return user.accessToken.tokenString
    }

    func ensureGmailLabelsScope() async throws {
        configureIfPossible()
        guard GoogleSetupConfig.current.isComplete else {
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
        let result = try await signIn.signIn(
            withPresenting: window,
            hint: user.profile?.email,
            additionalScopes: [calendarScope, gmailLabelsScope]
        )
        if !hasGmailLabelsScope(result.user) {
            throw AppError.gmailScopeNotGranted
        }
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
        user.grantedScopes?.contains(calendarScope) == true
    }

    private func hasGmailLabelsScope(_ user: GIDGoogleUser) -> Bool {
        user.grantedScopes?.contains(gmailLabelsScope) == true
    }

    func signOut() {
        signIn.signOut()
    }

    func clearSavedUserGrant() async {
        configureIfPossible()
        guard signIn.currentUser != nil else {
            signIn.signOut()
            return
        }
        do {
            try await disconnect()
        } catch {
            signIn.signOut()
        }
    }

    func disconnect() async throws {
        configureIfPossible()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            signIn.disconnect { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        signIn.signOut()
    }

    private func configureIfPossible() {
        guard signIn.configuration == nil,
              let clientID = GoogleSetupConfig.current.clientID.nilIfBlank else {
            return
        }
        configure(clientID: clientID)
    }
}

enum GoogleSignInFactory {
    @MainActor
    static func makeSignIn() -> GIDSignIn {
        #if os(macOS)
        if let local = makeMacFileKeychainSignIn() {
            return local
        }
        #endif
        return GIDSignIn.sharedInstance
    }

    @MainActor
    private static func makeMacFileKeychainSignIn() -> GIDSignIn? {
        let store = KeychainStore(itemName: "auth", keychainAttributes: [KeychainAttribute.useFileBasedKeychain])
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
}

@MainActor
final class AuthWindow {
    private let label = NSTextField(labelWithString: "")

    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GWS Menu"
        window.center()
        window.isReleasedWhenClosed = false

        label.alignment = .center
        label.frame = NSRect(x: 24, y: 78, width: 372, height: 24)
        window.contentView?.addSubview(label)
        return window
    }()

    func present(message: String) -> NSWindow {
        label.stringValue = message
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    func hide() {
        window.orderOut(nil)
    }
}

@MainActor
final class GoogleCalendarService {
    private let authClient: GoogleSignInAuthClient
    private let iso = ISO8601DateFormatter()

    init(authClient: GoogleSignInAuthClient) {
        self.authClient = authClient
        iso.formatOptions = [.withInternetDateTime]
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
            URLQueryItem(name: "timeMin", value: iso.string(from: start)),
            URLQueryItem(name: "timeMax", value: iso.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "timeZone", value: TimeZone.autoupdatingCurrent.identifier),
            URLQueryItem(name: "maxResults", value: "100")
        ]

        let response: GoogleEventsResponse = try await get(components.url!, token: token)
        return response.items
            .filter(\.belongsOnMyCalendar)
            .compactMap { MeetingEvent(event: $0, calendarName: nil) }
    }

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.api(body)
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.api(body)
        }

        let decoded = try JSONDecoder().decode(GmailLabelResponse.self, from: data)
        return decoded.messagesUnread ?? 0
    }
}

struct GmailLabelResponse: Decodable {
    let messagesUnread: Int?
}

struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendar]
}

struct GoogleCalendar: Decodable {
    let id: String
    let summary: String
    let hidden: Bool?
    let accessRole: String?
}

struct GoogleEventsResponse: Decodable {
    let items: [GoogleEvent]
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
        CalendarPersonLabel.displayName(displayName, email: email, isSelf: selfPerson == true)
    }
}

struct MeetingParticipant: Identifiable {
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

    var responseText: String? {
        switch responseStatus {
        case "accepted":
            return "Accepted"
        case "tentative":
            return "Tentative"
        case "declined":
            return "Declined"
        case "needsAction":
            return "No response"
        default:
            return nil
        }
    }

    var trailingText: String? {
        role?.nilIfBlank
    }

    var helpText: String {
        [label, email, role?.nilIfBlank, responseText]
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
        return CalendarPersonLabel.displayName(displayName, email: email, isSelf: selfAttendee == true)
    }
}

enum CalendarPersonLabel {
    static func displayName(_ displayName: String?, email: String?, isSelf: Bool) -> String? {
        if isSelf {
            return "You"
        }

        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           !name.contains("@") {
            return name
        }

        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        return email.split(separator: "@").first.map(String.init) ?? email
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
        if attendees?.first(where: { $0.selfAttendee == true })?.responseStatus == "declined" {
            return false
        }
        return true
    }
}

struct GoogleEventDate: Decodable {
    let dateTime: String?
    let date: String?
}

struct MeetingEvent {
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

    init?(event: GoogleEvent, calendarName: String?) {
        let fractionalParser = ISO8601DateFormatter()
        fractionalParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]

        func parseDateTime(_ value: String?) -> Date? {
            guard let value else { return nil }
            if let parsed = fractionalParser.date(from: value) {
                return parsed
            }
            return parser.date(from: value)
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
        self.organizerName = event.organizer?.label ?? event.creator?.label
        self.guestCount = MeetingEvent.guestCount(from: event)
        self.participants = MeetingEvent.participants(from: event)
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

    var timeText: String {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: start, to: end)
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

    func dayText(relativeTo now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        if calendar.isDate(start, inSameDayAs: now) {
            return "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(start, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }

        let weekday = weekdayText(for: start)
        if isNextWeek(start, relativeTo: now, calendar: calendar) {
            return "Next \(weekday)"
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

    private func weekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var startTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: start)
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

    var participantToolTip: String {
        let host = organizerName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map { "Host: \($0)" }
        let guests = guestCount == 1 ? "1 guest" : "\(guestCount) guests"
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

struct GoogleSetupConfig: Equatable {
    var clientID: String
    var reversedClientID: String

    var isComplete: Bool {
        clientID.nilIfBlank != nil && resolvedReversedClientID != nil
    }

    var resolvedReversedClientID: String? {
        reversedClientID.nilIfBlank ?? Self.reversedClientID(from: clientID)
    }

    static var current: GoogleSetupConfig {
        GoogleSetupConfig(
            clientID: Bundle.main.googleClientID ?? "",
            reversedClientID: Bundle.main.googleReversedClientID ?? ""
        )
    }

    static func normalized(clientID: String, reversedClientID: String) throws -> GoogleSetupConfig {
        if containsClientSecret(in: clientID) {
            throw GoogleSetupError.webClientCredential
        }

        let normalizedClientID = extractedClientID(from: clientID) ?? clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidClientID(normalizedClientID) else {
            throw GoogleSetupError.invalidClientID
        }

        let normalizedReversedClientID = reversedClientID.nilIfBlank ?? Self.reversedClientID(from: normalizedClientID) ?? ""
        guard normalizedReversedClientID.hasPrefix("com.googleusercontent.apps."),
              !normalizedReversedClientID.contains("YOUR_GOOGLE_CLIENT_ID") else {
            throw GoogleSetupError.invalidURLScheme
        }

        return GoogleSetupConfig(clientID: normalizedClientID, reversedClientID: normalizedReversedClientID)
    }

    static func reversedClientID(from clientID: String) -> String? {
        guard let normalized = extractedClientID(from: clientID) else {
            return nil
        }
        let suffix = ".apps.googleusercontent.com"
        return "com.googleusercontent.apps." + normalized.dropLast(suffix.count)
    }

    static func containsClientSecret(in input: String) -> Bool {
        input.range(of: "client_secret", options: .caseInsensitive) != nil ||
            input.range(of: "client secret", options: .caseInsensitive) != nil
    }

    static func looksLikeCredentialDocument(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") ||
            trimmed.hasPrefix("<") ||
            input.range(of: "client_id", options: .caseInsensitive) != nil ||
            input.range(of: "CLIENT_ID") != nil ||
            input.range(of: "GIDClientID") != nil ||
            containsClientSecret(in: input)
    }

    static func extractedClientID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isValidClientID(trimmed) {
            return trimmed
        }

        if let data = trimmed.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data),
               let value = firstClientIDValue(in: json) {
                return value
            }
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let value = firstClientIDValue(in: plist) {
                return value
            }
        }

        return firstClientIDMatch(in: trimmed)
    }

    private static func firstClientIDValue(in object: Any) -> String? {
        if let string = object as? String, isValidClientID(string) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let dictionary = object as? [String: Any] {
            for key in ["client_id", "CLIENT_ID", "GIDClientID"] {
                if let value = dictionary[key] as? String, isValidClientID(value) {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            for value in dictionary.values {
                if let found = firstClientIDValue(in: value) {
                    return found
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let found = firstClientIDValue(in: value) {
                    return found
                }
            }
        }

        return nil
    }

    private static func firstClientIDMatch(in text: String) -> String? {
        let pattern = #"[A-Za-z0-9_-]+\.apps\.googleusercontent\.com"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        let value = String(text[matchRange])
        return isValidClientID(value) ? value : nil
    }

    private static func isValidClientID(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasSuffix(".apps.googleusercontent.com") &&
            !normalized.contains("YOUR_GOOGLE_CLIENT_ID")
    }
}

struct GoogleSetupResult {
    let isSuccess: Bool
    let message: String

    static func success(_ message: String) -> GoogleSetupResult {
        GoogleSetupResult(isSuccess: true, message: message)
    }

    static func failure(_ message: String) -> GoogleSetupResult {
        GoogleSetupResult(isSuccess: false, message: message)
    }
}

enum GoogleSetupError: LocalizedError {
    case invalidClientID
    case invalidURLScheme
    case cannotReadInfoPlist
    case cannotUpdateAppSignature(String)
    case webClientCredential

    var errorDescription: String? {
        switch self {
        case .invalidClientID:
            return "Paste a Google OAuth client ID ending in .apps.googleusercontent.com."
        case .invalidURLScheme:
            return "Paste the reversed client ID URL scheme that starts with com.googleusercontent.apps."
        case .cannotReadInfoPlist:
            return "Could not read this app's Info.plist. Rebuild with the Google client values instead."
        case .cannotUpdateAppSignature(let details):
            return "Setup was saved, but macOS rejected the updated app signature. Reinstall GWS Menu from the README and try again. \(details)"
        case .webClientCredential:
            return "This looks like a Web application credential because it contains a client secret. Create an Apple/iOS OAuth client instead."
        }
    }
}

enum GoogleAppBundleSetup {
    static func apply(config: GoogleSetupConfig) throws {
        let infoURL = infoPlistURL()
        var plist = try readInfoPlist(from: infoURL)

        plist["GIDClientID"] = config.clientID
        plist["CFBundleURLTypes"] = [
            [
                "CFBundleURLSchemes": [config.reversedClientID]
            ]
        ]

        try writeInfoPlistAndUpdateSignature(plist, to: infoURL)
        registerCurrentApp()
    }

    static func reset() throws {
        let infoURL = infoPlistURL()
        var plist = try readInfoPlist(from: infoURL)

        plist.removeValue(forKey: "GIDClientID")
        plist.removeValue(forKey: "GIDServerClientID")

        if let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] {
            let filteredURLTypes = urlTypes.compactMap { urlType -> [String: Any]? in
                guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else {
                    return urlType
                }
                let remainingSchemes = schemes.filter { !$0.hasPrefix("com.googleusercontent.apps.") }
                guard !remainingSchemes.isEmpty else {
                    return nil
                }
                var updated = urlType
                updated["CFBundleURLSchemes"] = remainingSchemes
                return updated
            }

            if filteredURLTypes.isEmpty {
                plist.removeValue(forKey: "CFBundleURLTypes")
            } else {
                plist["CFBundleURLTypes"] = filteredURLTypes
            }
        }

        try writeInfoPlistAndUpdateSignature(plist, to: infoURL)
        registerCurrentApp()
    }

    private static func infoPlistURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
    }

    private static func readInfoPlist(from infoURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: infoURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw GoogleSetupError.cannotReadInfoPlist
        }
        return plist
    }

    private static func writeInfoPlist(_ plist: [String: Any], to infoURL: URL) throws {
        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: infoURL, options: .atomic)
    }

    private static func writeInfoPlistAndUpdateSignature(_ plist: [String: Any], to infoURL: URL) throws {
        let previousData = try? Data(contentsOf: infoURL)

        try writeInfoPlist(plist, to: infoURL)

        do {
            try updateCurrentAppSignature()
        } catch {
            if let previousData {
                try? previousData.write(to: infoURL, options: .atomic)
            }
            throw error
        }
    }

    private static func updateCurrentAppSignature() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = [
            "--force",
            "--sign",
            "-",
            Bundle.main.bundleURL.path
        ]

        let errorPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            throw GoogleSetupError.cannotUpdateAppSignature(error.localizedDescription)
        }

        guard task.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank ?? "codesign exited with status \(task.terminationStatus)."
            throw GoogleSetupError.cannotUpdateAppSignature(details)
        }
    }

    private static func registerCurrentApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \(Bundle.main.bundleURL.path.shellQuoted)"
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        if (try? task.run()) != nil {
            task.waitUntilExit()
        }
    }
}

enum AppError: LocalizedError {
    case missingBundleConfig
    case invalidResponse
    case notSignedIn
    case calendarScopeNotGranted
    case gmailScopeNotGranted
    case notificationPermissionDenied
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

    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
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
