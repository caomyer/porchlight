import SwiftUI

/// A person's colored initial at the phone's three sizes, growing a little with
/// Dynamic Type. Someone who isn't there (an archived or unknown id) shows the
/// household's heart, as on the wall.
struct PersonAvatar: View {
    enum Size {
        /// In a slot, a pill or a row.
        case small
        /// The "You" button on every tab.
        case regular
        /// The top of the You sheet.
        case large

        var points: CGFloat {
            switch self {
            case .small: 24
            case .regular: 32
            case .large: 52
            }
        }
    }

    let person: Person?
    @PhoneMetric private var side: CGFloat

    init(_ person: Person?, size: Size = .regular) {
        self.person = person
        _side = PhoneMetric(wrappedValue: size.points, upTo: size == .large ? 1.4 : 1.6)
    }

    var body: some View {
        if let person {
            Avatar(person: person, size: side)
        } else {
            AnyoneAvatar(size: side)
        }
    }
}
