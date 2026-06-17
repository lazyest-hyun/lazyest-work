import AuthenticationServices
import AppKit
import CryptoKit
import Foundation
import GWSMenuCore
import Security

struct MicrosoftSetupConfig: Equatable {
    static let defaultTenantID = "organizations"
    static let redirectScheme = "gwsmenu"
    static let redirectURI = "gwsmenu://microsoft-auth"

    var clientID: String
    var tenantID: String

    var isComplete: Bool {
        clientID.nilIfBlank != nil && tenantID.nilIfBlank != nil
    }

    static func normalized(clientID: String, tenantID: String) throws -> MicrosoftSetupConfig {
        if containsClientSecret(in: clientID) || containsClientSecret(in: tenantID) {
            throw MicrosoftSetupError.clientSecretNotSupported
        }

        let normalizedClientID = extractedClientID(from: clientID) ?? clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidClientID(normalizedClientID) else {
            throw MicrosoftSetupError.invalidClientID
        }

        let normalizedTenantID = tenantID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? defaultTenantID
        guard isValidTenantID(normalizedTenantID) else {
            throw MicrosoftSetupError.invalidTenantID
        }

        return MicrosoftSetupConfig(clientID: normalizedClientID, tenantID: normalizedTenantID)
    }

    static func containsClientSecret(in input: String) -> Bool {
        input.range(of: "client_secret", options: .caseInsensitive) != nil ||
            input.range(of: "client secret", options: .caseInsensitive) != nil ||
            input.range(of: "secretText", options: .caseInsensitive) != nil
    }

    static func extractedClientID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isValidClientID(trimmed) {
            return trimmed
        }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let value = firstClientIDValue(in: json) {
            return value
        }

        return firstClientIDMatch(in: trimmed)
    }

    private static func firstClientIDValue(in object: Any) -> String? {
        if let string = object as? String, isValidClientID(string) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let dictionary = object as? [String: Any] {
            for key in ["client_id", "clientId", "appId", "applicationId"] {
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
        return isValidClientID(value) ? value : nil
    }

    private static func isValidClientID(_ value: String) -> Bool {
        UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
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
    case invalidClientID
    case invalidTenantID
    case clientSecretNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidClientID:
            return "Paste the Microsoft Entra Application (client) ID. It should look like a UUID."
        case .invalidTenantID:
            return "Use organizations, a tenant ID, or a tenant domain."
        case .clientSecretNotSupported:
            return "GWS Menu is a public native app. Do not paste a Microsoft client secret."
        }
    }
}

enum MicrosoftSetupSettings {
    private static let clientIDKey = "microsoftClientID"
    private static let tenantIDKey = "microsoftTenantID"

    static func load() -> MicrosoftSetupConfig {
        MicrosoftSetupConfig(
            clientID: UserDefaults.standard.string(forKey: clientIDKey) ?? "",
            tenantID: UserDefaults.standard.string(forKey: tenantIDKey) ?? MicrosoftSetupConfig.defaultTenantID
        )
    }

    static func save(_ config: MicrosoftSetupConfig) {
        UserDefaults.standard.set(config.clientID, forKey: clientIDKey)
        UserDefaults.standard.set(config.tenantID, forKey: tenantIDKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: clientIDKey)
        UserDefaults.standard.removeObject(forKey: tenantIDKey)
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
            return "Microsoft setup needed"
        case .signedOut:
            return "Not connected"
        case .connected(let account):
            return account ?? "Connected"
        }
    }
}

struct MicrosoftTokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountName: String?
    var userID: String?

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

final class MicrosoftTokenStore {
    private let service = "io.github.gwsmenu.microsoft-graph"
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

    init(authWindow: AuthWindow) {
        self.authWindow = authWindow
    }

    func configure(_ config: MicrosoftSetupConfig) {
        self.config = config
    }

    func connectionState() -> MicrosoftConnectionState {
        guard config.isComplete else {
            return .missingSetup
        }
        guard let tokenSet = try? tokenStore.load() else {
            return .signedOut
        }
        return .connected(account: tokenSet.accountName)
    }

    func signIn(config: MicrosoftSetupConfig) async throws {
        configure(config)
        guard config.isComplete else {
            throw MicrosoftSetupError.invalidClientID
        }

        let verifier = PKCE.randomVerifier()
        let state = UUID().uuidString
        let code = try await authorizationCode(verifier: verifier, state: state, config: config)
        var tokenSet = try await exchangeCode(code, verifier: verifier, config: config)
        let profile = try await fetchProfile(accessToken: tokenSet.accessToken)
        tokenSet.accountName = profile.userPrincipalName ?? profile.displayName
        tokenSet.userID = profile.id
        try tokenStore.save(tokenSet)
    }

    func accessToken() async throws -> String {
        guard config.isComplete else {
            throw MicrosoftSetupError.invalidClientID
        }
        guard var tokenSet = try tokenStore.load() else {
            throw AppError.microsoftNotSignedIn
        }
        if tokenSet.hasValidAccessToken() {
            return tokenSet.accessToken
        }

        tokenSet = try await refresh(tokenSet, config: config)
        try tokenStore.save(tokenSet)
        return tokenSet.accessToken
    }

