import AppKit
import ZeroTabCore

/// Public APIs can prove a matched window is on screen, but off-screen alone proves no Space membership.
enum SpaceProvider {
    struct Snapshot {
        let topology: SpaceTopology?
        let visibleWindows: [VisibleWindow]
    }

    static func snapshot() -> Snapshot {
        Snapshot(topology: ReadOnlySpaceBridge.shared.topology(), visibleWindows: visibleWindows())
    }

    static func otherSpaceCandidates(pid: pid_t, topology: SpaceTopology?) -> Set<UInt32> {
        guard let topology,
              let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var result = Set<UInt32>()
        for row in rows {
            guard row[kCGWindowOwnerPID as String] as? Int32 == pid,
                  row[kCGWindowLayer as String] as? Int == 0,
                  let alpha = row[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width >= 100, frame.height >= 80,
                  let id = row[kCGWindowNumber as String] as? UInt32,
                  topology.location(of: ReadOnlySpaceBridge.shared.membership(of: id)) == .other else { continue }
            result.insert(id)
        }
        return result
    }

    static func placement(windowID: UInt32?, pid: pid_t, frame: CGRect?, snapshot: Snapshot) -> (SpaceLocation, String?) {
        if let topology = snapshot.topology {
            let membership = ReadOnlySpaceBridge.shared.membership(of: windowID)
            let location = topology.location(of: membership)
            if location != .unknown { return (location, topology.label(of: membership)) }
        }
        return (location(pid: pid, frame: frame, windows: snapshot.visibleWindows), nil)
    }

    /// A conservative veto against reopening when AX omitted physical windows.
    static func mayHaveUnresolvedWindows(pid: pid_t) -> Bool {
        guard let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return true }
        return rows.contains { row in
            guard row[kCGWindowOwnerPID as String] as? Int32 == pid,
                  row[kCGWindowLayer as String] as? Int == 0,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return frame.width > 1 && frame.height > 1
        }
    }

    struct VisibleWindow {
        let pid: pid_t
        let frame: CGRect
    }

    static func visibleWindows() -> [VisibleWindow] {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let pid = row[kCGWindowOwnerPID as String] as? Int32,
                  let layer = row[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return VisibleWindow(pid: pid, frame: rect)
        }
    }

    static func location(pid: pid_t, frame: CGRect?, windows: [VisibleWindow]) -> SpaceLocation {
        guard let frame else { return .unknown }
        let matches = windows.filter {
            $0.pid == pid && abs($0.frame.minX - frame.minX) < 2 && abs($0.frame.minY - frame.minY) < 2
                && abs($0.frame.width - frame.width) < 2 && abs($0.frame.height - frame.height) < 2
        }
        return matches.count == 1 ? .current : .unknown
    }
}
