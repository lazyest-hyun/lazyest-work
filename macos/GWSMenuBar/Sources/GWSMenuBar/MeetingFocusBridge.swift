import Foundation
import GWSMenuCore

private final class ShortcutProcessOutput: @unchecked Sendable {
    private static let byteLimit = 1_048_576
    private let lock = NSLock()
    private let completion = DispatchSemaphore(value: 0)
    private var output = Data()
    private var errorOutput = Data()
    private var outputWasTruncated = false
    private var errorOutputWasTruncated = false
    private var outputClosed = false
    private var errorOutputClosed = false
    private var processExited = false
    private var didSignal = false

    func consume(_ data: Data, fromStandardError: Bool, handle: FileHandle) {
        lock.lock()
        if data.isEmpty {
            handle.readabilityHandler = nil
            if fromStandardError {
                errorOutputClosed = true
            } else {
                outputClosed = true
            }
        } else if fromStandardError {
            Self.appendBounded(data, to: &errorOutput, wasTruncated: &errorOutputWasTruncated)
        } else {
            Self.appendBounded(data, to: &output, wasTruncated: &outputWasTruncated)
        }
        signalIfCompleteLocked()
        lock.unlock()
    }

    func processDidExit() {
        lock.lock()
        processExited = true
        signalIfCompleteLocked()
        lock.unlock()
    }

    func wait(timeout: TimeInterval) -> DispatchTimeoutResult {
        completion.wait(timeout: .now() + timeout)
    }

    func strings() -> (output: String, error: String) {
        lock.lock()
        let output = self.output
        let errorOutput = self.errorOutput
        let outputWasTruncated = outputWasTruncated
        let errorOutputWasTruncated = errorOutputWasTruncated
        lock.unlock()
        return (
            Self.string(from: output, wasTruncated: outputWasTruncated),
            Self.string(from: errorOutput, wasTruncated: errorOutputWasTruncated)
        )
    }

    private static func appendBounded(_ chunk: Data, to buffer: inout Data, wasTruncated: inout Bool) {
        let remainingCapacity = max(0, byteLimit - buffer.count)
        if remainingCapacity > 0 {
            buffer.append(contentsOf: chunk.prefix(remainingCapacity))
        }
        if chunk.count > remainingCapacity {
            wasTruncated = true
        }
    }

    private static func string(from data: Data, wasTruncated: Bool) -> String {
        var output = String(decoding: data, as: UTF8.self)
        if wasTruncated {
            if !output.isEmpty, !output.hasSuffix("\n") {
                output.append("\n")
            }
            output.append("[output truncated after 1 MiB]")
        }
        return output
    }

    private func signalIfCompleteLocked() {
        guard !didSignal, processExited, outputClosed, errorOutputClosed else { return }
        didSignal = true
        completion.signal()
    }
}

enum MeetingFocusApplyResult: Equatable, Sendable {
    case idle
    case activated
    case alreadyActive
    case cleared
    case pausedForManualOverride(eventID: String)
}

final class MeetingFocusBridge: @unchecked Sendable {
    private static let helperShortcutName = "DND Raycast"
    private static let helperInstalledCacheKey = "meetingFocusHelperInstalledCache"
    private let operationLock = NSLock()
    private let helperCacheLock = NSLock()
    private var helperInstalledCache: Bool?

    private let managedActiveKey = "meetingFocusManagedActive"
    private let managedEventIDKey = "meetingFocusManagedEventID"
    private let managedPreexistingActiveKey = "meetingFocusPreexistingActive"
    private let pausedEventIDKey = "meetingFocusPausedEventID"

    init() {
        helperInstalledCache = (UserDefaults.standard.object(forKey: Self.helperInstalledCacheKey) as? NSNumber)?.boolValue
    }

    func apply(_ state: MeetingFocusState) throws -> MeetingFocusApplyResult {
        try operationLock.withLock {
            try applyLocked(state)
        }
    }

