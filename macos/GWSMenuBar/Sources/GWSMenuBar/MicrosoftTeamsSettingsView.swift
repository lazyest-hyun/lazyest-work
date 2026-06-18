import SwiftUI

struct MicrosoftTeamsSettingsCard: View {
    let connectionState: MicrosoftConnectionState
    let isConfigured: Bool
    @Binding var isPresenceEnabled: Bool
    let onConnect: () -> Void
    let onSignOut: () -> Void
    let onClearPresence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Teams status")
                        .font(.system(size: 13, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: $isPresenceEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!connectionState.isConnected)
                    .help(connectionState.isConnected ? "Set Teams Busy during accepted meetings" : "Connect Microsoft first")
            }

            HStack(spacing: 8) {
                if connectionState.isConnected {
                    Button("Sign Out", action: onSignOut)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Clear", action: onClearPresence)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Clear only the GWS Menu Teams presence session")
                } else {
                    Button("Connect Microsoft", action: onConnect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!isConfigured)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .menuSurface()
    }

    private var statusText: String {
        if !isConfigured {
            return "Teams sign-in is not available in this build."
        }
        switch connectionState {
        case .missingSetup:
            return "Teams sign-in is not available in this build."
        case .signedOut:
            return "Connect once. GWS Menu stores the token in Keychain."
        case .connected(let account):
            return "Connected: \(account ?? "Microsoft")."
        }
    }
}
