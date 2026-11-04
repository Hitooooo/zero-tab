import Foundation

public enum WindowAdmission {
    public static func accepts(isChrome: Bool, remoteOnly: Bool, standardWindow: Bool, hasTitle: Bool) -> Bool {
        // Browser documents always expose a title; empty-title roots are commonly helper surfaces.
        // A remote-only root needs both semantic facts before it is presented as a user window.
        if isChrome || remoteOnly { return standardWindow && hasTitle }
        return true
    }
}
