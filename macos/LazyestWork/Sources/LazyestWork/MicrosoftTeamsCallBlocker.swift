@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation

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
    private static let controlScrollEnabledKey = "teamsControlScrollBlockEnabled"
    private static let pendingEnableKey = "teamsCallBlockPendingEnableAfterPermission"
    private static let statusKey = "teamsCallBlockStatusText"

    static func loadEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func saveEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
    }

    static func loadControlScrollEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: controlScrollEnabledKey)
    }

    static func saveControlScrollEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: controlScrollEnabledKey)
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

    var isReady: Bool {
        self == .ready
    }

    var statusText: String {
        switch self {
        case .ready:
            return "Off. Turn on Teams call confirmation."
        case .missingAccessibility:
            return "Off. Accessibility permission is needed before Teams calls can be blocked."
        }
    }

    var runningStatusText: String {
        "On. Teams calls require confirmation."
    }

    var eventMonitoringUnavailableText: String {
        switch self {
        case .missingAccessibility:
            return "Off. Accessibility permission is not detected for Lazyest Work."
        case .ready:
            return "Off. macOS did not allow event monitoring. Quit and reopen Lazyest Work."
        }
    }

    var pendingEnableStatusText: String {
        switch self {
        case .missingAccessibility:
            return "Waiting for Accessibility permission. Enable Lazyest Work in System Settings."
        case .ready:
            return "Waiting for macOS event monitoring. Lazyest Work will turn on Teams call block automatically."
        }
    }

    static func current() -> TeamsCallBlockPermissionState {
        let accessibilityGranted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
        return accessibilityGranted ? .ready : .missingAccessibility
    }
}

final class MicrosoftTeamsCallBlocker: ObservableObject, @unchecked Sendable {
    private final class CallbackContext {
        weak var blocker: MicrosoftTeamsCallBlocker?

        init(blocker: MicrosoftTeamsCallBlocker) {
            self.blocker = blocker
        }
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var isControlScrollBlockEnabled = false
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
    private let inputDrivenWindowRefreshInterval: TimeInterval = 0.2
    private let windowSnapshotStaleInterval: TimeInterval = 5.0
    private var passThroughUntil = Date.distantPast
    private var swallowMouseUpUntil = Date.distantPast
    private var swallowAllUntil = Date.distantPast
    private var isShowingConfirmation = false
    private var isTeamsActive = false
    private var teamsProcessIdentifiers = Set<pid_t>()
    private var teamsWindowFrames: [CGRect] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapIncludesScrollWheel = false
    private var workspaceObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var teamsAccessibilityObservers: [pid_t: AXObserver] = [:]
    private var isTeamsWindowRefreshScheduled = false
    private var requiresInputDrivenWindowRefresh = false
    private var lastTeamsWindowSnapshotAt = Date.distantPast
    private var lastInputDrivenWindowRefreshAt = Date.distantPast
    private var callbackContextPointer: UnsafeMutableRawPointer?
    private var permissionRetryTimer: Timer?
    private var permissionRetryCount = 0
    private var confirmationTask: Task<Void, Never>?
    private var shouldContinuePermissionRequests = false
    private var didRequestAccessibility = false
    private var lastTeamsAccessibilityWarmUp = Date.distantPast

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        for observer in teamsAccessibilityObservers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        permissionRetryTimer?.invalidate()
        confirmationTask?.cancel()
        if let callbackContextPointer {
            Unmanaged<CallbackContext>.fromOpaque(callbackContextPointer).release()
        }
    }

    private var hasEnabledProtection: Bool {
        isEnabled || isControlScrollBlockEnabled
    }

    private var callProtectionStatusText: String {
        isEnabled
            ? permissionState.runningStatusText
            : permissionState.statusText
    }

    func configure(savedEnabled: Bool, savedControlScrollBlockEnabled: Bool) {
        permissionState = TeamsCallBlockPermissionState.current()
        let shouldResumePermissionRequest = isPendingEnableAfterPermission
        isEnabled = savedEnabled
        isControlScrollBlockEnabled = savedControlScrollBlockEnabled

        guard hasEnabledProtection || isPendingEnableAfterPermission else {
            setStatus(permissionState.statusText)
            return
        }

        let started = startIfPossible()
        if started {
            finishEnableSuccess()
        } else {
            beginPendingEnableAfterPermission(openPermissionsIfMissing: shouldResumePermissionRequest)
        }
    }

