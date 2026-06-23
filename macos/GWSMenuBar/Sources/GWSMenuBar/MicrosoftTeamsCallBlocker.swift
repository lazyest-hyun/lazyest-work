@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation
import IOKit.hid

@MainActor
private final class TeamsCallConfirmationController: NSObject {
    private let panel: NSPanel
    private var confirmed = false

    override init() {
        let text = AppText(language: AppLanguageSettings.load())
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 196),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        panel.isReleasedWhenClosed = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "phone.arrow.up.right", accessibilityDescription: nil) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        icon.contentTintColor = .systemOrange

        let title = NSTextField(labelWithString: text.callConfirmTitle)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail

        let message = NSTextField(labelWithString: text.callConfirmMessage)
        message.translatesAutoresizingMaskIntoConstraints = false
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 3
        message.lineBreakMode = .byWordWrapping

        let textStack = NSStackView(views: [title, message])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8

        let headerStack = NSStackView(views: [icon, textStack])
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.alignment = .top
        headerStack.spacing = 14

        let cancelButton = NSButton(title: text.cancel, target: self, action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let confirmButton = NSButton(title: text.callConfirmAction, target: self, action: #selector(confirm))
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        confirmButton.contentTintColor = .systemBlue

        let buttonStack = NSStackView(views: [cancelButton, confirmButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 10
        buttonStack.distribution = .fillEqually

        container.addSubview(headerStack)
        container.addSubview(buttonStack)
        panel.contentView = container

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),
            cancelButton.widthAnchor.constraint(equalToConstant: 96),
            confirmButton.widthAnchor.constraint(equalToConstant: 112)
        ])
    }

    func run() -> Bool {
        panel.center()
        NSApplication.shared.runModal(for: panel)
        panel.close()
        return confirmed
    }

    @objc private func confirm() {
        confirmed = true
        NSApplication.shared.stopModal()
    }

    @objc private func cancel() {
        confirmed = false
        NSApplication.shared.stopModal()
    }
}

enum TeamsCallBlockSettings {
    private static let enabledKey = "teamsCallBlockEnabled"
    private static let pendingEnableKey = "teamsCallBlockPendingEnableAfterPermission"
    private static let statusKey = "teamsCallBlockStatusText"

    static func loadEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func saveEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
    }

    static func loadPendingEnableAfterPermission() -> Bool {
        UserDefaults.standard.bool(forKey: pendingEnableKey)
    }

    static func savePendingEnableAfterPermission(_ isPending: Bool) {
        UserDefaults.standard.set(isPending, forKey: pendingEnableKey)
    }

    static func loadStatusText() -> String? {
        UserDefaults.standard.string(forKey: statusKey)
    }

    static func saveStatusText(_ statusText: String) {
        UserDefaults.standard.set(statusText, forKey: statusKey)
    }
}

enum TeamsCallBlockPermissionState: Equatable {
    case ready
    case missingAccessibility
    case missingInputMonitoring
    case missingAccessibilityAndInputMonitoring

    var isReady: Bool {
        self == .ready
    }

    var hasAccessibility: Bool {
        switch self {
        case .ready, .missingInputMonitoring:
            return true
        case .missingAccessibility, .missingAccessibilityAndInputMonitoring:
            return false
        }
    }

    var hasInputMonitoring: Bool {
        switch self {
        case .ready, .missingAccessibility:
            return true
        case .missingInputMonitoring, .missingAccessibilityAndInputMonitoring:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .ready:
            return "Off. Turn on to confirm Teams calls and block Teams Control-scroll."
        case .missingAccessibility:
            return "Off. Accessibility permission is needed before Teams calls can be blocked."
        case .missingInputMonitoring:
            return "Off. Input Monitoring permission is needed before Teams events can be watched."
        case .missingAccessibilityAndInputMonitoring:
            return "Off. Accessibility permission is needed before Teams calls can be blocked."
        }
    }

    var runningStatusText: String {
        "On. Teams calls require confirmation; Control-scroll is blocked in Teams."
    }

    var eventMonitoringUnavailableText: String {
        switch self {
        case .missingAccessibility, .missingAccessibilityAndInputMonitoring:
            return "Off. Accessibility permission is not detected for GWS Menu."
        case .missingInputMonitoring:
            return "Off. Input Monitoring is not detected for GWS Menu."
        case .ready:
            return "Off. macOS did not allow event monitoring. Quit and reopen GWS Menu."
        }
    }

