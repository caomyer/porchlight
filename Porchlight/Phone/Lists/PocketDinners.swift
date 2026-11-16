import SwiftUI

/// This week's dinners from the wall's meal plan, as a list. A dinner opens the wall's
/// dinner editor; "Add what it needs" puts its ingredients on the grocery list.
struct PocketDinners: View {
    let onEdit: (DayKey) -> Void
    let onNeeds: (DayKey) -> Void

    @Environment(HomeStore.self) private var home

    var body: some View {
        let calendar = home.calendar
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(home.week.days.enumerated()), id: \.element) { index, day in
                    if index > 0 { RowDivider() }
                    row(day, calendar: calendar)
                }
            }
            .phoneCard()
            Text("Tap a dinner to plan or change it. Groceries it needs go on the grocery list.")
                .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private func row(_ day: DayKey, calendar: Calendar) -> some View {
        let meal = home.meal(on: day)
        let weekday = day.formatted(.dateTime.weekday(.abbreviated), calendar: calendar)
        let isToday = day == home.today
        return HStack(spacing: 10) {
            Button { onEdit(day) } label: {
                AdaptiveRow {
                    Text(weekday)
                        .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                        .foregroundStyle(isToday ? Theme.accent : Theme.muted)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(meal.map { "\($0.emoji ?? "🍽️") \($0.title)" } ?? "Plan dinner")
                        .phoneFont(.body, 14, weight: meal == nil ? 600 : 700, relativeTo: .subheadline)
                        .foregroundStyle(meal == nil ? Theme.muted : Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isToday { PhoneTag(text: "today") }
                }
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.formatted(.dateTime.weekday(.wide), calendar: calendar) + ": " + (meal?.title ?? "no dinner planned"))
            .accessibilityHint(meal == nil ? "Plan a dinner" : "Change the dinner")
            if meal != nil {
                Button { onNeeds(day) } label: {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add what \(meal?.title ?? "it") needs to groceries")
            }
        }
    }
}

/// "What does Taco Tuesday need?": ingredients typed in one line, each added to the
/// grocery list under its aisle, credited to me.
struct PocketDinnerNeeds: View {
    let day: DayKey

    @Environment(HomeStore.self) private var home
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let meal = home.meal(on: day)
        let titles = DinnerIngredients.titles(from: text)
        PhoneSheet(label: meal.map { "\($0.emoji ?? "🍽️") \($0.title)" }, title: "What does it need?") {
            TextField("Tortillas, limes", text: $text)
                .phoneFont(.body, 15, weight: 600)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { add(titles) }
                .fieldStyle()
                .accessibilityIdentifier("needs")
            Text("Separate items with commas. Each goes on the grocery list in its aisle.")
                .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
        } footer: {
            Button(titles.count > 1 ? "Add \(titles.count) to groceries" : "Add to groceries") { add(titles) }
                .buttonStyle(PhoneButtonStyle())
                .disabled(titles.isEmpty)
                .accessibilityIdentifier("add-needs")
        }
        .onAppear { focused = true }
    }

    private func add(_ titles: [String]) {
        guard let groceries = home.lists(of: .grocery).first else { return }
        let added = titles.filter { home.addItem($0, to: groceries, addedBy: me?.id) }
        dismiss()
        guard !added.isEmpty else { return }
        toasts.showAfterSheet(UndoToast(
            emoji: "🛒",
            title: added.count == 1 ? "\(added[0]) added to \(groceries.title.lowercased())" : "\(added.count) items added to \(groceries.title.lowercased())",
            detail: ListFormatter.localizedString(byJoining: added)
        ))
    }
}

/// Turning a line of typed ingredients into grocery items. Pure, covered by PocketListsTests.
enum DinnerIngredients {
    /// "tortillas, limes and cilantro" -> ["Tortillas", "Limes", "Cilantro"]. Items are not
    /// merged with what is already on the list: the same thing added twice shows twice.
    static func titles(from text: String) -> [String] {
        text
            .replacingOccurrences(of: " and ", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}
