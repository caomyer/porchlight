import SwiftUI

// The phone's dishes (docs/design/dishes.md, journeys P4, P5, P7 and P8 of
// docs/proposals/dishes-and-recipes.html): the Food tab's Dishes view, a dish's page,
// a restaurant's page, renaming and removing a dish.

// MARK: - The Dishes view

/// The Food tab's second view: one search field, filters, then favourites, home and each
/// restaurant's dishes. Every row opens its dish.
struct PocketDishesView: View {
    @Environment(FoodStore.self) private var store
    @State private var query = ""
    @State private var filter: Filter = .all
    @AppStorage("dishes.introSeen") private var introSeen = false

    enum Filter: String, CaseIterable {
        case all, favorites, home, out

        var title: String {
            switch self {
            case .all: "All"
            case .favorites: "★ Favourites"
            case .home: "🏠 Home"
            case .out: "📍 Out"
            }
        }
    }

    var body: some View {
        let book = store.book
        VStack(alignment: .leading, spacing: 12) {
            search
            if book.mostHad.isEmpty {
                empty
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                results(book.search(query))
            } else {
                if !introSeen { intro(count: book.mostHad.count) }
                filters
                sections(book)
            }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField("Search dishes and places", text: $query)
                .phoneFont(.body, 15, weight: 600)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("dish-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }

    private var filters: some View {
        FlowLayout(spacing: 6, lineSpacing: 0) {
            ForEach(Filter.allCases, id: \.self) { choice in
                PhoneChoice(title: choice.title, isOn: filter == choice) { filter = choice }
                    .accessibilityIdentifier("dish-filter-\(choice.rawValue)")
            }
        }
    }

    /// Once, after the update: the diary already knew its dishes.
    private func intro(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your diary already knew \(count == 1 ? "1 dish" : "\(count) dishes")")
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Each meal you named became a dish, and the same name at the same place became one. Rename or merge any that came out wrong.")
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Got it") { introSeen = true }
                .buttonStyle(PhoneButtonStyle(small: true))
                .fixedSize()
                .accessibilityIdentifier("dishes-intro-ok")
        }
        .phoneCard(tint: Theme.good)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("🍽️").font(.system(size: 46)).accessibilityHidden(true)
            Text("Name what you eat, and Porchlight remembers it")
                .phoneFont(.display, 22, weight: 600, relativeTo: .title2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Each dish you add when you log a meal shows up here, with every time you had it and how everyone liked it.")
                .phoneFont(.body, 14.5, weight: 500)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dishes-empty")
    }

    @ViewBuilder
    private func sections(_ book: DishBook) -> some View {
        if filter == .all || filter == .favorites {
            let favorites = book.favorites
            if !favorites.isEmpty {
                section("★ Favourites", meta: "\(favorites.count)", dishes: favorites, showKitchen: true)
            } else if filter == .favorites {
                Text("No favourites yet. Star a dish on its page to keep it here.")
                    .phoneFont(.body, 14, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .phoneCard()
            }
        }
        if filter == .all || filter == .home {
            let home = book.homeDishes
            if !home.isEmpty {
                section("🏠 Home", meta: home.count == 1 ? "1 dish" : "\(home.count) dishes", dishes: home, showKitchen: false)
            }
        }
        if filter == .all || filter == .out {
            ForEach(book.placesWithDishes, id: \.place.id) { place, dishes in
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink(value: PocketFoodRoute.place(place.id)) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("📍 \(place.name)")
                                .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 8)
                            Text("\(dishes.count == 1 ? "1 dish" : "\(dishes.count) dishes") ›")
                                .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("place-\(place.name)")
                    rows(Array(dishes.prefix(3)), showKitchen: false)
                }
            }
            let elsewhere = book.elsewhereDishes
            if !elsewhere.isEmpty {
                section("🏢 Elsewhere", meta: "\(elsewhere.count)", dishes: elsewhere, showKitchen: false)
            }
        }
    }

    private func section(_ title: String, meta: String, dishes: [Dish], showKitchen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(meta)
                    .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 4)
            rows(dishes, showKitchen: showKitchen)
        }
    }

