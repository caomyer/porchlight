import SwiftUI

extension View {
    /// Keeps this device's row in the current household up to date: written when the
    /// device opens the household, when its name, role, person or iCloud account changes,
    /// and once a day when it comes to the front (docs/design/households.md).
    func keepsThisDeviceRow() -> some View {
        modifier(ThisDeviceRow())
    }
}

private struct ThisDeviceRow: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(SyncController.self) private var sync
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(\.scenePhase) private var scenePhase

    private struct Key: Hashable {
        var householdId: Household.ID?
        var row: ThisDevice
        var isActive: Bool
    }

    private var row: ThisDevice? {
        guard let household = model.household, household.setupCompleted else { return nil }
        let me = device.me(in: household.id).flatMap(model.people.person)
        return ThisDevice(
            name: device.name(me: me),
            role: device.role,
            model: device.model,
            personId: me?.id,
            userName: sync.userName ?? sharing.userName
        )
    }

    func body(content: Content) -> some View {
        content.task(id: Key(householdId: model.household?.id, row: row ?? ThisDevice(name: "", role: device.role, model: ""), isActive: scenePhase == .active)) {
            guard scenePhase == .active, let row else { return }
            model.saveThisDevice(row)
        }
    }
}
