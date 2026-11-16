/// Star counts in words, the same everywhere on the phone: "1 star", "2 stars", "+1 star".
enum StarWords {
    static func count(_ stars: Int) -> String {
        "\(stars) \(stars == 1 ? "star" : "stars")"
    }

    static func earned(_ stars: Int) -> String {
        "+" + count(stars)
    }

    /// "star" or "stars" alone, for a sentence whose number is shown on its own.
    static func noun(_ stars: Int) -> String {
        stars == 1 ? "star" : "stars"
    }
}
