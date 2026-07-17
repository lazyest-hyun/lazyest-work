import SwiftUI

struct MicrosoftTeamsSettingsCard: View {
    let language: AppLanguage
    let connectionState: MicrosoftConnectionState
    let isCalendarConnected: Bool
    let usesNativeAuth: Bool
    let isCLIInstalled: Bool
    let operation: MicrosoftTeamsOperation
    let presenceStatusText: String
    @Binding var isPresenceEnabled: Bool
    let onInstallCLI: () -> Void
    let onConnect: () -> Void
    let onSignOut: () -> Void
    private var text: AppText { AppText(language: language) }

    var body: some View {
        VStack(spacing: 8) {
            if !usesNativeAuth {
                cliRow
            }
            accountRow
            automationRow
        }
    }

    private var cliRow: some View {
        settingsRow(symbol: "terminal") {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.teamsCLIName)
                    .font(.system(size: 13, weight: .semibold))
                if !isCLIInstalled {
                    Text(text.teamsCLIRequired)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if operation == .installingCLI {
                workingLabel(text.teamsInstallingCLI)
            } else if isCLIInstalled {
                statusLabel(text.installed, symbol: "checkmark.circle.fill", color: .green)
            } else {
                Button(text.install, action: onInstallCLI)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(operation.isActive)
            }
        }
    }

    private var accountRow: some View {
        settingsRow(symbol: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.teamsMicrosoftAccount)
                    .font(.system(size: 13, weight: .semibold))
                Text(accountSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if operation == .signingIn {
                workingLabel(text.teamsSigningIn)
            } else if operation == .signingOut {
                workingLabel(text.teamsSigningOut)
            } else if operation == .checkingConnection {
                workingLabel(text.teamsCheckingConnection)
            } else if connectionState.isConnected {
                Button(text.signOut, action: onSignOut)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button(text.signIn, action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canSignIn || operation.isActive)
            }
        }
    }

    private var automationRow: some View {
        settingsRow(symbol: "person.crop.circle.badge.clock") {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.teamsMeetingBusy)
                    .font(.system(size: 13, weight: .semibold))
                Text(automationSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isPresenceEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(
                    operation.isActive ||
                        (!isPresenceEnabled && (!connectionState.isConnected || !isCalendarConnected))
                )
                .help(text.teamsBusyHelp)
        }
    }

    private func settingsRow<Content: View>(
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .menuSurface()
    }

    private func workingLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func statusLabel(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
    }

    private var canSignIn: Bool {
        usesNativeAuth || isCLIInstalled
    }

    private var accountSubtitle: String {
        switch connectionState {
        case .missingSetup:
            return isCLIInstalled ? text.teamsSignedOut : text.teamsInstallFirst
        case .signedOut:
            return text.teamsSignedOut
        case .failed:
            return text.teamsConnectionCheckFailed
        case .connected(let account):
            return account ?? text.connected
        }
    }

    private var automationSubtitle: String {
        guard connectionState.isConnected else {
            return isPresenceEnabled ? text.teamsResumeAfterSignIn : text.teamsSignInFirst
        }
        guard isCalendarConnected else {
            return text.teamsCalendarRequired
        }
        guard isPresenceEnabled else {
            return text.teamsBusyOffSubtitle
        }
        return text.localizedTeamsPresenceStatus(presenceStatusText)
    }
}

struct MicrosoftTeamsCallProtectionSettingsCard: View {
    let language: AppLanguage
    @Binding var isEnabled: Bool
    let statusText: String
    private var text: AppText { AppText(language: language) }

    var body: some View {
        MicrosoftTeamsProtectionToggleRow(
            title: text.teamsCallConfirm,
            subtitle: text.localizedCallBlockStatus(statusText),
            symbol: "phone.badge.checkmark",
            isOn: $isEnabled,
            help: text.teamsCallBlockHelp
        )
    }
}

struct MicrosoftTeamsControlScrollBlockSettingsCard: View {
    let language: AppLanguage
    @Binding var isEnabled: Bool
    private var text: AppText { AppText(language: language) }

    var body: some View {
        MicrosoftTeamsProtectionToggleRow(
            title: text.teamsControlScrollBlock,
            subtitle: text.s(
                "Only blocks Control-scroll in the frontmost Teams window.",
                "Teams가 전면일 때만 Control+스크롤을 차단합니다."
            ),
            symbol: "magnifyingglass.circle",
            isOn: $isEnabled,
            help: text.teamsControlScrollBlock
        )
    }
}

private struct MicrosoftTeamsProtectionToggleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(help)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .menuSurface()
    }
}