    private func applyLocked(_ state: MeetingFocusState) throws -> MeetingFocusApplyResult {
        let defaults = UserDefaults.standard
        switch state {
        case .active(_, let eventID):
            if pausedEventID(defaults) == eventID {
                return .pausedForManualOverride(eventID: eventID)
            } else if pausedEventID(defaults) != nil {
                clearPausedEvent(defaults)
            }

            if defaults.bool(forKey: managedActiveKey) {
                if defaults.string(forKey: managedEventIDKey) != eventID {
                    defaults.set(eventID, forKey: managedEventIDKey)
                    return .alreadyActive
                }
                if (try? currentFocusIsActive()) == false {
                    savePausedEvent(eventID, defaults)
                    clearManagedFocusState(defaults)
                    return .pausedForManualOverride(eventID: eventID)
                }
                return .alreadyActive
            }
            guard try isHelperShortcutInstalledLocked() else {
                throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: "helper shortcut is not installed")
            }
            let wasAlreadyActive = try currentFocusIsActive()
            if !wasAlreadyActive {
                try runHelperShortcut(command: "on")
            }
            defaults.set(true, forKey: managedActiveKey)
            defaults.set(eventID, forKey: managedEventIDKey)
            defaults.set(wasAlreadyActive, forKey: managedPreexistingActiveKey)
            return wasAlreadyActive ? .alreadyActive : .activated
        case .inactive:
            clearPausedEvent(defaults)
            guard defaults.bool(forKey: managedActiveKey) else {
                return .idle
            }
            guard try isHelperShortcutInstalledLocked() else {
                clearManagedFocusState(defaults)
                return .cleared
            }
            if !defaults.bool(forKey: managedPreexistingActiveKey) {
                try runHelperShortcut(command: "off")
            }
            clearManagedFocusState(defaults)
            return .cleared
        }
    }

    func isHelperShortcutInstalled() throws -> Bool {
        // Some callers are synchronous MainActor UI actions. Never make those
        // wait behind an in-flight focus transition (which can run multiple
        // shortcut commands); detached refreshes populate this cache.
        if Thread.isMainThread {
            return cachedHelperInstalled() ?? false
        }

        guard operationLock.try() else {
            return cachedHelperInstalled() ?? false
        }
        defer { operationLock.unlock() }
        return try isHelperShortcutInstalledLocked()
    }

    private func isHelperShortcutInstalledLocked() throws -> Bool {
        let output = try runShortcuts(arguments: ["list"], standardInput: nil, timeout: 10)
        let isInstalled = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(Self.helperShortcutName)
        cacheHelperInstalled(isInstalled)
        return isInstalled
    }

    private func cachedHelperInstalled() -> Bool? {
        helperCacheLock.withLock { helperInstalledCache }
    }

    private func cacheHelperInstalled(_ isInstalled: Bool) {
        helperCacheLock.withLock {
            helperInstalledCache = isInstalled
        }
        UserDefaults.standard.set(isInstalled, forKey: Self.helperInstalledCacheKey)
    }

    func openHelperInstaller() throws {
        guard let url = AppResourceLocator.url(
            named: Self.helperShortcutName,
            extension: "shortcut",
            subdirectory: "FocusShortcuts"
        ) else {
            throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: "bundled helper shortcut is missing")
        }
        try SystemOpener.openFile(url)
    }

    private func runHelperShortcut(command: String) throws {
        _ = try runShortcuts(
            arguments: ["run", Self.helperShortcutName],
            standardInput: command,
            timeout: 30
        )
    }

    private func currentFocusIsActive() throws -> Bool {
        let output = try runShortcuts(
            arguments: ["run", Self.helperShortcutName],
            standardInput: "status",
            timeout: 30
        )
        if let status = FocusStatusParser.parse(output) {
            return status
        }
        throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: "could not read current Do Not Disturb status")
    }

    private func clearManagedFocusState(_ defaults: UserDefaults) {
        defaults.set(false, forKey: managedActiveKey)
        defaults.removeObject(forKey: managedEventIDKey)
        defaults.removeObject(forKey: managedPreexistingActiveKey)
    }

    private func pausedEventID(_ defaults: UserDefaults) -> String? {
        defaults.string(forKey: pausedEventIDKey)
    }

    private func savePausedEvent(_ eventID: String, _ defaults: UserDefaults) {
        defaults.set(eventID, forKey: pausedEventIDKey)
    }

    private func clearPausedEvent(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: pausedEventIDKey)
    }

    private func runShortcuts(arguments: [String], standardInput: String?, timeout: TimeInterval) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let processOutput = ShortcutProcessOutput()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if standardInput != nil {
            process.standardInput = inputPipe
        }
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            processOutput.consume(handle.availableData, fromStandardError: false, handle: handle)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            processOutput.consume(handle.availableData, fromStandardError: true, handle: handle)
        }
        process.terminationHandler = { _ in
            processOutput.processDidExit()
        }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: error.localizedDescription)
        }
        if let standardInput {
            inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }
        if processOutput.wait(timeout: timeout) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            if processOutput.wait(timeout: 1) == .timedOut, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = processOutput.wait(timeout: 1)
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: "shortcuts timed out")
        }

        let capturedOutput = processOutput.strings()
        guard process.terminationStatus == 0 else {
            let detail = capturedOutput.error
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank ?? "shortcuts exited with status \(process.terminationStatus)"
            throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: detail)
        }
        return capturedOutput.output
    }
}