    func graphUserID() async throws -> String {
        guard var tokenSet = try tokenStore.load() else {
            throw AppError.microsoftNotSignedIn
        }
        if let userID = tokenSet.userID?.nilIfBlank {
            return userID
        }

        let accessToken = try await accessToken()
        let profile = try await fetchProfile(accessToken: accessToken)
        tokenSet.userID = profile.id
        tokenSet.accountName = profile.userPrincipalName ?? profile.displayName ?? tokenSet.accountName
        try tokenStore.save(tokenSet)
        return profile.id
    }

    func signOut() throws {
        try tokenStore.clear()
    }

    func handle(url: URL) -> Bool {
        url.scheme == MicrosoftSetupConfig.redirectScheme
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        authWindow.present(message: "Sign in with Microsoft to update Teams status.")
    }

    private func authorizationCode(
        verifier: String,
        state: String,
        config: MicrosoftSetupConfig
    ) async throws -> String {
        let authURL = try authorizationURL(verifier: verifier, state: state, config: config)
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
                    continuation.resume(returning: try Self.authorizationCode(from: callbackURL, expectedState: state))
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

    private func authorizationURL(
        verifier: String,
        state: String,
        config: MicrosoftSetupConfig
    ) throws -> URL {
        var components = URLComponents(string: "https://login.microsoftonline.com/\(config.tenantID)/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: MicrosoftSetupConfig.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
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
            throw AppError.api([error, description].compactMap(\.self).joined(separator: ": "))
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
        _ code: String,
        verifier: String,
        config: MicrosoftSetupConfig
    ) async throws -> MicrosoftTokenSet {
        let response: MicrosoftTokenResponse = try await tokenRequest(
            parameters: [
                "client_id": config.clientID,
                "scope": scopes.joined(separator: " "),
                "code": code,
                "redirect_uri": MicrosoftSetupConfig.redirectURI,
                "grant_type": "authorization_code",
                "code_verifier": verifier
            ],
            tenantID: config.tenantID
        )
        guard let refreshToken = response.refreshToken?.nilIfBlank else {
            throw AppError.api("Microsoft did not return a refresh token. Check that offline_access is allowed.")
        }
        return MicrosoftTokenSet(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            accountName: nil,
            userID: nil
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
            userID: tokenSet.userID
        )
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

@MainActor
final class MicrosoftTeamsPresenceService {
    private let authClient: MicrosoftGraphAuthClient
    private let managedSessionKey = "teamsPresenceManagedSession"

    init(authClient: MicrosoftGraphAuthClient) {
        self.authClient = authClient
    }

    func apply(_ state: MeetingFocusState, now: Date) async throws {
        switch state {
        case .active(let end, let eventID):
            try await setBusyIfNeeded(until: end, eventID: eventID, now: now)
        case .inactive:
            try await clearManagedPresenceIfNeeded()
        }
    }

    func clearManagedPresenceIfNeeded() async throws {
        let defaults = UserDefaults.standard
        guard let session = loadManagedSession(defaults) else {
            return
        }

        do {
            let accessToken = try await authClient.accessToken()
            try await postPresenceAction(
                path: "/users/\(session.userID.pathSegmentEncoded)/presence/clearPresence",
                accessToken: accessToken,
                body: ["sessionId": session.sessionID]
            )
        } catch {
            if !isMissingPresenceSession(error) {
                throw error
            }
        }
        clearManagedState(defaults)
    }

    func clearLocalManagedState() {
        clearManagedState(UserDefaults.standard)
    }

    private func setBusyIfNeeded(until end: Date, eventID: String, now: Date) async throws {
        let defaults = UserDefaults.standard
        let managedSession = loadManagedSession(defaults)
        guard TeamsPresencePolicy.shouldRefreshManagedPresence(
            eventID: eventID,
            managedSession: managedSession,
            now: now
        ) else {
            return
        }

        let config = MicrosoftSetupSettings.load()
        let request = TeamsPresencePolicy.setPresenceRequest(sessionID: config.clientID, until: end, now: now)
        let accessToken = try await authClient.accessToken()
        let userID = try await authClient.graphUserID()
        try await postPresenceAction(
            path: "/users/\(userID.pathSegmentEncoded)/presence/setPresence",
            accessToken: accessToken,
            body: [
                "sessionId": request.sessionID,
                "availability": request.availability,
                "activity": request.activity,
                "expirationDuration": request.expirationDuration
            ]
        )
        saveManagedSession(
            TeamsPresencePolicy.managedSession(eventID: eventID, request: request, userID: userID),
            defaults
        )
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

    private func isMissingPresenceSession(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("404") ||
            error.localizedDescription.localizedCaseInsensitiveContains("notfound")
    }

    private func clearManagedState(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: managedSessionKey)
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
