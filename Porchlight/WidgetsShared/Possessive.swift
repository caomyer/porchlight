import Foundation

extension String {
    /// The possessive of a name, for anything shown: "Mia's", "James's", "Yo-Yo's".
    /// Every possessive the app builds from a name comes here, so the rule lives in one place.
    /// A name that is a plural noun ("Tomatoes") still takes "'s": nothing on the device tells
    /// it from a name that ends in "s" ("James") reliably (see docs/design/households.md).
    var possessive: String { "\(self)'s" }
}
