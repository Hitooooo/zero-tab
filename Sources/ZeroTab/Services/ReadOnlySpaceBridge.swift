import AppKit
import ApplicationServices
import Darwin
import ZeroTabCore

/// User-approved, read-only compatibility boundary. No capture, mutation, focus, or remote-token APIs.
final class ReadOnlySpaceBridge {
    static let shared = ReadOnlySpaceBridge()
    private typealias Connection = @convention(c) () -> UInt32
    private typealias WindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias DisplaySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias WindowSpaces = @convention(c) (UInt32, Int, CFArray) -> Unmanaged<CFArray>?

    // Keep framework handles alive for as long as function pointers can be used.
    private let skyLight: UnsafeMutableRawPointer?
    private let process: UnsafeMutableRawPointer?
    private let connection: Connection?
    private let windowID: WindowID?
    private let displaySpaces: DisplaySpaces?
    private let windowSpaces: WindowSpaces?

    var available: Bool { connection != nil && windowID != nil && displaySpaces != nil && windowSpaces != nil }

    private init() {
        let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
        let own = dlopen(nil, RTLD_LAZY)
        skyLight = sky; process = own
        connection = Self.lookup("CGSMainConnectionID", in: sky, as: Connection.self)
        windowID = Self.lookup("_AXUIElementGetWindow", in: own, as: WindowID.self)
        displaySpaces = Self.lookup("CGSCopyManagedDisplaySpaces", in: sky, as: DisplaySpaces.self)
        windowSpaces = Self.lookup("CGSCopySpacesForWindows", in: sky, as: WindowSpaces.self)
    }

    private static func lookup<T>(_ name: String, in handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    func topology() -> SpaceTopology? {
        guard available, let connection, let displaySpaces,
              let raw = displaySpaces(connection())?.takeRetainedValue() as? [[String: Any]], !raw.isEmpty else { return nil }
        var visible = Set<UInt64>()
        var known = Set<UInt64>()
        var labels: [UInt64: String] = [:]
        var badges: [UInt64: String] = [:]
        var order: [UInt64] = []
        for (displayIndex, display) in raw.enumerated() {
            guard let current = display["Current Space"] as? [String: Any],
                  let currentID = current["id64"] as? NSNumber,
                  let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
            visible.insert(currentID.uint64Value)
            var desktopIndex = 0
            var fullscreenIndex = 0
            for space in spaces {
                guard let id = space["id64"] as? NSNumber else { return nil }
                known.insert(id.uint64Value)
                order.append(id.uint64Value)
                let prefix = raw.count > 1 ? "显示器 \(displayIndex + 1) · " : ""
                if (space["type"] as? NSNumber)?.intValue == 0 {
                    desktopIndex += 1
                    labels[id.uint64Value] = "\(prefix)桌面 \(desktopIndex)"
                    badges[id.uint64Value] = SpaceBadge.label(number: desktopIndex,
                        display: raw.count > 1 ? displayIndex + 1 : nil)
                } else {
                    fullscreenIndex += 1
                    labels[id.uint64Value] = "\(prefix)全屏空间 \(fullscreenIndex)"
                    badges[id.uint64Value] = SpaceBadge.label(number: fullscreenIndex,
                        display: raw.count > 1 ? displayIndex + 1 : nil, fullscreen: true)
                }
            }
        }
        guard !visible.isEmpty, visible.isSubset(of: known) else { return nil }
        return SpaceTopology(visible: visible, known: known, labels: labels, order: order, badges: badges)
    }

    func identifier(of element: AXUIElement) -> UInt32? {
        identifierResult(of: element).id
    }

    func identifierResult(of element: AXUIElement) -> (id: UInt32?, error: Int32) {
        guard let windowID else { return (nil, AXError.notImplemented.rawValue) }
        var id: UInt32 = 0
        let error = windowID(element, &id)
        return (error == AXError.success.rawValue && id != 0 ? id : nil, error)
    }

    func membership(of id: UInt32?) -> Set<UInt64>? {
        guard available, let connection, let windowSpaces, let id,
              let raw = windowSpaces(connection(), 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue()
                as? [NSNumber] else { return nil }
        return Set(raw.map(\.uint64Value))
    }
}
