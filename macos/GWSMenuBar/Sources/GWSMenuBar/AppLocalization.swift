import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .korean:
            return "한국어"
        case .english:
            return "English"
        }
    }
}

enum AppLanguageSettings {
    private static let languageKey = "appLanguage"

    static func load() -> AppLanguage {
        if let value = UserDefaults.standard.string(forKey: languageKey),
           let language = AppLanguage(rawValue: value) {
            return language
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("ko") ? .korean : .english
    }

    static func save(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }
}

struct AppText {
    let language: AppLanguage

    func s(_ english: String, _ korean: String) -> String {
        language == .korean ? korean : english
    }

    var settings: String { s("Settings", "설정") }
    var back: String { s("Back", "뒤로") }
    var general: String { s("General", "일반") }
    var languageLabel: String { s("Language", "언어") }
    var languageSubtitle: String { s("Choose the app display language.", "앱 표시 언어를 선택합니다.") }
    var openAtLogin: String { s("Open at login", "로그인 시 열기") }
    var openAtLoginSubtitle: String { s("Start GWS Menu when you sign in to macOS.", "macOS 로그인 시 GWS Menu를 시작합니다.") }
    var githubRepository: String { s("GitHub repository", "GitHub 저장소") }
    var githubRepositorySubtitle: String { s("Open releases, issues, and source updates.", "릴리스, 이슈, 소스 업데이트를 엽니다.") }
    var open: String { s("Open", "열기") }
    var calendar: String { s("Calendar", "캘린더") }
    var desktopAlerts: String { s("Desktop alerts", "데스크톱 알림") }
    var desktopAlertsSubtitle: String { s("Use macOS Notifications for meeting reminders.", "회의 리마인더에 macOS 알림을 사용합니다.") }
    var meetingAlert: String { s("Meeting alert", "회의 알림") }
    var testAlert: String { s("Test alert", "테스트 알림") }
    var testAlertSubtitle: String { s("Send a sample macOS meeting notification.", "macOS 회의 알림 샘플을 보냅니다.") }
    var send: String { s("Send", "보내기") }
    var doNotDisturbDuringMeetings: String { s("Do Not Disturb during meetings", "회의 중 방해금지") }
    var dndApprovalNeeded: String { s("Approval needed. Click Approve once, then Add Shortcut.", "승인이 필요합니다. 승인 후 macOS에서 단축어 추가를 한 번 누르세요.") }
    var dndSubtitle: String { s("Turns on Do Not Disturb only for accepted meetings. Existing approval is reused.", "수락한 회의 중에만 방해금지를 켭니다. 기존 승인은 재사용됩니다.") }
    var dndPausedSubtitle: String { s("Paused for this meeting because Do Not Disturb was changed manually.", "방해금지를 직접 변경해서 이 회의 동안 자동화를 멈췄습니다.") }
    var approve: String { s("Approve", "승인") }
    var approveHelp: String { s("Open macOS Shortcuts approval", "macOS 단축어 승인을 엽니다") }
    var notificationSettings: String { s("Notification settings", "알림 설정") }
    var notificationSettingsSubtitle: String { s("Open this app's macOS notification controls.", "이 앱의 macOS 알림 설정을 엽니다.") }
    var teamsCallBlock: String { s("Teams call block", "Teams 통화 차단") }
    var teamsCallBlockHelp: String { s("Ask before Teams call buttons and block Control-scroll zoom", "Teams 통화 버튼 확인 및 Control-스크롤 확대 차단") }
    var teamsStatus: String { s("Teams status", "Teams 상태") }
    var mail: String { s("Mail", "메일") }
    var inboxUnreadBadge: String { s("Inbox unread badge", "받은편지함 안 읽음 배지") }
    var inboxUnreadBadgeSubtitle: String { s("Shows Gmail unread count. Refreshes faster after opening Gmail.", "Gmail 안 읽음 개수를 표시합니다. Gmail을 연 뒤 잠시 더 빠르게 갱신합니다.") }
    var account: String { s("Account", "계정") }
    var googleAccount: String { s("Google account", "Google 계정") }
    var signOut: String { s("Sign Out", "로그아웃") }
    var googleSetup: String { s("Google setup", "Google 설정") }
    var resetGoogleSetup: String { s("Reset Google setup", "Google 설정 초기화") }
    var resetGoogleSetupSubtitle: String { s("Remove saved setup values and start over.", "저장된 설정 값을 제거하고 다시 시작합니다.") }
    var reset: String { s("Reset", "초기화") }
    var cancel: String { s("Cancel", "취소") }
    var resetGoogleSetupQuestion: String { s("Reset Google setup?", "Google 설정을 초기화할까요?") }
    var resetGoogleSetupMessage: String {
        s(
            "This signs out, revokes the saved Google grant if possible, removes the Client ID and URL scheme from this app, then restarts GWS Menu. You will need Open Setup again.",
            "로그아웃하고 가능한 경우 저장된 Google 권한을 회수한 뒤, 이 앱에서 Client ID와 URL scheme을 제거하고 GWS Menu를 재시작합니다. 이후 Open Setup을 다시 해야 합니다."
        )
    }