    var pendingEnableStatusText: String {
        switch self {
        case .missingAccessibility, .missingAccessibilityAndInputMonitoring:
            return "Waiting for Accessibility permission. Enable GWS Menu in System Settings."
        case .missingInputMonitoring:
            return "Waiting for Input Monitoring permission. Enable GWS Menu in System Settings."
        case .ready:
            return "Waiting for macOS event monitoring. GWS Menu will turn on Teams call block automatically."
        }
    }

    static func current() -> TeamsCallBlockPermissionState {
        let accessibilityGranted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
        let hidInputGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let eventInputGranted: Bool
        if #available(macOS 10.15, *) {
            eventInputGranted = CGPreflightListenEventAccess()
        } else {
            eventInputGranted = true
        }
        let inputMonitoringGranted = hidInputGranted || eventInputGranted

        switch (accessibilityGranted, inputMonitoringGranted) {
        case (true, true):
            return .ready
        case (false, false):
            return .missingAccessibilityAndInputMonitoring
        case (false, true):
            return .missingAccessibility
        case (true, false):
            return .missingInputMonitoring
        }
    }
}

final class MicrosoftTeamsCallBlocker: ObservableObject, @unchecked Sendable {
    @Published private(set) var isEnabled = false
    @Published private(set) var permissionState = TeamsCallBlockPermissionState.current()
    @Published private(set) var isPendingEnableAfterPermission = TeamsCallBlockSettings.loadPendingEnableAfterPermission()
    @Published private(set) var statusText = TeamsCallBlockSettings.loadStatusText()
        ?? TeamsCallBlockPermissionState.current().statusText

    private let teamsBundleIdentifiers: Set<String> = [
        "com.microsoft.teams2",
        "com.microsoft.teams"
    ]
    private let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    private let callActionRoles: Set<String> = [
        kAXButtonRole as String,
        kAXMenuItemRole as String
    ]

    private let blockedCallActionPhrases: [String] = [
        "지금 모임 시작",
        "모임 시작",
        "오디오 통화",
        "영상 통화",
        "화상 통화",
        "비디오 통화",
        "음성 통화",
        "통화 시작",
        "전화 걸기",
        "영상 전화",
        "화상 전화",
        "Meet now",
        "Start meeting",
        "Start a meeting",
        "Audio call",
        "Video call",
        "Start call",
        "Make a call"
    ]

    private let exactBlockedCallActionLabels: Set<String> = [
        "전화",
        "Call"
    ]

    private let allowCooldown: TimeInterval = 0.7
    private var passThroughUntil = Date.distantPast
    private var swallowMouseUpUntil = Date.distantPast
    private var swallowAllUntil = Date.distantPast
    private var isShowingConfirmation = false
    private var isTeamsActive = false
    private var teamsProcessIdentifiers = Set<pid_t>()
    private var teamsWindowFrames: [CGRect] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?
    private var windowRefreshTimer: Timer?
    private var permissionRetryTimer: Timer?
    private var lastTeamsAccessibilityWarmUp = Date.distantPast

    func configure(savedEnabled: Bool) {
        permissionState = TeamsCallBlockPermissionState.current()

        guard savedEnabled || isPendingEnableAfterPermission else {
            isEnabled = false
            setStatus(permissionState.statusText)
            return
        }

        let started = startIfPossible()
        if started {
            finishEnableSuccess()
        } else {
            beginPendingEnableAfterPermission(openPermissionsIfMissing: false)
        }
    }

    @discardableResult
    func setEnabled(_ shouldEnable: Bool, openPermissionsIfMissing: Bool = false) -> Bool {
        guard shouldEnable else {
            clearPendingEnableAfterPermission()
            stop()
            isEnabled = false
            TeamsCallBlockSettings.saveEnabled(false)
            refreshPermissions()
            setStatus(permissionState.statusText)
            return false
        }

        let started = startIfPossible()
        if started {
            finishEnableSuccess()
            return true
        }

        beginPendingEnableAfterPermission(openPermissionsIfMissing: openPermissionsIfMissing)
        return false
    }

