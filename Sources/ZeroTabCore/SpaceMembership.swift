import Foundation

public struct SpaceTopology: Sendable {
    public let visible: Set<UInt64>
    public let known: Set<UInt64>
    public let labels: [UInt64: String]
    public let order: [UInt64]
    public init(visible: Set<UInt64>, known: Set<UInt64>, labels: [UInt64: String] = [:], order: [UInt64] = []) {
        self.visible = visible; self.known = known; self.labels = labels; self.order = order
    }

    public func label(of membership: Set<UInt64>?) -> String? {
        guard let membership, !membership.isEmpty else { return nil }
        let names = order.filter { membership.contains($0) }.compactMap { labels[$0] }
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    public func location(of membership: Set<UInt64>?) -> SpaceLocation {
        guard let membership, !membership.isEmpty, !visible.isEmpty else { return .unknown }
        if !membership.isDisjoint(with: visible) { return .current }
        return membership.isSubset(of: known) ? .other : .unknown
    }
}
