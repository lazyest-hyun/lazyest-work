public enum TeamsInputProtectionPermissionState: Equatable, Sendable {
    case ready
    case missingAccessibility
}

public enum TeamsInputProtectionPolicy {
    public static func permissionState(accessibilityGranted: Bool) -> TeamsInputProtectionPermissionState {
        accessibilityGranted ? .ready : .missingAccessibility
    }

    public static func shouldBlockControlScroll(
        isEnabled: Bool,
        controlKeyIsDown: Bool,
        isTeamsFrontmost: Bool,
        isInsideTeamsWindow: Bool
    ) -> Bool {
        isEnabled &&
            controlKeyIsDown &&
            isTeamsFrontmost &&
            isInsideTeamsWindow
    }
}
