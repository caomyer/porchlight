import SwiftUI

/// "Your households" in the You sheet (journey A5, `a5switch`): each household this phone
/// belongs to, who you are there and how many live there, a tick on the one showing, one
/// tap to switch, and "Join or start another". Today, Food, Lists and Glow show one
/// household at a time; reminders come from all of them, each named.
struct PocketHouseholds: View {
    /// After a switch: the You sheet closes so the tabs show the household.
    let onSwitch: () -> Void
    let onAnother: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your households")
                .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            PhoneList {
                ForEach(Array(model.households.enumerated()), id: \.element.id) { index, choice in
                    if index > 0 { RowDivider() }
                    row(choice)
                }
                RowDivider()
                AnotherHouseholdRow(action: onAnother)
            }
            Text("Today, Food, Lists and Glow show one household at a time. Reminders come from all of them, each named.")
                .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var colors: [Household.ID: PersonColor] {
        HouseholdLook.colors(for: model.households.map(\.id))
    }

    private func row(_ choice: HouseholdChoice) -> some View {
        let isCurrent = choice.id == model.household?.id
        return Button {
            model.switchHousehold(to: choice.id)
            onSwitch()
        } label: {
            HStack(spacing: 12) {
                HouseholdBadge(name: choice.household.name, color: colors[choice.id] ?? .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.household.name)
                        .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        .foregroundStyle(Theme.ink)
                    Text(choice.line(me: device.me(in: choice.id)))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isCurrent ? "Showing now" : "")
        .accessibilityHint(isCurrent ? "" : "Shows this household")
        .accessibilityIdentifier("household-\(choice.household.name)")
    }
}

/// How a household looks in the list, so two read apart at a glance with nothing stored:
/// the first letter of its name on a tint of a color drawn from its id. People are solid
/// circles; a household is a soft rounded square, so the two never look alike.
enum HouseholdLook {
    /// A color for each household, drawn from its id so it is the same on every device and
    /// every launch. When two in the list would share one, the later moves to the next free
    /// color, so households differ while there are colors to go round.
    static func colors(for ids: [Household.ID]) -> [Household.ID: PersonColor] {
        let palette = PersonColor.allCases
        var taken = Set<PersonColor>()
        var colors: [Household.ID: PersonColor] = [:]
        for id in ids {
            let start = Int(stableHash(id.description) % UInt64(palette.count))
            let free = (0..<palette.count).map { palette[(start + $0) % palette.count] }.first { !taken.contains($0) }
            let color = free ?? palette[start]
            taken.insert(color)
            colors[id] = color
        }
        return colors
    }

    /// "L" for The Lake House, "G" for Grandma Rosa's: the first letter after a leading "The".
    static func initial(_ name: String) -> String {
        var words = name.split(separator: " ")
        if words.count > 1, words[0].lowercased() == "the" { words.removeFirst() }
        return words.first?.first.map { String($0).uppercased() } ?? "?"
    }

    /// FNV-1a, which unlike `hashValue` is the same in every process.
    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// A household's initial on a soft tint of its color, a rounded square beside its name.
struct HouseholdBadge: View {
    let name: String
    let color: PersonColor

    @Environment(\.colorScheme) private var scheme
    @PhoneMetric private var side: CGFloat = 36

    var body: some View {
        Text(HouseholdLook.initial(name))
            .phoneFont(.display, 18, weight: 700, relativeTo: .headline)
            .foregroundStyle(color.color)
            .frame(width: side, height: side)
            .background(color.color.opacity(scheme == .dark ? 0.26 : 0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// "Join or start another household".
struct AnotherHouseholdRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.accentSoft))
                    .accessibilityHidden(true)
                Text("Join or start another")
                    .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("another-household")
    }
}

/// "Join or start another": the welcome's two doors, for a phone that already belongs to
/// a household. Starting one runs the same setup as a first household; joining needs an
/// invite or a code from that household's owner.
struct AnotherHouseholdPage: View {
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Another household")
                    .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("For a co-parent's home, a grandparent's, or a neighbor's pets. Each household keeps its own people, care and lists, and this phone shows one at a time.")
                    .phoneFont(.body, 14, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onStart) {
                    Text("Start a household")
                        .phoneFont(.body, 16, weight: 700)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.accentInk)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("start-another")
                PhoneList {
                    way("✉️", "Join with an invite", "Open the invite its owner sent you. Porchlight asks if you want to join.")
                    RowDivider()
                    way("📷", "Or scan its code", "On that household owner's iPhone, open Porchlight: You › Invite someone › Show a code, and point the Camera app at it.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("")
    }

    private func way(_ emoji: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).phoneFont(.body, 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                Text(detail)
                    .phoneFont(.body, 13, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
