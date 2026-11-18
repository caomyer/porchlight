import Testing
@testable import Porchlight

@Suite("Possessives")
struct PossessiveTests {
    @Test("Every name takes 's, names ending in s included", arguments: [
        "Mia", "Yo-Yo", "Grandma Rosa", "James", "Chris", "Iris", "Lucas",
    ])
    func names(_ name: String) {
        #expect(name.possessive == "\(name)'s")
    }
}
