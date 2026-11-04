import AppKit
import ApplicationServices
import Darwin
import OSLog
import ZeroTabCore

/// User-approved, bounded AX handle lookup for physical windows omitted by AXWindows.
/// Called only on WindowCatalog's serial worker. Does not walk child trees, capture pixels or activate apps.
final class CrossSpaceDiscovery {
    private typealias CreateElement = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private let process: UnsafeMutableRawPointer?
    private let createElement: CreateElement?
    private var cursors: [pid_t: DiscoveryCursor] = [:]
    private var resolved: [pid_t: [UInt32: AXUIElement]] = [:]
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "Discovery")

    init() {
        let handle = dlopen(nil, RTLD_LAZY)
        process = handle
        if let handle, let pointer = dlsym(handle, "_AXUIElementCreateWithRemoteToken") {
            createElement = unsafeBitCast(pointer, to: CreateElement.self)
        } else { createElement = nil }
    }

    func forget(pid: pid_t) { cursors[pid] = nil; resolved[pid] = nil }
    func cachedElements(pid: pid_t) -> [AXUIElement] { Array((resolved[pid] ?? [:]).values) }
    func contains(pid: pid_t, windowID: UInt32?) -> Bool {
        guard let windowID else { return false }; return resolved[pid]?[windowID] != nil
    }
    func needsBackgroundWork(pid: pid_t) -> Bool { createElement != nil && cursors[pid]?.needsBackgroundWork == true }

    func find(pid: pid_t, missing: Set<UInt32>, automatic: Bool) -> [AXUIElement] {
        var cursor = cursors[pid] ?? DiscoveryCursor()
        cursor.update(targets: missing)
        guard let createElement, !missing.isEmpty, !automatic || cursor.needsBackgroundWork else {
            cursors[pid] = cursor; return []
        }
        let seed = RemoteElementToken.make(pid: pid, identifier: cursor.nextID)
        guard let token = CFDataCreateMutableCopy(nil, 20, seed as CFData),
              let bytes = CFDataGetMutableBytePtr(token) else { return [] }
        let start = DispatchTime.now().uptimeNanoseconds
        let deadline = start + 120_000_000
        var candidateID = cursor.nextID
        var remaining = missing
        var result: [AXUIElement] = []
        while !remaining.isEmpty && candidateID < UInt64.max && DispatchTime.now().uptimeNanoseconds < deadline {
            var rawID = candidateID
            withUnsafeBytes(of: &rawID) { source in
                UnsafeMutableRawPointer(bytes).advanced(by: 12).copyMemory(from: source.baseAddress!, byteCount: 8)
            }
            candidateID += 1
            guard let element = createElement(token)?.takeRetainedValue() else { continue }
            // A blocking IPC can finish slightly past the slice deadline; cap each candidate's messaging timeout.
            AXUIElementSetMessagingTimeout(element, 0.01)
            let identity = ReadOnlySpaceBridge.shared.identifierResult(of: element)
            if identity.error == AXError.cannotComplete.rawValue {
                candidateID -= 1; break // Do not permanently skip an element just because its app was busy.
            }
            guard let wid = identity.id, remaining.contains(wid) else { continue }
            guard DispatchTime.now().uptimeNanoseconds < deadline,
                  let role = AXAccess.value(element, kAXRoleAttribute) as? String else {
                candidateID -= 1; break
            }
            guard role == kAXWindowRole else { continue }
            AXUIElementSetMessagingTimeout(element, 0.25)
            var retained = resolved[pid] ?? [:]
            if retained.count >= 256, let oldest = retained.keys.min() { retained[oldest] = nil }
            retained[wid] = element
            resolved[pid] = retained
            result.append(element)
            remaining.remove(wid)
        }
        cursor.finishRound(nextID: candidateID, found: missing.subtracting(remaining))
        cursors[pid] = cursor
        let elapsed = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        logger.info("Discovery slice: found=\(result.count), remaining=\(remaining.count), elapsedMs=\(elapsed), rounds=\(cursor.rounds), nextElement=\(cursor.nextID)")
        return result
    }
}
