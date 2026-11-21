import SwiftUI

// The phone's recipes (docs/design/dishes.md, "Recipes"; journeys P6 and P7 of
// docs/proposals/dishes-and-recipes.html): the Food tab's Recipes view, the recipe
// editor, and a recipe's page.

// MARK: - The bank

/// The Food tab's third view: our home dishes that know how they are made. Search by name
/// or ingredient, "Haven't made in a while", every recipe, and the dishes we cook often
/// that have none yet. A new household sees why it is empty.
struct PocketRecipesView: View {
    let onAdd: (Dish?) -> Void
    let onPlan: (Dish) -> Void

    @Environment(FoodStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @PhoneMetric(upTo: 1.4) private var oftenArt: CGFloat = 34

    var body: some View {
        let bank = store.recipeBank
        let entries = bank.entries
        VStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                empty(bank)
            } else {
                search
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    results(bank.search(query))
                } else {
                    if let waiting = bank.notMadeInAWhile(now: CompanionClock.now(), calendar: store.calendar) {
                        notMadeInAWhile(waiting)
                    }
                    list(entries)
                    Button { onAdd(nil) } label: { Label("New recipe", systemImage: "plus") }
                        .buttonStyle(PhoneButtonStyle(kind: .ghost))
                        .accessibilityIdentifier("new-recipe")
                    cookedOften(bank)
                }
            }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Search recipes and ingredients", text: $query)
                .phoneFont(.body, 15, weight: 600)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("recipe-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }

    private func notMadeInAWhile(_ entry: RecipeBank.Entry) -> some View {
        let calendar = store.calendar
        let last = entry.last.map { RecipeWords.last($0.eatenAt, now: CompanionClock.now(), calendar: calendar) } ?? ""
        return HStack(alignment: .center, spacing: 10) {
            Text("🕰️").font(.system(size: 18)).accessibilityHidden(true)
            NavigationLink(value: PocketFoodRoute.recipe(entry.dish.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haven't made in a while").phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline).foregroundStyle(Theme.ink)
                    Text([entry.dish.name, last, entry.face.map { "usually \($0.emoji)" }].compactMap { $0 }.joined(separator: " · "))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Plan it") { onPlan(entry.dish) }
                .phoneFont(.body, 13, weight: 800, relativeTo: .footnote)
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("plan-waiting")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("not-made-in-a-while")
    }

    private func list(_ entries: [RecipeBank.Entry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { RowDivider() }
                PocketRecipeRow(entry: entry)
            }
        }
        .padding(.vertical, -4)
        .phoneCard()
    }

    @ViewBuilder
    private func results(_ found: [RecipeBank.Entry]) -> some View {
        if found.isEmpty {
            Text("No recipe has \"\(query.trimmingCharacters(in: .whitespaces))\" yet.")
                .phoneFont(.body, 14, weight: 600)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .phoneCard()
        } else {
            list(found)
        }
    }

    @ViewBuilder
    private func cookedOften(_ bank: RecipeBank) -> some View {
        let often = bank.cookedOftenWithoutRecipe()
        if !often.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                PhoneCardHeader(title: "You cook these often", meta: "no recipe yet")
                ForEach(Array(often.enumerated()), id: \.element.dish.id) { index, item in
                    if index > 0 { RowDivider() }
                    cookedOftenRow(item.dish, times: item.times)
                        .padding(.vertical, 2)
                }
            }
            .phoneCard()
        }
    }

    /// A dish we cook without a recipe: like the bank's rows, the words beside the picture
    /// (wrapping) at the standard sizes, below it at the accessibility sizes.
    @ViewBuilder
    private func cookedOftenRow(_ dish: Dish, times: Int) -> some View {
        let words = VStack(alignment: .leading, spacing: 1) {
            Text(dish.name).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
            Text(DishWords.times(times)).phoneFont(.body, 12, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        let add = Button("+ Recipe") { onAdd(dish) }
            .phoneFont(.body, 13, weight: 800, relativeTo: .footnote)
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Add a recipe for \(dish.name)")
            .accessibilityIdentifier("add-recipe-\(dish.name)")
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack { DishArt(dish: dish, size: oftenArt); Spacer(minLength: 8); add }
                words
            }
        } else {
            HStack(spacing: 10) {
                DishArt(dish: dish, size: oftenArt)
                words
                Spacer(minLength: 4)
                add
            }
        }
    }

    private func empty(_ bank: RecipeBank) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Text("📖").font(.system(size: 46)).accessibilityHidden(true)
                Text("Keep the recipes you actually cook")
                    .phoneFont(.display, 22, weight: 600, relativeTo: .title2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Start with one you make often. Type it, paste it from a website, or snap the card.")
                    .phoneFont(.body, 14.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("recipes-empty")
            Button { onAdd(nil) } label: { Label("Add a recipe", systemImage: "plus") }
                .buttonStyle(PhoneButtonStyle())
                .accessibilityIdentifier("new-recipe")
            cookedOften(bank)
        }
    }
}

/// A recipe in the bank: its card photo or its dish's picture, name, whose and how often
/// cooked, and its usual face.
struct PocketRecipeRow: View {
    let entry: RecipeBank.Entry

