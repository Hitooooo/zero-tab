import AppKit
import ApplicationServices
import ZeroTabCore

struct WindowRecord: Identifiable, @unchecked Sendable {
    let id: UUID
    let pid: pid_t
    let element: AXUIElement
    let windowID: UInt32?
    let title: String
    let minimized: Bool
    let frame: CGRect?
    var location: SpaceLocation
    var spaceLabel: String?
    var attention: UInt64
    var focused: Bool
}

enum WindowQuery: @unchecked Sendable {
    case success([WindowRecord])
    case unavailable(String)
}

struct SwitchItem: Identifiable {
    let id: String
    let title: String
    let application: NSRunningApplication
    let icon: NSImage
    let window: WindowRecord?
    var location: SpaceLocation { window?.location ?? .current }
}
