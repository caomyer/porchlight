import Foundation
@testable import Porchlight

/// Lets fixtures write ids as small numbers: `1` is `00000000-0000-0000-0000-000000000001`.
/// They sort like the numbers, so fixtures read as before ids became UUIDs.
extension Porchlight.ID: @retroactive ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", value))!)
    }

    /// The fixture id for a computed number.
    static func number(_ value: Int) -> ID {
        ID(integerLiteral: value)
    }

    /// The number a fixture id was made from.
    var number: Int {
        Int(description.suffix(12), radix: 16) ?? -1
    }
}
