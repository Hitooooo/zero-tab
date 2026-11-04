import AppKit
import ZeroTabCore

enum SpaceProvider {
    struct ServerWindow {
        let id: UInt32
        let pid: pid_t
        let frame: CGRect
        let layer: Int
        let alpha: Double
        let onScreen: Bool?
    }

    struct Snapshot {
        let topology: SpaceTopology?
        let windows: [ServerWindow]

        func onScreen(windowID: UInt32?) -> Bool? {
            guard let windowID else { return nil }
            return windows.first { $0.id == windowID }?.onScreen
        }
    }

    static func snapshot() -> Snapshot {
        let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        // kCGWindowIsOnscreen is optional. Finder's retained helper surfaces omit it.
        // Resolve those rows from a successful public on-screen inventory, never by
        // treating a missing dictionary key (or a failed query) as false.
        var onScreenIDs: Set<UInt32>?
        if rows?.contains(where: { $0[kCGWindowIsOnscreen as String] as? Bool == nil }) == true,
           let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let identifiers = visible.compactMap { $0[kCGWindowNumber as String] as? UInt32 }
            if identifiers.count == visible.count { onScreenIDs = Set(identifiers) }
        }
        let windows = (rows ?? []).compactMap { row -> ServerWindow? in
            guard let id = row[kCGWindowNumber as String] as? UInt32,
                  let pid = row[kCGWindowOwnerPID as String] as? Int32,
                  let layer = row[kCGWindowLayer as String] as? Int,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return ServerWindow(id: id, pid: pid, frame: frame, layer: layer,
                alpha: row[kCGWindowAlpha as String] as? Double ?? 0,
                onScreen: WindowPresence.onScreen(reported: row[kCGWindowIsOnscreen as String] as? Bool,
                    appearsInOnScreenList: onScreenIDs.map { $0.contains(id) }))
        }
        return Snapshot(topology: ReadOnlySpaceBridge.shared.topology(), windows: windows)
    }

    static func otherSpaceCandidates(pid: pid_t, snapshot: Snapshot) -> Set<UInt32> {
        guard let topology = snapshot.topology else { return [] }
        return Set(snapshot.windows.filter {
            $0.pid == pid && $0.layer == 0 && $0.alpha > 0 && $0.frame.width >= 100 && $0.frame.height >= 80
                && topology.location(of: ReadOnlySpaceBridge.shared.membership(of: $0.id)) == .other
        }.map(\.id))
    }

    static func placement(windowID: UInt32?, pid: pid_t, frame: CGRect?, snapshot: Snapshot) -> (SpaceLocation, String?, Set<UInt64>?) {
        let membership = ReadOnlySpaceBridge.shared.membership(of: windowID)
        if let topology = snapshot.topology {
            let location = topology.location(of: membership)
            if location != .unknown { return (location, topology.label(of: membership), membership) }
        }
        guard let frame else { return (.unknown, nil, membership) }
        let matches = snapshot.windows.filter {
            $0.pid == pid && $0.layer == 0 && $0.onScreen == true
                && abs($0.frame.minX - frame.minX) < 2 && abs($0.frame.minY - frame.minY) < 2
                && abs($0.frame.width - frame.width) < 2 && abs($0.frame.height - frame.height) < 2
        }
        return (matches.count == 1 ? .current : .unknown, nil, membership)
    }

}
