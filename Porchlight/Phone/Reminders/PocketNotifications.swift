import SwiftUI
import UIKit

/// "Notifications" in the You sheet: which routines remind this person, and when, and
/// whether their chores do. It says what reminders are before iOS asks; with
/// notifications turned off it says how to turn them on. Choices stay on this phone.
struct PocketNotifications: View {
    @Environment(CompanionStore.self) private var companions
    @Environment(ReminderSettings.self) private var settings
    @Environment(\.scenePhase) private var phase
    @State private var access: NotificationAccess?
    @State private var isAsking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(companions.snapshot.household?.name ?? "Your household")
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    Text("Notifications")
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                }
                switch access {
                case .notDetermined: askFirst
                case .denied: denied
                case .allowed: choices
                case nil: EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        // Coming back from Settings may have changed the answer.
        .task(id: phase) { access = await NotificationAccess.current() }
    }

    // MARK: Access

    private var askFirst: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remind you about your routines?")
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
            Text("Only the ones you choose, like a walk when its window opens, and your own chores the evening before. Nothing when someone else logs something.")
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
            Button("Allow reminders") {
                isAsking = true
                Task {
                    access = await NotificationAccess.request()
                    isAsking = false
                }
            }
            .buttonStyle(PhoneButtonStyle())
            .disabled(isAsking)
            .accessibilityIdentifier("allow-reminders")
        }
        .phoneCard()
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications are turned off")
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
            Text("Porchlight can't remind you. In Settings, open Porchlight › Notifications and turn on Allow Notifications.")
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PhoneButtonStyle(kind: .ghost))
            .accessibilityIdentifier("open-settings")
        }
        .phoneCard()
    }

    // MARK: Choices

    @ViewBuilder
    private var choices: some View {
        let slots = ReminderSlots.all(companions.snapshot)
        if !slots.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("Your routines")
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    if index > 0 { RowDivider() }
                    slotRow(slot)
                }
            }
            .phoneCard()
        }
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Chores")
            choresRow
        }
        .phoneCard()
        Text("Porchlight never notifies you about what others did. These choices are for this \(DeviceWords.this) only.")
            .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
            .foregroundStyle(Theme.muted)
    }

    private func slotRow(_ slot: ReminderSlots.Slot) -> some View {
        let timing = settings.choices.timing(slot.routine.id, slot: slot.index)
        return AdaptiveRow {
            HStack(spacing: 10) {
                Text(slot.routine.emoji).phoneFont(.body, 18).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    Text(ReminderSlots.describe(timing, window: slot.window))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Menu {
                ForEach(CareReminderTiming.allCases) { option in
                    Button(ReminderSlots.choice(option, window: slot.window)) {
                        settings.update { $0.care[ReminderChoices.slotKey(slot.routine.id, slot: slot.index)] = option }
                    }
                }
            } label: {
                ChoiceLabel(text: timing == .off ? "Off" : "On", isOn: timing != .off)
            }
            .accessibilityLabel("\(slot.title): \(ReminderSlots.describe(timing, window: slot.window))")
            .accessibilityIdentifier("remind-\(slot.title)")
        }
        .padding(.vertical, 4)
    }

    private var choresRow: some View {
        let isOn = settings.choices.chores
        return AdaptiveRow {
            HStack(spacing: 10) {
                Text("☑️").phoneFont(.body, 18).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your chores").phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    Text(isOn ? "The evening before they're due · 7 pm" : "Off")
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { settings.update { $0.chores.toggle() } } label: {
                ChoiceLabel(text: isOn ? "On" : "Off", isOn: isOn)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your chores, the evening before")
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityIdentifier("remind-chores")
        }
        .padding(.vertical, 4)
    }
}

/// The small outlined "On" / "Off" on a choice row.
private struct ChoiceLabel: View {
    let text: String
    let isOn: Bool

    var body: some View {
        Text(text)
            .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Theme.accentSoft : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Theme.accent : Theme.line))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// The care slots a person can be reminded of, and their words. Pure.
enum ReminderSlots {
    struct Slot: Identifiable {
        var routine: CareRoutine
        var index: Int
        var window: CareWindow
        /// "Yo-Yo · evening walk".
        var title: String
        var id: String { ReminderChoices.slotKey(routine.id, slot: index) }
    }

    static func all(_ snapshot: CompanionSnapshot) -> [Slot] {
        snapshot.routines.flatMap { routine -> [Slot] in
            guard let companion = snapshot.companions.first(where: { $0.id == routine.companionId }) else { return [] }
            return routine.effectiveWindows.enumerated().map { index, window in
                Slot(routine: routine, index: index, window: window, title: "\(companion.name) · \(CareCatchUp.slotName(window, of: routine))")
            }
        }
    }

    /// "5-8pm · when it opens", "Only if missed by 7pm", "Off".
    static func describe(_ timing: CareReminderTiming, window: CareWindow) -> String {
        switch timing {
        case .off: "Off"
        case .opens: window.isAllDay ? "Due days · 9 am" : "\(window.rangeText) · when it opens"
        case .missed: window.isAllDay ? "Only if missed by 7 pm" : "Only if missed by \(window.end >= 24 * 60 ? "midnight" : CareTime.hour(window.end))"
        }
    }

    /// The menu's words for each choice.
    static func choice(_ timing: CareReminderTiming, window: CareWindow) -> String {
        switch timing {
        case .off: "Off"
        case .opens: window.isAllDay ? "In the morning it's due" : "When it opens, \(CareTime.hour(window.start))"
        case .missed: describe(.missed, window: window)
        }
    }
}
