# Workspace Icons

This directory is intentionally committed without third-party product icon PNGs
and excluded from the Swift package resources.

The app falls back to SF Symbols when cached PNGs are absent. For permitted
local/internal use, `scripts/sync-google-app-icons.swift` writes downloaded
icons to `~/Library/Application Support/Lazyest Work/WorkspaceIcons` after the
caller reviews and accepts the relevant brand/trademark guidelines. It does not
build or install the app.
