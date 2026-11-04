import Foundation

public struct SpaceTopology: Sendable {
    public let visible: Set<UInt64>
    public let known: Set<UInt64>
    public let labels: [UInt64: String]
    public let badges: [UInt64: String]
    public let order: [UInt64]
    public init(visible: Set<UInt64>, known: Set<UInt64>, labels: [UInt64: String] = [:], order: [UInt64] = [], badges: [UInt64: String] = [:]) {
        self.visible = visible; self.known = known; self.labels = labels; self.order = order; self.badges = badges
    }

    public func label(of membership: Set<UInt64>?) -> String? {
        guard let membership, !membership.isEmpty else { return nil }
        let names = order.filter { membership.contains($0) }.compactMap { labels[$0] }
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    public func badge(of membership: Set<UInt64>?) -> String? {
        guard let membership, !membership.isEmpty,
              membership.isSubset(of: known) else { return nil }
        let values = order.filter { membership.contains($0) }.compactMap { badges[$0] }
        guard values.count == membership.count else { return nil }
        return values.joined(separator: "/")
    }

    public func location(of membership: Set<UInt64>?) -> SpaceLocation {
        guard let membership, !membership.isEmpty, !visible.isEmpty else { return .unknown }
        if !membership.isDisjoint(with: visible) { return .current }
        return membership.isSubset(of: known) ? .other : .unknown
    }
}

public enum SpaceBadge {
    public static func label(number: Int, display: Int? = nil, fullscreen: Bool = false) -> String {
        let circled: String
        switch number {
        case 1...20: circled = String(UnicodeScalar(0x2460 + number - 1)!)
        case 21...35: circled = String(UnicodeScalar(0x3251 + number - 21)!)
        case 36...50: circled = String(UnicodeScalar(0x32B1 + number - 36)!)
        default: circled = "(\(number))"
        }
        let prefix = display.map { "\($0)·" } ?? ""
        return prefix + (fullscreen ? "全" : "") + circled
    }
}