    @Environment(FoodStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @PhoneMetric(upTo: 1.4) private var art: CGFloat = 52

    var body: some View {
        let addedBy = entry.recipe.addedById.flatMap { id in store.snapshot.everyone.first { $0.id == id }?.name }
        let line = RecipeWords.bankLine(
            addedBy: addedBy, hasLink: entry.recipe.link != nil, hasCard: !entry.photos.isEmpty,
            times: entry.times, last: entry.last?.eatenAt, now: CompanionClock.now(), calendar: store.calendar
        )
        NavigationLink(value: PocketFoodRoute.recipe(entry.dish.id)) {
            Group {
                if typeSize.isAccessibilitySize {
                    // Stacked: the picture and the face, then the words at full width.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { RecipePicture(entry: entry, size: art); Spacer(); trailing }
                        words(line)
                    }
                } else {
                    HStack(spacing: 12) {
                        RecipePicture(entry: entry, size: art)
                        words(line)
                        Spacer(minLength: 4)
                        trailing
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([entry.dish.name, line, entry.face?.phrase].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("recipe-\(entry.dish.name)")
    }

    private func words(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.dish.name).phoneFont(.display, 17, weight: 600, relativeTo: .headline).foregroundStyle(Theme.ink)
            Text(line).phoneFont(.body, 12, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailing: some View {
        if let face = entry.face {
            Text(face.emoji).phoneFont(.body, 18, weight: 400, relativeTo: .subheadline).accessibilityLabel(face.phrase)
        } else if entry.times == 0 {
            PhoneTag(text: "New")
        }
    }
}

/// A recipe's picture: the first card photo, else its dish's.
struct RecipePicture: View {
    let entry: RecipeBank.Entry
    var size: CGFloat

    var body: some View {
        if let photo = entry.photos.first {
            PhotoView(PhotoRequest(.recipeThumbnail(photo.id, byteCount: 0))) { _ in DishArt(dish: entry.dish, size: size) }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .accessibilityHidden(true)
        } else {
            DishArt(dish: entry.dish, size: size, corner: 0.22)
        }
    }
}

// MARK: - A recipe's page

/// How a dish is made, and what it remembers: whose, serves, how often and when last
/// cooked; We made this and Plan it; ingredients to pick for groceries; steps; notes;
/// where it came from; photos of the card. Edit and Remove (with Undo) at the end.
struct PocketRecipePage: View {
    let dishId: Dish.ID
    let onCook: (Dish) -> Void
    let onPlan: (Dish) -> Void
    let onEdit: (Dish) -> Void

    @Environment(FoodStore.self) private var store
    @Environment(HomeStore.self) private var home
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var picked: Set<Int> = []
    @State private var confirmingRemove = false
    @State private var wholeCard: RecipePhoto?
    @PhoneMetric(upTo: 1.3) private var hero: CGFloat = 96
    /// The tick box beside an ingredient, grown with its words.
    @PhoneMetric(upTo: 2.2) private var box: CGFloat = 18

    var body: some View {
        Group {
            if let dish = store.book.dish(dishId), let entry = store.recipeBank.entry(dish) {
                content(entry)
            } else {
                Text("This recipe was removed.")
                    .phoneFont(.body, 15, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
    }

    private func content(_ entry: RecipeBank.Entry) -> some View {
        let recipe = entry.recipe
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(entry)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    Button { onCook(entry.dish) } label: { Text("🍳 We made this") }
                        .buttonStyle(PhoneButtonStyle(small: true))
                        .fixedSize()
                        .accessibilityIdentifier("we-made-this")
                    Button { onPlan(entry.dish) } label: { Text("📅 Plan it") }
                        .buttonStyle(PhoneButtonStyle(kind: .ghost, small: true))
                        .fixedSize()
                        .accessibilityIdentifier("plan-recipe")
                }
                ingredients(recipe.ingredientLines, dish: entry.dish)
                steps(recipe.stepLines)
                if !recipe.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        PhoneCardHeader(title: "Notes", meta: nil)
                        Text(recipe.notes).phoneFont(.body, 14.5, weight: 500).fixedSize(horizontal: false, vertical: true)
                    }
                    .phoneCard()
                }
                cards(entry.photos)
                if let link = recipe.link, let url = URL(string: link) {
                    Button { openURL(url) } label: {
                        Label(url.host() ?? link, systemImage: "link")
                            .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("recipe-link")
                }
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    PhoneChoice(title: "✏️ Edit", isOn: false) { onEdit(entry.dish) }
                        .accessibilityIdentifier("edit-recipe")
                    NavigationLink(value: PocketFoodRoute.dish(entry.dish.id)) {
                        Text("🍽️ Every time").phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recipe-dish")
                    PhoneChoice(title: "🗑️ Remove", isOn: false) { confirmingRemove = true }
                        .accessibilityIdentifier("remove-recipe")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(entry.dish.name)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .confirmationDialog("Remove the recipe?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove recipe", role: .destructive) { remove(entry) }
            Button("Keep it", role: .cancel) {}
        } message: {
            let plans = home.snapshot.meals.filter { PlannedDish.dish(for: $0, in: store.book)?.id == entry.dish.id }.count
            Text(RecipeWords.removeSheet(dishName: entry.dish.name, meals: entry.times, plannedDinners: plans))
        }
        .fullScreenCover(item: $wholeCard) { photo in
            PocketWholeCard(photo: photo) { wholeCard = nil }
        }
    }

    private func header(_ entry: RecipeBank.Entry) -> some View {
        let addedBy = entry.recipe.addedById.flatMap { id in store.snapshot.everyone.first { $0.id == id } }
        let whose = addedBy.map { $0.id == me?.id ? "Yours" : $0.name.possessive }
        let cooked = RecipeWords.cookedLine(times: entry.times, last: entry.last?.eatenAt, now: CompanionClock.now(), calendar: store.calendar)
        let title = VStack(alignment: .leading, spacing: 4) {
            Text(entry.dish.name)
                .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("recipe-title")
            Text([whose, RecipeWords.serves(entry.recipe.serves)].compactMap { $0 }.joined(separator: " · "))
                .phoneFont(.body, 13.5, weight: 600, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
            Text(cooked)
                .phoneFont(.body, 13.5, weight: 600, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("recipe-cooked")
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { RecipePicture(entry: entry, size: hero); title }
            VStack(alignment: .leading, spacing: 12) { RecipePicture(entry: entry, size: hero); title }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func ingredients(_ lines: [String], dish: Dish) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                let title = Text("Ingredients").phoneFont(.display, 17, weight: 600, relativeTo: .headline).accessibilityAddTraits(.isHeader)
                // A sentence until something is ticked: a button that can't be pressed looks missing.
                let groceries = Group {
                    if picked.isEmpty {
                        Text("Tick what to buy")
                            .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("groceries-hint")
                    } else {
                        Button("Add \(picked.count) to groceries") { addToGroceries(lines, dish: dish) }
                            .phoneFont(.body, 13, weight: 800, relativeTo: .footnote)
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add-to-groceries")
                    }
                }
                .frame(minHeight: 44)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { title.fixedSize(); Spacer(minLength: 8); groceries.fixedSize() }
                    VStack(alignment: .leading, spacing: 0) { title; groceries }
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 { RowDivider() }
                    Button {
                        if picked.contains(index) { picked.remove(index) } else { picked.insert(index) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: picked.contains(index) ? "checkmark.square.fill" : "square")
                                .font(.system(size: box, weight: .semibold))
                                .foregroundStyle(picked.contains(index) ? Theme.accent : Theme.muted)
                            Text(line).phoneFont(.body, 14.5, weight: 600).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked.contains(index) ? .isSelected : [])
                    .accessibilityHint("Picks it for the grocery list")
                    .accessibilityIdentifier("ingredient-\(index)")
                }
            }
            .phoneCard()
        }
    }

    @ViewBuilder
    private func steps(_ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PhoneCardHeader(title: "Steps", meta: "\(lines.count)")
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .phoneFont(.body, 12, weight: 800, relativeTo: .caption)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(Theme.surface2, in: Circle())
                        Text(line).phoneFont(.body, 14.5, weight: 500).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .phoneCard()
        }
    }

    @ViewBuilder
    private func cards(_ photos: [RecipePhoto]) -> some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PhoneCardHeader(title: "The card", meta: photos.count == 1 ? "1 photo" : "\(photos.count) photos")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            Button { wholeCard = photo } label: {
                                PhotoView(PhotoRequest(.recipeThumbnail(photo.id, byteCount: 0))) { _ in Theme.surface2 }
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Photo of the card")
                        }
                    }
                }
            }
            .phoneCard()
        }
    }

    private func addToGroceries(_ lines: [String], dish: Dish) {
        guard let list = home.lists(of: .grocery).first else { return }
        let chosen = lines.indices.filter(picked.contains).map { lines[$0] }
        let added = home.addIngredients(chosen, to: list, addedBy: me?.id)
        picked = []
        guard !added.isEmpty else { return }
        let words = RecipeWords.addedToGroceries(added.map(\.title))
        toasts.show(UndoToast(
            emoji: "🛒", title: words.title, detail: words.detail,
            action: UndoToast.Action(title: "Undo") { [home] in home.removeItems(added) }
        ))
    }

    private func remove(_ entry: RecipeBank.Entry) {
        guard let removal = store.removeRecipe(of: entry.dish.id) else { return }
        dismiss()
        toasts.show(UndoToast(
            emoji: "📖", title: "Recipe removed", detail: "\(entry.dish.name) stays a dish",
            action: UndoToast.Action(title: "Undo") { [store] in store.restore(removal) }
        ))
    }
}

/// A photo of the card, whole, over everything; a tap closes it.
private struct PocketWholeCard: View {
    let photo: RecipePhoto
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PhotoView(request: PhotoRequest(.recipeImage(photo.id, byteCount: 0))) { image in
                image.resizable().scaledToFit()
            } placeholder: { _ in ProgressView().tint(.white) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Photo of the card. Close")
        .accessibilityIdentifier("whole-card")
    }
}

// MARK: - The editor

/// Adds or edits a recipe: the name (joining the home dish of that name), serves,
/// ingredients and steps one per line (pasted text is cleaned on saving), where it came
/// from (a link, photos of the card), and notes.
struct PocketRecipeEditor: View {
    /// The dish being given a recipe or edited; nil for a new one from the bank.
    let dish: Dish?

    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var serves: Int?
    @State private var ingredients = ""
    @State private var steps = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var photos: [EditedCard] = []
    @State private var snapping = false
    @State private var error: String?
    @State private var loaded = false

