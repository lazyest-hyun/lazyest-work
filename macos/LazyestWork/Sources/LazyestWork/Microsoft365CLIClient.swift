import Foundation
import LazyestWorkCore

struct Microsoft365CLIStatus: Decodable {
    let connectedAs: String?
}

struct Microsoft365CLICommand {
    let executableURL: URL
    let argumentsPrefix: [String]
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private static let byteLimit = 1_048_576
    private let lock = NSLock()
    private var data = Data()
    private var wasTruncated = false

    func append(_ chunk: Data) {
        lock.lock()
        let remainingCapacity = max(0, Self.byteLimit - data.count)
        if remainingCapacity > 0 {
            data.append(contentsOf: chunk.prefix(remainingCapacity))
        }
        if chunk.count > remainingCapacity {
            wasTruncated = true
        }
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        let wasTruncated = wasTruncated
        lock.unlock()

        var output = String(decoding: snapshot, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if wasTruncated {
            if !output.isEmpty {
                output.append("\n")
            }
            output.append("[output truncated after 1 MiB]")
        }
        return output
    }
}

private actor Microsoft365OperationGate {
    private var isOccupied = false
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var waiterOrder: [UUID] = []

    func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard isOccupied else {
            isOccupied = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                    waiterOrder.append(id)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        waiterOrder.removeAll { $0 == id }
        continuation.resume(throwing: CancellationError())
    }

    private func release() {
        while !waiterOrder.isEmpty {
            let id = waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            continuation.resume()
            return
        }
        isOccupied = false
    }
}

private final class AsyncProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let outputBuffer = ProcessOutputBuffer()
    private let errorBuffer = ProcessOutputBuffer()

    private var process: Process?
    private var continuation: CheckedContinuation<String, Error>?
    private var standardOutputHandle: FileHandle?
    private var standardErrorHandle: FileHandle?
    private var timeoutWorkItem: DispatchWorkItem?
    private var killWorkItem: DispatchWorkItem?
    private var forcedError: Error?
    private var terminationStatus: Int32?
    private var standardOutputClosed = false
    private var standardErrorClosed = false
    private var isFinished = false

    func run(command: Microsoft365CLICommand, arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                start(command: command, arguments: arguments, timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            self.stop(with: CancellationError())
        }
    }

