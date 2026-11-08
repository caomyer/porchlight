#if DEBUG
import Foundation

enum CalendarSamples {
    /// Seeds sample data matching the mocks (DEBUG `-sampleHousehold` only).
    static func seed(_ database: AppDatabase, household: Household, people: [Person]) throws {}
}
#endif
