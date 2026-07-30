# Security Policy

## Reporting a Vulnerability

Please do not file public issues for suspected credential leaks, OAuth bugs, or
token-handling vulnerabilities.

For now, report privately to the repository owner. Include:

- affected commit or release
- reproduction steps
- expected impact
- whether any OAuth client ID, token, or private key may have been exposed

## Credential Handling

Lazyest Work does not require a Google client secret. Native apps are public OAuth
clients. User sign-in state is handled through Google Sign-In and Keychain.
Calendar access is read-only. The optional Gmail badge uses Gmail label unread
counts only, not message sender, subject, body, or attachments. Lazyest Work does not
send desktop mail alerts in the public-safe scope set.

For an unmanaged installation, Microsoft Teams presence setup uses the real
Microsoft 365 CLI once to create a single-tenant, user-owned public client
without administrator consent. Lazyest Work stores its public client and tenant
IDs in app preferences. Sign-in then uses OAuth authorization code with PKCE and
a temporary localhost callback, requests delegated `User.Read` and
`Presence.ReadWrite` access, and stores the refresh credential in Keychain. No
Microsoft client secret is created or bundled.

Creating that registration needs a directory write permission, which the setup
step obtains by signing the CLI in as Microsoft's own Azure CLI public client
(`04b07795-8ddb-461a-bbee-02f9e1bf7b46`). That client is pre-authorized on
Microsoft Graph, so an ordinary member gets the permission without an
administrator consent prompt — and the resulting token is broad, covering
`Application.ReadWrite.All` and `Directory.AccessAsUser.All` among others.
Microsoft 365 CLI writes such tokens to plain files in the home directory
(`~/.cli-m365-msal.json`), so setup runs the CLI against a private temporary
home that is deleted when it finishes. That credential never reaches the real
cache, and the user's own CLI state is untouched: no connection is added, none
is switched, and none is removed. Deleting a connection afterwards would not be
equivalent — `m365 connection remove` drops MSAL tokens by account rather than
by client, so it can sign out a connection the user still relies on.

Two consequences are worth stating plainly: setup depends on Microsoft
continuing to pre-authorize the Azure CLI client, and it cannot succeed in a
tenant that blocks users from registering applications.

Do not commit:

- OAuth client secrets
- access or refresh tokens
- signing certificates or provisioning profiles
- generated app bundles under `dist/`
- generated Google product icon PNGs
