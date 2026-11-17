import Foundation
import Testing
@testable import Porchlight

/// Every screen that names where the household lives tells the truth for sync's state.
@Suite("Where the household lives")
struct HouseholdHomeTests {
    private func home(_ status: SyncStatus, isOwner: Bool = true, owner: String? = "James") -> HouseholdHome {
        .from(status, isOwner: isOwner, ownerName: owner)
    }

    @Test("Sync off: on this device only, and inviting says to turn sync on")
    func off() {
        let home = home(.off(.switchedOff))
        #expect(home == .thisDeviceOnly)
        #expect(home.whereText(device: "iPad") == "on this iPad only")
        #expect(home.inviteBlocker(device: "iPad") == "Turn on iCloud sync to invite phones.")
        #expect(home.turnsOnWithTheSwitch)
    }

    @Test("Sync that can't run here is never called iCloud")
    func unavailable() {
        for reason in [SyncOffReason.sampleData, .noEntitlement, .failed("No network")] {
            let home = home(.off(reason))
            #expect(home == .syncUnavailable)
            #expect(home.whereText(device: "iPhone") == "on this iPhone only")
            #expect(home.inviteBlocker(device: "iPhone") != nil)
            #expect(!home.turnsOnWithTheSwitch, "the switch can't fix it")
        }
    }

    @Test("Sync on: in this user's iCloud, or the owner's, and inviting works")
    func on() {
        for status in [SyncStatus.upToDate(lastSynced: .now), .syncing, .waiting(lastSynced: nil), .iCloudFull] {
            #expect(home(status).whereText(device: "iPad") == "stored in your iCloud")
            #expect(home(status, isOwner: false).whereText(device: "iPad") == "stored in James's iCloud")
            #expect(home(status).inviteBlocker(device: "iPad") == nil)
            #expect(home(status, isOwner: false).inviteBlocker(device: "iPad") == nil)
        }
        #expect(home(.syncing, isOwner: false, owner: nil).whereText(device: "iPad") == "stored in its owner's iCloud")
        #expect(HouseholdHome.from(.syncing, isOwner: true, ownerName: "James", onSharedScreen: true).whereText(device: "iPad")
                == "stored in James's iCloud", "the hallway wall names its owner")
        #expect(HouseholdHome.from(.syncing, isOwner: true, ownerName: nil, onSharedScreen: true) == .yourICloud)
    }

    @Test("Signed out, or waiting for a choice: here until that is sorted, and inviting says how")
    func stuck() {
        let signedOut = home(.noAccount)
        #expect(signedOut.whereText(device: "iPad") == "on this iPad until you sign in to iCloud")
        #expect(signedOut.inviteBlocker(device: "iPad") == "Sign in to iCloud in the Settings app to invite phones.")
        for decision in [SyncDecision.accountChanged, .restoredCopy] {
            let waiting = home(.needsDecision(decision))
            #expect(waiting.whereText(device: "iPad") == "on this iPad until you choose what to do about iCloud sync")
            #expect(waiting.inviteBlocker(device: "iPad") == "Choose what to do about iCloud sync to invite phones.")
        }
    }
}