    /// A card photo in the editor: one saved already, or one just taken.
    struct EditedCard: Identifiable {
        var id: RecipePhoto.ID
        var new: NewRecipePhoto?
    }

    private var existing: Recipe? { dish.flatMap { store.book.recipe(of: $0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameField
                    joins
                    group("Serves") {
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach([2, 4, 6, 8], id: \.self) { count in
                                PhoneChoice(title: "\(count)", isOn: serves == count) { serves = serves == count ? nil : count }
                                    .accessibilityIdentifier("serves-\(count)")
                            }
                        }
                    }
                    group("Ingredients", hint: "one per line") {
                        lines($ingredients, placeholder: "2 lb chicken thighs\n1 onion", id: "recipe-ingredients")
                    }
                    group("Steps", hint: "one per line") {
                        lines($steps, placeholder: "Brown the chicken in batches.", id: "recipe-steps")
                    }
                    group("From") {
                        TextField("Link, e.g. example.com/curry", text: $link)
                            .phoneFont(.body, 15, weight: 600)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .fieldStyle()
                            .accessibilityIdentifier("recipe-link-field")
                        cardRow
                    }
                    group("Notes") {
                        lines($notes, placeholder: "Ava likes it mild.", id: "recipe-notes")
                    }
                    if let error {
                        Text(error).phoneFont(.body, 13, weight: 600, relativeTo: .footnote).foregroundStyle(Theme.accent)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(existing == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(DishName.key(name).isEmpty)
                        .accessibilityIdentifier("save-recipe")
                }
            }
        }
        .tint(Theme.accent)
        .fullScreenCover(isPresented: $snapping) {
            PocketCameraStep(
                small: name.isEmpty ? nil : name,
                title: "Photo of the card",
                caption: name.isEmpty ? "The card" : name,
                remaining: RecipeLimits.photos - photos.count,
                onImages: { images in
                    snapping = false
                    Task { await addCards(images) }
                },
                onClose: { snapping = false }
            )
        }
        .onAppear(perform: load)
    }

