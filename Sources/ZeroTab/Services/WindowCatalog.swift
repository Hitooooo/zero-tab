import AppKit
import ApplicationServices
import ZeroTabCore
import OSLog

final class WindowCatalog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.hitomeng.ZeroTab.windows", qos: .userInitiated)
    // Accessed only on queue. Process generations are reset on termination.
    private var cache: [pid_t: [WindowRecord]] = [:]
    private var attention: UInt64 = 0
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "Windows")
    private let discovery = CrossSpaceDiscovery()
    private var scheduled: [pid_t: UInt64] = [:]
    private var epochs: [pid_t: UInt64] = [:]

    func query(pid: pid_t, continueDiscovery: Bool = false, completion: @escaping (WindowQuery) -> Void) {
        queue.async { [self] in
            let result = read(pid: pid, automatic: !continueDiscovery)
            DispatchQueue.main.async { completion(result) }
            scheduleWarmup(pid: pid)
        }
    }

    func forget(pid: pid_t) {
        queue.async {
            self.cache[pid] = nil; self.discovery.forget(pid: pid)
            self.epochs[pid, default: 0] &+= 1; self.scheduled[pid] = nil
        }
    }

    private func scheduleWarmup(pid: pid_t) {
        guard discovery.needsBackgroundWork(pid: pid), scheduled[pid] == nil else { return }
        let epoch = epochs[pid, default: 0]
        scheduled[pid] = epoch
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.scheduled[pid] == epoch, self.epochs[pid, default: 0] == epoch else { return }
            self.scheduled[pid] = nil
            guard AXIsProcessTrusted(), kill(pid, 0) == 0 else { return }
            _ = self.read(pid: pid, automatic: true)
            self.scheduleWarmup(pid: pid)
        }
    }

    private func read(pid: pid_t, automatic: Bool = false) -> WindowQuery {
        guard AXIsProcessTrusted() else { return .unavailable("请先授予辅助功能权限。") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
        guard error == .success, let raw, let published = raw as? [AXUIElement] else {
            return .unavailable("暂时无法读取该应用的窗口，请稍后重试。")
        }
        let focused = AXAccess.element(app, kAXFocusedWindowAttribute)
        let bridge = ReadOnlySpaceBridge.shared
        let focusedID = focused.flatMap { bridge.identifier(of: $0) }
        let isChrome = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.google.Chrome"
        let main = AXAccess.element(app, kAXMainWindowAttribute)
        var elements = published
        for candidate in [focused, main].compactMap({ $0 }) {
            if !elements.contains(where: { CFEqual($0, candidate) }) { elements.append(candidate) }
        }
        let publishedIDs = Set(elements.compactMap { bridge.identifier(of: $0) })
        let old = cache[pid] ?? []
        // Retained elements can remain valid on other Spaces even when the app omits them from kAXWindows.
        for record in old where !elements.contains(where: { CFEqual($0, record.element) }) {
            if AXAccess.value(record.element, kAXRoleAttribute) as? String == kAXWindowRole { elements.append(record.element) }
        }
        // Keep resolved helper handles too: suppressing them from UI must not trigger repeated rediscovery.
        for element in discovery.cachedElements(pid: pid) where !elements.contains(where: { CFEqual($0, element) }) {
            if AXAccess.value(element, kAXRoleAttribute) as? String == kAXWindowRole { elements.append(element) }
        }
        let snapshot = SpaceProvider.snapshot()
        let represented = Set(elements.compactMap { bridge.identifier(of: $0) })
        let missing = SpaceProvider.otherSpaceCandidates(pid: pid, topology: snapshot.topology).subtracting(represented)
        elements.append(contentsOf: discovery.find(pid: pid, missing: missing, automatic: automatic))
        var records: [WindowRecord] = []
        var seenIDs = Set<UInt32>()
        var suppressed = 0
        for element in elements {
            let windowID = bridge.identifier(of: element)
            if let windowID, !seenIDs.insert(windowID).inserted { continue }
            let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
                              kAXPositionAttribute, kAXSizeAttribute]
            guard let values = AXAccess.values(element, attributes) else {
                return .unavailable("应用尚未响应窗口查询，请稍后重试。")
            }
            // A failed role read is unknown, never evidence of zero windows.
            guard let role = values[kAXRoleAttribute] as? String else {
                return .unavailable("应用尚未响应窗口查询，请稍后重试。")
            }
            guard role == kAXWindowRole else { continue }
            let subrole = values[kAXSubroleAttribute] as? String
            if subrole == kAXFloatingWindowSubrole || subrole == kAXSystemFloatingWindowSubrole { continue }
            let previous = old.first {
                if let windowID, let oldID = $0.windowID { return windowID == oldID }
                return CFEqual($0.element, element)
            }
            let isFocused: Bool
            if let windowID, let focusedID { isFocused = windowID == focusedID }
            else { isFocused = focused.map { CFEqual($0, element) } ?? false }
            var rank = previous?.attention ?? 0
            // The AX focused attribute of a background app is a seed, not evidence of current global focus.
            if isFocused && previous?.focused != true {
                attention &+= 1; rank = attention
            }
            let frame = AXAccess.frame(position: values[kAXPositionAttribute], size: values[kAXSizeAttribute])
            let placement = SpaceProvider.placement(windowID: windowID, pid: pid, frame: frame, snapshot: snapshot)
            let title = (values[kAXTitleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTitle = title?.isEmpty == false
            let remoteOnly = discovery.contains(pid: pid, windowID: windowID) && !publishedIDs.contains(windowID ?? 0)
            guard WindowAdmission.accepts(isChrome: isChrome, remoteOnly: remoteOnly,
                standardWindow: subrole == kAXStandardWindowSubrole, hasTitle: hasTitle) else {
                suppressed += 1; continue
            }
            records.append(WindowRecord(
                id: previous?.id ?? UUID(), pid: pid, element: element, windowID: windowID,
                title: title?.isEmpty == false ? title! : "未命名窗口 \(records.count + 1)",
                minimized: (values[kAXMinimizedAttribute] as? Bool) ?? false,
                frame: frame, location: placement.0, spaceLabel: placement.1,
                attention: rank, focused: isFocused
            ))
        }
        if records.isEmpty && SpaceProvider.mayHaveUnresolvedWindows(pid: pid) {
            return .unavailable("该应用可能还有未列出的窗口，已避免重复新建。")
        }
        // Prevent indistinguishable duplicate labels without pretending to know document paths.
        let groups = Dictionary(grouping: records, by: \.title)
        var duplicateOrdinals: [UUID: Int] = [:]
        for group in groups.values where group.count > 1 {
            for (index, record) in group.sorted(by: { $0.id.uuidString < $1.id.uuidString }).enumerated() {
                duplicateOrdinals[record.id] = index + 1
            }
        }
        records = records.map { record in
            guard let ordinal = duplicateOrdinals[record.id] else { return record }
            return WindowRecord(id: record.id, pid: record.pid, element: record.element, windowID: record.windowID,
                title: "\(record.title) · \(ordinal)", minimized: record.minimized,
                frame: record.frame, location: record.location, spaceLabel: record.spaceLabel, attention: record.attention, focused: record.focused)
        }
        cache[pid] = records
        let current = records.filter { $0.location == .current }.count
        let other = records.filter { $0.location == .other }.count
        let unknown = records.count - current - other
        logger.info("Window membership: current=\(current), other=\(other), unknown=\(unknown), suppressedHelpers=\(suppressed)")
        return .success(records)
    }
}
