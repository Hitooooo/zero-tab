import Foundation

public enum WindowAdmission {
    public static func accepts(isPublished: Bool, standardWindow: Bool, hasTitle: Bool) -> Bool {
        // Preserve untitled windows officially published by any app. Supplemental
        // handles (including focused/main hints) need stronger semantic evidence.
        isPublished || (standardWindow && hasTitle)
    }
}
