import SwiftUI

/// "What we had" in Snap and Edit, on the phone and the wall (docs/design/dishes.md, "The
/// editor"; frames P1, P2 and W1 of docs/proposals/dishes-and-recipes.html): the meal's
/// dish lines, each with the table's face and a way off; "Last time here" for a restaurant
/// we know; and one field that suggests what we get here, or what we cook, as you type.
/// Saving never waits for a dish: what is typed when Save is tapped is the last dish, and
/// none at all is a whole meal.
struct DishLinesField: View {
    enum Style { case phone, wall }

    let style: Style
    @Binding var edit: DishLinesEdit
    let kitchen: DishFormKitchen
    /// The dishes of the restaurant's last meal, for "Last time here"; empty otherwise.
    let lastTime: [Dish]
    var placeholder = "What was it? e.g. Pho"

    @Environment(FoodStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.keepDishFieldInView) private var keepInView
    @FocusState private var focused: Bool

    static let fieldID = "dish-field"

    var body: some View {
        VStack(alignment: .leading, spacing: style == .wall ? 8 : 6) {
            header
            if !edit.lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(edit.lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { divider }
                        row(line, index: index)
                    }
                }
            }
            chips
            // Above the field: typing, the field sits just over the keyboard, so what it
            // suggests has to be above it to be seen.
            suggestions
            field
                .id(Self.fieldID)
        }
        .onChange(of: edit.text) { _, _ in
            // After the suggestions have laid out.
            guard focused, let keepInView else { return }
            Task { @MainActor in keepInView.scroll() }
        }
        .onChange(of: edit.lines.count) { _, _ in
            guard focused, let keepInView else { return }
            Task { @MainActor in keepInView.scroll() }
        }
    }

    // MARK: Pieces

    private var header: some View {
        Group {
            switch style {
            case .phone:
                (Text("What we had").foregroundStyle(Theme.ink) + Text(" · \(kitchen.words)").foregroundStyle(Theme.muted))
                    .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
            case .wall:
                SheetLabel(title: "What we had", note: "· \(kitchen.words)")
            }
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("dish-header")
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    /// The dish a line names: the one picked, else this kitchen's dish of that name.
    private func dish(for line: DishLinesEdit.Line) -> Dish? {
        if let id = line.dishId, let dish = store.book.dish(id), dish.kitchen == kitchen.kitchen { return dish }
        return store.book.liveDishes.first { $0.kitchen == kitchen.kitchen && $0.key == line.key }
    }

    /// "8th time here", "New here": counting this meal.
    private func countWords(_ line: DishLinesEdit.Line, dish: Dish?) -> String {
        let here = kitchen.kitchen.placeId != nil
        guard let dish else { return here ? "New here" : "New" }
        let count = store.book.summary(of: dish.id).count + (line.wasSaved ? 0 : 1)
        return DishWords.ordinal(count, here: here)
    }

    /// Last time's face for a dish this meal adds, as a hint beside the faces.
    private func lastFace(_ line: DishLinesEdit.Line, dish: Dish?) -> MealRating? {
        guard !line.wasSaved, let dish, let last = store.book.times(of: dish.id).first else { return nil }
        return last.line.rating ?? last.faces.values.max { $0.rawValue < $1.rawValue }
    }

    private func row(_ line: DishLinesEdit.Line, index: Int) -> some View {
        let dish = dish(for: line)
        let words = countWords(line, dish: dish)
        let hint = lastFace(line, dish: dish)
        return Group {
            switch style {
            case .phone:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        art(line, dish: dish, size: typeSize.isAccessibilitySize ? 44 : 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.name).phoneFont(.body, 15, weight: 700, relativeTo: .subheadline)
                            Text(words).phoneFont(.body, 12, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        removeButton(line)
                    }
                    faces(line, hint: hint, size: 32, font: 16)
                        .padding(.leading, typeSize.isAccessibilitySize ? 0 : 44)
                }
                .padding(.vertical, 8)
            case .wall:
                HStack(spacing: 12) {
                    art(line, dish: dish, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        // Never cut short: the name wraps, and the count and last time's
                        // face each have a line of their own beside the faces.
                        Text(line.name).font(.body(15.5, weight: 700))
                        Text(words)
                            .font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("dish-count-\(line.name)")
                        if let hint {
                            Text("last time \(hint.emoji)")
                                .font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
                                .accessibilityIdentifier("dish-last-\(line.name)")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    Spacer(minLength: 6)
                    FaceChoice(rating: line.rating, size: 34, font: 17) { edit.setRating(line.id, $0) }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("dish-faces-\(line.name)")
                    removeButton(line)
                }
                .padding(.vertical, 6)
            }
        }
        .contextMenu {
            if index > 0 { Button { edit.move(line.id, by: -1) } label: { Label("Move up", systemImage: "arrow.up") } }
            if index + 1 < edit.lines.count { Button { edit.move(line.id, by: 1) } label: { Label("Move down", systemImage: "arrow.down") } }
            Button(role: .destructive) { edit.remove(line.id) } label: { Label("Take off", systemImage: "xmark") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(line.name)
        .accessibilityAction(named: "Move up") { edit.move(line.id, by: -1) }
        .accessibilityAction(named: "Move down") { edit.move(line.id, by: 1) }
        .accessibilityIdentifier("dish-line-\(line.name)")
    }

    @ViewBuilder
    private func faces(_ line: DishLinesEdit.Line, hint: MealRating?, size: CGFloat, font: CGFloat) -> some View {
        let choice = FaceChoice(rating: line.rating, size: size, font: font) { edit.setRating(line.id, $0) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dish-faces-\(line.name)")
        let last = hint.map { face in
            Text("last time \(face.emoji)")
                .phoneFont(.body, 11.5, weight: 600, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { choice; last }
            VStack(alignment: .leading, spacing: 4) { choice; last }
        }
    }

    private func art(_ line: DishLinesEdit.Line, dish: Dish?, size: CGFloat) -> some View {
        Group {
            if let dish {
                DishArt(dish: dish, size: size)
            } else {
                PlateArt(
                    emoji: DishIllustration.suggestEmoji(for: line.name) ?? DishIllustration.fallbackEmoji,
                    tint: Color(hex: UInt32(DishIllustration.suggestTint(for: line.name))), plate: 0.66, emojiSize: size * 0.42
                )
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .accessibilityHidden(true)
            }
        }
    }

    private func removeButton(_ line: DishLinesEdit.Line) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { edit.remove(line.id) } } label: {
            Image(systemName: "xmark")
                .font(.system(size: style == .wall ? 12 : 11, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, height: 28)
                .background(Theme.surface2, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take \(line.name) off")
        .accessibilityIdentifier("remove-dish-\(line.name)")
    }

    // MARK: Last time here

    @ViewBuilder
    private var chips: some View {
        let left = lastTime.filter { !edit.keys.contains($0.key) && !edit.dishIds.contains($0.id) }
        if !left.isEmpty, !edit.isFull {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last time here")
                    .modifier(DishFieldFont(style: style, size: 12.5, weight: 600, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(left) { dish in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { _ = edit.add(dish.name, dishId: dish.id) }
                        } label: {
                            Text("+ \(dish.emoji) \(dish.name)")
                                .modifier(DishFieldFont(style: style, size: 12.5, weight: 800, relativeTo: .footnote))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .overlay(Capsule().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(dish.name)")
                        .accessibilityIdentifier("dish-chip-\(dish.name)")
                    }
                }
            }
        }
    }

    // MARK: Typing

    private var field: some View {
        HStack(spacing: 10) {
            Text(DishIllustration.suggestEmoji(for: edit.text) ?? DishIllustration.fallbackEmoji)
                .font(.system(size: style == .wall ? 22 : 20))
                .accessibilityHidden(true)
            TextField(edit.lines.isEmpty ? placeholder : "Add another dish", text: $edit.text)
                .modifier(DishFieldFont(style: style, size: style == .wall ? 17 : 16, weight: 600, relativeTo: .body))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit {
                    // Done adds the dish and puts the keyboard away, which would otherwise
                    // cover Save; "Add another dish" is one tap for the next.
                    withAnimation(.easeOut(duration: 0.15)) { _ = edit.commitText() }
                    focused = false
                }
                .disabled(edit.isFull)
                .accessibilityIdentifier("dish")
        }
        .fieldStyle()
    }

    @ViewBuilder
    private var suggestions: some View {
        let typed = DishName.key(edit.text)
        if !typed.isEmpty {
            let found = store.book.suggestions(for: edit.text, kitchen: kitchen.kitchen, excluding: edit.dishIds, limit: 4)
                .filter { !edit.keys.contains($0.dish.key) }
            let exact = found.contains { $0.isHere && $0.dish.key == typed } || edit.keys.contains(typed)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(found.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 { divider }
                    suggestionRow(suggestion)
                }
                if !exact {
                    if !found.isEmpty { divider }
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { _ = edit.commitText() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 30, height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Add \u{201C}\(DishName.cleaned(edit.text))\u{201D}")
                                    .modifier(DishFieldFont(style: style, size: 14.5, weight: 700, relativeTo: .subheadline))
                                    .foregroundStyle(Theme.ink)
                                Text(kitchen.kitchen == .home ? "A new dish we cook" : "A new dish \(kitchen.words)")
                                    .modifier(DishFieldFont(style: style, size: 12, weight: 600, relativeTo: .caption))
                                    .foregroundStyle(Theme.muted)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dish-add-typed")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dish suggestions")
        }
    }

    private func suggestionRow(_ suggestion: DishBook.Suggestion) -> some View {
        let calendar = store.calendar
        let today = store.today(CompanionClock.now())
        let detail = [
            suggestion.isHere ? nil : DishWords.kitchen(suggestion.dish, places: store.snapshot.places),
            DishWords.times(suggestion.count),
            suggestion.last.map { DishWords.last($0, today: today, calendar: calendar) },
        ].compactMap { $0 }.joined(separator: " · ")
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                edit.text = ""
                // Picked from another kitchen it is the same name here, not the same dish.
                _ = edit.add(suggestion.dish.name, dishId: suggestion.isHere ? suggestion.dish.id : nil)
            }
        } label: {
            HStack(spacing: 10) {
                DishArt(dish: suggestion.dish, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.dish.name)
                        .modifier(DishFieldFont(style: style, size: 14.5, weight: 700, relativeTo: .subheadline))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .modifier(DishFieldFont(style: style, size: 12, weight: 600, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let face = suggestion.face { Text(face.emoji).font(.system(size: 16)) }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dish-suggestion-\(suggestion.dish.name)")
    }
}

/// Scrolls the form that holds the dish field so the field's bottom sits just over the
/// keyboard, given by a form whose scroll view can do it. Suggestions open above the field,
/// and would otherwise push it under the keyboard.
struct KeepDishFieldInView {
    let scroll: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var keepDishFieldInView: KeepDishFieldInView? = nil
}

extension View {
    /// Gives a dish field inside this scroll view a way to stay over the keyboard.
    func keepsDishFieldInView(_ proxy: ScrollViewProxy) -> some View {
        environment(\.keepDishFieldInView, KeepDishFieldInView {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(DishLinesField.fieldID, anchor: .bottom) }
        })
    }
}

/// The phone's type grows with Dynamic Type; the wall's stays its own size.
private struct DishFieldFont: ViewModifier {
    let style: DishLinesField.Style
    let size: CGFloat
    let weight: CGFloat
    let relativeTo: Font.TextStyle

    func body(content: Content) -> some View {
        switch style {
        case .phone: content.phoneFont(.body, size, weight: weight, relativeTo: relativeTo)
        case .wall: content.font(.body(size, weight: weight))
        }
    }
}

/// The wall's "What we had": the kitchen and "Last time here" worked out from the form's
/// Where and restaurant.
struct WallDishLines: View {
    @Binding var edit: DishLinesEdit
    let sources: MealSources
    let place: PlaceDraft?
    /// The meal being edited, so its own visit isn't "last time here".
    let entryId: JournalEntry.ID?
    var placeholder = "What was it? e.g. Dan dan noodles"

    @Environment(FoodStore.self) private var store

    var body: some View {
        let named = sources.hasPlace ? place : nil
        let known = store.place(matching: named)
        DishLinesField(
            style: .wall,
            edit: $edit,
            kitchen: DishFormKitchen.of(sources: sources, place: named, known: known),
            lastTime: known.flatMap { store.book.lastTime(at: $0.id, excluding: entryId)?.dishes } ?? [],
            placeholder: placeholder
        )
    }
}
