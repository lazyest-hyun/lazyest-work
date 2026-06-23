import AuthenticationServices
import AppKit
import CryptoKit
import Foundation
import GWSMenuCore
import Security

struct MicrosoftSetupConfig: Equatable {
    static let defaultTenantID = "organizations"
    static let defaultBundleID = "io.github.gwsmenu.app"

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

    var isComplete: Bool {
        (try? Self.normalized(clientID: clientID, tenantID: tenantID)) != nil
    }

    static func normalized(clientID: String, tenantID: String) throws -> MicrosoftSetupConfig {
        let normalizedClientID = extractedClientID(from: clientID) ?? clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: normalizedClientID) != nil else {
            throw MicrosoftSetupError.missingBundleConfig
        }

        let normalizedTenantID = tenantID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? defaultTenantID
        guard isValidTenantID(normalizedTenantID) else {
            throw MicrosoftSetupError.missingBundleConfig
        }

        return MicrosoftSetupConfig(clientID: normalizedClientID, tenantID: normalizedTenantID)
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
    static func load() -> MicrosoftSetupConfig {
        MicrosoftSetupConfig(
            clientID: Bundle.main.microsoftClientID ?? "",
            tenantID: Bundle.main.microsoftTenantID ?? MicrosoftSetupConfig.defaultTenantID
        )
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
            return "Not configured in this build"
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
        guard (try? MicrosoftSetupConfig.normalized(clientID: config.clientID, tenantID: config.tenantID)) != nil else {
            return .missingSetup
        }
        guard let tokenSet = try? tokenStore.load() else {
            return .signedOut
        }
        return .connected(account: tokenSet.accountName)
    }

    func signIn(config: MicrosoftSetupConfig) async throws {
        let normalized = try MicrosoftSetupConfig.normalized(clientID: config.clientID, tenantID: config.tenantID)
        configure(normalized)

        let verifier = PKCE.randomVerifier()
        let state = UUID().uuidString
        let code = try await authorizationCode(verifier: verifier, state: state, config: normalized)
        var tokenSet = try await exchangeCode(code, verifier: verifier, config: normalized)
        let profile = try await fetchProfile(accessToken: tokenSet.accessToken)
        tokenSet.accountName = profile.userPrincipalName ?? profile.displayName
        tokenSet.userID = profile.id
        try tokenStore.save(tokenSet)
    }

    func accessToken() async throws -> String {
        let normalized = try MicrosoftSetupConfig.normalized(clientID: config.clientID, tenantID: config.tenantID)
        guard var tokenSet = try tokenStore.load() else {
            throw AppError.microsoftNotSignedIn
        }
        if tokenSet.hasValidAccessToken() {
            return tokenSet.accessToken
        }

        tokenSet = try await refresh(tokenSet, config: normalized)
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
            throw AppError.api("Microsoft did not return a refresh token.")
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

    func clearLocalManagedState() {
        clearManagedState(UserDefaults.standard)
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
           managedSession.expiresAt > now {
            let presence = try await currentPresence()
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
