import SwiftUI

struct MicrosoftTeamsSettingsCard: View {
    let language: AppLanguage
    let connectionState: MicrosoftConnectionState
    let isConfigured: Bool
    let presenceStatusText: String
    @Binding var isPresenceEnabled: Bool
    let onConnect: () -> Void
    let onSignOut: () -> Void
    private var text: AppText { AppText(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(text.teamsStatus)
                        .font(.system(size: 13, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if connectionState.isConnected {
                        Text(presenceStatusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $isPresenceEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(toggleHelpText)
            }

            HStack(spacing: 8) {
                if connectionState.isConnected {
                    Spacer()
                    Button(text.signOut, action: onSignOut)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button(text.teamsConnectMicrosoft, action: onConnect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!isConfigured)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .menuSurface()
    }

    private var statusText: String {
        if !isConfigured {
            return text.teamsCLIUnavailable
        }
        switch connectionState {
        case .missingSetup:
            return text.teamsCLIUnavailable
        case .signedOut:
            return text.teamsConnectOnce
        case .connected(let account):
            return text.connectedMicrosoft(account)
        }
    }

    private var toggleHelpText: String {
        if !isConfigured {
            return text.teamsInstallCLIHelp
        }
        if !connectionState.isConnected {
            return text.teamsConnectBeforeEnable
        }
        return text.teamsBusyHelp
    }
}

struct MicrosoftTeamsCallBlockSettingsCard: View {
    let language: AppLanguage
    @Binding var isEnabled: Bool
    let statusText: String
    private var text: AppText { AppText(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "phone.badge.checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(text.teamsCallBlock)
                        .font(.system(size: 13, weight: .semibold))
                    Text(text.localizedCallBlockStatus(statusText))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(text.teamsCallBlockHelp)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .menuSurface()
    }
}
