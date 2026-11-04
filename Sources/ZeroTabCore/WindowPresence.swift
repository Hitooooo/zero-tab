import Foundation

public enum WindowPresence {
    /// A missing optional field can be resolved by a successful on-screen list.
    /// Failure of both queries remains unknown, rather than evidence of closure.
    public static func onScreen(reported: Bool?, appearsInOnScreenList: Bool?) -> Bool? {
        reported ?? appearsInOnScreenList
    }

    /// Off-screen alone never discards minimized, hidden or other-Space windows.
    public static func isNotPresented(location: SpaceLocation, onScreen: Bool?,
                                      minimized: Bool?, applicationHidden: Bool, hasAssignedSpace: Bool? = nil) -> Bool {
        minimized == false && !applicationHidden && onScreen == false
            && (location == .current || (location == .unknown && hasAssignedSpace == false))
    }
}
