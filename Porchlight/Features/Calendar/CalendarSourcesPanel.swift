import SwiftUI
import UIKit

/// Calendar access and the per-calendar mapping table. Shared by the
/// onboarding step and the Settings section.
struct CalendarSourcesPanel: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch store.access {
            case .notDetermined:
                AccessPrompt()
            case .denied:
                AccessDenied()
            case .granted:
                AccountsCard()
                MappingTable()
            }
            if let error = store.lastError {
                Text(error)
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

@MainActor
private func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}

/// The calendar glyph in a soft accent tile.
private struct CalendarTile: View {
    var symbol = "calendar"
    var size: CGFloat = 54

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .regular))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Theme.accent.wash(0.14), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Permission states

private struct AccessPrompt: View {
    @Environment(CalendarStore.self) private var store
    @State private var isAsking = false

    var body: some View {
        VStack(spacing: 14) {
            CalendarTile(size: 72)
            Text("Show your calendars on the wall")
                .font(.display(26))
            Text("Porchlight reads the calendars this iPad already has, like iCloud, Google and Outlook, and passes on the ones you choose to everyone's phones. It adds or changes an event only when you do.")
                .font(.body(15, weight: 500))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            Button {
                isAsking = true
                Task {
                    await store.requestAccess()
                    isAsking = false
                }
            } label: {
                Text("Allow calendar access")
                    .font(.body(18, weight: 700))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isAsking)
            .padding(.top, 6)
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }
}

private struct AccessDenied: View {
    var body: some View {
        HStack(spacing: 18) {
            CalendarTile(symbol: "calendar.badge.exclamationmark")
            VStack(alignment: .leading, spacing: 3) {
                Text("Calendar access is turned off")
                    .font(.body(16, weight: 700))
                Text("Porchlight can't read your calendars yet. In iPad Settings, open Porchlight › Calendars and choose Full Access.")
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open iPad Settings", action: openAppSettings)
                .buttonStyle(SecondaryButtonStyle())
        }
        .foregroundStyle(Theme.ink)
        .card()
    }
}

// MARK: - Accounts

private struct AccountsCard: View {
    @State private var showsLinkTip = false

    var body: some View {
        HStack(spacing: 18) {
            CalendarTile()
            VStack(alignment: .leading, spacing: 2) {
                Text("Add accounts once, in iPad Settings")
                    .font(.body(16, weight: 700))
                Text("Settings › Calendar › Accounts supports Google, iCloud, Outlook, Yahoo, Exchange and CalDAV. Shared calendars come along automatically.")
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ProviderBadge(color: Color(hex: 0x4285F4)) { Text("G") }
                    ProviderBadge(color: Color(hex: 0x555555)) { Image(systemName: "applelogo") }
                    ProviderBadge(color: Color(hex: 0x0F6CBD)) { Text("O") }
                    ProviderBadge(color: Color(hex: 0x6001D2)) { Text("Y") }
                    ProviderBadge(color: Theme.accent) { Image(systemName: "link") }
                }
                .padding(.top, 8)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Button("Open iPad Settings", action: openAppSettings)
                Button {
                    showsLinkTip = true
                } label: {
                    Label("Add calendar link", systemImage: "plus")
                }
                .popover(isPresented: $showsLinkTip, arrowEdge: .bottom) {
                    LinkTip()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
        }
        .foregroundStyle(Theme.ink)
        .card()
    }
}

private struct ProviderBadge<Content: View>: View {
    let color: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// How to add an ICS link: iPadOS only lets the system subscribe to one.
private struct LinkTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a calendar link")
                .font(.display(22))
            Text("School, sports team or holiday calendars often come as a link ending in .ics. Subscribe to it once on this iPad and it shows up in the list below.")
                .font(.body(14, weight: 500))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Copy the calendar link.")
                step(2, "Open Settings › Calendar › Accounts › Add Account › Other.")
                step(3, "Tap Add Subscribed Calendar and paste the link.")
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Theme.ink)
        .padding(22)
        .frame(width: 380)
        .background(Theme.surface)
        .presentationBackground(Theme.surface)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.body(12, weight: 800))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accent.wash(0.14), in: Circle())
            Text(text).font(.body(14, weight: 600))
        }
    }
}