    private func rows(_ dishes: [Dish], showKitchen: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(dishes.enumerated()), id: \.element.id) { index, dish in
                if index > 0 { RowDivider() }
                PocketDishRow(dish: dish, showKitchen: showKitchen)
            }
        }
        .padding(.vertical, -4)
        .phoneCard()
    }

    @ViewBuilder
    private func results(_ found: (dishes: [Dish], places: [FoodPlace])) -> some View {
        if found.dishes.isEmpty && found.places.isEmpty {
            Text("Nothing called \"\(query.trimmingCharacters(in: .whitespaces))\" yet.")
                .phoneFont(.body, 14, weight: 600)
                .foregroundStyle(Theme.muted)
                .phoneCard()
        }
        if !found.dishes.isEmpty {
            section("Dishes", meta: "\(found.dishes.count)", dishes: found.dishes, showKitchen: true)
        }
        if !found.places.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Places").phoneFont(.display, 17, weight: 600, relativeTo: .headline)
                    Spacer()
                    Text("\(found.places.count)").phoneFont(.body, 12, weight: 700, relativeTo: .caption).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 0) {
                    ForEach(Array(found.places.enumerated()), id: \.element.id) { index, place in
                        if index > 0 { RowDivider() }
                        PocketPlaceRow(place: place)
                    }
                }
                .padding(.vertical, -4)
                .phoneCard()
            }
        }
    }
}

/// A dish in a list: its picture, name, where it's from and how often, and its usual face.
struct PocketDishRow: View {
    let dish: Dish
    var showKitchen = true