    func refreshPermissions() {
        permissionState = TeamsCallBlockPermissionState.current()
        if isPendingEnableAfterPermission, !isEnabled {
            retryPendingEnableAfterPermission()
            return
        }
        if isEnabled, eventTap != nil {
            setStatus(permissionState.runningStatusText)
        } else {
            setStatus(permissionState.statusText)
        }
    }

    func stop() {
        stopEventTap()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        windowRefreshTimer?.invalidate()
        windowRefreshTimer = nil
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        isTeamsActive = false
        teamsProcessIdentifiers.removeAll()
        teamsWindowFrames.removeAll()
        lastTeamsAccessibilityWarmUp = .distantPast
    }

    private func finishEnableSuccess() {
        isPendingEnableAfterPermission = false
        TeamsCallBlockSettings.savePendingEnableAfterPermission(false)
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        isEnabled = true
        TeamsCallBlockSettings.saveEnabled(true)
        setStatus(permissionState.runningStatusText)
    }

    private func beginPendingEnableAfterPermission(openPermissionsIfMissing: Bool) {
        isEnabled = false
        TeamsCallBlockSettings.saveEnabled(false)
        isPendingEnableAfterPermission = true
        TeamsCallBlockSettings.savePendingEnableAfterPermission(true)
        setStatus(permissionState.pendingEnableStatusText)
        startPermissionRetryTimer()

        if openPermissionsIfMissing {
            requestMissingPermission(for: permissionState)
        }
    }

    private func clearPendingEnableAfterPermission() {
        isPendingEnableAfterPermission = false
        TeamsCallBlockSettings.savePendingEnableAfterPermission(false)
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
    }

