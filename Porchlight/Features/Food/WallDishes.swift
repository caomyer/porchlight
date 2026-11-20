import SwiftUI

// The wall's dishes (docs/design/dishes.md, journeys W2 and W3 of
// docs/proposals/dishes-and-recipes.html): the Dishes view beside Week and Month, a dish's
// sheet, a restaurant's sheet ("what do we get here?"), and everyone's own faces after
// dinner. Laid out for the kitchen screen, not the phone's stretched.

// MARK: - The Dishes view

struct WallDishesView: View {
    let onOpenDish: (Dish) -> Void
    let onOpenPlace: (FoodPlace) -> Void

    @Environment(FoodStore.self) private var store
    @State private var query = ""
    @State private var filter: PocketDishesView.Filter = .all

    var body: some View {
        let book = store.book
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                search
                ForEach(PocketDishesView.Filter.allCases, id: \.self) { choice in
                    FoodHeaderChip(title: choice.title, isSelected: filter == choice) { filter = choice }
                }
            }
            if book.mostHad.isEmpty {
                empty
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                                grids(book)
                            } else {
                                let found = book.search(query)
                                if found.dishes.isEmpty && found.places.isEmpty {
                                    Text("Nothing called \"\(query.trimmingCharacters(in: .whitespaces))\" yet.")
                                        .font(.body(16, weight: 600)).foregroundStyle(Theme.muted)
                                }
                                if !found.dishes.isEmpty { grid("Dishes", meta: "\(found.dishes.count)", dishes: found.dishes) }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    places(book)
                        .frame(width: 300)
                }
            }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Search dishes and places", text: $query)
                .font(.body(16, weight: 600))
                .autocorrectionDisabled()
                .accessibilityIdentifier("wall-dish-search")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).stroke(Theme.line))
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Text("🍽️").font(.system(size: 60)).accessibilityHidden(true)
            Text("Name what you eat, and Porchlight remembers it").font(.display(30))
            Text("Each dish you add when you snap a meal shows up here, with every time you had it and how everyone liked it.")
                .font(.body(17, weight: 500)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wall-dishes-empty")
    }

    @ViewBuilder
    private func grids(_ book: DishBook) -> some View {
        if filter == .all || filter == .favorites {
            let favorites = book.favorites
            if !favorites.isEmpty { grid("★ Favourites", meta: "\(favorites.count)", dishes: favorites) }
            else if filter == .favorites {
                Text("No favourites yet. Star a dish to keep it here.").font(.body(16, weight: 600)).foregroundStyle(Theme.muted)
            }
        }
        if filter == .all || filter == .home {
            let home = book.homeDishes
            if !home.isEmpty { grid("🏠 Home", meta: home.count == 1 ? "1 dish" : "\(home.count) dishes", dishes: home) }
        }
        if filter == .out {
            ForEach(book.placesWithDishes, id: \.place.id) { place, dishes in
                grid("📍 \(place.name)", meta: dishes.count == 1 ? "1 dish" : "\(dishes.count) dishes", dishes: dishes)
            }
        }
        if filter == .all || filter == .out {
            let elsewhere = book.elsewhereDishes
            if !elsewhere.isEmpty { grid("🏢 Elsewhere", meta: "\(elsewhere.count)", dishes: elsewhere) }
        }
    }

    private func grid(_ title: String, meta: String, dishes: [Dish]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.display(22)).accessibilityAddTraits(.isHeader)
                Text(meta).font(.body(13, weight: 700)).foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 170), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(dishes) { dish in card(dish) }
            }
        }
    }

    private func card(_ dish: Dish) -> some View {
        let summary = store.book.summary(of: dish.id)
        return Button { onOpenDish(dish) } label: {
            VStack(alignment: .leading, spacing: 8) {
                DishArt(dish: dish, size: 132, corner: 0.09)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dish.favorite ? "\(dish.name) ★" : dish.name)
                        .font(.display(16))
                        .lineLimit(2)
                        .foregroundStyle(Theme.ink)
                    Text([DishWords.kitchen(dish, places: store.snapshot.places), DishWords.times(summary.count)].joined(separator: " · "))
                        .font(.body(12, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                if let face = summary.face {
                    Text(face.emoji).font(.system(size: 18))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wall-dish-\(dish.name)")
    }

    /// "Ordering in?": our places, most visited first, each with the dish we like best.
    private func places(_ book: DishBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ordering in?").font(.display(20))
                Spacer()
                Text("by visits").font(.body(12, weight: 700)).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 4)
            let places = book.placesWithDishes
            if places.isEmpty {
                Text("Restaurants show up here once you name what you had there.")
                    .font(.body(14, weight: 600)).foregroundStyle(Theme.muted)
            }
            ForEach(Array(places.enumerated()), id: \.element.place.id) { index, item in
                if index > 0 { Divider().overlay(Theme.line) }
                let summary = book.summary(of: item.place.id)
                Button { onOpenPlace(item.place) } label: {
                    HStack(spacing: 10) {
                        Text("📍").font(.system(size: 20)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place.name).font(.body(15, weight: 700)).foregroundStyle(Theme.ink)
                            Text([summary.visits == 1 ? "1 visit" : "\(summary.visits) visits",
                                  item.dishes.first.map { "\($0.name)\(book.summary(of: $0.id).face.map { " \($0.emoji)" } ?? "")" }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("wall-place-\(item.place.name)")
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

// MARK: - A dish's sheet

struct WallDishSheet: View {
    let dishId: Dish.ID
    let onOpenPlace: (FoodPlace) -> Void
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var renaming: String?
    @State private var twin: Dish?
    @State private var confirmingRemove = false
    @State private var removal: DishRemoval?

    var body: some View {
        WallSheet(width: 760, staysAboveKeyboard: true, onClose: onClose) {
            if let dish = store.book.dish(dishId) {
                content(dish)
            } else if let removal {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(removal.dish.name) was removed").font(.display(28))
                    Text("It was taken off \(removal.lines.count == 1 ? "1 meal" : "\(removal.lines.count) meals"). The meals stay, with their photos.")
                        .font(.body(16, weight: 500)).foregroundStyle(Theme.muted)
                    HStack {
                        Button("Undo") { store.restore(removal); self.removal = nil }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("wall-undo-remove")
                        Spacer()
                        Button("Done", action: onClose).buttonStyle(PrimaryButtonStyle())
                    }
                }
            } else {
                Text("This dish was removed.").font(.body(17, weight: 600)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func content(_ dish: Dish) -> some View {
        let book = store.book
        let summary = book.summary(of: dish.id)
        let times = book.times(of: dish.id)
        let today = store.today()
        return HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                DishArt(dish: dish, size: 220, corner: 0.06)
                HStack(spacing: 8) {
                    stat("\(summary.count)", summary.count == 1 ? "time" : "times")
                    stat(summary.first.map { DishWords.day($0, today: today, calendar: store.calendar) } ?? "–", "first")
                    stat(summary.last.map { DishWords.day($0, today: today, calendar: store.calendar) } ?? "–", "last")
                }
                .frame(width: 220)
            }
            VStack(alignment: .leading, spacing: 14) {
                if let name = renaming {
                    rename(dish, name: name)
                } else {
                    Text(dish.name).font(.display(32)).accessibilityIdentifier("wall-dish-title")
                    kitchen(dish)
                }
                let usual = book.usualFaces(of: dish.id)
                if !usual.isEmpty {
                    SheetLabel(title: "How we like it", note: "· usual face")
                    HStack(spacing: 18) {
                        ForEach(usual, id: \.person.id) { person, face in
                            HStack(spacing: 8) {
                                Avatar(person: person, size: 30)
                                Text(face.rating.emoji).font(.system(size: 24))
                                Text("\(face.count) of \(face.of)").font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(person.name): \(face.rating.phrase)")
                        }
                    }
                }
                SheetLabel(title: "Every time", note: "· \(times.count)")
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(times) { time in
                            HStack(spacing: 12) {
                                Text(DishWords.day(time.entry, today: today, calendar: store.calendar))
                                    .font(.body(13, weight: 800)).foregroundStyle(Theme.muted)
                                    .frame(width: 78, alignment: .leading)
                                Text(time.entry.slot).font(.body(15, weight: 700))
                                Text(DishWords.faces(time.faces, people: store.snapshot.everyone, me: nil))
                                    .font(.body(13, weight: 600)).foregroundStyle(Theme.muted)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .frame(maxHeight: 190)
                if renaming == nil { actions(dish, count: summary.count) }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.display(18)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.body(11.5, weight: 600)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func kitchen(_ dish: Dish) -> some View {
        switch dish.kitchen {
        case let .place(id):
            if let place = store.snapshot.places.first(where: { $0.id == id }) {
                Button { onOpenPlace(place) } label: {
                    Text("📍 \(place.name)\(place.address.map { " · \($0)" } ?? "") ›")
                        .font(.body(15, weight: 700)).foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        case .home: Text("🏠 Home-cooked").font(.body(15, weight: 600)).foregroundStyle(Theme.muted)
        case .elsewhere: Text("🏢 Elsewhere").font(.body(15, weight: 600)).foregroundStyle(Theme.muted)
        }
    }

    private func actions(_ dish: Dish, count: Int) -> some View {
        HStack(spacing: 10) {
            Button { store.setFavorite(dish.id, !dish.favorite) } label: {
                Label(dish.favorite ? "Favourite" : "Favourite", systemImage: dish.favorite ? "star.fill" : "star")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("wall-dish-favorite")
            Button { renaming = dish.name } label: { Label("Rename", systemImage: "pencil") }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            if confirmingRemove {
                Button("Keep it") { confirmingRemove = false }.buttonStyle(SecondaryButtonStyle())
                Button(count == 0 ? "Remove dish" : "Take off \(count == 1 ? "1 meal" : "\(count) meals")") {
                    removal = store.removeDish(dish.id)
                    confirmingRemove = false
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button { confirmingRemove = true } label: { Label("Remove", systemImage: "trash") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func rename(_ dish: Dish, name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: Binding(get: { renaming ?? "" }, set: { renaming = $0; twin = nil }))
                .font(.display(28))
                .submitLabel(.done)
                .onSubmit { save(dish) }
                .accessibilityIdentifier("wall-dish-name")
            if let twin {
                Text("\(twin.name) is already a dish here, \(DishWords.times(store.book.summary(of: twin.id).count)). Merge them, and their meals become one history?")
                    .font(.body(14, weight: 600))
                    .padding(12)
                    .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 10) {
                Button("Cancel") { renaming = nil; twin = nil }.buttonStyle(SecondaryButtonStyle())
                if let twin {
                    Button("Keep apart") { renaming = nil; self.twin = nil }.buttonStyle(SecondaryButtonStyle())
                    Button("Merge") {
                        store.mergeDish(dish.id, into: twin.id)
                        renaming = nil
                        self.twin = nil
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Save") { save(dish) }.buttonStyle(PrimaryButtonStyle())
                }
            }
            if let error = store.lastError { Text(error).font(.body(13, weight: 600)).foregroundStyle(Theme.accent) }
        }
    }

    private func save(_ dish: Dish) {
        do {
            try store.renameDish(dish.id, to: renaming ?? dish.name)
            renaming = nil
        } catch let DishError.nameTaken(other) {
            twin = store.book.dish(other)
        } catch {
            store.lastError = error.userMessage
        }
    }
}

// MARK: - A restaurant's sheet

struct WallPlaceSheet: View {
    let placeId: FoodPlace.ID
    let onOpenDish: (Dish) -> Void
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        WallSheet(width: 760, onClose: onClose) {
            if let place = store.snapshot.places.first(where: { $0.id == placeId }) {
                content(place)
            }
        }
    }

    private func content(_ place: FoodPlace) -> some View {
        let book = store.book
        let summary = book.summary(of: place.id)
        let today = store.today()
        return HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text(([place.name] + [place.address].compactMap { $0 }).joined(separator: " · ").uppercased())
                    .font(.body(11, weight: 800)).tracking(1.1).foregroundStyle(Theme.muted)
                Text("What we get here").font(.display(30)).accessibilityIdentifier("wall-place-title")
                Text([summary.visits == 1 ? "1 visit" : "\(summary.visits) visits",
                      summary.last.map { DishWords.last($0, today: today, calendar: store.calendar) }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.body(14, weight: 600)).foregroundStyle(Theme.muted)
                VStack(spacing: 0) {
                    ForEach(summary.dishes) { dish in
                        let dishSummary = book.summary(of: dish.id)
                        Button { onOpenDish(dish) } label: {
                            HStack(spacing: 12) {
                                DishArt(dish: dish, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(dish.favorite ? "\(dish.name) ★" : dish.name).font(.body(16, weight: 700))
                                        .foregroundStyle(dishSummary.face == .meh ? Theme.muted : Theme.ink)
                                    Text(DishWords.times(dishSummary.count)).font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 4)
                                if let face = dishSummary.face { Text(face.emoji).font(.system(size: 22)) }
                                Text("\(dishSummary.count)").font(.body(13, weight: 800)).foregroundStyle(Theme.muted).frame(minWidth: 20, alignment: .trailing)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("wall-place-dish-\(dish.name)")
                        Divider().overlay(Theme.line)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                if let last = summary.last, !summary.lastDishes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last time, \(DishWords.day(last, today: today, calendar: store.calendar))").font(.display(20))
                        Text(PocketFood.eaters(store.eaters(of: last), everyone: store.ateTogether(last), householdSize: store.people.count, me: nil))
                            .font(.body(13, weight: 600)).foregroundStyle(Theme.muted)
                        Text(book.dishes(of: last).map { line, dish in
                            "\(dish.name)\((line.rating).map { " \($0.emoji)" } ?? "")"
                        }.joined(separator: " · "))
                        .font(.body(14, weight: 600))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Polaroid(entry: last, rotation: 2, emojiSize: 60, captionSize: 20, plate: 0.5, badgeSize: 24)
                        .frame(width: 190)
                        .frame(maxWidth: .infinity)
                }
                HStack {
                    Spacer()
                    Button("Close", action: onClose).buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(width: 260)
        }
    }
}

// MARK: - After dinner

/// Everyone who ate taps their own face, dish by dish, with big targets and no typing: the
/// wall's best job for faces.
struct WallRateEach: View {
    let entry: JournalEntry
    let onDone: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var index = 0

    var body: some View {
        let dishes = store.book.dishes(of: entry)
        VStack(alignment: .leading, spacing: 16) {
            if dishes.indices.contains(index) {
                let current = dishes[index]
                let faces = store.book.faces(of: current.line, entry: entry)
                Text("AFTER DINNER").font(.body(11, weight: 800)).tracking(1.1).foregroundStyle(Theme.muted)
                Text("How was the \(current.dish.name.lowercased())?").font(.display(30))
                    .accessibilityIdentifier("wall-rate-title")
                Text(current.line.rating.map { "Everyone who ate taps their own face. The table said \($0.emoji)." } ?? "Everyone who ate taps their own face.")
                    .font(.body(15, weight: 500)).foregroundStyle(Theme.muted)
                ForEach(store.eaters(of: entry)) { person in
                    HStack(spacing: 14) {
                        Avatar(person: person, size: 40)
                        Text(person.name).font(.body(18, weight: 700)).frame(width: 90, alignment: .leading)
                        FaceChoice(rating: faces[person.id], size: 54, font: 28) { chosen in
                            store.setPersonFace(current.line, person: person.id, chosen == current.line.rating ? nil : chosen)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("wall-faces-\(person.name)")
                    }
                }
                HStack {
                    Text("\(index + 1) of \(dishes.count) dishes").font(.body(13, weight: 600)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Done", action: onDone).buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("wall-rate-done")
                    if index + 1 < dishes.count {
                        Button("Next dish ›") { index += 1 }.buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("wall-rate-next")
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
