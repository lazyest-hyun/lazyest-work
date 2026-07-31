import AuthenticationServices
import AppKit
import CryptoKit
import Foundation
import LazyestWorkCore
import Security

enum MicrosoftOAuthRedirectMode: Equatable, Sendable {
    case appScheme
    case loopback
}

struct MicrosoftSetupConfig: Equatable, Sendable {
    static let defaultTenantID = "organizations"
    static let defaultBundleID = "com.lazyest.work"

    static var redirectScheme: String {
        redirectScheme(for: Bundle.main.bundleIdentifier ?? defaultBundleID)
    }

    static var redirectURI: String {
        "\(redirectScheme)://auth"
    }

    static func redirectScheme(for bundleID: String) -> String {
        "msauth.\(bundleID)"
    }

    static func redirectURI(for bundleID: String) -> String {
        "\(redirectScheme(for: bundleID))://auth"
    }

    var clientID: String
    var tenantID: String
    var redirectMode: MicrosoftOAuthRedirectMode = .appScheme

    var isComplete: Bool {
        (try? Self.normalized(clientID: clientID, tenantID: tenantID)) != nil
    }

    var usesLoopbackRedirect: Bool {
        redirectMode == .loopback
    }

    func normalized() throws -> MicrosoftSetupConfig {
        try Self.normalized(
            clientID: clientID,
            tenantID: tenantID,
            redirectMode: redirectMode
        )
    }

    static func normalized(
        clientID: String,
        tenantID: String,
        redirectMode: MicrosoftOAuthRedirectMode = .appScheme
    ) throws -> MicrosoftSetupConfig {
        let normalizedClientID = extractedClientID(from: clientID) ?? clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: normalizedClientID) != nil else {
            throw MicrosoftSetupError.missingBundleConfig
        }

        let normalizedTenantID = tenantID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? defaultTenantID
        guard isValidTenantID(normalizedTenantID) else {
            throw MicrosoftSetupError.missingBundleConfig
        }

        return MicrosoftSetupConfig(
            clientID: normalizedClientID,
            tenantID: normalizedTenantID,
            redirectMode: redirectMode
        )
    }

    static func extractedClientID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if UUID(uuidString: trimmed) != nil {
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
        if let string = object as? String, UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let dictionary = object as? [String: Any] {
            for key in ["client_id", "clientId", "appId", "applicationId", "GWSMicrosoftClientID"] {
                if let value = dictionary[key] as? String,
                   UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
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
        let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        let value = String(text[matchRange])
        return UUID(uuidString: value) != nil ? value : nil
    }

    private static func isValidTenantID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased() == "organizations" {
            return true
        }
        if UUID(uuidString: trimmed) != nil {
            return true
        }
        return trimmed.contains(".") && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }
}

enum MicrosoftSetupError: LocalizedError {
    case missingBundleConfig

    var errorDescription: String? {
        "Teams status is not configured in this build."
    }
}

enum MicrosoftSetupSettings {
    private static let personalClientIDKey = "microsoftPersonalClientID"
    private static let personalTenantIDKey = "microsoftPersonalTenantID"

    static func load() -> MicrosoftSetupConfig {
        if let clientID = Bundle.main.microsoftClientID {
            return MicrosoftSetupConfig(
                clientID: clientID,
                tenantID: Bundle.main.microsoftTenantID ?? MicrosoftSetupConfig.defaultTenantID,
                redirectMode: .appScheme
            )
        }

        let defaults = UserDefaults.standard
        if let clientID = defaults.string(forKey: personalClientIDKey)?.nilIfEmpty,
           let tenantID = defaults.string(forKey: personalTenantIDKey)?.nilIfEmpty {
            return MicrosoftSetupConfig(
                clientID: clientID,
                tenantID: tenantID,
                redirectMode: .loopback
            )
        }

        return MicrosoftSetupConfig(
            clientID: "",
            tenantID: MicrosoftSetupConfig.defaultTenantID,
            redirectMode: .loopback
        )
    }

    static func savePersonalApp(_ config: MicrosoftSetupConfig) throws {
        let normalized = try MicrosoftSetupConfig.normalized(
            clientID: config.clientID,
            tenantID: config.tenantID,
            redirectMode: .loopback
        )
        let defaults = UserDefaults.standard
        defaults.set(normalized.clientID, forKey: personalClientIDKey)
        defaults.set(normalized.tenantID, forKey: personalTenantIDKey)
    }