    @discardableResult
    func setEnabled(_ shouldEnable: Bool, openPermissionsIfMissing: Bool = false) -> Bool {
        isEnabled = shouldEnable
        TeamsCallBlockSettings.saveEnabled(shouldEnable)
        return applyFeatureChange(openPermissionsIfMissing: openPermissionsIfMissing)
    }

    @discardableResult
    func setControlScrollBlockEnabled(_ shouldEnable: Bool, openPermissionsIfMissing: Bool = false) -> Bool {
        isControlScrollBlockEnabled = shouldEnable
        TeamsCallBlockSettings.saveControlScrollEnabled(shouldEnable)
        return applyFeatureChange(openPermissionsIfMissing: openPermissionsIfMissing)
    }

    private func applyFeatureChange(openPermissionsIfMissing: Bool) -> Bool {
        guard hasEnabledProtection else {
            clearPendingEnableAfterPermission()
            stop()
            setStatus(permissionState.statusText)
            return false
        }

        if startIfPossible() {
            finishEnableSuccess()
        } else {
            beginPendingEnableAfterPermission(openPermissionsIfMissing: openPermissionsIfMissing)
        }
        return true
    }

    func refreshPermissions() {
        permissionState = TeamsCallBlockPermissionState.current()
        if isPendingEnableAfterPermission {
            retryPendingEnableAfterPermission()
            return
        }
        setStatus(callProtectionStatusText)
    }

    func stop() {
        stopEventTap()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        removeTeamsAccessibilityObservers()
        releaseCallbackContext()
        isTeamsWindowRefreshScheduled = false
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        confirmationTask?.cancel()
        confirmationTask = nil
        isTeamsActive = false
        teamsProcessIdentifiers.removeAll()
        teamsWindowFrames.removeAll()
        lastTeamsAccessibilityWarmUp = .distantPast
    }

    private func finishEnableSuccess() {
        shouldContinuePermissionRequests = false
        didRequestAccessibility = false
        isPendingEnableAfterPermission = false
        TeamsCallBlockSettings.savePendingEnableAfterPermission(false)
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        permissionRetryCount = 0
        setStatus(callProtectionStatusText)
    }

    private func beginPendingEnableAfterPermission(openPermissionsIfMissing: Bool) {
        isPendingEnableAfterPermission = true
        TeamsCallBlockSettings.savePendingEnableAfterPermission(true)
        setStatus(permissionState.pendingEnableStatusText)
        startPermissionRetryTimer()

        shouldContinuePermissionRequests = openPermissionsIfMissing
        requestCurrentPermissionIfNeeded()
    }

    private func clearPendingEnableAfterPermission() {
        shouldContinuePermissionRequests = false
        didRequestAccessibility = false
        isPendingEnableAfterPermission = false
        TeamsCallBlockSettings.savePendingEnableAfterPermission(false)
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        permissionRetryCount = 0
    }

