import SwiftUI

/// The Lists tab: the household's lists (groceries by aisle, who added what) and this
/// week's dinners from the wall's meal plan. Everything added here is "added by" me.
struct PocketListsScreen: View {
    /// A list, or the week's dinners.
    enum Page: Hashable {
        case list(HomeList.ID)
        case dinners
    }

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.me) private var me
    @State private var page: Page?
    @State private var editingDinner: DayKey?
    @State private var needs: DayKey?

    var body: some View {
        let lists = home.snapshot.lists
        let shown = page ?? lists.first.map { .list($0.id) } ?? .dinners
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PocketHeader(small: "Lists", title: title(shown))
                picker(lists, shown: shown)
                switch shown {
                case let .list(id):
                    if let list = lists.first(where: { $0.id == id }) {
                        PocketListCard(list: list)
                    }
                case .dinners:
                    PocketDinners(onEdit: { editingDinner = $0 }, onNeeds: { needs = $0 })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .paperUnderStatusBar()
        .task { home.ensureDefaultLists() }
        .sheet(item: Binding(get: { editingDinner.map(DayItem.init) }, set: { editingDinner = $0?.day })) { item in
            PhoneEditorSheet { MealEditor(day: item.day) }
        }
        .sheet(item: Binding(get: { needs.map(DayItem.init) }, set: { needs = $0?.day })) { item in
            PocketDinnerNeeds(day: item.day)
        }
    }

    private struct DayItem: Identifiable {
        let day: DayKey
        var id: String { day.rawValue }
    }

    private func title(_ page: Page) -> String {
        switch page {
        case let .list(id): home.snapshot.lists.first { $0.id == id }?.title ?? "Lists"
        case .dinners: "Dinners"
        }
    }

    /// "Groceries · 8", "House · 4", then "Dinners".
    private func picker(_ lists: [HomeList], shown: Page) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(lists) { list in
                    let open = home.items(in: list).filter { !$0.checked }.count
                    chip("\(list.title) · \(open)", isOn: shown == .list(list.id)) { page = .list(list.id) }
                }
                chip("This week's dinners", isOn: shown == .dinners) { page = .dinners }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                .foregroundStyle(isOn ? Theme.surface : Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOn ? Theme.ink : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One list: the add field on top, then its items (groceries under their aisles), each
/// with who added it. Checked items stay until someone clears them, so two people in
/// the store see the same list.
private struct PocketListCard: View {
    let list: HomeList

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.me) private var me
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        let items = home.items(in: list)
        VStack(alignment: .leading, spacing: 12) {
            addField
            VStack(alignment: .leading, spacing: 2) {
                if items.isEmpty {
                    Text(list.kind == .grocery ? "Nothing to buy. Add what's running low above." : "All clear. Add something above.")
                        .phoneFont(.body, 13.5, weight: 600)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 7)
                } else if list.kind == .grocery {
                    ForEach(Array(GrocerySections.group(items).enumerated()), id: \.element.name) { index, section in
                        Text(section.name.uppercased())
                            .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                            .tracking(1.1)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, index == 0 ? 0 : 8)
                            .accessibilityAddTraits(.isHeader)
                        rows(section.items)
                    }
                } else {
                    rows(items)
                }
            }
            .phoneCard()
            if items.contains(where: \.checked) {
                Button("Clear checked") {
                    withAnimation(.easeOut(duration: 0.2)) { home.clearChecked(in: list) }
                }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
            }
            Text("Checked items stay until someone taps \"Clear checked\", so the list is right while two people shop.")
                .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.muted)
            TextField("Add to \(list.title.lowercased())", text: $title)
                .phoneFont(.body, 15, weight: 600)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(add)
                .accessibilityIdentifier("add-item")
            if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: add)
                    .phoneFont(.body, 13, weight: 800, relativeTo: .subheadline)
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Add \(title) to \(list.title.lowercased())")
                    .accessibilityIdentifier("add-item-button")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        .tint(Theme.accent)
    }

    private func rows(_ items: [ListItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                row(item)
            }
        }
    }

    private func row(_ item: ListItem) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { home.toggle(item) }
        } label: {
            HStack(spacing: 10) {
                PocketCheck(isOn: item.checked)
                Text(item.title)
                    .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    .strikethrough(item.checked, color: Theme.muted)
                    .foregroundStyle(item.checked ? Theme.muted : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let id = item.addedById {
                    PersonAvatar(model.person(id), size: .small)
                }
            }
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { home.delete(item) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityLabel(item.title)
        .accessibilityValue([item.checked ? "Checked" : "Not checked", item.addedById.flatMap(model.person).map { "added by \($0.id == me?.id ? "you" : $0.name)" }].compactMap { $0 }.joined(separator: ", "))
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if home.addItem(trimmed, to: list, addedBy: me?.id) {
            title = ""
            // Keep the keyboard up for the next item.
            focused = true
        }
    }
}

/// The phone's round check box: green once ticked, like the wall's list rows.
struct PocketCheck: View {
    let isOn: Bool
    @PhoneMetric private var side: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(isOn ? Theme.good : Theme.line, lineWidth: 2)
            .background(isOn ? Theme.good : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.5, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
