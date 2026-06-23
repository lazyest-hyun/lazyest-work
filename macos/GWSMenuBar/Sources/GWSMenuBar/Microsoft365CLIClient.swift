import Foundation
import GWSMenuCore

struct Microsoft365CLIStatus: Decodable {
    let connectedAs: String?
}

struct Microsoft365CLICommand {
    let executableURL: URL
    let argumentsPrefix: [String]
}

final class Microsoft365CLIClient: @unchecked Sendable {
    private static let packageName = "@pnp/cli-microsoft365"
    private static let graphCommandLineToolsAppID = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
    private static let tenant = "organizations"

    static var isAvailable: Bool {
        resolvedCommand() != nil
    }

    var isAvailable: Bool {
        Self.isAvailable
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
            if let status = try? JSONDecoder().decode(Microsoft365CLIStatus.self, from: Data(output.utf8)) {
                return .connected(account: status.connectedAs)
            }
            return output.localizedCaseInsensitiveContains("logged out") ? .signedOut : .connected(account: nil)
        } catch {
            return .signedOut
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

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try Self.runSync(command: command, arguments: arguments, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(command: Microsoft365CLICommand, arguments: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.argumentsPrefix + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                throw AppError.api("Microsoft 365 CLI timed out.")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let details = [output, errorOutput]
                .compactMap { $0.nilIfBlank }
                .joined(separator: "\n")
                .nilIfBlank ?? "m365 exited with status \(process.terminationStatus)."
            throw AppError.api(details)
        }

        return output
    }

    private static func resolvedCommand() -> Microsoft365CLICommand? {
        if let m365 = findExecutable(named: "m365") {
            return Microsoft365CLICommand(executableURL: m365, argumentsPrefix: [])
        }
        if let npx = findExecutable(named: "npx") {
            return Microsoft365CLICommand(executableURL: npx, argumentsPrefix: ["-y", "-p", packageName, "m365"])
        }
        return nil
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
