import Foundation

public struct DiscoveryCursor: Sendable {
    public private(set) var nextID: UInt64 = 0
    public private(set) var rounds = 0
    public private(set) var targets = Set<UInt32>()
    public static let automaticRoundLimit = 8
    public init() {}

    public mutating func update(targets newTargets: Set<UInt32>) {
        // Finding some targets must not restart the already-scanned prefix for the remaining ones.
        if !newTargets.isSubset(of: targets) { nextID = 0; rounds = 0 }
        targets = newTargets
    }

    public var needsBackgroundWork: Bool { !targets.isEmpty && rounds < Self.automaticRoundLimit }
    public mutating func finishRound(nextID: UInt64, found: Set<UInt32>) {
        self.nextID = nextID
        targets.subtract(found)
        rounds += 1
    }
}

public enum RemoteElementToken {
    /// Native little-endian macOS token layout: pid, reserved, Cocoa marker, 64-bit element identifier.
    public static func make(pid: Int32, identifier: UInt64) -> Data {
        var data = Data(repeating: 0, count: 20)
        var owner = pid
        var marker: UInt32 = 0x636f636f
        var identifier = identifier
        data.withUnsafeMutableBytes { target in
            withUnsafeBytes(of: &owner) { target.baseAddress!.copyMemory(from: $0.baseAddress!, byteCount: 4) }
            withUnsafeBytes(of: &marker) { target.baseAddress!.advanced(by: 8).copyMemory(from: $0.baseAddress!, byteCount: 4) }
            withUnsafeBytes(of: &identifier) { target.baseAddress!.advanced(by: 12).copyMemory(from: $0.baseAddress!, byteCount: 8) }
        }
        return data
    }
}
