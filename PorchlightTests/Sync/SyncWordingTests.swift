import Foundation
import Testing
@testable import Porchlight

/// The one line Settings says about sync in each state where iCloud is missing or a choice
/// is waiting, and that each of those states counts as stuck, which is what puts the dot on
/// the gear. The wall's UI tests keep one launch that shows the line and the dot on screen
/// (`SyncSettingsTests`); the words for each state are checked here.
@Suite("What Settings says about sync")
struct SyncWordingTests {
    @Test("Each way iCloud can be missing says why, and what to do")
    func missingICloud() {
        #expect(SyncStatus.account(.signedOut).summary == "iCloud is off for Porchlight: this iPad isn't signed in to iCloud, or iCloud is turned off for Porchlight. Turn it on in the Settings app to sync again; everything stays here meanwhile.")
        #expect(SyncStatus.account(.restricted).summary == "iCloud isn't allowed on this iPad: Screen Time, or whoever manages it, has turned it off. Everything stays here.")
        #expect(SyncStatus.account(.needsSignIn).summary == "iCloud needs you to sign in again. Sign in to your Apple Account in the Settings app to sync again; everything stays here meanwhile.")
        #expect(SyncStatus.account(.couldNotCheck).summary == "Can't check this iPad's iCloud account right now. Changes keep saving here and go up once iCloud answers.")
    }

    @Test("A full iCloud and a waiting choice say what sync is waiting for")
    func pausedAndWaiting() {
        #expect(SyncStatus.iCloudFull.summary == "Paused until there's room in iCloud.")
        #expect(SyncStatus.needsDecision(.accountChanged).summary == "The household on this iPad belongs to the earlier account, so nothing syncs until you choose what to do with it.")
        #expect(SyncStatus.needsDecision(.restoredCopy).summary == "It was put back from a backup, so iCloud may have newer walks, meals and chores. Nothing syncs until you choose, and this copy is never sent over what is in iCloud.")
    }

    @Test("Every missing iCloud, a full one and a waiting choice are stuck, so the gear shows its dot; off and working are not")
    func stuck() {
        let stuck: [SyncStatus] = [
            .account(.signedOut), .account(.restricted), .account(.needsSignIn), .account(.couldNotCheck),
            .iCloudFull, .needsDecision(.accountChanged), .needsDecision(.restoredCopy),
            .waiting(lastSynced: nil), .notChecked(lastSynced: nil), .notAccepted(count: 1),
        ]
        for status in stuck {
            #expect(status.isStuck, "\(status)")
        }
        let fine: [SyncStatus] = [.off(.switchedOff), .off(.sampleData), .upToDate(lastSynced: nil), .syncing]
        for status in fine {
            #expect(!status.isStuck, "\(status)")
        }
    }
}