    private func start(
        command: Microsoft365CLICommand,
        arguments: [String],
        timeout: TimeInterval,
        continuation: CheckedContinuation<String, Error>
    ) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.argumentsPrefix + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, fromStandardError: false, handle: handle)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, fromStandardError: true, handle: handle)
        }
        process.terminationHandler = { [weak self] process in
            self?.processDidTerminate(status: process.terminationStatus)
        }

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.stop(with: AppError.api("Microsoft 365 CLI timed out."))
        }
        lock.lock()
        self.process = process
        self.continuation = continuation
        standardOutputHandle = outputPipe.fileHandleForReading
        standardErrorHandle = errorPipe.fileHandleForReading
        self.timeoutWorkItem = timeoutWorkItem
        if let errorBeforeLaunch = forcedError {
            lock.unlock()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            finish(throwing: errorBeforeLaunch)
            return
        }
        do {
            // Keep cancellation from interleaving between the final preflight
            // check and launch. `Process.run()` returns as soon as the child is
            // spawned; termination/output callbacks may wait briefly on this lock.
            try process.run()
        } catch {
            lock.unlock()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            finish(throwing: error)
            return
        }
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeout,
            execute: timeoutWorkItem
        )
    }

    private func consume(_ data: Data, fromStandardError: Bool, handle: FileHandle) {
        if data.isEmpty {
            handle.readabilityHandler = nil
            lock.lock()
            if fromStandardError {
                standardErrorClosed = true
            } else {
                standardOutputClosed = true
            }
            let shouldComplete = terminationStatus != nil && standardOutputClosed && standardErrorClosed
            lock.unlock()
            if shouldComplete {
                finishFromProcessExit()
            }
            return
        }

        if fromStandardError {
            errorBuffer.append(data)
        } else {
            outputBuffer.append(data)
        }
    }

    private func processDidTerminate(status: Int32) {
        lock.lock()
        terminationStatus = status
        let shouldComplete = standardOutputClosed && standardErrorClosed
        lock.unlock()
        if shouldComplete {
            finishFromProcessExit()
        }
    }

    private func finishFromProcessExit() {
        lock.lock()
        let status = terminationStatus ?? -1
        let forcedError = forcedError
        lock.unlock()

        if let forcedError {
            finish(throwing: forcedError)
            return
        }

        let output = outputBuffer.string()
        let errorOutput = errorBuffer.string()
        guard status == 0 else {
            let details = [output, errorOutput]
                .compactMap { $0.nilIfBlank }
                .joined(separator: "\n")
                .nilIfBlank ?? "m365 exited with status \(status)."
            finish(throwing: AppError.api(details))
            return
        }
        finish(returning: output)
    }

    private func stop(with error: Error) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        if forcedError == nil {
            forcedError = error
        }
        let process = process
        let hasScheduledForcedFinish = killWorkItem != nil
        lock.unlock()

        guard let process, process.isRunning else {
            finishForcedExecution()
            return
        }

        process.terminate()
        guard !hasScheduledForcedFinish else { return }

        let pid = process.processIdentifier
        let killWorkItem = DispatchWorkItem { [weak self, weak process] in
            if let process, process.isRunning {
                Darwin.kill(pid, SIGKILL)
            }
            // A spawned npm/brew/npx child can inherit the pipe descriptors
            // after the direct Process has exited. Do not wait for that child
            // to close EOF: close our read ends and release the caller/gate.
            self?.finishForcedExecution()
        }
        lock.lock()
        let shouldScheduleForcedFinish: Bool
        if self.killWorkItem == nil {
            self.killWorkItem = killWorkItem
            shouldScheduleForcedFinish = true
        } else {
            shouldScheduleForcedFinish = false
        }
        lock.unlock()
        if shouldScheduleForcedFinish {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: killWorkItem)
        }
    }

    private func finishForcedExecution() {
        lock.lock()
        let error = forcedError ?? CancellationError()
        lock.unlock()
        finish(throwing: error)
    }

    private func finish(returning output: String) {
        finish(with: .success(output))
    }

    private func finish(throwing error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<String, Error>) {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        killWorkItem?.cancel()
        killWorkItem = nil
        process = nil
        let standardOutputHandle = standardOutputHandle
        let standardErrorHandle = standardErrorHandle
        self.standardOutputHandle = nil
        self.standardErrorHandle = nil
        lock.unlock()

        standardOutputHandle?.readabilityHandler = nil
        standardErrorHandle?.readabilityHandler = nil
        try? standardOutputHandle?.close()
        try? standardErrorHandle?.close()
        continuation.resume(with: result)
    }
}

final class Microsoft365CLIClient: @unchecked Sendable {
    private static let packageName = "@pnp/cli-microsoft365"
    private static let graphCommandLineToolsAppID = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
    private static let tenant = "organizations"
    private static let operationGate = Microsoft365OperationGate()

    static var isAvailable: Bool {
        installedCommand() != nil
    }

    var isAvailable: Bool {
        Self.isAvailable
    }

    func installIfNeeded() async throws {
        guard !isAvailable else { return }
        try await Self.operationGate.perform {
            guard Self.installedCommand() == nil else { return }
            AppLog.teamsCLI.notice("Microsoft 365 CLI installation started")
            try await Self.install()
            AppLog.teamsCLI.notice("Microsoft 365 CLI installation completed")
        }
    }

    func connectionState() async -> MicrosoftConnectionState {
        guard isAvailable else {
            return .missingSetup
        }

        do {
            let output = try await run(["status", "-o", "json"], timeout: 45)
            if let statusText = try? JSONDecoder().decode(String.self, from: Data(output.utf8)),
               statusText.localizedCaseInsensitiveContains("logged out") {
                return .signedOut
            }
            if let status = try? JSONDecoder().decode(Microsoft365CLIStatus.self, from: Data(output.utf8)),
               let account = status.connectedAs?.nilIfBlank {
                return .connected(account: account)
            }
            return output.localizedCaseInsensitiveContains("logged out") ? .signedOut : .failed
        } catch {
            AppLog.teamsCLI.error("Microsoft CLI connection check failed: \(error.localizedDescription, privacy: .private)")
            return .failed
        }
    }