// MARK: - Mapping table

private enum Columns {
    static let owner: CGFloat = 150
    static let visibility: CGFloat = 170
    static let toggle: CGFloat = 70
    static let spacing: CGFloat = 12
}

private struct MappingTable: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        let mappings = store.mappings
        VStack(spacing: 0) {
            HStack(spacing: Columns.spacing) {
                Text("Calendar · \(mappings.count) found").frame(maxWidth: .infinity, alignment: .leading)
                Text("Account").frame(maxWidth: .infinity, alignment: .leading)
                Text("Belongs to").frame(width: Columns.owner, alignment: .leading)
                Text("Household sees").frame(width: Columns.visibility, alignment: .leading)
                Text("On wall").frame(width: Columns.toggle, alignment: .leading)
            }
            .font(.body(11.5, weight: 800))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }

            if mappings.isEmpty {
                Text("No calendars on this iPad yet. Add an account in iPad Settings and it will appear here.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Scroll only when there are more calendars than fit.
                ViewThatFits(in: .vertical) {
                    rows(mappings)
                    ScrollView { rows(mappings) }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .background(SurfaceShape(cornerRadius: Theme.radius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        // The choices have been seen here, so this iPad may pass its calendars on.
        .onAppear { if !mappings.isEmpty { store.choicesSeen() } }
    }

    private func rows(_ mappings: [(calendar: ExternalCalendar, source: CalendarSource)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(mappings.enumerated()), id: \.element.calendar.id) { index, mapping in
                MappingRow(calendar: mapping.calendar, source: mapping.source)
                    .overlay(alignment: .bottom) {
                        if index < mappings.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                    }
            }
        }
    }
}

private struct MappingRow: View {
    let calendar: ExternalCalendar
    let source: CalendarSource

    @Environment(CalendarStore.self) private var store

    var body: some View {
        HStack(spacing: Columns.spacing) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: UInt32(truncatingIfNeeded: calendar.colorHex)))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .font(.body(14, weight: 700))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(calendar.account)
                .font(.body(13, weight: 600))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ownerMenu
                .frame(width: Columns.owner)
            visibilityMenu
                .frame(width: Columns.visibility)
            Toggle("Show \(calendar.title) on the wall", isOn: Binding(
                get: { source.isShown },
                set: { store.setShown($0, for: source) }
            ))
            .labelsHidden()
            .tint(Theme.good)
            .scaleEffect(0.82, anchor: .leading)
            .frame(width: Columns.toggle, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var ownerMenu: some View {
        Menu {
            ForEach(store.people) { person in
                Button(person.name) { store.setOwner(.person(person.id), for: source) }
            }
            Button("Everyone") { store.setOwner(.everyone, for: source) }
        } label: {
            DropdownLabel {
                OwnerAvatar(owner: source.owner, people: store.people, size: 22)
                Text(ownerName(source.owner, people: store.people))
            }
        }
        .accessibilityLabel("\(calendar.title) belongs to \(ownerName(source.owner, people: store.people))")
    }

    private var visibilityMenu: some View {
        Menu {
            ForEach(CalendarChoice.allCases) { choice in
                Button { store.setSharing(choice, for: source) } label: {
                    Text(choice.label)
                    Text(choice.explanation)
                }
            }
        } label: {
            DropdownLabel {
                Text(source.sharing.label)
            }
        }
        .accessibilityLabel("\(calendar.title): the household sees \(source.sharing.label)")
        .accessibilityIdentifier("sharing-\(calendar.title)")
    }
}

/// The bordered dropdown look from the mock: content, then a small caret.
private struct DropdownLabel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()
                .font(.body(13, weight: 700))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line))
        .contentShape(Rectangle())
    }
}
