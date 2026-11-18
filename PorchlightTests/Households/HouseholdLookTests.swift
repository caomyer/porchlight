import Foundation
import Testing
@testable import Porchlight

@Suite("How a household looks in the switcher")
struct HouseholdLookTests {
    private func id(_ text: String) -> Household.ID { Household.ID(UUID(uuidString: text)!) }

    @Test func initialSkipsALeadingThe() {
        #expect(HouseholdLook.initial("The Lake House") == "L")
        #expect(HouseholdLook.initial("Grandma Rosa's") == "G")
        #expect(HouseholdLook.initial("the cabin") == "C")
        #expect(HouseholdLook.initial("The") == "T")
        #expect(HouseholdLook.initial("") == "?")
    }

    @Test func colorsAreStableAndDistinct() {
        let ids = (0..<PersonColor.allCases.count).map { _ in Household.ID(UUID()) }
        let colors = HouseholdLook.colors(for: ids)
        #expect(Set(colors.values).count == ids.count, "every household its own color while they go round")
        #expect(HouseholdLook.colors(for: ids) == colors, "the same every time")
        // A household keeps its color whatever comes after it in the list.
        let first = id("00000000-0000-0000-0000-000000000001")
        #expect(HouseholdLook.colors(for: [first])[first] == HouseholdLook.colors(for: [first] + ids)[first])
    }
}
