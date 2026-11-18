import CoreLocation
import Foundation
import Observation
import SwiftUI

/// Local weather for the wall, from Open-Meteo (free, no account or key).
///
/// Privacy: the iPad's approximate location is looked up once (with the user's
/// permission), rounded to about 1 km, cached on the device, and only those
/// rounded coordinates are sent to api.open-meteo.com.
@MainActor
@Observable
final class WeatherStore: StoredFirstObservable {
    struct Day: Equatable, Sendable {
        var day: DayKey
        var code: Int
        var high: Double
        var low: Double
    }

    struct Now: Equatable, Sendable {
        var temperature: Double
        var code: Int
        var isDay = true
    }

    @ObservationIgnored @StoredFirst private(set) var now: Now? = nil
    @ObservationIgnored @StoredFirst private(set) var days: [DayKey: Day] = [:]
    @ObservationIgnored @StoredFirst private(set) var unitSymbol = "°"

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let locator = OneShotLocator()

    static let enabledKey = "weather.enabled"
    private static let coordinateKey = "weather.coordinate"

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start() {
        refreshTask?.cancel()
        guard isEnabled else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        now = nil
        days = [:]
    }

    func day(_ key: DayKey) -> Day? { days[key] }

    private func refresh() async {
        guard let coordinate = await coordinate() else { return }
        do {
            let forecast = try await OpenMeteo.fetch(latitude: coordinate.latitude, longitude: coordinate.longitude)
            now = forecast.now
            days = Dictionary(uniqueKeysWithValues: forecast.days.map { ($0.day, $0) })
        } catch {
            // Keep the last good forecast; the next refresh retries.
        }
    }

    private func coordinate() async -> CLLocationCoordinate2D? {
        if let saved = Self.savedCoordinate { return saved }
        guard let location = await locator.locate() else { return nil }
        let rounded = [
            (location.coordinate.latitude * 100).rounded() / 100,
            (location.coordinate.longitude * 100).rounded() / 100,
        ]
        UserDefaults.standard.set(rounded, forKey: Self.coordinateKey)
        return CLLocationCoordinate2D(latitude: rounded[0], longitude: rounded[1])
    }

    /// The household's approximate location, once weather has found it.
    static var savedCoordinate: CLLocationCoordinate2D? {
        guard let saved = UserDefaults.standard.array(forKey: coordinateKey) as? [Double], saved.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: saved[0], longitude: saved[1])
    }

    /// Forgets the cached location, e.g. after the household moves.
    static func forgetLocation() {
        UserDefaults.standard.removeObject(forKey: coordinateKey)
    }
}

// MARK: - Open-Meteo

enum OpenMeteo {
    struct Forecast: Sendable {
        var now: WeatherStore.Now?
        var days: [WeatherStore.Day]
    }

    static var usesFahrenheit: Bool {
        Locale.current.measurementSystem == .us
    }

    static func url(latitude: Double, longitude: Double) -> URL {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: usesFahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "past_days", value: "7"),
            URLQueryItem(name: "forecast_days", value: "8"),
        ]
        return parts.url!
    }

    static func fetch(latitude: Double, longitude: Double) async throws -> Forecast {
        var request = URLRequest(url: url(latitude: latitude, longitude: longitude))
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> Forecast {
        struct Payload: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double
                var weather_code: Int
                var is_day: Int?
            }
            struct Daily: Decodable {
                var time: [String]
                var weather_code: [Int?]
                var temperature_2m_max: [Double?]
                var temperature_2m_min: [Double?]
            }
            var current: Current?
            var daily: Daily?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var days: [WeatherStore.Day] = []
        if let daily = payload.daily {
            for (index, day) in daily.time.enumerated() {
                guard index < daily.weather_code.count, let code = daily.weather_code[index],
                      let high = daily.temperature_2m_max[safe: index] ?? nil,
                      let low = daily.temperature_2m_min[safe: index] ?? nil else { continue }
                days.append(WeatherStore.Day(day: DayKey(rawValue: day), code: code, high: high, low: low))
            }
        }
        let now = payload.current.map { WeatherStore.Now(temperature: $0.temperature_2m, code: $0.weather_code, isDay: ($0.is_day ?? 1) == 1) }
        return Forecast(now: now, days: days)
    }
}

/// WMO weather codes to a symbol, an emoji and a short label.
enum WeatherCondition {
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max" : "moon.stars"
        case 1, 2: isDay ? "cloud.sun" : "cloud.moon"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...57: "cloud.drizzle"
        case 61...67: "cloud.rain"
        case 71...77, 85, 86: "cloud.snow"
        case 80...82: "cloud.heavyrain"
        case 95...99: "cloud.bolt.rain"
        default: "cloud"
        }
    }

    static func emoji(_ code: Int) -> String {
        switch code {
        case 0: "☀️"
        case 1, 2: "⛅"
        case 3: "☁️"
        case 45, 48: "🌫"
        case 51...67, 80...82: "🌧"
        case 71...77, 85, 86: "❄️"
        case 95...99: "⛈"
        default: "☁️"
        }
    }

    static func label(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "Sunny" : "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77, 85, 86: "Snow"
        case 80...82: "Showers"
        case 95...99: "Thunderstorms"
        default: "Cloudy"
        }
    }
}

/// Asks for "when in use" permission and returns one approximate location.
@MainActor
private final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func locate() async -> CLLocation? {
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined where AppFiles.isSandboxed:
                // Sample launches (screenshots, UI tests) never raise a permission prompt.
                finish(nil)
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .notDetermined: break
            default: self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

/// Current weather in the Today header: symbol, temperature, condition and high.
struct WeatherBadge: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(AppModel.self) private var model

    var body: some View {
        if let now = weather.now {
            let today = weather.day(DayKey(.now, calendar: model.calendar))
            HStack(spacing: 10) {
                Image(systemName: WeatherCondition.symbol(now.code, isDay: now.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26, weight: .regular))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(now.temperature.rounded()))\(weather.unitSymbol)")
                        .font(.display(30))
                    Text(today.map { "\(WeatherCondition.label(now.code, isDay: now.isDay)) · high \(Int($0.high.rounded()))\(weather.unitSymbol)" } ?? WeatherCondition.label(now.code, isDay: now.isDay))
                        .font(.body(12.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
