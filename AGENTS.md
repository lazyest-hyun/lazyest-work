# Install Instructions for AI Agents

## GitHub Account Routing

- This is a Lazyest brand repository owned by `lazyest-hyun`.
- Use `gh-lazyest` for GitHub CLI operations and the `lazyest-hyun` remote for pushes. Never use `gh auth switch`.
- Keep the repository private unless the user explicitly approves public visibility.
- A source push is not authorization to create a tag, GitHub Release, download, or store submission.

## Distribution install and runtime verification

- Do not launch or use `dist/Lazyest Work.app` for local UI, permission, Keychain, Teams, or runtime testing. Files under `dist/` are packaging artifacts only.
- Runtime verification must use `/Applications/Lazyest Work.app` installed from a Developer ID-signed and Apple-notarized PKG.
- For current-source verification, build and notarize the app and PKG with `scripts/package-macos-release.sh`, install that PKG into `/Applications`, then launch and test `/Applications/Lazyest Work.app`.
- For a published version, download the PKG from the `lazyest-hyun/lazyest-work` GitHub Release with `gh-lazyest`, verify its checksum, Developer ID Installer signature, and notarization before installation.
- Never treat a source build, a signed app in `dist/`, or successful notarization as runtime verification.
- Do not connect accounts, accept permissions, or change app settings unless the user asks.

The user must enter administrator credentials directly in the macOS Installer UI when installation requires them.