    private func startPermissionRetryTimer() {
        guard permissionRetryTimer == nil else { return }
        permissionRetryCount = 0
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.permissionRetryCount += 1
            self.retryPendingEnableAfterPermission()
            if self.permissionRetryCount >= 60, !self.hasEnabledProtection {
                self.permissionRetryTimer?.invalidate()
                self.permissionRetryTimer = nil
            }
        }
        permissionRetryTimer?.tolerance = 0.25
    }

    private func retryPendingEnableAfterPermission() {
        guard isPendingEnableAfterPermission, hasEnabledProtection else {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
            return
        }

        let previousState = permissionState
        permissionState = TeamsCallBlockPermissionState.current()
        if permissionState != previousState {
            requestCurrentPermissionIfNeeded()
        }
        if startIfPossible() {
            finishEnableSuccess()
            return
        }

        setStatus(permissionState.pendingEnableStatusText)
    }

    private func requestCurrentPermissionIfNeeded() {
        guard shouldContinuePermissionRequests,
              permissionState == .missingAccessibility,
              !didRequestAccessibility else {
            return
        }
        didRequestAccessibility = true
        requestMissingPermission(for: permissionState)
    }

    private func startIfPossible() -> Bool {
        permissionState = TeamsCallBlockPermissionState.current()

        guard hasEnabledProtection else {
            stop()
            return true
        }

        // Creating an event tap before TCC is ready can trigger its own macOS
        // permission alert. Keep permission requests in one explicit path.
        guard permissionState.isReady else {
            stopEventTap()
            return false
        }

        installWorkspaceObservers()
        refreshActiveApplication()
        guard !isTeamsActive || eventTap != nil else {
            setStatus(permissionState.eventMonitoringUnavailableText)
            return false
        }
        return true
    }

    private func requestMissingPermission(for state: TeamsCallBlockPermissionState) {
        switch state {
        case .missingAccessibility:
            let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptOption: true] as CFDictionary)
        case .ready:
            return
        }
    }

    private func startEventTap() -> Bool {
        let includesScrollWheel = isControlScrollBlockEnabled && isTeamsActive
        if eventTap != nil, eventTapIncludesScrollWheel == includesScrollWheel {
            return true
        }

        stopEventTap()

        var mask: CGEventMask = 0
        if isEnabled {
            mask |= CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            mask |= CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        }
        if includesScrollWheel {
            mask |= CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        }
        guard mask != 0 else { return true }

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<CallbackContext>.fromOpaque(userInfo).takeUnretainedValue()
            guard let blocker = context.blocker else { return Unmanaged.passUnretained(event) }
            return blocker.handleEvent(proxy: proxy, type: type, event: event)
        }

        let tap = createEventTap(location: .cghidEventTap, mask: mask, callback: callback)
            ?? createEventTap(location: .cgSessionEventTap, mask: mask, callback: callback)

        guard let tap else { return false }
        AppLog.teamsGuard.notice("Teams event tap started")
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap
        runLoopSource = source
        eventTapIncludesScrollWheel = includesScrollWheel
        CGEvent.tapEnable(tap: tap, enable: true)
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
            userInfo: callbackUserInfo()
        )
    }

    private func callbackUserInfo() -> UnsafeMutableRawPointer {
        if let callbackContextPointer {
            return callbackContextPointer
        }
        let pointer = UnsafeMutableRawPointer(
            Unmanaged.passRetained(CallbackContext(blocker: self)).toOpaque()
        )
        callbackContextPointer = pointer
        return pointer
    }

    private func releaseCallbackContext() {
        guard let callbackContextPointer else { return }
        self.callbackContextPointer = nil
        Unmanaged<CallbackContext>.fromOpaque(callbackContextPointer).release()
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
        eventTapIncludesScrollWheel = false
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
                self?.updateActiveApplication(app)
            }
        }

        if screenParametersObserver == nil {
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleTeamsWindowRefresh()
            }
        }
    }

    private func refreshActiveApplication() {
        updateActiveApplication(NSWorkspace.shared.frontmostApplication)
    }

    private func updateActiveApplication(_ app: NSRunningApplication?) {
        isTeamsActive = app.map(isTeamsApplication) ?? false
        guard isTeamsActive else {
            removeTeamsAccessibilityObservers()
            teamsProcessIdentifiers.removeAll()
            teamsWindowFrames.removeAll()
            _ = ensureEventTapForActiveApplication()
            return
        }

        refreshTeamsWindows()
        installTeamsAccessibilityObservers()
        guard ensureEventTapForActiveApplication() else {
            setStatus(permissionState.eventMonitoringUnavailableText)
            return
        }
        setEventTapEnabled(true)
    }

    @discardableResult
    private func ensureEventTapForActiveApplication() -> Bool {
        // Keep the global tap absent outside Teams. This avoids routing any
        // Chrome or other-app input through Lazyest Work at all.
        guard hasEnabledProtection, isTeamsActive else {
            stopEventTap()
            return true
        }

        let needsScrollWheel = isControlScrollBlockEnabled
        if eventTap != nil, eventTapIncludesScrollWheel == needsScrollWheel {
            return true
        }
        return startEventTap()
    }

    private func setEventTapEnabled(_ enabled: Bool) {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: enabled)
    }

    private func installTeamsAccessibilityObservers() {
        let activeProcessIdentifiers = teamsProcessIdentifiers
        let staleProcessIdentifiers = teamsAccessibilityObservers.keys.filter {
            !activeProcessIdentifiers.contains($0)
        }
        for processIdentifier in staleProcessIdentifiers {
            removeTeamsAccessibilityObserver(for: processIdentifier)
        }

        let callback: AXObserverCallback = { observer, element, notification, userInfo in
            guard let userInfo else { return }
            let context = Unmanaged<CallbackContext>.fromOpaque(userInfo).takeUnretainedValue()
            guard let blocker = context.blocker else { return }
            blocker.handleTeamsAccessibilityNotification(
                observer: observer,
                element: element,
                notification: notification as String
            )
        }
        let userInfo = callbackUserInfo()

        for processIdentifier in activeProcessIdentifiers where teamsAccessibilityObservers[processIdentifier] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(processIdentifier, callback, &observer) == .success,
                  let observer else {
                enableInputDrivenWindowRefreshFallback()
                continue
            }

            teamsAccessibilityObservers[processIdentifier] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

            let app = AXUIElementCreateApplication(processIdentifier)
            addTeamsAccessibilityNotification(
                observer,
                element: app,
                notification: kAXWindowCreatedNotification,
                userInfo: userInfo
            )
            addTeamsAccessibilityNotification(
                observer,
                element: app,
                notification: kAXFocusedWindowChangedNotification,
                userInfo: userInfo
            )
            registerTeamsWindowNotifications(forApplication: app, observer: observer, userInfo: userInfo)
        }
    }

    @discardableResult
    private func addTeamsAccessibilityNotification(
        _ observer: AXObserver,
        element: AXUIElement,
        notification: String,
        userInfo: UnsafeMutableRawPointer
    ) -> Bool {
        let result = AXObserverAddNotification(observer, element, notification as CFString, userInfo)
        let registered = result == .success || result == .notificationAlreadyRegistered
        if !registered {
            enableInputDrivenWindowRefreshFallback()
        }
        return registered
    }

    private func enableInputDrivenWindowRefreshFallback() {
        guard !requiresInputDrivenWindowRefresh else { return }
        requiresInputDrivenWindowRefresh = true
        AppLog.teamsGuard.notice("Teams AX window notifications unavailable; using input-driven refresh")
    }

    private func registerTeamsWindowNotifications(
        forApplication app: AXUIElement,
        observer: AXObserver,
        userInfo: UnsafeMutableRawPointer
    ) {
        for window in elementArrayAttribute(app, kAXWindowsAttribute).prefix(8) {
            registerTeamsWindowNotifications(for: window, observer: observer, userInfo: userInfo)
        }
    }

    private func registerTeamsWindowNotifications(
        for window: AXUIElement,
        observer: AXObserver,
        userInfo: UnsafeMutableRawPointer
    ) {
        for notification in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
            addTeamsAccessibilityNotification(
                observer,
                element: window,
                notification: notification,
                userInfo: userInfo
            )
        }
    }

    private func handleTeamsAccessibilityNotification(
        observer: AXObserver,
        element: AXUIElement,
        notification: String
    ) {
        guard isTeamsActive else { return }
        if notification == kAXWindowCreatedNotification {
            let userInfo = callbackUserInfo()
            registerTeamsWindowNotifications(for: element, observer: observer, userInfo: userInfo)
        } else if notification == kAXFocusedWindowChangedNotification {
            var processIdentifier: pid_t = 0
            if AXUIElementGetPid(element, &processIdentifier) == .success {
                let app = AXUIElementCreateApplication(processIdentifier)
                let userInfo = callbackUserInfo()
                registerTeamsWindowNotifications(forApplication: app, observer: observer, userInfo: userInfo)
            }
        }
        scheduleTeamsWindowRefresh()
    }

    private func scheduleTeamsWindowRefresh() {
        guard isTeamsActive, !isTeamsWindowRefreshScheduled else { return }
        isTeamsWindowRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isTeamsWindowRefreshScheduled = false
            guard self.isTeamsActive else { return }
            self.refreshTeamsWindows()
            self.installTeamsAccessibilityObservers()
        }
    }

    private func removeTeamsAccessibilityObserver(for processIdentifier: pid_t) {
        guard let observer = teamsAccessibilityObservers.removeValue(forKey: processIdentifier) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func removeTeamsAccessibilityObservers() {
        for observer in teamsAccessibilityObservers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        teamsAccessibilityObservers.removeAll()
        requiresInputDrivenWindowRefresh = false
        lastInputDrivenWindowRefreshAt = .distantPast
    }

    private func refreshTeamsWindows() {
        guard isTeamsActive else {
            teamsProcessIdentifiers.removeAll()
            teamsWindowFrames.removeAll()
            return
        }

        let teamsApps = NSWorkspace.shared.runningApplications.filter(isTeamsApplication)
        teamsProcessIdentifiers = Set(teamsApps.map(\.processIdentifier))
        warmUpTeamsAccessibilityIfNeeded()

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            teamsWindowFrames = []
            lastTeamsWindowSnapshotAt = .distantPast
            return
        }

        lastTeamsWindowSnapshotAt = Date()
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
            if type == .tapDisabledByTimeout {
                AppLog.teamsGuard.error("Teams event tap timed out and is being re-enabled")
            } else {
                AppLog.teamsGuard.notice("Teams event tap was disabled by user input and is being re-enabled")
            }
            if isTeamsActive, hasEnabledProtection {
                setEventTapEnabled(true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Scroll must stay transparent outside the frontmost Teams window. In
        // particular, this keeps Control-scroll browser zoom out of this guard.
        if type == .scrollWheel {
            guard isControlScrollBlockEnabled else {
                return Unmanaged.passUnretained(event)
            }
            return handleScrollWheel(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        if Date() < swallowAllUntil {
            return nil
        }

        refreshTeamsWindowSnapshotForRelevantInputIfNeeded(type: type, event: event)
        let location = event.location
        guard isTeamsEvent(at: location) else {
            return Unmanaged.passUnretained(event)
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

        confirmationTask?.cancel()
        confirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled,
                  self.isEnabled,
                  self.isTeamsEvent(at: location) else {
                return
            }
            self.confirmThenClick(at: location)
            self.confirmationTask = nil
        }

        return nil
    }

    private func refreshTeamsWindowSnapshotForRelevantInputIfNeeded(type: CGEventType, event: CGEvent) {
        let isRelevantInput = type == .leftMouseDown
        guard isTeamsActive, isRelevantInput else { return }

        let now = Date()
        let isOutsideKnownWindow = !teamsWindowFrames.isEmpty
            && !teamsWindowFrames.contains(where: { $0.contains(event.location) })
        let isSnapshotStale = now.timeIntervalSince(lastTeamsWindowSnapshotAt) >= windowSnapshotStaleInterval
        guard isOutsideKnownWindow || requiresInputDrivenWindowRefresh || isSnapshotStale else { return }

        if !isOutsideKnownWindow,
           now.timeIntervalSince(lastInputDrivenWindowRefreshAt) < inputDrivenWindowRefreshInterval {
            return
        }
        lastInputDrivenWindowRefreshAt = now
        refreshTeamsWindows()
        installTeamsAccessibilityObservers()
    }

    private func isTeamsEvent(at location: CGPoint) -> Bool {
        guard isTeamsActive,
              let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              isTeamsApplication(frontmostApplication) else {
            return false
        }

        if teamsWindowFrames.contains(where: { $0.contains(location) }) {
            return true
        }
        return teamsWindowFrames.isEmpty
    }

    private func handleScrollWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isControlScrollBlockEnabled,
              controlKeyIsDown(for: event),
              isFrontmostTeamsWindow(at: event.location) else {
            return Unmanaged.passUnretained(event)
        }

        setStatus("Blocked Teams Control-scroll zoom.")
        return nil
    }

    private func controlKeyIsDown(for event: CGEvent) -> Bool {
        event.flags.contains(.maskControl)
    }

    private func isFrontmostTeamsWindow(at location: CGPoint) -> Bool {
        guard isTeamsActive,
              let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              isTeamsApplication(frontmostApplication) else {
            return false
        }

        // A missing window snapshot is never sufficient reason to suppress an
        // input event. At worst, a newly opened Teams window gets one normal
        // Control-scroll; other apps are never affected.
        return teamsWindowFrames.contains(where: { $0.contains(location) })
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
        if let hitElement = accessibilityElement(at: location),
           isTeamsElement(hitElement) {
            if isRiskyCallElement(hitElement) {
                return true
            }
            if callActionRoles.contains(stringAttribute(hitElement, kAXRoleAttribute)) {
                return false
            }
        }

        return scannedAccessibilityCandidates(at: location).contains { target in
            isTeamsElement(target) && isRiskyCallElement(target)
        }
    }

    private func scannedAccessibilityCandidates(at location: CGPoint) -> [AXUIElement] {
        warmUpTeamsAccessibilityIfNeeded()

        var matches: [(element: AXUIElement, area: CGFloat)] = []
        var remainingBudget = 360

        for processIdentifier in teamsProcessIdentifiers {
            let app = AXUIElementCreateApplication(processIdentifier)
            for window in elementArrayAttribute(app, kAXWindowsAttribute).prefix(2) {
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
        guard depth <= 10, remainingBudget > 0 else { return }
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
        for child in children.prefix(32) {
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
            guard statusText != newStatus else { return }
            statusText = newStatus
            TeamsCallBlockSettings.saveStatusText(newStatus)
        } else {
            DispatchQueue.main.async {
                guard self.statusText != newStatus else { return }
                self.statusText = newStatus
                TeamsCallBlockSettings.saveStatusText(newStatus)
            }
        }
    }
}