    static func clearPersonalApp() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: personalClientIDKey)
        defaults.removeObject(forKey: personalTenantIDKey)
    }
}

enum TeamsPresenceSettings {
    private static let enabledKey = "teamsPresenceEnabled"

    static func loadEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func saveEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
    }
}

enum MicrosoftConnectionState: Equatable {
    case missingSetup
    case signedOut
    case failed
    case connected(account: String?)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var accountLine: String {
        switch self {
        case .missingSetup:
            return "Not configured in this build"
        case .signedOut:
            return "Not connected"
        case .failed:
            return "Connection check failed"
        case .connected(let account):
            return account ?? "Connected"
        }
    }
}

enum MicrosoftTeamsOperation: Equatable {
    case idle
    case installingCLI
    case settingUp
    case signingIn
    case signingOut

    var isActive: Bool { self != .idle }
}

struct MicrosoftTokenSet: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountName: String?
    var userID: String?
    var clientID: String?
    var tenantID: String?

    func hasValidAccessToken(now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) > 60
    }
}

struct MicrosoftTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct MicrosoftTokenErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct MicrosoftAuthorizationGrant {
    let code: String
    let redirectURI: String
}

private final class MicrosoftOAuthLoopbackServer: @unchecked Sendable {
    private static let callbackTimeout: TimeInterval = 300
    private static let maximumRequestBytes = 65_536
    // A connection that never completes its request line must not stall the
    // whole sign-in. Reads are bounded so an idle or half-open client is
    // dropped and the real Microsoft callback still gets accepted.
    private static let requestReadTimeout: TimeInterval = 10
    private static let acceptBacklog: Int32 = 8

    private let descriptor: Int32
    private let descriptorLock = NSLock()
    private var isClosed = false

    let redirectURI: String

