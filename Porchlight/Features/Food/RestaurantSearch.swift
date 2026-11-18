import Contacts
import MapKit
import Observation

/// Live restaurant lookup while typing: Apple Maps autocomplete near the household,
/// then the full place (address, location, phone, website) once one is picked.
/// Needs no API key and no location permission; it searches around the weather's
/// saved location when there is one.
@MainActor
@Observable
final class RestaurantSearch: StoredFirstObservable {
    struct Suggestion: Identifiable, Equatable {
        let id: Int
        let title: String
        let subtitle: String
    }

    /// The text being searched; each change refreshes `suggestions`.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 2 {
                completer.cancel()
                suggestions = []
                completions = []
                isSearching = false
            } else {
                isSearching = true
                completer.queryFragment = trimmed
            }
        }
    }

    @ObservationIgnored @StoredFirst private(set) var suggestions: [Suggestion] = []
    @ObservationIgnored @StoredFirst private(set) var isSearching = false
    /// The last lookup failed (offline, rate-limited); typed names still save.
    @ObservationIgnored @StoredFirst private(set) var isOffline = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let relay = CompleterRelay()
    @ObservationIgnored private var completions: [MKLocalSearchCompletion] = []

    static let maxSuggestions = 6
    /// How far around home to look first (Maps still finds farther places by name).
    static let searchRadius: CLLocationDistance = 25_000

    init(near coordinate: CLLocationCoordinate2D? = WeatherStore.savedCoordinate) {
        completer.resultTypes = .pointOfInterest
        completer.pointOfInterestFilter = Self.foodFilter
        if let coordinate {
            completer.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: Self.searchRadius, longitudinalMeters: Self.searchRadius)
        }
        relay.onResults = { [weak self] results in self?.receive(results) }
        relay.onFailure = { [weak self] noMatches in self?.fail(noMatches: noMatches) }
        completer.delegate = relay
    }

    static let foodFilter = MKPointOfInterestFilter(including: [
        .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .nightlife,
    ])

    private func receive(_ results: [MKLocalSearchCompletion]) {
        completions = Array(results.prefix(Self.maxSuggestions))
        suggestions = completions.enumerated().map { index, completion in
            Suggestion(id: index, title: completion.title, subtitle: Self.withoutHomeCountry(completion.subtitle))
        }
        isSearching = false
        isOffline = false
    }

    private func fail(noMatches: Bool) {
        suggestions = []
        completions = []
        isSearching = false
        isOffline = !noMatches
    }

    /// The full place behind a suggestion; falls back to its name and address line
    /// if Maps can't be reached.
    func resolve(_ suggestion: Suggestion) async -> PlaceDraft {
        let fallback = PlaceDraft(name: suggestion.title, address: suggestion.subtitle.isEmpty ? nil : suggestion.subtitle)
        guard completions.indices.contains(suggestion.id),
              completions[suggestion.id].title == suggestion.title else { return fallback }
        let request = MKLocalSearch.Request(completion: completions[suggestion.id])
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = Self.foodFilter
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return fallback }
        return Self.place(from: item, fallback: fallback)
    }

    static func place(from item: MKMapItem, fallback: PlaceDraft) -> PlaceDraft {
        var place = fallback
        place.name = item.name ?? fallback.name
        place.address = address(of: item).map { withoutHomeCountry($0) } ?? fallback.address
        let coordinate = coordinate(of: item)
        place.latitude = coordinate.latitude
        place.longitude = coordinate.longitude
        place.category = item.pointOfInterestCategory.map(categoryName)
        place.phone = item.phoneNumber
        place.url = item.url?.absoluteString
        if #available(iOS 18.0, *) { place.mapsId = item.identifier?.rawValue }
        return place
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) { return item.location.coordinate }
        return item.placemark.coordinate
    }

    private static func address(of item: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            if let short = item.address?.shortAddress, !short.isEmpty { return short }
            return item.address?.fullAddress
        }
        guard let postal = item.placemark.postalAddress else { return nil }
        let line = [postal.street, postal.city].filter { !$0.isEmpty }.joined(separator: ", ")
        return line.isEmpty ? nil : line
    }

    /// Drops a trailing ", United States" (the household's own country) from an address line.
    static func withoutHomeCountry(_ address: String, locale: Locale = .current) -> String {
        guard let region = locale.region?.identifier,
              let country = locale.localizedString(forRegionCode: region) else { return address }
        let suffix = ", " + country
        return address.hasSuffix(suffix) ? String(address.dropLast(suffix.count)) : address
    }

    /// "Restaurant", "Cafe", "Food market".
    static func categoryName(_ category: MKPointOfInterestCategory) -> String {
        switch category {
        case .restaurant: "Restaurant"
        case .cafe: "Cafe"
        case .bakery: "Bakery"
        case .brewery: "Brewery"
        case .winery: "Winery"
        case .foodMarket: "Food market"
        case .nightlife: "Bar"
        default: "Place"
        }
    }
}

/// Forwards completer callbacks (which MapKit delivers on the main thread) to the search.
@MainActor
private final class CompleterRelay: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    var onResults: (([MKLocalSearchCompletion]) -> Void)?
    /// Called with true when Maps simply found nothing.
    var onFailure: ((Bool) -> Void)?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onResults?(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onFailure?((error as? MKError)?.code == .placemarkNotFound)
    }
}