    private func startPermissionRetryTimer() {
        guard permissionRetryTimer == nil else { return }
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.retryPendingEnableAfterPermission()
        }
    }

    private func retryPendingEnableAfterPermission() {
        guard isPendingEnableAfterPermission, !isEnabled else {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
            return
        }

        permissionState = TeamsCallBlockPermissionState.current()
        if startIfPossible() {
            finishEnableSuccess()
            return
        }

        setStatus(permissionState.pendingEnableStatusText)
    }

    private func startIfPossible() -> Bool {
        permissionState = TeamsCallBlockPermissionState.current()

        if startEventTap() {
            setStatus(permissionState.runningStatusText)
            return true
        }

        stopEventTap()
        setStatus(permissionState.eventMonitoringUnavailableText)
        return false
    }

    private func requestMissingPermission(for state: TeamsCallBlockPermissionState) {
        let urlString: String
        switch state {
        case .missingAccessibility, .missingAccessibilityAndInputMonitoring:
            let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptOption: true] as CFDictionary)
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .missingInputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .ready:
            return
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func startEventTap() -> Bool {
        if eventTap != nil {
            installWorkspaceObservers()
            refreshActiveApplication()
            return true
        }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let blocker = Unmanaged<MicrosoftTeamsCallBlocker>.fromOpaque(userInfo).takeUnretainedValue()
            return blocker.handleEvent(proxy: proxy, type: type, event: event)
        }

        let tap = createEventTap(location: .cghidEventTap, mask: mask, callback: callback)
            ?? createEventTap(location: .cgSessionEventTap, mask: mask, callback: callback)

        guard let tap else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source

        installWorkspaceObservers()
        refreshActiveApplication()
        return true
    }

    private func createEventTap(
        location: CGEventTapLocation,
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack
    ) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func stopEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func installWorkspaceObservers() {
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    self?.refreshActiveApplication()
                    return
                }
                self?.isTeamsActive = self?.isTeamsApplication(app) ?? false
                self?.refreshTeamsWindows()
            }
        }

        if windowRefreshTimer == nil {
            windowRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.refreshTeamsWindows()
            }
        }
    }

    private func refreshActiveApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            isTeamsActive = false
            refreshTeamsWindows()
            return
        }
        isTeamsActive = isTeamsApplication(app)
        refreshTeamsWindows()
    }

    private func refreshTeamsWindows() {
        let teamsApps = NSWorkspace.shared.runningApplications.filter(isTeamsApplication)
        teamsProcessIdentifiers = Set(teamsApps.map(\.processIdentifier))
        warmUpTeamsAccessibilityIfNeeded()

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            teamsWindowFrames = []
            return
        }

        teamsWindowFrames = windows.compactMap { window in
            guard let ownerPid = window[kCGWindowOwnerPID as String] as? pid_t,
                  teamsProcessIdentifiers.contains(ownerPid),
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"],
                  let y = bounds["Y"],
                  let width = bounds["Width"],
                  let height = bounds["Height"],
                  width > 20,
                  height > 20 else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private func handleEvent(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        if Date() < swallowAllUntil {
            return nil
        }

        let location = event.location
        guard isTeamsEvent(at: location) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel {
            return handleScrollWheel(event)
        }

        if type == .leftMouseUp, Date() < swallowMouseUpUntil {
            return nil
        }

        guard type == .leftMouseDown else {
            return Unmanaged.passUnretained(event)
        }

        guard Date() > passThroughUntil, !isShowingConfirmation else {
            return Unmanaged.passUnretained(event)
        }

        guard isRiskyCallClick(at: location) else {
            return Unmanaged.passUnretained(event)
        }

        swallowMouseUpUntil = Date().addingTimeInterval(1.0)
        swallowAllUntil = Date().addingTimeInterval(0.8)
        setStatus("Blocked a Teams call click.")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.confirmThenClick(at: location)
        }

        return nil
    }

    private func isTeamsEvent(at location: CGPoint) -> Bool {
        if teamsWindowFrames.contains(where: { $0.contains(location) }) {
            return true
        }
        return isTeamsActive && teamsWindowFrames.isEmpty
    }

    private func handleScrollWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard controlKeyIsDown(for: event) else {
            return Unmanaged.passUnretained(event)
        }

        setStatus("Blocked Teams Control-scroll zoom.")
        return nil
    }

    private func controlKeyIsDown(for event: CGEvent) -> Bool {
        if event.flags.contains(.maskControl) {
            return true
        }

        if CGEventSource.flagsState(.hidSystemState).contains(.maskControl) {
            return true
        }

        return CGEventSource.flagsState(.combinedSessionState).contains(.maskControl)
    }

    private func isTeamsElement(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return isTeamsApplication(app)
    }

    private func isTeamsApplication(_ app: NSRunningApplication) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier,
           teamsBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if let bundleURL = app.bundleURL?.path,
           bundleURL.contains("/Microsoft Teams.app/") || bundleURL.hasSuffix("/Microsoft Teams.app") {
            return true
        }

        return app.localizedName == "Microsoft Teams"
    }

    private func accessibilityElement(at location: CGPoint) -> AXUIElement? {
        warmUpTeamsAccessibilityIfNeeded()

        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(location.x),
            Float(location.y),
            &element
        )
        guard result == .success else { return nil }
        return element
    }

    private func isRiskyCallClick(at location: CGPoint) -> Bool {
        for target in accessibilityCandidates(at: location) {
            guard isTeamsElement(target), isRiskyCallElement(target) else {
                continue
            }
            return true
        }
        return false
    }

    private func accessibilityCandidates(at location: CGPoint) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        if let hitElement = accessibilityElement(at: location) {
            candidates.append(hitElement)
        }

        candidates.append(contentsOf: scannedAccessibilityCandidates(at: location))
        return candidates
    }

    private func scannedAccessibilityCandidates(at location: CGPoint) -> [AXUIElement] {
        warmUpTeamsAccessibilityIfNeeded()

        var matches: [(element: AXUIElement, area: CGFloat)] = []
        var remainingBudget = 900

        for processIdentifier in teamsProcessIdentifiers {
            let app = AXUIElementCreateApplication(processIdentifier)
            for window in elementArrayAttribute(app, kAXWindowsAttribute).prefix(4) {
                collectInteractiveElements(
                    in: window,
                    at: location,
                    depth: 0,
                    remainingBudget: &remainingBudget,
                    matches: &matches
                )
                guard remainingBudget > 0 else { break }
            }
        }

        return matches
            .sorted { $0.area < $1.area }
            .map(\.element)
    }

    private func collectInteractiveElements(
        in element: AXUIElement,
        at location: CGPoint,
        depth: Int,
        remainingBudget: inout Int,
        matches: inout [(element: AXUIElement, area: CGFloat)]
    ) {
        guard depth <= 12, remainingBudget > 0 else { return }
        remainingBudget -= 1

        let frame = elementFrame(element)
        if let frame, !frame.insetBy(dx: -2, dy: -2).contains(location) {
            return
        }

        let role = stringAttribute(element, kAXRoleAttribute)
        if callActionRoles.contains(role), let frame, frame.contains(location) {
            matches.append((element, max(1, frame.width * frame.height)))
        }

        let children = elementArrayAttribute(element, kAXChildrenAttribute)
        for child in children.prefix(40) {
            collectInteractiveElements(
                in: child,
                at: location,
                depth: depth + 1,
                remainingBudget: &remainingBudget,
                matches: &matches
            )
            guard remainingBudget > 0 else { break }
        }
    }

    private func warmUpTeamsAccessibilityIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastTeamsAccessibilityWarmUp) > 1.0 else { return }
        lastTeamsAccessibilityWarmUp = now

        for processIdentifier in teamsProcessIdentifiers {
            warmUpTeamsAccessibility(processIdentifier: processIdentifier)
        }
    }

    private func warmUpTeamsAccessibility(processIdentifier: pid_t) {
        let app = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetAttributeValue(
            app,
            enhancedUserInterfaceAttribute as CFString,
            kCFBooleanTrue
        )

        for window in elementArrayAttribute(app, kAXWindowsAttribute).prefix(4) {
            let windowChildren = elementArrayAttribute(window, kAXChildrenAttribute)
            for child in windowChildren.prefix(6) {
                _ = elementArrayAttribute(child, kAXChildrenAttribute)
            }
        }
    }

    private func isRiskyCallElement(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<9 {
            guard let node = current else { return false }
            let role = stringAttribute(node, kAXRoleAttribute)
            let text = searchableText(for: node)

            if callActionRoles.contains(role), matchesRiskyTerm(text) {
                return true
            }

            current = elementAttribute(node, kAXParentAttribute)
        }
        return false
    }

    private func searchableText(for element: AXUIElement) -> String {
        var parts: [String] = []
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
            let value = stringAttribute(element, attr)
            if !value.isEmpty {
                parts.append(value)
            }
        }
        parts.append(childText(for: element, depth: 2))
        return parts.joined(separator: " ")
    }

    private func childText(for element: AXUIElement, depth: Int) -> String {
        guard depth > 0 else { return "" }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return ""
        }

        var parts: [String] = []
        for child in children.prefix(8) {
            for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
                let value = stringAttribute(child, attr)
                if !value.isEmpty {
                    parts.append(value)
                }
            }
            let nested = childText(for: child, depth: depth - 1)
            if !nested.isEmpty {
                parts.append(nested)
            }
        }
        return parts.joined(separator: " ")
    }

    private func matchesRiskyTerm(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if exactBlockedCallActionLabels.contains(normalized) {
            return true
        }
        return blockedCallActionPhrases.contains { term in
            normalized.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = axValueAttribute(element, kAXPositionAttribute),
              let sizeValue = axValueAttribute(element, kAXSizeAttribute) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func axValueAttribute(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }

    private func elementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    @MainActor
    private func confirmThenClick(at location: CGPoint) {
        guard !isShowingConfirmation else { return }
        isShowingConfirmation = true

        let previousPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let confirmed = TeamsCallConfirmationController().run()
        NSApplication.shared.setActivationPolicy(previousPolicy)
        isShowingConfirmation = false

        guard confirmed else {
            setStatus("Teams call click was cancelled.")
            return
        }

        setStatus("Teams call click was confirmed.")
        swallowAllUntil = .distantPast
        swallowMouseUpUntil = .distantPast
        passThroughUntil = Date().addingTimeInterval(allowCooldown)
        synthesizeClick(at: location)
    }

    private func synthesizeClick(at location: CGPoint) {
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func setStatus(_ newStatus: String) {
        if Thread.isMainThread {
            statusText = newStatus
            TeamsCallBlockSettings.saveStatusText(newStatus)
        } else {
            DispatchQueue.main.async {
                self.statusText = newStatus
                TeamsCallBlockSettings.saveStatusText(newStatus)
            }
        }
    }
}
