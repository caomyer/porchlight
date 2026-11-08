import SwiftUI

enum ListsSheet: Identifiable {
    case meal(DayKey)
    case item(ListItem, ListKind)

    var id: String {
        switch self {
        case let .meal(day): "meal-\(day)"
        case let .item(item, _): "item-\(item.id ?? -1)"
        }
    }
}

/// This week's dinners across the top, groceries and to-dos below.
struct ListsScreen: View {
    @Environment(HomeStore.self) private var store
    @State private var sheet: ListsSheet?
    @State private var groceryListId: Int64?
    @State private var todoListId: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeHeader(title: "Lists & meals", subtitle: "This week's dinners and what to buy") { EmptyView() }
            MealStrip { day in present(.meal(day)) }
            // Groceries get a little more room than to-dos (1.1 : 1, as in the mock).
            GeometryReader { proxy in
                let groceryWidth = (proxy.size.width - 16) * 1.1 / 2.1
                HStack(alignment: .top, spacing: 16) {
                    ListCard(kind: .grocery, selection: $groceryListId, present: present)
                        .frame(width: groceryWidth)
                    ListCard(kind: .todo, selection: $todoListId, present: present)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .task { store.ensureDefaultLists() }
        .wallSheet(item: $sheet) { sheet in
            switch sheet {
            case let .meal(day): MealEditor(day: day)
            case let .item(item, kind): ListItemEditor(item: item, kind: kind)
            }
        }
        #if DEBUG
        .task {
            if UserDefaults.standard.string(forKey: "homeSheet") == "meal" { present(.meal(store.today)) }
        }
        #endif
    }

    private func present(_ sheet: ListsSheet) {
        withoutAnimation { self.sheet = sheet }
    }
}

// MARK: - Meals

private struct MealStrip: View {
    @Environment(HomeStore.self) private var store
    let onEdit: (DayKey) -> Void

    var body: some View {
        let calendar = store.calendar
        HStack(spacing: 10) {
            ForEach(store.week.days, id: \.self) { day in
                let meal = store.meal(on: day)
                let isToday = day == store.today
                Button { onEdit(day) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated), calendar: calendar).uppercased())
                            .font(.body(11, weight: 800))
                            .tracking(0.7)
                            .foregroundStyle(Theme.muted)
                        if let meal {
                            Text(meal.emoji ?? "🍽️")
                                .font(.system(size: 28))
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                            Text(meal.title)
                                .font(.body(13.5, weight: 700))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.muted.opacity(0.7))
                                .frame(height: 34)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                            Text("Plan dinner")
                                .font(.body(13.5, weight: 600))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 13)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 128)
                    .background(isToday ? Theme.accent.wash(0.14) : Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                    .overlay {
                        if isToday {
                            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide), calendar: calendar) + ": " + (meal?.title ?? "no dinner planned"))
            }
        }
    }
}

// MARK: - Lists

private struct ListCard: View {
    @Environment(HomeStore.self) private var store
    let kind: ListKind
    @Binding var selection: Int64?
    let present: (ListsSheet) -> Void