    func signIn() async throws {
        _ = try await run(
            [
                "login",
                "--ensure",
                "--authType", "browser",
                "--appId", Self.graphCommandLineToolsAppID,
                "--tenant", Self.tenant,
                "-o", "none"
            ],
            timeout: 300
        )
    }

    func signOut() async throws {
        _ = try await run(["logout", "-o", "none"], timeout: 60)
    }

    func profile() async throws -> MicrosoftProfile {
        let output = try await run(
            [
                "request",
                "--url", "https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName",
                "-o", "json"
            ],
            timeout: 60
        )
        return try JSONDecoder().decode(MicrosoftProfile.self, from: Data(output.utf8))
    }

    func setPreferredPresence(userID: String, request: TeamsPresenceSetRequest) async throws {
        let body = [
            "availability": request.availability,
            "activity": request.activity,
            "expirationDuration": request.expirationDuration
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyText = String(data: bodyData, encoding: .utf8) ?? "{}"
        _ = try await run(
            [
                "request",
                "--method", "post",
                "--url", "https://graph.microsoft.com/v1.0/users/\(userID.pathSegmentEncoded)/presence/setUserPreferredPresence",
                "--body", bodyText,
                "--content-type", "application/json",
                "-o", "none"
            ],
            timeout: 60
        )
    }

    func clearPreferredPresence(userID: String) async throws {
        _ = try await run(
            [
                "request",
                "--method", "post",
                "--url", "https://graph.microsoft.com/v1.0/users/\(userID.pathSegmentEncoded)/presence/clearUserPreferredPresence",
                "-o", "none"
            ],
            timeout: 60
        )
    }

    func currentPresence() async throws -> MicrosoftPresence {
        let output = try await run(
            [
                "request",
                "--url", "https://graph.microsoft.com/v1.0/me/presence",
                "-o", "json"
            ],
            timeout: 60
        )
        return try JSONDecoder().decode(MicrosoftPresence.self, from: Data(output.utf8))
    }

    private func run(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        guard let command = Self.resolvedCommand() else {
            throw AppError.api("Microsoft 365 CLI is not available. Install Node.js/npm or m365 CLI first.")
        }

        let operation = arguments.first ?? "unknown"
        AppLog.teamsCLI.debug("Starting m365 operation: \(operation, privacy: .public)")
        return try await Self.operationGate.perform {
            let execution = AsyncProcessExecution()
            return try await execution.run(command: command, arguments: arguments, timeout: timeout)
        }
    }

    private static func install() async throws {
        if installedCommand() != nil { return }

        if findExecutable(named: "npm") == nil {
            guard let brew = findExecutable(named: "brew") else {
                throw AppError.api("Homebrew is required to install Node.js and Microsoft 365 CLI.")
            }
            try await runInstaller(executableURL: brew, arguments: ["install", "node"], timeout: 900)
        }

        guard let npm = findExecutable(named: "npm") else {
            throw AppError.api("Node.js installation finished, but npm was not found.")
        }
        try await runInstaller(
            executableURL: npm,
            arguments: ["install", "-g", "\(packageName)@latest"],
            timeout: 900
        )

        guard installedCommand() != nil else {
            throw AppError.api("Microsoft 365 CLI installation finished, but m365 was not found.")
        }
    }

    private static func runInstaller(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws {
        let execution = AsyncProcessExecution()
        _ = try await execution.run(
            command: Microsoft365CLICommand(executableURL: executableURL, argumentsPrefix: []),
            arguments: arguments,
            timeout: timeout
        )
    }

    private static func resolvedCommand() -> Microsoft365CLICommand? {
        if let installed = installedCommand() {
            return installed
        }
        if let npx = findExecutable(named: "npx") {
            return Microsoft365CLICommand(executableURL: npx, argumentsPrefix: ["-y", "-p", packageName, "m365"])
        }
        return nil
    }

    private static func installedCommand() -> Microsoft365CLICommand? {
        guard let m365 = findExecutable(named: "m365") else { return nil }
        return Microsoft365CLICommand(executableURL: m365, argumentsPrefix: [])
    }

    private static func findExecutable(named name: String) -> URL? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var directories = pathValue.split(separator: ":").map(String.init)
        directories.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])

        var seen = Set<String>()
        for directory in directories where seen.insert(directory).inserted {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
