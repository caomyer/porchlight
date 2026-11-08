import Foundation
import Testing
@testable import Porchlight

@Suite("Weather")
struct WeatherTests {
    @Test("Requests only rounded coordinates")
    func url() {
        let url = OpenMeteo.url(latitude: 37.774929, longitude: -122.419416).absoluteString
        #expect(url.contains("latitude=37.77"))
        #expect(url.contains("longitude=-122.42"))
        #expect(!url.contains("37.7749"))
    }

    @Test("Parses current conditions and daily highs")
    func parse() throws {
        let json = """
        {"current":{"temperature_2m":58.2,"weather_code":0,"is_day":0},
         "daily":{"time":["2026-11-07","2026-11-08"],"weather_code":[2,null],
                  "temperature_2m_max":[64.1,60.0],"temperature_2m_min":[48.0,47.5]}}
        """
        let forecast = try OpenMeteo.parse(Data(json.utf8))
        #expect(forecast.now == WeatherStore.Now(temperature: 58.2, code: 0, isDay: false))
        #expect(WeatherCondition.label(0, isDay: false) == "Clear")
        #expect(forecast.days.count == 1)
        #expect(forecast.days.first?.day == DayKey(rawValue: "2026-11-07"))
        #expect(forecast.days.first?.high == 64.1)
    }

    @Test("Weather codes map to symbols and labels", arguments: [(0, "sun.max", "Sunny"), (63, "cloud.rain", "Rain"), (95, "cloud.bolt.rain", "Thunderstorms")])
    func conditions(code: Int, symbol: String, label: String) {
        #expect(WeatherCondition.symbol(code) == symbol)
        #expect(WeatherCondition.label(code) == label)
    }
}