    init() throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AppError.api("Microsoft sign-in could not start a local callback.")
        }

        var reuseAddress: Int32 = 1
        _ = withUnsafePointer(to: &reuseAddress) {
            Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_REUSEADDR,
                $0,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0, Darwin.listen(descriptor, Self.acceptBacklog) == 0 else {
            Darwin.close(descriptor)
            throw AppError.api("Microsoft sign-in could not open a local callback.")
        }

        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &boundAddressLength)
            }
        }
        guard nameStatus == 0 else {
            Darwin.close(descriptor)
            throw AppError.api("Microsoft sign-in could not read its local callback.")
        }

        self.descriptor = descriptor
        // The app registration contains `http://localhost`; Entra ID requires
        // the runtime redirect host to match that registered URI.
        redirectURI = "http://localhost:\(UInt16(bigEndian: boundAddress.sin_port))"
    }

    deinit {
        closeListener()
    }

    func waitForCallback(expectedState: String) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(
                            returning: try self.waitForCallbackSync(expectedState: expectedState)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.closeListener()
        }
    }

    private func waitForCallbackSync(expectedState: String) throws -> URL {
        defer { closeListener() }

        let deadline = Date().addingTimeInterval(Self.callbackTimeout)

        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw AppError.api("Microsoft sign-in timed out.")
            }

            var descriptorToPoll = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let pollStatus = Darwin.poll(
                &descriptorToPoll,
                1,
                Int32((remaining * 1000).rounded(.up))
            )
            if pollStatus < 0, errno == EINTR {
                continue
            }
            guard pollStatus > 0, descriptorToPoll.revents & Int16(POLLIN) != 0 else {
                throw AppError.api(
                    pollStatus == 0
                        ? "Microsoft sign-in timed out."
                        : "Microsoft sign-in local callback failed."
                )
            }

            let clientDescriptor = Darwin.accept(descriptor, nil, nil)
            guard clientDescriptor >= 0 else {
                if errno == EINTR || errno == ECONNABORTED {
                    continue
                }
                throw AppError.api("Microsoft sign-in local callback failed.")
            }

            // Anything else that reaches this port — a local port scanner, a
            // reloaded tab, a stale request — is answered and ignored. Only a
            // redirect carrying the state issued for this sign-in ends the wait.
            if let callbackURL = handleConnection(clientDescriptor, expectedState: expectedState) {
                return callbackURL
            }
        }
    }

    /// Reads one accepted connection and returns the redirect URL only when it
    /// carries this sign-in's state. Always closes `clientDescriptor`.
    private func handleConnection(_ clientDescriptor: Int32, expectedState: String) -> URL? {
        defer { Darwin.close(clientDescriptor) }

        setSocketFlag(clientDescriptor, option: SO_NOSIGPIPE)
        var readTimeout = timeval(tv_sec: Int(Self.requestReadTimeout), tv_usec: 0)
        _ = withUnsafePointer(to: &readTimeout) {
            Darwin.setsockopt(
                clientDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                $0,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }

        guard let request = try? receiveRequest(from: clientDescriptor),
              let callbackURL = try? callbackURL(from: request) else {
            return nil
        }

        let queryItems = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        guard queryItems.first(where: { $0.name == "state" })?.value == expectedState else {
            sendResponse(to: clientDescriptor, succeeded: false)
            return nil
        }

        // An Entra ID error redirect also carries the state and no code. It is
        // still this sign-in's answer, so it is returned for the caller to read.
        sendResponse(
            to: clientDescriptor,
            succeeded: queryItems.contains { $0.name == "code" }
        )
        return callbackURL
    }

    private func setSocketFlag(_ descriptor: Int32, option: Int32) {
        var enabled: Int32 = 1
        _ = withUnsafePointer(to: &enabled) {
            Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                option,
                $0,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }
    }

    private func receiveRequest(from descriptor: Int32) throws -> String {
        var requestData = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)

        while requestData.count < Self.maximumRequestBytes {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            guard count > 0 else { break }
            requestData.append(contentsOf: buffer.prefix(count))
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                break
            }
        }

        guard let request = String(data: requestData, encoding: .utf8),
              request.contains("\r\n\r\n") else {
            throw AppError.api("Microsoft sign-in returned an invalid local callback.")
        }
        return request
    }

    private func callbackURL(from request: String) throws -> URL {
        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            throw AppError.api("Microsoft sign-in returned an invalid local callback.")
        }
        let components = requestLine.split(separator: " ", maxSplits: 2)
        guard components.count == 3,
              components[0] == "GET",
              components[1].hasPrefix("/"),
              let callbackURL = URL(string: redirectURI + String(components[1])) else {
            throw AppError.api("Microsoft sign-in returned an invalid local callback.")
        }
        return callbackURL
    }

    private func sendResponse(to descriptor: Int32, succeeded: Bool) {
        let title = succeeded ? "Microsoft sign-in completed" : "Microsoft sign-in did not complete"
        let message = succeeded
            ? "Return to Lazyest Work. You can close this tab."
            : "Return to Lazyest Work for the detailed error."
        let body = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
        </head>
        <body>
          <main>
            <h1>\(title)</h1>
            <p>\(message)</p>
          </main>
        </body>
        </html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r
        Cache-Control: no-store\r
        Connection: close\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        let responseData = Data(response.utf8)
        responseData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    private func closeListener() {
        descriptorLock.lock()
        guard !isClosed else {
            descriptorLock.unlock()
            return
        }
        isClosed = true
        Darwin.close(descriptor)
        descriptorLock.unlock()
    }
}

