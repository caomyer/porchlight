import SwiftUI
import UIKit

/// "Calendars on this iPhone": which of this phone's calendars Today shows, and for each
/// what the household gets (docs/design/calendar-shared.md): Show everything, Keep it
/// quiet, Busy only or Just me. Asking for calendar access happens here, after saying why.
/// Nothing is passed on from this device until this page has shown the choices once.
struct PocketCalendars: View {
    @Environment(CalendarStore.self) private var store
    @State private var isAsking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("On this \(DeviceWords.this)")
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    Text("Calendars")
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                }
                switch store.access {
                case .notDetermined: askFirst
                case .denied: denied
                case .granted: choices
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
    }

    // MARK: Access

    /// Why first, then the system prompt.
    private var askFirst: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bring your calendars to the household")
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
            Text("Porchlight reads the calendars this \(DeviceWords.this) already has, like iCloud, Google and Outlook, and passes on the ones you choose, so the wall and everyone's phone show them. It never changes them.")
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
            Button("Allow calendar access") {
                isAsking = true
                Task {
                    await store.requestAccess()
                    isAsking = false
                }
            }
            .buttonStyle(PhoneButtonStyle())
            .disabled(isAsking)
            .accessibilityIdentifier("allow-calendars")
        }
        .phoneCard()
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar access is turned off")
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
            Text("Porchlight can't read this \(DeviceWords.this)'s calendars. In Settings, open Porchlight › Calendars and choose Full Access.")
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PhoneButtonStyle(kind: .ghost))
        }
        .phoneCard()
    }

    // MARK: Choices

    @ViewBuilder
    private var choices: some View {
        Text("Choose what your household sees from each calendar. A work calendar is a good one to keep quiet: everyone sees one block a day, like \"at work until 5:30\", with the meetings a tap away.")
            .phoneFont(.body, 13.5, weight: 500, relativeTo: .subheadline)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { store.choicesSeen() }
        let mappings = store.mappings
        if mappings.isEmpty {
            Text("This \(DeviceWords.this) has no calendars yet. Add an account in Settings › Calendar.")
                .phoneFont(.body, 13.5, weight: 600)
                .foregroundStyle(Theme.muted)
                .phoneCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(mappings.enumerated()), id: \.element.source.id) { index, mapping in
                    if index > 0 { RowDivider() }
                    row(mapping.calendar, source: mapping.source)
                }
            }
            .phoneCard()
        }
        Text("Passed on through your household's iCloud, to the people in it. Busy only sends the times, never titles, places or notes. Just me sends nothing. The tick is for Today on this \(DeviceWords.this).")
            .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ calendar: ExternalCalendar, source: CalendarSource) -> some View {
        HStack(spacing: 10) {
            Button { store.setShown(!source.isShown, for: source) } label: {
                HStack(spacing: 10) {
                    PocketCheck(isOn: source.isShown)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: UInt32(truncatingIfNeeded: calendar.colorHex)))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(calendar.title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        Text(calendar.account)
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(calendar.title) on Today")
            .accessibilityValue(source.isShown ? "On" : "Off")
            Menu {
                ForEach(CalendarChoice.allCases) { choice in
                    Button { store.setSharing(choice, for: source) } label: {
                        Text(choice.label)
                        Text(choice.explanation)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(source.sharing.label)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(source.sharing == .justMe ? Theme.surface : Theme.accentSoft, in: Capsule())
                .overlay(Capsule().strokeBorder(source.sharing == .justMe ? Theme.line : Theme.accent))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(calendar.title) is shared as \(source.sharing.label)")
            .accessibilityIdentifier("sharing-\(calendar.title)")
        }
        .padding(.vertical, 4)
    }
}
