import SwiftUI

// Editor sheets for chores, rewards, meals and list items. Each one lives inside a `WallSheet`.

// MARK: - Chore

struct ChoreEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @Environment(\.closeWallSheet) private var close
    @Environment(\.horizontalSizeClass) private var sizeClass
    let chore: Chore?
    /// Whose a new chore starts as; the first person when nil (the phone passes "me").
    var newOwner: Person.ID?

    @State private var title = ""
    @State private var emoji = ""
    @State private var ownerId: Person.ID?
    @State private var repeatChoice: RepeatChoice?
    @State private var timeHint = ""
    @State private var stars = 1
    @State private var error: String?
    @State private var loaded = false

    private static let hintSuggestions = ["before noon", "after dinner", "anytime"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(chore == nil ? "New chore" : "Edit chore").font(.display(28))
            HStack(spacing: 12) {
                EmojiField(emoji: $emoji, placeholder: "🧹")
                TextField("What needs doing?", text: $title)
                    .font(.body(18, weight: 600))
                    .fieldStyle()
                    .submitLabel(.done)
            }
            EditorRow(label: "Whose chore") {
                FlowLayout(spacing: 8) {
                    ForEach(model.people) { person in
                        ChoiceChip(title: person.name, isSelected: ownerId == person.id, tint: person.color.color) {
                            Avatar(person: person, size: 30)
                        } action: { ownerId = person.id }
                    }
                    ChoiceChip(title: "Anyone", isSelected: ownerId == nil, tint: Theme.everyone) {
                        AnyoneAvatar(size: 30)
                    } action: { ownerId = nil }
                }
            }
            EditorRow(label: "Repeats") {
                if repeatChoice != nil {
                    RepeatPicker(
                        choice: Binding(get: { repeatChoice! }, set: { repeatChoice = $0 }),
                        calendar: store.calendar,
                        today: store.today,
                        maxInterval: HomeLimits.interval.upperBound
                    )
                }
            }
            EditorRow(label: "When, roughly") {
                // A phone stacks the field over its suggestions; the wall keeps them in a row.
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        hintField
                        FlowLayout(spacing: 8) { hintChips }
                    }
                } else {
                    HStack(spacing: 8) {
                        hintField.frame(width: 180)
                        hintChips
                    }
                }
            }
            if isCompact {
                EditorRow(label: "Stars") {
                    CountStepper(value: $stars, range: HomeLimits.stars)
                }
                VStack(spacing: 10) {
                    saveButton.buttonStyle(PhoneButtonStyle())
                    if chore != nil { archiveButton.buttonStyle(PhoneButtonStyle(kind: .ghost)) }
                }
            } else {
                HStack(alignment: .bottom) {
                    EditorRow(label: "Stars") {
                        CountStepper(value: $stars, range: HomeLimits.stars)
                    }
                    Spacer()
                    if chore != nil {
                        archiveButton.buttonStyle(SecondaryButtonStyle())
                    }
                    saveButton.buttonStyle(PrimaryButtonStyle())
                }
            }
            ErrorLine(message: error)
        }
        .foregroundStyle(Theme.ink)
        .onAppear(perform: load)
    }

    private var isCompact: Bool { sizeClass == .compact }

    private var hintField: some View {
        TextField("e.g. 7-9am", text: $timeHint)
            .font(.body(16, weight: 600))
            .fieldStyle()
    }

    private var hintChips: some View {
        ForEach(Self.hintSuggestions, id: \.self) { hint in
            ChoiceChip(title: hint, isSelected: timeHint == hint) { timeHint = timeHint == hint ? "" : hint }
        }
    }

    private var saveButton: some View {
        Button(chore == nil ? "Add chore" : "Save", action: save)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder
    private var archiveButton: some View {
        if let chore {
            Button(chore.archived ? "Restore" : "Archive") {
                store.setArchived(chore, !chore.archived)
                close()
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let calendar = store.calendar
        guard let chore else {
            ownerId = newOwner ?? model.people.first?.id
            repeatChoice = RepeatChoice(recurrence: .daily, start: store.today, calendar: calendar)
            return
        }
        repeatChoice = RepeatChoice(recurrence: chore.recurrence, start: chore.anchor, calendar: calendar)
        title = chore.title
        emoji = chore.emoji ?? ""
        ownerId = chore.ownerId
        timeHint = chore.timeHint ?? ""
        stars = chore.stars
    }

    private func save() {
        guard let repeatChoice else { return }
        let draft = ChoreDraft(
            title: title, emoji: emoji, ownerId: ownerId, recurrence: repeatChoice.recurrence,
            anchorDay: repeatChoice.startDay(calendar: store.calendar), timeHint: timeHint, stars: stars
        )
        if store.saveChore(draft, id: chore?.id) {
            close()
        } else {
            error = store.lastError
        }
    }
}

// MARK: - Reward

struct RewardEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @Environment(\.closeWallSheet) private var close
    let reward: Reward?

    @State private var title = ""
    @State private var emoji = ""
    @State private var target = 30
    @State private var ownerId: Person.ID?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reward == nil ? "New reward" : "Edit reward").font(.display(28))
                Text("Stars from checked-off chores count toward it. A shared goal counts everyone's stars.")
                    .font(.body(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.trailing, 40)
            }
            HStack(spacing: 12) {
                EmojiField(emoji: $emoji, placeholder: "🎁")
                TextField("A treat to look forward to", text: $title)
                    .font(.body(18, weight: 600))
                    .fieldStyle()
            }
            EditorRow(label: "For") {
                FlowLayout(spacing: 8) {
                    ForEach(model.people) { person in
                        ChoiceChip(title: person.name, isSelected: ownerId == person.id, tint: person.color.color) {
                            Avatar(person: person, size: 30)
                        } action: { ownerId = person.id }
                    }
                    ChoiceChip(title: "Together", isSelected: ownerId == nil, tint: Theme.everyone) {
                        AnyoneAvatar(size: 30)
                    } action: { ownerId = nil }
                }
            }
            HStack(alignment: .bottom) {
                EditorRow(label: "Goal") {
                    CountStepper(value: $target, range: 5...1000, step: 5, suffix: "stars")
                }
                Spacer()
                if let reward {
                    Button("Start over") {
                        store.restart(reward)
                        close()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button(reward.archived ? "Restore" : "Archive") {
                        store.setArchived(reward, !reward.archived)
                        close()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(reward == nil ? "Add reward" : "Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ErrorLine(message: error)
        }
        .foregroundStyle(Theme.ink)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let reward {
                title = reward.title
                emoji = reward.emoji ?? ""
                target = reward.targetStars
                ownerId = reward.ownerId
            } else {
                ownerId = model.people.first?.id
            }
        }
    }

    private func save() {
        let draft = RewardDraft(title: title, emoji: emoji, targetStars: target, ownerId: ownerId)
        if store.saveReward(draft, id: reward?.id) {
            close()
        } else {
            error = store.lastError
        }
    }
}

// MARK: - Meal

struct MealEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(FoodStore.self) private var food
    @Environment(\.closeWallSheet) private var close
    @Environment(\.colorScheme) private var scheme
    let day: DayKey

    @State private var title = ""
    @State private var emoji = ""
    @State private var emojiTouched = false
    /// The dish picked from what we cook, kept while the words still name it.
    @State private var picked: Dish?
    /// The planned dinner's own words: what we cook narrows only once they change.
    @State private var planned = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        let cooked = PlannedDish.suggestions(for: title == planned ? "" : title, in: food.book)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dinner").font(.display(28))
                Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day(), calendar: store.calendar))
                    .font(.body(15, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 12) {
                EmojiField(emoji: Binding(get: { emoji }, set: { emoji = $0; emojiTouched = true }), placeholder: "🍽️")
                TextField("What's for dinner?", text: $title)
                    .font(.body(18, weight: 600))
                    .fieldStyle()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: title) { _, newTitle in
                        // Suggest an emoji as they type, until they pick one themselves.
                        if !emojiTouched { emoji = MealEmoji.guess(newTitle) ?? "" }
                    }
            }
            if !cooked.isEmpty {
                // What we cook, so a dinner names its dish (docs/design/dishes.md, "Planned dinners").
                EditorRow(label: "What we cook") {
                    FlowLayout(spacing: 6) {
                        ForEach(cooked) { dish in
                            Button {
                                picked = dish
                                title = dish.name
                                emoji = dish.emoji
                                emojiTouched = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(dish.emoji)
                                    Text(dish.name).font(.body(15, weight: 700))
                                    if food.book.recipe(of: dish.id) != nil { Text("📖").accessibilityLabel(", with a recipe") }
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(Theme.surface2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("dinner-dish-\(dish.name)")
                        }
                    }
                }
            }
            EditorRow(label: "Pick an emoji") {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { option in
                        Button {
                            emoji = option
                            emojiTouched = true
                        } label: {
                            Text(option)
                                .font(.system(size: 26))
                                .frame(width: 48, height: 48)
                                .background(emoji == option ? Theme.accent.wash(0.16, in: scheme) : Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(emoji == option ? Theme.accent : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                ErrorLine(message: error)
                Spacer()
                if store.meal(on: day) != nil {
                    Button("Clear") {
                        if store.setMeal(on: day, title: "", emoji: nil) { close() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .foregroundStyle(Theme.ink)
        .onAppear {
            if let meal = store.meal(on: day) {
                planned = meal.title
                title = meal.title
                emoji = meal.emoji ?? ""
                emojiTouched = true
            }
            focused = true
        }
    }

    /// The guess for the current title first, then the usual palette.
    private var suggestions: [String] {
        let guess = MealEmoji.guess(title).map { [$0] } ?? []
        return guess + MealEmoji.palette.filter { !guess.contains($0) }
    }

    private func save() {
        let dishId = picked.flatMap { DishName.key(title) == $0.key ? $0.id : nil }
        if store.setMeal(on: day, title: title, emoji: emoji.isEmpty ? nil : emoji, dishId: dishId) {
            close()
        } else {
            error = store.lastError
        }
    }
}

// MARK: - List item

struct ListItemEditor: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.closeWallSheet) private var close
    let item: ListItem
    let kind: ListKind

    @State private var title = ""
    @State private var section = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit item").font(.display(28))
            TextField("Item", text: $title)
                .font(.body(18, weight: 600))
                .fieldStyle()
                .submitLabel(.done)
                .onSubmit(save)
            if kind == .grocery {
                EditorRow(label: "Section") {
                    FlowLayout(spacing: 8) {
                        ForEach(sections, id: \.self) { option in
                            ChoiceChip(title: option, isSelected: section == option) { section = option }
                        }
                    }
                    TextField("Or a new section", text: $section)
                        .font(.body(16, weight: 600))
                        .fieldStyle()
                        .frame(maxWidth: 280)
                }
            }
            HStack {
                ErrorLine(message: error)
                Spacer()
                Button("Delete") {
                    store.delete(item)
                    close()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .foregroundStyle(Theme.ink)
        .onAppear {
            title = item.title
            section = item.section ?? ""
        }
    }

    private var sections: [String] {
        GrocerySections.ordered(GrocerySections.standard + store.snapshot.items.compactMap(\.section) + [GrocerySections.other])
    }

    private func save() {
        if store.update(item, title: title, section: kind == .grocery ? section : nil) {
            close()
        } else {
            error = store.lastError
        }
    }
}
