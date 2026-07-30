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
Microsoft client secret is created or bundled. The CLI setup process runs with
an isolated temporary home directory with owner-only permissions. Lazyest Work
removes that temporary token and connection cache after setup, without reading,
switching, or deleting connections in the user's normal Microsoft 365 CLI
cache.

Do not commit:

- OAuth client secrets
- access or refresh tokens
- signing certificates or provisioning profiles
- generated app bundles under `dist/`
- generated Google product icon PNGs
