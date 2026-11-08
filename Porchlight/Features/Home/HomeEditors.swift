import SwiftUI

// Editor sheets for chores, rewards, meals and list items. Each one lives inside a `WallSheet`.

// MARK: - Chore

struct ChoreEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @Environment(\.closeWallSheet) private var close
    let chore: Chore?

    private enum Repeat: String, CaseIterable, Identifiable {
        case daily, weekdays, interval, once
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily: "Every day"
            case .weekdays: "Some days"
            case .interval: "Every few days"
            case .once: "Just once"
            }
        }
    }

    @State private var title = ""
    @State private var emoji = ""
    @State private var ownerId: Int64?
    @State private var repeatKind = Repeat.daily
    @State private var weekdays: Set<Int> = []
    @State private var interval = 3
    @State private var dueDate = Date.now
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
                HStack(spacing: 8) {
                    ForEach(Repeat.allCases) { kind in
                        ChoiceChip(title: kind.label, isSelected: repeatKind == kind) { repeatKind = kind }
                    }
                }
                repeatDetail
                    .frame(minHeight: 44, alignment: .leading)
            }
            EditorRow(label: "When, roughly") {
                HStack(spacing: 8) {
                    TextField("e.g. 7-9am", text: $timeHint)
                        .font(.body(16, weight: 600))
                        .fieldStyle()
                        .frame(width: 180)
                    ForEach(Self.hintSuggestions, id: \.self) { hint in
                        ChoiceChip(title: hint, isSelected: timeHint == hint) { timeHint = timeHint == hint ? "" : hint }
                    }
                }
            }
            HStack(alignment: .bottom) {
                EditorRow(label: "Stars") {
                    CountStepper(value: $stars, range: HomeLimits.stars)
                }
                Spacer()
                if let chore {
                    Button(chore.archived ? "Restore" : "Archive") {
                        store.setArchived(chore, !chore.archived)
                        close()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(chore == nil ? "Add chore" : "Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ErrorLine(message: error)
        }
        .foregroundStyle(Theme.ink)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var repeatDetail: some View {
        switch repeatKind {
        case .daily:
            Text("Shows up every day.")
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
        case .weekdays:
            HStack(spacing: 6) {
                ForEach(ChoreSchedule.orderedWeekdays(calendar: store.calendar), id: \.self) { day in
                    let isOn = weekdays.contains(day)
                    Button {
                        if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                    } label: {
                        Text(store.calendar.veryShortWeekdaySymbols[day - 1])
                            .font(.body(15, weight: 700))
                            .foregroundStyle(isOn ? Theme.surface : Theme.ink)
                            .frame(width: 42, height: 42)
                            .background(isOn ? Theme.ink : Theme.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.calendar.weekdaySymbols[day - 1])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        case .interval:
            HStack(spacing: 12) {
                CountStepper(value: $interval, range: 2...HomeLimits.interval.upperBound, suffix: "days")
                Text(chore == nil ? "starting today" : "counting from when it started")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
        case .once:
            HStack(spacing: 12) {
                Text("Due")
                    .font(.body(15, weight: 700))
                DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.accent)
                Text("It stays on the board until it's done.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let calendar = store.calendar
        weekdays = [calendar.component(.weekday, from: .now)]
        dueDate = store.week.last.startDate(in: calendar)
        guard let chore else {
            ownerId = model.people.first?.id
            return
        }
        title = chore.title
        emoji = chore.emoji ?? ""
        ownerId = chore.ownerId
        timeHint = chore.timeHint ?? ""
        stars = chore.stars
        switch chore.recurrence {
        case .daily: repeatKind = .daily
        case let .weekdays(days): repeatKind = .weekdays; weekdays = days
        case let .everyNDays(n): repeatKind = .interval; interval = max(n, 2)
        case .once: repeatKind = .once; dueDate = chore.anchor.startDate(in: calendar)
        }
    }

    private func save() {
        let calendar = store.calendar
        let recurrence: ChoreRecurrence = switch repeatKind {
        case .daily: .daily
        case .weekdays: .weekdays(weekdays)
        case .interval: .everyNDays(interval)
        case .once: .once
        }
        // Repeating chores keep their start day while the pattern stays the same, so
        // "every 3 days" doesn't shift when only the title changes.
        let anchor: DayKey
        if case .once = recurrence {
            anchor = DayKey(dueDate, calendar: calendar)
        } else if let chore, !chore.recurrence.isOnce, chore.recurrence == recurrence {
            anchor = chore.anchor
        } else {
            anchor = store.today
        }
        let draft = ChoreDraft(
            title: title, emoji: emoji, ownerId: ownerId, recurrence: recurrence,
            anchorDay: anchor, timeHint: timeHint, stars: stars
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
    @State private var ownerId: Int64?
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
    @Environment(\.closeWallSheet) private var close
    let day: DayKey

    @State private var title = ""
    @State private var emoji = ""
    @State private var emojiTouched = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
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
                                .background(emoji == option ? Theme.accent.wash(0.16) : Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        if store.setMeal(on: day, title: title, emoji: emoji.isEmpty ? nil : emoji) {
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