    private var nameField: some View {
        HStack(spacing: 10) {
            Text(DishIllustration.suggestEmoji(for: name) ?? dish?.emoji ?? "📖").font(.system(size: 20)).accessibilityHidden(true)
            TextField("Name, e.g. Chicken curry", text: $name)
                .phoneFont(.body, 17, weight: 700)
                .submitLabel(.done)
                .accessibilityIdentifier("recipe-name")
        }
        .fieldStyle()
    }

    /// "Joins the dish you already cook": a new recipe named like a home dish takes its history.
    @ViewBuilder
    private var joins: some View {
        if dish == nil, let joined = store.recipeBank.joins(name), store.book.recipe(of: joined.dish.id) == nil, joined.times > 0 {
            HStack(alignment: .top, spacing: 10) {
                Text("🔗").font(.system(size: 16)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Joins the dish you already cook").phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
                    Text("\(joined.dish.name) · Home · \(RecipeWords.cooked(joined.times)). Its history and faces come with it.")
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.goodSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("recipe-joins")
        }
    }

    private func group(_ title: String, hint: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased()).phoneFont(.body, 11, weight: 800, relativeTo: .caption).tracking(1)
                if let hint { Text(hint).phoneFont(.body, 11.5, weight: 600, relativeTo: .caption) }
            }
            .foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func lines(_ text: Binding<String>, placeholder: String, id: String) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .phoneFont(.body, 15, weight: 500)
            .lineLimit(3...)
            .fieldStyle()
            .accessibilityIdentifier(id)
    }

