import SwiftUI

// The wall's recipes (docs/design/dishes.md, "Recipes"; journey W4 of
// docs/proposals/dishes-and-recipes.html): Recipes beside Week, Month and Dishes as cards,
// a recipe readable from the stove, and dinner planned from what we cook. Laid out for the
// kitchen screen, not the phone's stretched.

// MARK: - The bank

struct WallRecipesView: View {
    let onOpen: (Dish) -> Void
    let onAdd: (Dish?) -> Void
    let onPlan: (Dish) -> Void

    @Environment(FoodStore.self) private var store
    @State private var query = ""

    var body: some View {
        let bank = store.recipeBank
        let entries = bank.entries
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                search
                Button { onAdd(nil) } label: { Label("New recipe", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("wall-new-recipe")
            }
            if entries.isEmpty {
                empty(bank)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        let shown = query.trimmingCharacters(in: .whitespaces).isEmpty ? entries : bank.search(query)
                        if query.trimmingCharacters(in: .whitespaces).isEmpty,
                           let waiting = bank.notMadeInAWhile(now: CompanionClock.now(), calendar: store.calendar) {
                            notMadeInAWhile(waiting)
                        }
                        if shown.isEmpty {
                            Text("No recipe has \"\(query.trimmingCharacters(in: .whitespaces))\" yet.")
                                .font(.body(16, weight: 600)).foregroundStyle(Theme.muted)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 14)], alignment: .leading, spacing: 14) {
                            ForEach(shown) { entry in card(entry) }
                        }
                        cookedOften(bank)
                    }
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Search recipes and ingredients", text: $query)
                .font(.body(16, weight: 600))
                .autocorrectionDisabled()
                .accessibilityIdentifier("wall-recipe-search")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).stroke(Theme.line))
    }

    private func notMadeInAWhile(_ entry: RecipeBank.Entry) -> some View {
        HStack(spacing: 14) {
            Text("🕰️").font(.system(size: 26)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Haven't made in a while").font(.body(17, weight: 700))
                Text([entry.dish.name, entry.last.map { RecipeWords.last($0.eatenAt, now: CompanionClock.now(), calendar: store.calendar) }, entry.face.map { "usually \($0.emoji)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.body(14, weight: 600)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Plan it") { onPlan(entry.dish) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("wall-plan-waiting")
            Button("Open") { onOpen(entry.dish) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func words(name: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.display(18)).lineLimit(2).foregroundStyle(Theme.ink)
            Text(line).font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ entry: RecipeBank.Entry) -> some View {
        let addedBy = entry.recipe.addedById.flatMap { id in store.snapshot.everyone.first { $0.id == id }?.name }
        let line = RecipeWords.bankLine(
            addedBy: addedBy, hasLink: entry.recipe.link != nil, hasCard: !entry.photos.isEmpty,
            times: entry.times, last: entry.last?.eatenAt, now: CompanionClock.now(), calendar: store.calendar
        )
        return Button { onOpen(entry.dish) } label: {
            VStack(alignment: .leading, spacing: 8) {
                RecipePicture(entry: entry, size: 170)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if let face = entry.face {
                            Text(face.emoji).font(.system(size: 22)).padding(8)
                        }
                    }
                // As tall as two lines of name and two of line, so every card in a row is one
                // height, with the line right under a short name.
                ZStack(alignment: .topLeading) {
                    words(name: "A\nA", line: "A\nA").hidden().accessibilityHidden(true)
                    words(name: entry.dish.name, line: line)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([entry.dish.name, line].joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("wall-recipe-\(entry.dish.name)")
    }

    @ViewBuilder
    private func cookedOften(_ bank: RecipeBank) -> some View {
        let often = bank.cookedOftenWithoutRecipe()
        if !often.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("You cook these often").font(.display(22)).accessibilityAddTraits(.isHeader)
                    Text("no recipe yet").font(.body(13, weight: 700)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 12) {
                    ForEach(often, id: \.dish.id) { item in
                        Button { onAdd(item.dish) } label: {
                            HStack(spacing: 10) {
                                DishArt(dish: item.dish, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.dish.name).font(.body(15, weight: 700)).foregroundStyle(Theme.ink)
                                    Text("\(DishWords.times(item.times)) · + Recipe").font(.body(12.5, weight: 700)).foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a recipe for \(item.dish.name)")
                        .accessibilityIdentifier("wall-add-recipe-\(item.dish.name)")
                    }
                }
            }
        }
    }

    private func empty(_ bank: RecipeBank) -> some View {
        VStack(spacing: 14) {
            Text("📖").font(.system(size: 60)).accessibilityHidden(true)
            Text("Keep the recipes you actually cook").font(.display(30))
            Text("Start with one you make often. Type it, paste it from a website, or snap the card.")
                .font(.body(17, weight: 500)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            cookedOften(bank)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wall-recipes-empty")
    }
}

// MARK: - The kitchen view

/// A recipe readable from the stove: big type, ingredients beside steps. We made this,
/// Plan it, ingredients ticked for the grocery list, Edit, and Remove with Undo.
struct WallRecipeSheet: View {
    let dishId: Dish.ID
    let onCook: (Dish) -> Void
    let onPlan: (Dish) -> Void
    let onEdit: (Dish) -> Void
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @Environment(HomeStore.self) private var home
    @State private var picked: Set<Int> = []
    @State private var added: [ListItem] = []
    @State private var confirmingRemove = false
    @State private var removal: RecipeRemoval?

    var body: some View {
        WallSheet(width: 1040, onClose: onClose) {
            if let dish = store.book.dish(dishId), let entry = store.recipeBank.entry(dish) {
                // A long recipe scrolls inside the sheet, which keeps a margin on screen.
                ViewThatFits(in: .vertical) {
                    content(entry)
                    ScrollView { content(entry) }
                        .scrollBounceBehavior(.basedOnSize)
                        .containerRelativeFrame(.vertical) { length, _ in length - 100 }
                }
            } else if let removal {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The recipe was removed").font(.display(28))
                    Text("The dish stays, with its meals and faces.").font(.body(16, weight: 500)).foregroundStyle(Theme.muted)
                    HStack {
                        Button("Undo") { store.restore(removal); self.removal = nil }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("wall-undo-remove-recipe")
                        Spacer()
                        Button("Done", action: onClose).buttonStyle(PrimaryButtonStyle())
                    }
                }
            } else {
                Text("This recipe was removed.").font(.body(17, weight: 600)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func content(_ entry: RecipeBank.Entry) -> some View {
        let recipe = entry.recipe
        let addedBy = recipe.addedById.flatMap { id in store.snapshot.everyone.first { $0.id == id }?.name }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                RecipePicture(entry: entry, size: 120)
                VStack(alignment: .leading, spacing: 6) {
                    // The whole name, readable from the stove, clear of the close button.
                    Text(entry.dish.name).font(.display(36))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 48)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("wall-recipe-title")
                    Text([addedBy?.possessive, RecipeWords.serves(recipe.serves),
                          RecipeWords.cookedLine(times: entry.times, last: entry.last?.eatenAt, now: CompanionClock.now(), calendar: store.calendar)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.body(17, weight: 600)).foregroundStyle(Theme.muted)
                    HStack(spacing: 10) {
                        Button("🍳 We made this") { onCook(entry.dish) }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("wall-we-made-this")
                        Button("📅 Plan it") { onPlan(entry.dish) }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("wall-plan-recipe")
                        Button("✏️ Edit") { onEdit(entry.dish) }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("wall-edit-recipe")
                        Button("🗑️ Remove") { confirmingRemove = true }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("wall-remove-recipe")
                    }
                    .padding(.top, 4)
                }
            }
            HStack(alignment: .top, spacing: 26) {
                ingredients(recipe.ingredientLines)
                    .frame(width: 380, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Steps").font(.display(24)).accessibilityAddTraits(.isHeader)
                    ForEach(Array(recipe.stepLines.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(index + 1)").font(.body(18, weight: 800))
                                .frame(width: 34, height: 34)
                                .background(Theme.surface2, in: Circle())
                            Text(step).font(.body(22, weight: 500)).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if !recipe.notes.isEmpty {
                        // Cooking information, read from the stove like the steps.
                        Text("Notes").font(.display(24)).accessibilityAddTraits(.isHeader).padding(.top, 10)
                        Text(recipe.notes).font(.body(22, weight: 500)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .confirmationDialog("Remove the recipe?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove recipe", role: .destructive) { removal = store.removeRecipe(of: entry.dish.id) }
            Button("Keep it", role: .cancel) {}
        } message: {
            let plans = home.snapshot.meals.filter { PlannedDish.dish(for: $0, in: store.book)?.id == entry.dish.id }.count
            Text(RecipeWords.removeSheet(dishName: entry.dish.name, meals: entry.times, plannedDinners: plans))
        }
    }

    @ViewBuilder
    private func ingredients(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients").font(.display(24)).accessibilityAddTraits(.isHeader)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Button {
                    if picked.contains(index) { picked.remove(index) } else { picked.insert(index) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: picked.contains(index) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(picked.contains(index) ? Theme.accent : Theme.muted)
                        Text(line).font(.body(20, weight: 600)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked.contains(index) ? .isSelected : [])
                .accessibilityIdentifier("wall-ingredient-\(index)")
            }
            if !added.isEmpty {
                let words = RecipeWords.addedToGroceries(added.map(\.title))
                HStack(spacing: 10) {
                    Text("🛒 \(words.title)").font(.body(15, weight: 700))
                    Button("Undo") { home.removeItems(added); added = [] }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("wall-undo-groceries")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("wall-groceries-added")
            } else if picked.isEmpty {
                // A sentence until something is ticked: a button that can't be pressed looks missing.
                Text("Tick what to buy").font(.body(17, weight: 600)).foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("wall-groceries-hint")
            } else {
                Button("Add \(picked.count) to groceries") { addToGroceries(lines) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("wall-add-to-groceries")
            }
        }
    }

    private func addToGroceries(_ lines: [String]) {
        guard let list = home.lists(of: .grocery).first else { return }
        added = home.addIngredients(lines.indices.filter(picked.contains).map { lines[$0] }, to: list, addedBy: nil)
        picked = []
    }
}

// MARK: - Planning from the bank

/// Which of the next seven days has this dish for dinner, on the wall.
struct WallPlanDinnerSheet: View {
    let dish: Dish
    let onClose: () -> Void

    @Environment(HomeStore.self) private var home
    @State private var planned: String?

    var body: some View {
        let calendar = home.calendar
        let days = (0..<7).map { home.today.adding(days: $0, calendar: calendar) }
        WallSheet(width: 560, onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(dish.emoji) \(dish.name)").font(.body(13, weight: 800)).foregroundStyle(Theme.muted)
                Text(planned ?? "Plan it for").font(.display(28))
                if planned == nil {
                    VStack(spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element) { index, day in
                            if index > 0 { Divider() }
                            Button { plan(day, index: index) } label: {
                                HStack {
                                    Text(name(day, index: index, calendar: calendar)).font(.body(18, weight: 700)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(home.meal(on: day).map { "\($0.emoji ?? "🍽️") \($0.title)" } ?? "Nothing planned")
                                        .font(.body(15, weight: 600)).foregroundStyle(Theme.muted)
                                }
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wall-plan-day-\(index)")
                        }
                    }
                } else {
                    Button("Done", action: onClose).buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private func name(_ day: DayKey, index: Int, calendar: Calendar) -> String {
        index == 0 ? "Tonight" : index == 1 ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide), calendar: calendar)
    }

    private func plan(_ day: DayKey, index: Int) {
        guard home.setMeal(on: day, title: dish.name, emoji: dish.emoji, dishId: dish.id) else { return }
        planned = "\(dish.name) is planned for \(name(day, index: index, calendar: home.calendar).lowercased())"
    }
}
