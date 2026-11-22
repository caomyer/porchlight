import SwiftUI
import UIKit

/// "Calendars on this iPhone": which of this phone's calendars Today shows, and for each
/// what the household gets (docs/design/calendar-shared.md): Show everything, Keep it
/// quiet, Busy only or Just me, and whose it is. Asking for calendar access happens here,
/// after saying why.
/// Nothing is passed on from this device until this page has shown the choices once.
struct PocketCalendars: View {
    @Environment(CalendarStore.self) private var store
    @State private var isAsking = false
    @State private var choosingHome = false
    @Environment(\.dynamicTypeSize) private var typeSize

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
                case .granted:
                    homeCalendar
                    choices
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .sheet(isPresented: $choosingHome) { PocketHomeCalendarSheet() }
    }

    // MARK: The home calendar

    /// Where events added in Porchlight are saved, for the whole household; changed here.
    private var homeCalendar: some View {
        let words: (title: String, detail: String) = switch store.home {
        case .notChosen: ("Not chosen yet", "Events added in Porchlight will be saved in it.")
        case let .found(calendar): ("\(calendar.title) · \(calendar.accountKind)", "Events added in Porchlight are saved here.")
        case let .notHere(home): (HomeCalendarLogic.name(home), "Not on this \(DeviceWords.this), so it adds nothing here.")
        case let .readOnly(calendar): ("\(calendar.title) · \(calendar.accountKind)", "This \(DeviceWords.this) can't add to it any more.")
        case .ambiguous: ("Which one?", "More than one of this \(DeviceWords.this)'s calendars has its name.")
        }
        return Button { choosingHome = true } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("HOME CALENDAR")
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                        .tracking(1.1)
                        .foregroundStyle(Theme.muted)
                    Text(words.title).phoneFont(.body, 15, weight: 700, relativeTo: .subheadline)
                    Text(words.detail)
                        .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Change").phoneFont(.body, 13, weight: 800, relativeTo: .footnote).foregroundStyle(Theme.accent)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-calendar")
        .phoneCard()
    }

    // MARK: Access

    /// Why first, then the system prompt.
    private var askFirst: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bring your calendars to the household")
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
            Text("Porchlight reads the calendars this \(DeviceWords.this) already has, like iCloud, Google and Outlook, and passes on the ones you choose, so the wall and everyone's phone show them. It adds or changes an event only when you do.")
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
        Text("Choose whose each calendar is and what your household sees from it. A work calendar is a good one to keep quiet: everyone sees one block a day, like \"at work until 5:30\", with the meetings a tap away.")
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

    /// The calendar, then whose it is and what the household sees, each a menu: on one line
    /// where they fit, the second under the first where they don't.
    private func row(_ calendar: ExternalCalendar, source: CalendarSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            showRow(calendar, source: source)
            FlowLayout(spacing: 8, lineSpacing: 4) {
                labelled("Belongs to") { ownerMenu(calendar, source: source) }
                labelled("Household sees") { sharingMenu(calendar, source: source) }
            }
            .padding(.leading, typeSize.isAccessibilitySize ? 0 : 34)
        }
        .padding(.vertical, 6)
    }

    /// "Belongs to" beside its menu, or over it at the accessibility sizes, where the two
    /// don't fit on one line.
    private func labelled(_ title: String, @ViewBuilder _ menu: () -> some View) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Text(title)
                .phoneFont(.body, 11.5, weight: 700, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
            menu()
        }
    }

    private func ownerMenu(_ calendar: ExternalCalendar, source: CalendarSource) -> some View {
        let name = ownerName(source.owner, people: store.people)
        return Menu {
            ForEach(store.people) { person in
                Button(person.name) { store.setOwner(.person(person.id), for: source) }
            }
            Button("Everyone") { store.setOwner(.everyone, for: source) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(source.ownerId.flatMap { id in store.people.first { $0.id == id }?.color.color } ?? Theme.everyone)
                    .frame(width: 8, height: 8)
                Text(name).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            // Its whole name where there is room; smaller only at the accessibility sizes.
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
            .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(calendar.title) belongs to \(name)")
        .accessibilityIdentifier("owner-\(calendar.title)")
    }

    private func showRow(_ calendar: ExternalCalendar, source: CalendarSource) -> some View {
        HStack(spacing: 10) {
            Button { store.setShown(!source.isShown, for: source) } label: {
                HStack(spacing: 10) {
                    PocketCheck(isOn: source.isShown)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: UInt32(truncatingIfNeeded: calendar.colorHex)))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(calendar.title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        // A calendar named by its address says the address once: then the kind.
                        Text(CalendarOwnerGuess.isAddress(calendar.title) && calendar.account.contains(calendar.title) ? calendar.accountKind : calendar.account)
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
        }
    }

    private func sharingMenu(_ calendar: ExternalCalendar, source: CalendarSource) -> some View {
        Menu {
            ForEach(CalendarChoice.allCases) { choice in
                Button { store.setSharing(choice, for: source) } label: {
                    Text(choice.label)
                    Text(choice.explanation)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(source.sharing.label).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            // Its whole name where there is room; smaller only at the accessibility sizes.
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
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
}
