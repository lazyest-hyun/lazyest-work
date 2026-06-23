import Foundation
import GWSMenuCore

enum MeetingFocusApplyResult: Equatable {
    case idle
    case activated
    case alreadyActive
    case cleared
    case pausedForManualOverride(eventID: String)
}

final class MeetingFocusBridge {
    private static let helperShortcutName = "DND Raycast"

    private let managedActiveKey = "meetingFocusManagedActive"
    private let managedEventIDKey = "meetingFocusManagedEventID"
    private let managedPreexistingActiveKey = "meetingFocusPreexistingActive"
    private let pausedEventIDKey = "meetingFocusPausedEventID"

    func apply(_ state: MeetingFocusState) throws -> MeetingFocusApplyResult {
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
            guard try isHelperShortcutInstalled() else {
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
            guard try isHelperShortcutInstalled() else {
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
        let output = try runShortcuts(arguments: ["list"], standardInput: nil)
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(Self.helperShortcutName)
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
        _ = try runShortcuts(arguments: ["run", Self.helperShortcutName], standardInput: command)
    }

    private func currentFocusIsActive() throws -> Bool {
        let output = try runShortcuts(arguments: ["run", Self.helperShortcutName], standardInput: "status")
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

    private func runShortcuts(arguments: [String], standardInput: String?) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if standardInput != nil {
            process.standardInput = inputPipe
        }
        do {
            try process.run()
        } catch {
            throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: error.localizedDescription)
        }
        if let standardInput {
            inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank ?? "shortcuts exited with status \(process.terminationStatus)"
            throw AppError.focusShortcutFailed(name: Self.helperShortcutName, detail: detail)
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
