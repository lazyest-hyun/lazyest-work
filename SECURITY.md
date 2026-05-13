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

GWS Menu does not require a Google client secret. Native apps are public OAuth
clients. User sign-in state is handled through Google Sign-In and Keychain.
Calendar access is read-only. The optional Gmail badge uses Gmail label unread
counts only, not message sender, subject, body, or attachments. GWS Menu does not
send desktop mail alerts in the public-safe scope set.

Do not commit:

- OAuth client secrets
- access or refresh tokens
- signing certificates or provisioning profiles
- generated app bundles under `dist/`
- generated Google product icon PNGs
