import AppKit
import SwiftUI

struct MicrosoftTeamsSettingsCard: View {
    @Binding var clientID: String
    @Binding var tenantID: String
    let connectionState: MicrosoftConnectionState
    @Binding var isPresenceEnabled: Bool
    let feedback: GoogleSetupResult?
    let onSave: () -> Void
    let onConnect: () -> Void
    let onSignOut: () -> Void
    let onClearPresence: () -> Void
    @State private var didCopyRedirectURI = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Microsoft Teams Busy")
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

            VStack(alignment: .leading, spacing: 6) {
                TextField("Application (client) ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                TextField("Tenant: organizations, tenant ID, or domain", text: $tenantID)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redirect URI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(MicrosoftSetupConfig.redirectURI)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(MicrosoftSetupConfig.redirectURI, forType: .string)
                    didCopyRedirectURI = true
                } label: {
                    Image(systemName: didCopyRedirectURI ? "checkmark" : "doc.on.doc")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Copy redirect URI")
            }
            .padding(9)
            .menuSurface(.inset, cornerRadius: 7)

            Text("In Microsoft Entra, create a public client/native app, add this redirect URI, then grant User.Read and Presence.ReadWrite.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let feedback {
                SetupFeedbackView(result: feedback)
            }

            HStack(spacing: 8) {
                Button("Save Setup", action: onSave)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if connectionState.isConnected {
                    Button("Sign Out", action: onSignOut)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Clear", action: onClearPresence)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Clear only the GWS Menu Teams presence session")
                } else {
                    Button("Connect", action: onConnect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canConnect)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .menuSurface()
        .onChange(of: clientID) { _, _ in didCopyRedirectURI = false }
    }

    private var canConnect: Bool {
        (try? MicrosoftSetupConfig.normalized(clientID: clientID, tenantID: tenantID)) != nil
    }

    private var statusText: String {
        switch connectionState {
        case .missingSetup:
            return "Save a Microsoft app Client ID first."
        case .signedOut:
            return "Connect once. Refresh token is stored in Keychain."
        case .connected(let account):
            return "Connected: \(account ?? "Microsoft Graph")."
        }
    }
}