    @Environment(FoodStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @PhoneMetric(upTo: 1.4) private var art: CGFloat = 36

    private func words(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dish.favorite ? "\(dish.name) ★" : dish.name)
                .phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                .foregroundStyle(Theme.ink)
            Text(detail)
                .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func face(_ face: MealRating?) -> some View {
        if let face {
            Text(face.emoji).phoneFont(.body, 18, weight: 400, relativeTo: .subheadline).accessibilityLabel(face.phrase)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .phoneFont(.body, 12, weight: 800, relativeTo: .subheadline)
            .foregroundStyle(Theme.muted)
            .accessibilityHidden(true)
    }

    var body: some View {
        let summary = store.book.summary(of: dish.id)
        let detail = [
            showKitchen ? DishWords.kitchen(dish, places: store.snapshot.places) : nil,
            DishWords.times(summary.count),
            summary.last.map { DishWords.last($0, today: store.today(CompanionClock.now()), calendar: store.calendar) },
        ].compactMap { $0 }.joined(separator: " · ")
        NavigationLink(value: PocketFoodRoute.dish(dish.id)) {
            Group {
                if typeSize.isAccessibilitySize {
                    // Stacked: the picture and the face, then the words at full width.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            DishArt(dish: dish, size: art)
                            Spacer(minLength: 4)
                            face(summary.face)
                            chevron
                        }
                        // Read first, as beside the picture: the name, then the face.
                        words(detail).accessibilitySortPriority(1)
                    }
                } else {
                    HStack(spacing: 10) {
                        DishArt(dish: dish, size: art)
                        words(detail)
                        Spacer(minLength: 4)
                        face(summary.face)
                        chevron
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dish-\(dish.name)")
    }
}

private struct PocketPlaceRow: View {
    let place: FoodPlace
    @Environment(FoodStore.self) private var store

    var body: some View {
        let summary = store.book.summary(of: place.id)
        NavigationLink(value: PocketFoodRoute.place(place.id)) {
            HStack(spacing: 10) {
                Text("📍").font(.system(size: 20)).frame(width: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline).foregroundStyle(Theme.ink)
                    Text([summary.visits == 1 ? "1 visit" : "\(summary.visits) visits",
                          summary.last.map { DishWords.last($0, today: store.today(CompanionClock.now()), calendar: store.calendar) }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A dish's page

/// A dish with its memory: how many times since when, each person's usual face, photos of
/// the meals it was on, and every time, newest first. Favourite, Rename and Remove below.
struct PocketDishDetail: View {
    let dishId: Dish.ID

    @Environment(FoodStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var confirmingRemove = false
    @State private var addingRecipe = false
    @PhoneMetric(upTo: 1.3) private var hero: CGFloat = 96

    var body: some View {
        Group {
            if let dish = store.book.dish(dishId) {
                content(dish)
            } else {
                Text("This dish was removed.")
                    .phoneFont(.body, 15, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
    }

    private func content(_ dish: Dish) -> some View {
        let book = store.book
        let summary = book.summary(of: dish.id)
        let times = book.times(of: dish.id)
        let today = store.today(CompanionClock.now())
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(dish)
                stats(summary, today: today)
                recipe(dish)
                faces(dish)
                photos(times)
                history(times, today: today)
                alsoHad(dish)
                actions(dish)
                if let error = store.lastError {
                    Text(error).phoneFont(.body, 13, weight: 600, relativeTo: .footnote).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(dish.name)
        // The title names the back button of the next page; the page shows its own.
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .sheet(isPresented: $renaming) { PocketRenameDish(dish: dish) }
        .sheet(isPresented: $addingRecipe) { PocketRecipeEditor(dish: dish) }
        .confirmationDialog(removeTitle(dish, count: summary.count), isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove dish", role: .destructive) { remove(dish) }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(summary.count == 1 ? "The meal stays, with its photos and its other dishes." : "The meals stay, with their photos and their other dishes.")
        }
        .onAppear { store.lastError = nil }
    }

    /// A home dish's recipe, or the way to add one (docs/design/dishes.md, "Recipes").
    @ViewBuilder
    private func recipe(_ dish: Dish) -> some View {
        if dish.kitchen == .home {
            if store.book.recipe(of: dish.id) != nil {
                NavigationLink(value: PocketFoodRoute.recipe(dish.id)) {
                    recipeRow(title: "The recipe", color: Theme.ink, mark: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dish-recipe")
            } else {
                Button { addingRecipe = true } label: {
                    recipeRow(title: "Add a recipe", color: Theme.accent, mark: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dish-add-recipe")
            }
        }
    }

    /// One line in a card, the card's own padding making it a whole touch.
    private func recipeRow(title: String, color: Color, mark: String) -> some View {
        HStack(spacing: 10) {
            Text("📖").phoneFont(.body, 18, weight: 400, relativeTo: .subheadline).accessibilityHidden(true)
            Text(title).phoneFont(.body, 15, weight: 700, relativeTo: .subheadline).foregroundStyle(color)
            Spacer(minLength: 8)
            Image(systemName: mark).phoneFont(.body, 12, weight: 800, relativeTo: .subheadline).foregroundStyle(color == Theme.ink ? Theme.muted : color)
                .accessibilityHidden(true)
        }
        .phoneCard()
        .contentShape(Rectangle())
    }

    private func removeTitle(_ dish: Dish, count: Int) -> String {
        count == 0 ? "Remove \(dish.name)?" : "Take \(dish.name) off \(count == 1 ? "1 meal" : "\(count) meals")?"
    }

    private func header(_ dish: Dish) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { DishArt(dish: dish, size: hero, corner: 0.19); title(dish) }
            VStack(alignment: .leading, spacing: 12) { DishArt(dish: dish, size: hero, corner: 0.19); title(dish) }
        }
        .padding(.top, 4)
    }

    private func title(_ dish: Dish) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dish.name)
                .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("dish-title")
            switch dish.kitchen {
            case let .place(id):
                if let place = store.snapshot.places.first(where: { $0.id == id }) {
                    NavigationLink(value: PocketFoodRoute.place(id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("📍 \(place.name) ›").phoneFont(.body, 13.5, weight: 700, relativeTo: .footnote).foregroundStyle(Theme.accent)
                            if let address = place.address {
                                Text(address).phoneFont(.body, 13, weight: 600, relativeTo: .footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dish-place")
                }
            case .home:
                Text("🏠 Home-cooked").phoneFont(.body, 13.5, weight: 600, relativeTo: .footnote).foregroundStyle(Theme.muted)
            case .elsewhere:
                Text("🏢 Elsewhere").phoneFont(.body, 13.5, weight: 600, relativeTo: .footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private func stats(_ summary: DishBook.Summary, today: DayKey) -> some View {
        let calendar = store.calendar
        let tiles: [(String, String)] = [
            ("\(summary.count)", summary.count == 1 ? "time" : "times"),
            (summary.first.map { DishWords.day($0, today: today, calendar: calendar) } ?? "–", "first"),
            (summary.last.map { DishWords.day($0, today: today, calendar: calendar) } ?? "–", "last"),
        ]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(tiles, id: \.1) { statTile($0.0, $0.1, stacked: true) } }
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) { ForEach(tiles, id: \.1) { statTile($0.0, $0.1, stacked: false) } }
        }
    }

    private func statTile(_ value: String, _ label: String, stacked: Bool) -> some View {
        Group {
            if stacked {
                VStack(spacing: 2) {
                    Text(value).phoneFont(.display, 20, weight: 600, relativeTo: .title3).lineLimit(1).minimumScaleFactor(0.7)
                    Text(label).phoneFont(.body, 11.5, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).phoneFont(.display, 20, weight: 600, relativeTo: .title3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(label).phoneFont(.body, 11.5, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func faces(_ dish: Dish) -> some View {
        let usual = store.book.usualFaces(of: dish.id)
        if !usual.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PhoneCardHeader(title: "How we like it", meta: "usual face")
                ForEach(usual, id: \.person.id) { person, face in
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            PersonAvatar(person, size: .small)
                            Text(person.id == me?.id ? "You" : person.name).phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                            Text(face.rating.emoji).phoneFont(.body, 18, weight: 400, relativeTo: .subheadline)
                            Spacer(minLength: 8)
                            Text("\(face.count) of \(face.of)").phoneFont(.body, 12, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                PersonAvatar(person, size: .small)
                                Text(person.id == me?.id ? "You" : person.name).phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                                Text(face.rating.emoji).phoneFont(.body, 18, weight: 400, relativeTo: .subheadline)
                            }
                            Text("\(face.count) of \(face.of)").phoneFont(.body, 12, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(person.id == me?.id ? "You" : person.name): \(face.rating.phrase), \(face.count) of \(face.of) times")
                }
            }
            .phoneCard()
        }
    }

    @ViewBuilder
    private func photos(_ times: [DishBook.Time]) -> some View {
        let meals = times.map(\.entry).filter { !store.photos(of: $0).isEmpty }
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PhoneCardHeader(title: "Photos", meta: meals.count == 1 ? "from 1 meal" : "from \(meals.count) meals")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(meals) { meal in
                            NavigationLink(value: PocketFoodRoute.meal(meal.id)) {
                                MealThumbnail(entry: meal, size: 56)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(PocketFood.mealName(day: meal.dayKey, slot: meal.slot, calendar: store.calendar))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .phoneCard()
        }
    }

    @ViewBuilder
    private func history(_ times: [DishBook.Time], today: DayKey) -> some View {
        if !times.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                PhoneCardHeader(title: "Every time", meta: "\(times.count)")
                ForEach(Array(times.enumerated()), id: \.element.id) { index, time in
                    if index > 0 { RowDivider() }
                    NavigationLink(value: PocketFoodRoute.meal(time.entry.id)) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(DishWords.day(time.entry, today: today, calendar: store.calendar)) · \(time.entry.slot.lowercased())")
                                    .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline).foregroundStyle(Theme.ink)
                                Text(DishWords.faces(time.faces, people: store.snapshot.everyone, me: me?.id))
                                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            if let face = time.line.rating ?? time.faces.values.max(by: { $0.rawValue < $1.rawValue }) {
                                Text(face.emoji).phoneFont(.body, 17, weight: 400, relativeTo: .subheadline)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            .phoneCard()
        }
    }

    @ViewBuilder
    private func alsoHad(_ dish: Dish) -> some View {
        let others = store.book.alsoHad(dish)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                PhoneCardHeader(title: "Also had at", meta: nil)
                ForEach(others) { other in PocketDishRow(dish: other) }
            }
            .phoneCard()
        }
    }

    private func actions(_ dish: Dish) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 4) {
            PhoneChoice(title: dish.favorite ? "★ Favourite" : "☆ Favourite", isOn: dish.favorite) {
                store.setFavorite(dish.id, !dish.favorite)
            }
            .accessibilityIdentifier("dish-favorite")
            PhoneChoice(title: "✏️ Rename", isOn: false) { renaming = true }
                .accessibilityIdentifier("dish-rename")
            PhoneChoice(title: "🗑️ Remove", isOn: false) { confirmingRemove = true }
                .accessibilityIdentifier("dish-remove")
        }
    }

    private func remove(_ dish: Dish) {
        guard let removal = store.removeDish(dish.id) else { return }
        dismiss()
        toasts.show(UndoToast(
            emoji: dish.emoji,
            title: "\(dish.name) removed",
            detail: removal.lines.isEmpty ? nil : "Taken off \(removal.lines.count == 1 ? "1 meal" : "\(removal.lines.count) meals")",
            action: UndoToast.Action(title: "Undo") { [store] in store.restore(removal) }
        ))
    }
}

// MARK: - Renaming

/// Renames a dish everywhere; a name the kitchen already has offers to merge the two.
private struct PocketRenameDish: View {
    let dish: Dish

    @Environment(FoodStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var twin: Dish?
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        PhoneSheet(label: "\(dish.name) · \(DishWords.kitchen(dish, places: store.snapshot.places))", title: "Rename the dish") {
            HStack(spacing: 10) {
                Text(dish.emoji).font(.system(size: 20)).accessibilityHidden(true)
                TextField("Name", text: $name)
                    .phoneFont(.body, 16, weight: 600)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: name) { _, _ in twin = nil; error = nil }
                    .accessibilityIdentifier("dish-name")
            }
            .fieldStyle()
            if let twin {
                let count = store.book.summary(of: twin.id).count
                HStack(alignment: .top, spacing: 10) {
                    Text("🔀").font(.system(size: 16)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(twin.name) is already a dish here").phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
                        Text("\(DishWords.times(count).prefix(1).uppercased() + DishWords.times(count).dropFirst()). Merge them, and their meals become one history?")
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("merge-offer")
            }
            if let error {
                Text(error).phoneFont(.body, 13, weight: 600, relativeTo: .footnote).foregroundStyle(Theme.accent)
            }
        } footer: {
            if let twin {
                HStack(spacing: 8) {
                    Button("Keep apart") { self.twin = nil; dismiss() }
                        .buttonStyle(PhoneButtonStyle(kind: .ghost))
                    Button("Merge") {
                        store.mergeDish(dish.id, into: twin.id)
                        dismiss()
                    }
                    .buttonStyle(PhoneButtonStyle())
                    .accessibilityIdentifier("merge")
                }
            } else {
                Button("Save", action: save)
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(DishName.key(name).isEmpty)
                    .accessibilityIdentifier("save-dish-name")
            }
        }
        .onAppear {
            name = dish.name
            focused = true
        }
    }

    private func save() {
        do {
            try store.renameDish(dish.id, to: name)
            dismiss()
        } catch let DishError.nameTaken(other) {
            twin = store.book.dish(other)
        } catch {
            self.error = error.userMessage
        }
    }
}

// MARK: - A restaurant's page

/// "What do we get here?": a restaurant's visits, last time's order, and everything we had
/// there, best face first, with the one to skip greyed.
struct PocketPlaceDetail: View {
    let placeId: FoodPlace.ID

    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let place = store.snapshot.places.first(where: { $0.id == placeId }) {
                content(place)
            } else {
                Text("This restaurant isn't in the diary any more.")
                    .phoneFont(.body, 15, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
    }

    private func content(_ place: FoodPlace) -> some View {
        let summary = store.book.summary(of: place.id)
        let today = store.today(CompanionClock.now())
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("place-title")
                    Text([place.address, summary.visits == 1 ? "1 visit" : "\(summary.visits) visits",
                          summary.last.map { DishWords.last($0, today: today, calendar: store.calendar) }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                if let last = summary.last, !summary.lastDishes.isEmpty {
                    lastTime(last, dishes: summary.lastDishes, today: today)
                }
                if summary.dishes.isEmpty {
                    Text("No dishes named here yet. Add them the next time you log a meal here.")
                        .phoneFont(.body, 14, weight: 600)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .phoneCard()
                } else {
                    ranked(summary.dishes)
                }
                if let url = directions(place) {
                    PhoneChoice(title: "🗺️ Directions", isOn: false) { openURL(url) }
                        .accessibilityIdentifier("place-directions")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(place.name)
        // The title names the back button of the next page; the page shows its own.
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
    }

    private func lastTime(_ meal: JournalEntry, dishes: [Dish], today: DayKey) -> some View {
        let faces = store.book.dishes(of: meal).map { line, dish in
            "\(dish.name)\((line.rating ?? store.book.faces(of: line, entry: meal).values.max { $0.rawValue < $1.rawValue }).map { " \($0.emoji)" } ?? "")"
        }
        return NavigationLink(value: PocketFoodRoute.meal(meal.id)) {
            HStack(alignment: .top, spacing: 10) {
                Text("🕘").font(.system(size: 18)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last time, \(DishWords.day(meal, today: today, calendar: store.calendar))")
                        .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                    Text(faces.joined(separator: " · "))
                        .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("place-last-time")
    }

    private func ranked(_ dishes: [Dish]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            PhoneCardHeader(title: "What we get here", meta: "best first")
            ForEach(Array(dishes.enumerated()), id: \.element.id) { index, dish in
                if index > 0 { RowDivider() }
                rankRow(dish)
            }
        }
        .phoneCard()
    }

    private func rankRow(_ dish: Dish) -> some View {
        let summary = store.book.summary(of: dish.id)
        let usual = store.book.usualFaces(of: dish.id)
        let everyone = Set(usual.map(\.face.rating)).count == 1 && usual.count == store.people.count && usual.count > 1
        let who = everyone
            ? "everyone \(usual[0].face.rating.emoji)"
            : usual.map { "\($0.person.id == me?.id ? "You" : $0.person.name) \($0.face.rating.emoji)" }.joined(separator: " ")
        let skip = summary.face == .meh
        return NavigationLink(value: PocketFoodRoute.dish(dish.id)) {
            HStack(spacing: 10) {
                DishArt(dish: dish, size: 34)
                    .opacity(skip ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dish.favorite ? "\(dish.name) ★" : dish.name)
                        .phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                        .foregroundStyle(skip ? Theme.muted : Theme.ink)
                    Text([DishWords.times(summary.count), who.isEmpty ? nil : who].compactMap { $0 }.joined(separator: " · "))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let face = summary.face {
                    Text(face.emoji).font(.system(size: 18))
                }
                Text("\(summary.count)")
                    .phoneFont(.body, 12, weight: 800, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 18, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("place-dish-\(dish.name)")
    }

    private func directions(_ place: FoodPlace) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "q", value: place.name)]
        if let latitude = place.latitude, let longitude = place.longitude {
            items.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
        } else if let address = place.address {
            items.append(URLQueryItem(name: "address", value: address))
        }
        components?.queryItems = items
        return components?.url
    }
}

// MARK: - A meal's dishes

/// "What we had" on a meal's page: each dish with its faces, opening the dish; "Rate each"
/// lets everyone who ate give their own face.
struct PocketMealDishes: View {
    let entry: JournalEntry

    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me
    @State private var rating = false

    var body: some View {
        let dishes = store.book.dishes(of: entry)
        if !dishes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What we had")
                        .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("Rate each") { rating = true }
                        .phoneFont(.body, 13, weight: 800, relativeTo: .footnote)
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("rate-each")
                }
                ForEach(Array(dishes.enumerated()), id: \.element.line.id) { index, item in
                    if index > 0 { RowDivider() }
                    row(item.line, item.dish)
                }
            }
            .phoneCard()
            .sheet(isPresented: $rating) { PocketRateEach(entry: entry) }
        }
    }

    private func row(_ line: MealDish, _ dish: Dish) -> some View {
        let faces = store.book.faces(of: line, entry: entry)
        let own = !store.book.ownFaces(of: line).isEmpty
        let detail = own
            ? DishWords.faces(faces, people: store.snapshot.everyone, me: me?.id)
            : DishWords.ordinal(store.book.ordinal(of: line), here: dish.kitchen.placeId != nil)
        let face = faces.values.max { $0.rawValue < $1.rawValue } ?? line.rating
        return NavigationLink(value: PocketFoodRoute.dish(dish.id)) {
            HStack(spacing: 10) {
                DishArt(dish: dish, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dish.name).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline).foregroundStyle(Theme.ink)
                    Text(detail).phoneFont(.body, 12, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let face { Text(face.emoji).font(.system(size: 18)).accessibilityLabel(face.phrase) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meal-dish-\(dish.name)")
    }
}

/// Everyone who ate gives their own face, dish by dish, starting from the table's.
struct PocketRateEach: View {
    let entry: JournalEntry

    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        let dishes = store.book.dishes(of: entry)
        let current = dishes.indices.contains(index) ? dishes[index] : nil
        PhoneSheet(label: current.map { "\($0.dish.name) · \(DishWords.kitchen($0.dish, places: store.snapshot.places))" }, title: "How was it for each of you?") {
            if let current {
                let faces = store.book.faces(of: current.line, entry: entry)
                Text(current.line.rating.map { "The table said \($0.emoji). Change anyone whose face was different." } ?? "Tap each person's face.")
                    .phoneFont(.body, 14, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(store.eaters(of: entry)) { person in
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { who(person); faceChoice(current.line, person: person, faces: faces) }
                        VStack(alignment: .leading, spacing: 6) { who(person); faceChoice(current.line, person: person, faces: faces) }
                    }
                }
            }
        } footer: {
            HStack(spacing: 8) {
                Button("Done") { dismiss() }
                    .buttonStyle(PhoneButtonStyle(kind: index + 1 < dishes.count ? .ghost : .primary))
                    .accessibilityIdentifier("rate-done")
                if index + 1 < dishes.count {
                    Button("Next: \(dishes[index + 1].dish.name) ›") { index += 1 }
                        .buttonStyle(PhoneButtonStyle())
                        .accessibilityIdentifier("rate-next")
                }
            }
        }
    }

    private func who(_ person: Person) -> some View {
        HStack(spacing: 8) {
            PersonAvatar(person, size: .regular)
            Text(person.id == me?.id ? "You" : person.name)
                .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                .frame(minWidth: 44, alignment: .leading)
        }
    }

    private func faceChoice(_ line: MealDish, person: Person, faces: [Person.ID: MealRating]) -> some View {
        FaceChoice(rating: faces[person.id], size: 36, font: 18) { chosen in
            // The table's face again means no face of their own.
            store.setPersonFace(line, person: person.id, chosen == line.rating ? nil : chosen)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(person.id == me?.id ? "You" : person.name)
        .accessibilityIdentifier("faces-\(person.name)")
    }
}