    private var lists: [HomeList] { store.lists(of: kind) }
    private var list: HomeList? { lists.first { $0.id == selection } ?? lists.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let list {
                let items = store.items(in: list)
                header(list: list, items: items)
                    .padding(.bottom, 4)
                GeometryReader { proxy in
                    ScrollView(showsIndicators: false) {
                        if items.isEmpty {
                            Text(kind == .grocery ? "Nothing to buy. Add what's running low below." : "All clear. Add a to-do below.")
                                .font(.body(15, weight: 600))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                        } else if kind == .grocery {
                            GroceryColumns(items: items, twoColumns: proxy.size.width > 420, present: present)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    ListItemRow(item: item, showsDivider: index < items.count - 1) { present(.item(item, kind)) }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                AddItemRow(list: list)
                    .padding(.top, 10)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }

    private func header(list: HomeList, items: [ListItem]) -> some View {
        let done = items.filter(\.checked).count
        return HStack(spacing: 10) {
            if lists.count > 1 {
                // Several lists of this kind: the title switches between them.
                Menu {
                    ForEach(lists) { option in
                        Button(option.title) { selection = option.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(list.title).font(.display(19))
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink)
                }
            } else {
                Text(list.title).font(.display(19))
            }
            Spacer()
            if done > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.clearChecked(in: list) }
                } label: {
                    Text("Clear checked")
                        .font(.body(13, weight: 700))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            Text(items.isEmpty ? "Empty" : "\(items.count) \(items.count == 1 ? "item" : "items") · \(done) done")
                .font(.body(13, weight: 600))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        .frame(height: 30)
    }
}

/// Grocery items grouped by section, split into two balanced columns when there is room.
private struct GroceryColumns: View {
    let items: [ListItem]
    let twoColumns: Bool
    let present: (ListsSheet) -> Void

    private var sections: [(name: String, items: [ListItem])] {
        let grouped = Dictionary(grouping: items) { $0.section ?? GrocerySections.other }
        return GrocerySections.ordered(grouped.keys).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        let sections = sections
        if twoColumns, sections.count > 1 {
            let split = GrocerySections.columnSplit(sections.map { $0.items.count })
            HStack(alignment: .top, spacing: 24) {
                column(Array(sections[..<split]))
                column(Array(sections[split...]))
            }
        } else {
            column(sections)
        }
    }

    private func column(_ sections: [(name: String, items: [ListItem])]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections, id: \.name) { section in
                Text(section.name.uppercased())
                    .font(.body(11.5, weight: 800))
                    .tracking(0.9)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    ListItemRow(item: item, showsDivider: index < section.items.count - 1) { present(.item(item, .grocery)) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ListItemRow: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let item: ListItem
    let showsDivider: Bool
    let onEdit: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { store.toggle(item) }
        } label: {
            HStack(spacing: 10) {
                CheckBox(isOn: item.checked, color: Theme.good, size: 22, cornerRadius: 7, lineWidth: 2, border: Theme.line)
                Text(item.title)
                    .font(.body(14.5, weight: 600))
                    .foregroundStyle(item.checked ? Theme.muted : Theme.ink)
                    .strikethrough(item.checked, color: Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                if let id = item.addedById, let person = model.person(id) {
                    Avatar(person: person, size: 22)
                }
            }
            .padding(.vertical, 7)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .contextMenu {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { store.delete(item) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(item.checked ? "Checked" : "Not checked")
    }
}

/// The inline "add" field at the bottom of a list, with who is adding and (for groceries) the aisle.
private struct AddItemRow: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let list: HomeList

    @State private var title = ""
    @State private var addedBy: Int64?
    /// A section picked by hand; nil means "use the guess".
    @State private var section: String?
    @FocusState private var focused: Bool

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var guessedSection: String { section ?? GrocerySections.guess(trimmed) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.muted)
                TextField(list.kind == .grocery ? "Add to \(list.title.lowercased())" : "Add a to-do", text: $title)
                    .font(.body(15, weight: 600))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .tint(Theme.accent)
                if list.kind == .grocery, !trimmed.isEmpty {
                    sectionMenu
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.surface2, in: Capsule())
            HStack(spacing: 2) {
                ForEach(model.people) { person in
                    let isOn = addedBy == person.id
                    Button { addedBy = isOn ? nil : person.id } label: {
                        Avatar(person: person, size: 26)
                            .opacity(isOn ? 1 : 0.35)
                            .padding(3)
                            .overlay(Circle().strokeBorder(isOn ? person.color.color : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Added by \(person.name)")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .onChange(of: title) { _, newValue in
            if newValue.isEmpty { section = nil }
        }
        .onAppear {
            if addedBy == nil { addedBy = model.people.first?.id }
        }
    }

    private var sectionMenu: some View {
        Menu {
            ForEach(GrocerySections.ordered(GrocerySections.standard + store.items(in: list).compactMap(\.section) + [GrocerySections.other]), id: \.self) { option in
                Button(option) { section = option }
            }
        } label: {
            HStack(spacing: 3) {
                Text(guessedSection)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.body(12, weight: 700))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Theme.surface, in: Capsule())
        }
        .accessibilityLabel("Section: \(guessedSection)")
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        let picked = list.kind == .grocery ? guessedSection : nil
        if store.addItem(trimmed, to: list, section: picked, addedBy: addedBy) {
            title = ""
            section = nil
            // Keep the keyboard up for the next item.
            focused = true
        }
    }
}
