import Foundation
import Testing
import UIKit
@testable import Porchlight

/// This device's role and who it belongs to: device-local, never in the database.
@Suite("Device settings")
@MainActor
struct DeviceSettingsTests {
    private let defaults: UserDefaults

    init() {
        let suite = "porchlight.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("An iPad starts as a shared screen and a phone as personal")
    func roleDefaults() {
        #expect(DeviceRole.standard(for: .pad) == .sharedScreen)
        #expect(DeviceRole.standard(for: .phone) == .personal)
        #expect(DeviceSettings(defaults: defaults, idiom: .pad).role == .sharedScreen)
        #expect(DeviceSettings(defaults: defaults, idiom: .phone).role == .personal)
    }

    @Test("A role that was set wins over the default, on the next launch too")
    func roleIsStored() {
        DeviceSettings(defaults: defaults, idiom: .pad).setRole(.personal)
        #expect(DeviceSettings(defaults: defaults, idiom: .pad).role == .personal)
    }

    @Test("\"Me\" is kept per household and survives a relaunch")
    func meIsPerHousehold() {
        let lake: Household.ID = 1, rosas: Household.ID = 2
        let settings = DeviceSettings(defaults: defaults, idiom: .phone)
        #expect(settings.me(in: lake) == nil)
        settings.setMe(10, in: lake)
        settings.setMe(20, in: rosas)
        let relaunched = DeviceSettings(defaults: defaults, idiom: .phone)
        #expect(relaunched.me(in: lake) == 10)
        #expect(relaunched.me(in: rosas) == 20)
        relaunched.setMe(nil, in: lake)
        #expect(DeviceSettings(defaults: defaults, idiom: .phone).me(in: lake) == nil)
        #expect(DeviceSettings(defaults: defaults, idiom: .phone).me(in: rosas) == 20)
    }

    @Test("Forgetting clears who this device was in every household, and nothing else")
    func forget() {
        DeviceSettings.store(me: 10, in: 1, defaults: defaults)
        DeviceSettings.store(me: 20, in: 2, defaults: defaults)
        DeviceSettings(defaults: defaults, idiom: .phone).setRole(.sharedScreen)
        DeviceSettings.forgetMe(defaults: defaults)
        let settings = DeviceSettings(defaults: defaults, idiom: .phone)
        #expect(settings.me(in: 1) == nil)
        #expect(settings.me(in: 2) == nil)
        #expect(settings.role == .sharedScreen)
    }
}