    private var cardRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { card in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let new = card.new, let image = UIImage(data: new.thumbnail) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                PhotoView(PhotoRequest(.recipeThumbnail(card.id, byteCount: 0))) { _ in Theme.surface2 }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button { photos.removeAll { $0.id == card.id } } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                        .offset(x: 10, y: -10)
                        .accessibilityLabel("Remove this photo of the card")
                    }
                }
                if photos.count < RecipeLimits.photos {
                    Button { snapping = true } label: {
                        Label("Photo of the card", systemImage: "camera")
                            .phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Theme.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recipe-card-photo")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = dish?.name ?? ""
        guard let recipe = existing else { return }
        serves = recipe.serves
        ingredients = recipe.ingredients
        steps = recipe.steps
        link = recipe.link ?? ""
        notes = recipe.notes
        photos = (store.snapshot.recipePhotos[recipe.id] ?? []).map { EditedCard(id: $0.id) }
    }

    private func addCards(_ images: [UIImage]) async {
        for image in images.prefix(RecipeLimits.photos - photos.count) {
            guard let prepared = try? await store.preparePhoto(image) else { continue }
            let new = NewRecipePhoto(image: prepared.image, thumbnail: prepared.thumbnail)
            photos.append(EditedCard(id: new.id, new: new))
        }
    }

    private func save() {
        var draft = RecipeDraft(name: name, dishId: dish?.id)
        draft.serves = serves
        draft.ingredients = RecipeText.pasted(ingredients)
        draft.steps = RecipeText.pasted(steps)
        draft.link = link
        draft.notes = notes
        draft.photos = photos.map { card in card.new.map(RecipePhotoItem.added) ?? .kept(card.id) }
        do {
            try store.saveRecipe(draft, addedBy: me?.id)
            dismiss()
        } catch let RecipeError.nameTaken(other) {
            error = "\(store.book.dish(other)?.name ?? "That") is already a dish we cook. Pick another name, or add the recipe to it from its page."
        } catch {
            self.error = error.userMessage
        }
    }
}

// MARK: - Planning a dinner from a recipe

/// "Plan it": which of the next seven days has this dish for dinner. A day that already
/// has a dinner says which, and planning replaces it.
struct PocketPlanDinner: View {
    let dish: Dish

    @Environment(HomeStore.self) private var home
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let calendar = home.calendar
        let days = (0..<7).map { home.today.adding(days: $0, calendar: calendar) }
        PhoneSheet(label: "\(dish.emoji) \(dish.name)", title: "Plan it for") {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    if index > 0 { RowDivider() }
                    row(day, index: index, calendar: calendar)
                }
            }
            .phoneCard()
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
        }
    }

    private func row(_ day: DayKey, index: Int, calendar: Calendar) -> some View {
        let planned = home.meal(on: day)
        return Button { plan(day) } label: {
            HStack(spacing: 10) {
                Text(index == 0 ? "Tonight" : index == 1 ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide), calendar: calendar))
                    .phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(planned.map { "\($0.emoji ?? "🍽️") \($0.title)" } ?? "Nothing planned")
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan-day-\(index)")
    }

    private func plan(_ day: DayKey) {
        guard home.setMeal(on: day, title: dish.name, emoji: dish.emoji, dishId: dish.id) else { return }
        dismiss()
        let when = day == home.today ? "tonight" : day.formatted(.dateTime.weekday(.wide), calendar: home.calendar)
        toasts.showAfterSheet(UndoToast(emoji: dish.emoji, title: "\(dish.name) planned for \(when)", detail: nil, action: nil))
    }
}