actor MicrosoftTokenStore {
    private let service = "com.lazyest.work.microsoft-graph"
    private let account = "tokens"

    func load() throws -> MicrosoftTokenSet? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppError.keychain("read Microsoft credentials", status)
        }
        guard let data = item as? Data else {
            throw AppError.invalidResponse
        }
        return try JSONDecoder().decode(MicrosoftTokenSet.self, from: data)
    }

    func save(_ tokenSet: MicrosoftTokenSet) throws {
        let data = try JSONEncoder().encode(tokenSet)
        let query = baseQuery()
        let attributes = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ] as [String: Any]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AppError.keychain("update Microsoft credentials", updateStatus)
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppError.keychain("save Microsoft credentials", addStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychain("delete Microsoft credentials", status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

@MainActor
final class MicrosoftGraphAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let authWindow: AuthWindow
    private let tokenStore = MicrosoftTokenStore()
    private var config = MicrosoftSetupSettings.load()
    private var currentSession: ASWebAuthenticationSession?
    private let scopes = ["offline_access", "User.Read", "Presence.ReadWrite"]
    /// Token endpoint errors that only a fresh interactive sign-in can clear.
    private static let reauthenticationErrorCodes: Set<String> = [
        "invalid_grant",
        "interaction_required",
        "login_required",
        "consent_required"
    ]

    init(authWindow: AuthWindow) {
        self.authWindow = authWindow
    }

    func configure(_ config: MicrosoftSetupConfig) {
        self.config = config
    }

    func connectionState() async -> MicrosoftConnectionState {
        guard let normalized = try? config.normalized() else {
            return .missingSetup
        }
        guard let tokenSet = try? await tokenStore.load(),
              tokenMatchesConfiguration(tokenSet, config: normalized) else {
            return .signedOut
        }
        return .connected(account: tokenSet.accountName)
    }

    func signIn(config: MicrosoftSetupConfig) async throws {
        let normalized = try config.normalized()
        configure(normalized)

        let verifier = PKCE.randomVerifier()
        let state = UUID().uuidString
        let grant = try await authorizationGrant(verifier: verifier, state: state, config: normalized)
        var tokenSet = try await exchangeCode(grant, verifier: verifier, config: normalized)
        let profile = try await fetchProfile(accessToken: tokenSet.accessToken)
        tokenSet.accountName = profile.userPrincipalName ?? profile.displayName
        tokenSet.userID = profile.id
        tokenSet.clientID = normalized.clientID
        tokenSet.tenantID = normalized.tenantID
        try await tokenStore.save(tokenSet)
    }

    func accessToken() async throws -> String {
        let normalized = try config.normalized()
        guard var tokenSet = try await tokenStore.load(),
              tokenMatchesConfiguration(tokenSet, config: normalized) else {
            throw AppError.microsoftNotSignedIn
        }
        if tokenSet.hasValidAccessToken() {
            return tokenSet.accessToken
        }

        do {
            tokenSet = try await refresh(tokenSet, config: normalized)
        } catch AppError.microsoftNotSignedIn {
            // The stored credential is dead. Dropping it moves the account to
            // signed out so the user is asked to reconnect, instead of leaving
            // a connection that reads as live and fails on every use.
            try? await tokenStore.clear()
            throw AppError.microsoftNotSignedIn
        }
        try await tokenStore.save(tokenSet)
        return tokenSet.accessToken
    }

    func graphUserID() async throws -> String {
        let normalized = try config.normalized()
        guard var tokenSet = try await tokenStore.load(),
              tokenMatchesConfiguration(tokenSet, config: normalized) else {
            throw AppError.microsoftNotSignedIn
        }
        if let userID = tokenSet.userID?.nilIfBlank {
            return userID
        }

        let accessToken = try await accessToken()
        let profile = try await fetchProfile(accessToken: accessToken)
        tokenSet.userID = profile.id
        tokenSet.accountName = profile.userPrincipalName ?? profile.displayName ?? tokenSet.accountName
        try await tokenStore.save(tokenSet)
        return profile.id
    }

    func signOut() async throws {
        try await tokenStore.clear()
    }

    func handle(url: URL) -> Bool {
        url.scheme == MicrosoftSetupConfig.redirectScheme
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        authWindow.present(message: "Sign in with Microsoft to update Teams status.")
    }

    private func authorizationGrant(
        verifier: String,
        state: String,
        config: MicrosoftSetupConfig
    ) async throws -> MicrosoftAuthorizationGrant {
        if config.usesLoopbackRedirect {
            return try await loopbackAuthorizationGrant(verifier: verifier, state: state, config: config)
        }

        let redirectURI = MicrosoftSetupConfig.redirectURI
        let authURL = try authorizationURL(
            verifier: verifier,
            state: state,
            redirectURI: redirectURI,
            config: config
        )
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: MicrosoftSetupConfig.redirectScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.currentSession = nil
                    self?.authWindow.hide()
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AppError.microsoftNotSignedIn)
                    return
                }
                do {
                    continuation.resume(
                        returning: MicrosoftAuthorizationGrant(
                            code: try Self.authorizationCode(from: callbackURL, expectedState: state),
                            redirectURI: redirectURI
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            if !session.start() {
                currentSession = nil
                continuation.resume(throwing: AppError.api("Microsoft sign-in could not start."))
            }
        }
    }

    private func loopbackAuthorizationGrant(
        verifier: String,
        state: String,
        config: MicrosoftSetupConfig
    ) async throws -> MicrosoftAuthorizationGrant {
        let server = try MicrosoftOAuthLoopbackServer()
        let authURL = try authorizationURL(
            verifier: verifier,
            state: state,
            redirectURI: server.redirectURI,
            config: config
        )

        _ = authWindow.present(message: "Complete Microsoft sign-in in your browser.")
        defer { authWindow.hide() }
        guard NSWorkspace.shared.open(authURL) else {
            throw AppError.api("Microsoft sign-in could not open your browser.")
        }

        let callbackURL = try await server.waitForCallback(expectedState: state)
        return MicrosoftAuthorizationGrant(
            code: try Self.authorizationCode(from: callbackURL, expectedState: state),
            redirectURI: server.redirectURI
        )
    }

    private func authorizationURL(
        verifier: String,
        state: String,
        redirectURI: String,
        config: MicrosoftSetupConfig
    ) throws -> URL {
        var components = URLComponents(string: "https://login.microsoftonline.com/\(config.tenantID)/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = components.url else {
            throw AppError.invalidResponse
        }
        return url
    }

    private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidResponse
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value
            throw AppError.api(
                "Microsoft sign-in failed: " +
                    [error, description].compactMap(\.self).joined(separator: ": ")
            )
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw AppError.api("Microsoft sign-in returned an invalid state.")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value?.nilIfBlank else {
            throw AppError.api("Microsoft sign-in did not return an authorization code.")
        }
        return code
    }

    private func exchangeCode(
        _ grant: MicrosoftAuthorizationGrant,
        verifier: String,
        config: MicrosoftSetupConfig
    ) async throws -> MicrosoftTokenSet {
        let response: MicrosoftTokenResponse = try await tokenRequest(
            parameters: [
                "client_id": config.clientID,
                "scope": scopes.joined(separator: " "),
                "code": grant.code,
                "redirect_uri": grant.redirectURI,
                "grant_type": "authorization_code",
                "code_verifier": verifier
            ],
            tenantID: config.tenantID
        )
        guard let refreshToken = response.refreshToken?.nilIfBlank else {
            throw AppError.api("Microsoft did not return a refresh token.")
        }
        return MicrosoftTokenSet(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            accountName: nil,
            userID: nil,
            clientID: config.clientID,
            tenantID: config.tenantID
        )
    }

    private func refresh(
        _ tokenSet: MicrosoftTokenSet,
        config: MicrosoftSetupConfig
    ) async throws -> MicrosoftTokenSet {
        let response: MicrosoftTokenResponse = try await tokenRequest(
            parameters: [
                "client_id": config.clientID,
                "scope": scopes.joined(separator: " "),
                "refresh_token": tokenSet.refreshToken,
                "grant_type": "refresh_token"
            ],
            tenantID: config.tenantID
        )
        return MicrosoftTokenSet(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken?.nilIfBlank ?? tokenSet.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            accountName: tokenSet.accountName,
            userID: tokenSet.userID,
            clientID: config.clientID,
            tenantID: config.tenantID
        )
    }

    private func tokenMatchesConfiguration(
        _ tokenSet: MicrosoftTokenSet,
        config: MicrosoftSetupConfig
    ) -> Bool {
        // A token without its issuing client and tenant cannot be proven to
        // belong to the active setup. Require both values rather than accepting
        // an unbound credential after configuration or tenant changes.
        guard let tokenClientID = tokenSet.clientID,
              let tokenTenantID = tokenSet.tenantID else {
            return false
        }
        return tokenClientID.caseInsensitiveCompare(config.clientID) == .orderedSame &&
            tokenTenantID.caseInsensitiveCompare(config.tenantID) == .orderedSame
    }

    private func tokenRequest<T: Decodable>(parameters: [String: String], tenantID: String) async throws -> T {
        let url = URL(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.formURLEncodedData()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let failure = try? JSONDecoder().decode(
                MicrosoftTokenErrorResponse.self,
                from: data
            ) {
                // A revoked or expired refresh token never recovers on retry,
                // so it has to be told apart from a transient failure. Reported
                // as a generic error it leaves the account reading as connected
                // while every presence update silently fails.
                if Self.reauthenticationErrorCodes.contains(failure.error) {
                    throw AppError.microsoftNotSignedIn
                }
                throw AppError.api(
                    "Microsoft token request failed: \(failure.errorDescription?.nilIfBlank ?? failure.error)"
                )
            }
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.api("Microsoft token request failed: \(body)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchProfile(accessToken: String) async throws -> MicrosoftProfile {
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me")!
        components.queryItems = [
            URLQueryItem(name: "$select", value: "id,displayName,userPrincipalName")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.api("Microsoft profile request failed: \(body)")
        }
        return try JSONDecoder().decode(MicrosoftProfile.self, from: data)
    }
}

struct MicrosoftProfile: Decodable {
    let id: String
    let displayName: String?
    let userPrincipalName: String?
}

struct MicrosoftPresence: Decodable, Equatable {
    let availability: String?
    let activity: String?

    var isPreferredBusy: Bool {
        availability == "Busy" && activity == "Busy"
    }
}

enum TeamsPresenceApplyResult: Equatable {
    case idle
    case alreadyActive(until: Date)
    case applied(until: Date)
    case cleared
    case pausedForManualOverride(eventID: String)
}

@MainActor
final class MicrosoftTeamsPresenceService {
    private let authClient: MicrosoftGraphAuthClient
    private let cliClient: Microsoft365CLIClient
    private let managedSessionKey = "teamsPresenceManagedSession"
    private let pausedEventIDKey = "teamsPresencePausedEventID"
    private let lastPresenceVerificationKey = "teamsPresenceLastVerificationAt"

    init(authClient: MicrosoftGraphAuthClient, cliClient: Microsoft365CLIClient) {
        self.authClient = authClient
        self.cliClient = cliClient
    }

    func apply(_ state: MeetingFocusState, now: Date) async throws -> TeamsPresenceApplyResult {
        switch state {
        case .active(let end, let eventID):
            return try await setBusyIfNeeded(until: end, eventID: eventID, now: now)
        case .inactive:
            let hadManagedSession = loadManagedSession(UserDefaults.standard) != nil
            try await clearManagedPresenceIfNeeded()
            clearPausedEvent(UserDefaults.standard)
            return hadManagedSession ? .cleared : .idle
        }
    }

    func clearManagedPresenceIfNeeded() async throws {
        let defaults = UserDefaults.standard
        guard let session = loadManagedSession(defaults) else {
            return
        }

        do {
            if usesNativeGraphAuth {
                let accessToken = try await authClient.accessToken()
                try await postPresenceAction(
                    path: "/users/\(session.userID.pathSegmentEncoded)/presence/clearUserPreferredPresence",
                    accessToken: accessToken,
                    body: [:]
                )
            } else {
                try await cliClient.clearPreferredPresence(userID: session.userID)
            }
        } catch {
            if !isMissingPresenceSession(error) {
                throw error
            }
        }
        clearManagedState(defaults)
    }

    func clearCurrentPreferredPresence() async throws {
        let defaults = UserDefaults.standard
        let userID: String
        if let session = loadManagedSession(defaults) {
            userID = session.userID
        } else if usesNativeGraphAuth {
            userID = try await authClient.graphUserID()
        } else {
            userID = try await cliClient.profile().id
        }

        do {
            if usesNativeGraphAuth {
                let accessToken = try await authClient.accessToken()
                try await postPresenceAction(
                    path: "/users/\(userID.pathSegmentEncoded)/presence/clearUserPreferredPresence",
                    accessToken: accessToken,
                    body: [:]
                )
            } else {
                try await cliClient.clearPreferredPresence(userID: userID)
            }
        } catch {
            if !isMissingPresenceSession(error) {
                throw error
            }
        }
        clearManagedState(defaults)
    }

    /// True while a Busy set by this app is still recorded as ours, whether or
    /// not Microsoft is currently connected.
    var hasManagedSession: Bool {
        loadManagedSession(UserDefaults.standard) != nil
    }

    func clearLocalManagedState() {
        let defaults = UserDefaults.standard
        clearManagedState(defaults)
        clearPausedEvent(defaults)
    }

    /// A saved managed session belongs to the Microsoft directory user that
    /// created it. Keep it when reconnecting the same account so a failed clear
    /// can retry, but never carry it into another account or an identity we
    /// cannot verify.
    func reconcileManagedStateWithCurrentAccount() async {
        let defaults = UserDefaults.standard
        guard let session = loadManagedSession(defaults) else {
            return
        }

        guard let currentUserID = try? await authClient.graphUserID(),
              currentUserID.caseInsensitiveCompare(session.userID) == .orderedSame else {
            clearManagedState(defaults)
            clearPausedEvent(defaults)
            return
        }
    }

    private func setBusyIfNeeded(
        until end: Date,
        eventID: String,
        now: Date
    ) async throws -> TeamsPresenceApplyResult {
        let defaults = UserDefaults.standard
        let managedSession = loadManagedSession(defaults)
        if pausedEventID(defaults) == eventID {
            return .pausedForManualOverride(eventID: eventID)
        } else if pausedEventID(defaults) != nil {
            clearPausedEvent(defaults)
        }

        if let managedSession,
           managedSession.eventID == eventID,
           managedSession.expiresAt > now,
           shouldVerifyCurrentPresence(defaults: defaults, now: now) {
            let presence = try await currentPresence()
            defaults.set(now, forKey: lastPresenceVerificationKey)
            if !presence.isPreferredBusy {
                savePausedEvent(eventID, defaults)
                clearManagedState(defaults)
                return .pausedForManualOverride(eventID: eventID)
            }
        }

        guard TeamsPresencePolicy.shouldRefreshManagedPresence(
            eventID: eventID,
            managedSession: managedSession,
            now: now
        ) else {
            return managedSession.map { .alreadyActive(until: $0.expiresAt) } ?? .idle
        }

        let request = TeamsPresencePolicy.preferredPresenceRequest(until: end, now: now)
        let userID: String
        if usesNativeGraphAuth {
            let accessToken = try await authClient.accessToken()
            userID = try await authClient.graphUserID()
            try await postPresenceAction(
                path: "/users/\(userID.pathSegmentEncoded)/presence/setUserPreferredPresence",
                accessToken: accessToken,
                body: [
                    "availability": request.availability,
                    "activity": request.activity,
                    "expirationDuration": request.expirationDuration
                ]
            )
        } else {
            let profile = try await cliClient.profile()
            userID = profile.id
            try await cliClient.setPreferredPresence(userID: userID, request: request)
        }
        saveManagedSession(
            TeamsPresencePolicy.managedSession(eventID: eventID, request: request, userID: userID),
            defaults
        )
        defaults.set(now, forKey: lastPresenceVerificationKey)
        return .applied(until: request.expiresAt)
    }

    private func postPresenceAction(path: String, accessToken: String, body: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.api("Microsoft Graph presence failed (\(http.statusCode)): \(body)")
        }
    }

    private func currentPresence() async throws -> MicrosoftPresence {
        if usesNativeGraphAuth {
            let accessToken = try await authClient.accessToken()
            var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/presence")!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw AppError.api("Microsoft Graph presence read failed (\(http.statusCode)): \(body)")
            }
            return try JSONDecoder().decode(MicrosoftPresence.self, from: data)
        }
        return try await cliClient.currentPresence()
    }

    private func isMissingPresenceSession(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("404") ||
            error.localizedDescription.localizedCaseInsensitiveContains("notfound")
    }

    private var usesNativeGraphAuth: Bool {
        MicrosoftSetupSettings.load().isComplete
    }

    private func clearManagedState(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: managedSessionKey)
        defaults.removeObject(forKey: lastPresenceVerificationKey)
    }

    private func shouldVerifyCurrentPresence(defaults: UserDefaults, now: Date) -> Bool {
        guard let lastVerifiedAt = defaults.object(forKey: lastPresenceVerificationKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastVerifiedAt) >= 300
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

    private func loadManagedSession(_ defaults: UserDefaults) -> TeamsManagedPresenceSession? {
        guard let data = defaults.data(forKey: managedSessionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(TeamsManagedPresenceSession.self, from: data)
    }

    private func saveManagedSession(_ session: TeamsManagedPresenceSession, _ defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(session) else {
            return
        }
        defaults.set(data, forKey: managedSessionKey)
    }
}

extension Bundle {
    var microsoftClientID: String? {
        guard let value = object(forInfoDictionaryKey: "GWSMicrosoftClientID") as? String,
              let trimmed = value.nilIfBlank,
              !trimmed.contains("YOUR_MICROSOFT_CLIENT_ID") else {
            return nil
        }
        return trimmed
    }

    var microsoftTenantID: String? {
        guard let value = object(forInfoDictionaryKey: "GWSMicrosoftTenantID") as? String,
              let trimmed = value.nilIfBlank else {
            return nil
        }
        return trimmed
    }
}

extension Dictionary where Key == String, Value == String {
    func formURLEncodedData() -> Data {
        let encoded = map { key, value in
            "\(key.formURLEncoded)=\(value.formURLEncoded)"
        }
        .joined(separator: "&")
        return Data(encoded.utf8)
    }
}

private extension String {
    var formURLEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

enum PKCE {
    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        if status != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64URLString()
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLString()
    }
}

extension Data {
    func base64URLString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