    var teamsCLIUnavailable: String { s("Microsoft 365 CLI is not available.", "Microsoft 365 CLI를 사용할 수 없습니다.") }
    var teamsConnectOnce: String { s("Connect once with Microsoft CLI.", "Microsoft CLI로 한 번 연결하세요.") }
    var teamsConnectMicrosoft: String { s("Connect Microsoft", "Microsoft 연결") }
    var teamsConnectBeforeEnable: String { s("Connect Microsoft before enabling Teams Busy", "Teams Busy를 켜기 전에 Microsoft를 연결하세요") }
    var teamsBusyHelp: String { s("Set Teams Busy during accepted meetings", "수락한 회의 중 Teams를 Busy로 설정합니다") }
    var teamsInstallCLIHelp: String { s("Install Node.js/npm or m365 CLI for Teams Busy", "Teams Busy를 사용하려면 Node.js/npm 또는 m365 CLI가 필요합니다") }
    var teamsManualPause: String { s("Paused for this meeting because Teams status was changed manually.", "Teams 상태를 직접 변경해서 이 회의 동안 자동화를 멈췄습니다.") }

    var callConfirmTitle: String { s("Start Teams call?", "Teams 통화를 시작할까요?") }
    var callConfirmMessage: String {
        s(
            "GWS Menu blocked an accidental click. Continue to run the Teams call button once.",
            "GWS Menu가 실수 클릭을 막았습니다. 계속하면 방금 누른 Teams 통화 버튼을 한 번 실행합니다."
        )
    }
    var callConfirmAction: String { s("Start call", "통화 시작") }

    func connectedMicrosoft(_ account: String?) -> String {
        s("Connected: \(account ?? "Microsoft").", "연결됨: \(account ?? "Microsoft").")
    }

    func minutesBefore(_ minutes: Int) -> String {
        if language == .korean {
            return "\(minutes)분 전"
        }
        return minutes == 1 ? "1 minute before" : "\(minutes) minutes before"
    }

    func shortMinutesBefore(_ minutes: Int) -> String {
        language == .korean ? "\(minutes)분 전" : "\(minutes)m before"
    }

    func localizedCallBlockStatus(_ status: String) -> String {
        guard language == .korean else { return status }
        switch status {
        case "Off. Turn on to confirm Teams calls and block Teams Control-scroll.":
            return "꺼짐. Teams 통화 확인과 Control-스크롤 차단을 켤 수 있습니다."
        case "Off. Accessibility permission is needed before Teams calls can be blocked.":
            return "꺼짐. Teams 통화를 차단하려면 손쉬운 사용 권한이 필요합니다."
        case "Off. Input Monitoring permission is needed before Teams events can be watched.":
            return "꺼짐. Teams 이벤트를 감시하려면 입력 모니터링 권한이 필요합니다."
        case "On. Teams calls require confirmation; Control-scroll is blocked in Teams.":
            return "켜짐. Teams 통화는 확인 후 실행되고 Control-스크롤은 차단됩니다."
        case "Off. Accessibility permission is not detected for GWS Menu.":
            return "꺼짐. GWS Menu의 손쉬운 사용 권한이 감지되지 않았습니다."
        case "Off. Input Monitoring is not detected for GWS Menu.":
            return "꺼짐. GWS Menu의 입력 모니터링 권한이 감지되지 않았습니다."
        case "Off. macOS did not allow event monitoring. Quit and reopen GWS Menu.":
            return "꺼짐. macOS가 이벤트 모니터링을 허용하지 않았습니다. GWS Menu를 다시 여세요."
        case "Waiting for Accessibility permission. Enable GWS Menu in System Settings.":
            return "손쉬운 사용 권한을 기다리는 중입니다. 시스템 설정에서 GWS Menu를 켜세요."
        case "Waiting for Input Monitoring permission. Enable GWS Menu in System Settings.":
            return "입력 모니터링 권한을 기다리는 중입니다. 시스템 설정에서 GWS Menu를 켜세요."
        case "Waiting for macOS event monitoring. GWS Menu will turn on Teams call block automatically.":
            return "macOS 이벤트 모니터링을 기다리는 중입니다. 준비되면 Teams 통화 차단을 자동으로 켭니다."
        case "Blocked a Teams call click.":
            return "Teams 통화 클릭을 차단했습니다."
        case "Blocked Teams Control-scroll zoom.":
            return "Teams Control-스크롤 확대를 차단했습니다."
        default:
            return status
        }
    }
}
