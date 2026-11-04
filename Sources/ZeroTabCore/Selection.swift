import Foundation

public enum SwitchMode: String, Sendable { case applications, windows }
public enum Direction: Sendable { case left, right, up, down }

public struct Selection: Equatable, Sendable {
    public private(set) var index: Int
    public let count: Int
    public let columns: Int

    public init(count: Int, columns: Int = 1, index: Int = 0) {
        self.count = max(0, count)
        self.columns = max(1, columns)
        self.index = count > 0 ? min(max(0, index), count - 1) : 0
    }

    public mutating func cycle(_ delta: Int) {
        guard count > 0 else { return }
        index = ((index + delta) % count + count) % count
    }

    public mutating func move(_ direction: Direction, linear: Bool = false) {
        guard count > 0 else { return }
        if linear {
            let delta = (direction == .left || direction == .up) ? -1 : 1
            index = min(max(0, index + delta), count - 1)
            return
        }
        let row = index / columns
        let column = index % columns
        switch direction {
        case .left: if column > 0 { index -= 1 }
        case .right: if column + 1 < columns && index + 1 < count { index += 1 }
        case .up: if row > 0 { index -= columns }
        case .down:
            let nextRow = (row + 1) * columns
            if nextRow < count { index = min(nextRow + column, count - 1) }
        }
    }
}

public enum SpaceLocation: Int, Sendable { case current, other, unknown }

public struct RankedItem<ID: Hashable & Sendable>: Sendable {
    public let id: ID
    public let location: SpaceLocation
    public let attention: UInt64
    public let ordinal: Int
    public init(id: ID, location: SpaceLocation, attention: UInt64, ordinal: Int) {
        self.id = id; self.location = location; self.attention = attention; self.ordinal = ordinal
    }
}

public enum CandidateOrder {
    public static func sorted<ID>(_ items: [RankedItem<ID>]) -> [RankedItem<ID>] {
        items.sorted {
            if $0.location != $1.location { return $0.location.rawValue < $1.location.rawValue }
            if $0.attention != $1.attention { return $0.attention > $1.attention }
            return $0.ordinal < $1.ordinal
        }
    }
}
