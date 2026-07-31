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

Creating the registration borrows Microsoft's pre-authorized Azure CLI public
client (`04b07795-8ddb-461a-bbee-02f9e1bf7b46`). Its bootstrap token can carry
broad directory permissions such as `Application.ReadWrite.All` and
`Directory.AccessAsUser.All`. The CLI setup process therefore runs with an
isolated temporary home directory with owner-only permissions. Lazyest Work
removes that temporary token and connection cache after setup, without reading,
switching, or deleting connections in the user's normal Microsoft 365 CLI
cache.

Lazyest Work does not clean up bootstrap state with `m365 connection remove`.
Microsoft 365 CLI and MSAL can remove cached tokens by account rather than by
the client that created them, which can force an unrelated connection for the
same account to sign in again. Setup instead deletes only its isolated temporary
home. This setup cannot bypass a tenant that blocks user app registration or
delegated consent, and it depends on Microsoft continuing to pre-authorize its
Azure CLI public client for the required directory operation.

Do not commit:

- OAuth client secrets
- access or refresh tokens
- signing certificates or provisioning profiles
- generated app bundles under `dist/`
- generated Google product icon PNGs
