import SwiftUI

/// Where the Food tab goes from the diary.
enum PocketFoodRoute: Hashable {
    case meal(JournalEntry.ID)
    case dish(Dish.ID)
    case place(FoodPlace.ID)
}

/// The Food tab's two views: the diary, and the dishes it remembers.
enum PocketFoodView: String, CaseIterable {
    case diary = "Diary"
    case dishes = "Dishes"
}

/// The Food tab (`b5week`): the week's plates as the wall's grid at phone size, with empty
/// slots to fill; "On this day"; then the diary, day by day, with who ate each meal and who
/// added it. "Snap a meal" stays at the bottom. Lists only ever load thumbnails, through
/// `PhotoImages`; whole shots load only on a meal's own page.
struct PocketFoodScreen: View {
    @Environment(FoodStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.me) private var me
    @State private var path: [PocketFoodRoute] = []
    @State private var snap: CaptureRequest?
    @State private var addingPhoto: JournalEntry?
    /// The meal just saved, ringed in the grid for a moment (`b5saved`).
    @State private var fresh: JournalEntry.ID?
    @State private var view: PocketFoodView = .diary
    /// How many weeks before this one the diary shows: 0 is the seven days ending today.
    @State private var weeksBack: Int

    init(weeksBack: Int = 0) {
        _weeksBack = State(initialValue: weeksBack)
    }

    var body: some View {
        NavigationStack(path: $path) {
            diary
                .navigationTitle("Food")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PocketFoodRoute.self) { route in
                    Group {
                        switch route {
                        case let .meal(id): PocketMealDetail(entryId: id) { addingPhoto = $0 }
                        case let .dish(id): PocketDishDetail(dishId: id)
                        case let .place(id): PocketPlaceDetail(placeId: id)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { PocketYouButton() }
                    }
                    .toolbarBackground(Theme.background, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
                }
        }
        .tint(Theme.accent)
        .fullScreenCover(item: $snap, onDismiss: toasts.showPending) { request in
            PocketSnap(request: request, onSaved: saved)
        }
        .fullScreenCover(item: $addingPhoto) { entry in
            PocketCameraStep(
                small: entry.title,
                title: "Add a photo",
                caption: entry.title,
                remaining: AppDatabase.photoLimit - store.photos(of: entry).count,
                closeLabel: "Close",
                onImages: { images in
                    addingPhoto = nil
                    Task { await store.addPhotos(images, to: entry) }
                },
                onClose: { addingPhoto = nil }
            )
        }
        #if DEBUG
        .onAppear(perform: applyDebugLaunch)
        #endif
    }

    private var diary: some View {
        TimelineView(.everyMinute) { _ in
            let today = store.today(CompanionClock.now())
            let limit = PocketFood.weeksBackLimit(firstDay: store.snapshot.entries.lazy.map { DayKey(rawValue: $0.day) }.min(), today: today, calendar: store.calendar)
            let shown = min(weeksBack, limit)
            let days = PocketFood.week(endingOn: today, weeksBack: shown, calendar: store.calendar)
            let meals = days.reduce(0) { $0 + store.entries(on: $1).count }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PocketHeader(small: store.isEnabled ? headerLine(days: days, meals: meals) : "Food", title: "What we ate")
                    if store.isEnabled {
                        // No identifier on the whole: it would replace each segment's own.
                        PhoneSegments(choices: PocketFoodView.allCases, selection: $view, title: \.rawValue)
                        switch view {
                        case .diary:
                            PocketFoodWeek(
                                days: days, today: today, fresh: fresh,
                                pager: WeekPage(weeksBack: shown, limit: limit, meals: meals) { weeksBack = $0 },
                                onOpen: open
                            ) { day, slot in
                                snap = CaptureRequest(day: day, slot: slot)
                            }
                            // "On this day" is about today, so only this week has it.
                            if shown == 0 { PocketFoodMemory(today: today, onOpen: open) }
                            PocketFoodDays(days: days.reversed(), today: today, isThisWeek: shown == 0, onOpen: open)
                        case .dishes:
                            PocketDishesView()
                        }
                    } else {
                        off
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                if store.isEnabled { snapButton(today: today) }
            }
            // A new day starts on this week.
            .onChange(of: today) { weeksBack = 0 }
        }
        .background(Theme.background)
        .paperUnderStatusBar()
    }

    /// "Nov 10 to 16 · 20 meals" over the diary, "48 dishes · 11 places" over the dishes.
    private func headerLine(days: [DayKey], meals: Int) -> String {
        switch view {
        case .diary: return PocketFood.weekLine(days, meals: meals, calendar: store.calendar)
        case .dishes:
            let book = store.book
            let dishes = book.mostHad.count
            let places = book.placesWithDishes.count
            return "\(dishes == 1 ? "1 dish" : "\(dishes) dishes") · \(places == 1 ? "1 place" : "\(places) places")"
        }
    }

    /// The one thing to do here, always in reach.
    private func snapButton(today: DayKey) -> some View {
        Button { snap = CaptureRequest(day: today) } label: {
            Label("Snap a meal", systemImage: "camera.fill")
        }
        .buttonStyle(PhoneButtonStyle())
        .accessibilityIdentifier("snap-meal")
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0), .init(color: Theme.background, location: 0.35)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// The household hasn't turned the diary on; any member's phone can (rule 6).
    private var off: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The food diary is off")
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
            Text("Turn it on to snap meals here and see the week's plates on the wall.")
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on the food diary") { store.setEnabled(true) }
                .buttonStyle(PhoneButtonStyle())
                .accessibilityIdentifier("turn-on-food")
        }
        .phoneCard()
    }

    private func open(_ entry: JournalEntry) {
        path.append(.meal(entry.id))
    }

    /// Back on the diary: the toast says where it went, with a way to open it, and its
    /// slot is ringed in the grid for a moment.
    private func saved(_ entry: JournalEntry, eaterIds: Set<Person.ID>, place: PlaceDraft?) {
        let people = store.people.filter { eaterIds.contains($0.id) }
        let everyone = store.people.count > 1 && people.count == store.people.count
        let who = PocketFood.eaters(people, everyone: everyone, householdSize: store.people.count, me: me?.id)
        let words = PocketFood.savedToast(entry, placeName: place?.name, eaters: who, calendar: store.calendar)
        let id = entry.id
        toasts.showAfterSheet(UndoToast(
            emoji: entry.emoji ?? DishIllustration.fallbackEmoji,
            title: words.title,
            detail: words.detail,
            action: UndoToast.Action(title: "Open") { path.append(.meal(id)) }
        ))
        weeksBack = PocketFood.weeksBack(of: DayKey(rawValue: entry.day), today: store.today(CompanionClock.now()), calendar: store.calendar)
        withAnimation(.easeOut(duration: 0.2)) { fresh = id }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if fresh == id { withAnimation(.easeIn(duration: 0.4)) { fresh = nil } }
        }
    }

    #if DEBUG
    /// `-debugFoodView snap|details|detail` on a phone: opens the camera, the details of a
    /// new meal, or today's first meal (the one with photos in the sample household).
    private func applyDebugLaunch() {
        let today = store.today(CompanionClock.now())
        // `-debugFoodWeeksBack 2`: the diary opens on an earlier week.
        if let weeks = UserDefaults.standard.string(forKey: "debugFoodWeeksBack").flatMap(Int.init) { weeksBack = weeks }
        switch UserDefaults.standard.string(forKey: "debugFoodView") {
        case "snap", "details": snap = CaptureRequest(day: today)
        case "detail":
            if let entry = store.entries(on: today).first ?? store.snapshot.entries.last { path = [.meal(entry.id)] }
        case "dishes": view = .dishes
        case "dish":
            view = .dishes
            if let dish = store.book.liveDishes.first(where: { $0.name == "Pho tai" }) ?? store.book.mostHad.first { path = [.dish(dish.id)] }
        case "place":
            view = .dishes
            if let place = store.snapshot.places.first(where: { $0.name == "Pho Saigon House" }) { path = [.place(place.id)] }
        default: break
        }
    }
    #endif
}

// MARK: - The week

/// The wall's week of plates at phone size: a column per day, a row per meal. A logged
/// meal is its cover's thumbnail; an empty one up to today is a dashed square to snap.
private struct PocketFoodWeek: View {
    let days: [DayKey]
    let today: DayKey
    let fresh: JournalEntry.ID?
    let pager: WeekPage
    let onOpen: (JournalEntry) -> Void
    let onSnap: (DayKey, String) -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            WeekPager(page: pager, days: days)
            grid
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Meals \(PocketFood.range(days, calendar: store.calendar))")
        }
        .phoneCard()
    }

    private var grid: some View {
        let calendar = store.calendar
        return Grid(horizontalSpacing: 5, verticalSpacing: 6) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(days, id: \.self) { day in
                    Text(initial(day, calendar: calendar))
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                        .foregroundStyle(day == today ? Theme.accent : Theme.muted)
                        .accessibilityHidden(true)
                }
            }
            ForEach(store.slots, id: \.self) { slot in
                GridRow {
                    Text(PocketFood.shortSlot(slot))
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .gridColumnAlignment(.leading)
                        .accessibilityHidden(true)
                    ForEach(days, id: \.self) { day in
                        cell(day: day, slot: slot)
                    }
                }
            }
        }
        // A picture of the week, not its words: every meal in it is also a row in the
        // diary below, at full size. Grown further, the labels would squeeze the plates.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// "M", "T": the weekday's first letter.
    private func initial(_ day: DayKey, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))
        return calendar.veryShortStandaloneWeekdaySymbols[weekday - 1]
    }

    @ViewBuilder
    private func cell(day: DayKey, slot: String) -> some View {
        let entries = store.entries(on: day, slot: slot)
        let name = PocketFood.mealName(day: day, slot: slot, calendar: store.calendar)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if let first = entries.first {
            Button { onOpen(first) } label: {
                MealIllustration(entry: first, plate: 0.62, emojiSize: 15)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(alignment: .bottomTrailing) {
                        if entries.count > 1 {
                            Text("+\(entries.count - 1)")
                                .font(.body(9, weight: 800))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .background(Color.black.opacity(0.55), in: Capsule())
                                .padding(2)
                        }
                    }
                    .overlay {
                        if entries.contains(where: { $0.id == fresh }) {
                            shape.strokeBorder(Theme.accent, lineWidth: 3)
                        }
                    }
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name): " + ListFormat.join(entries.map(\.title)))
            .accessibilityIdentifier("plate-\(day.rawValue)-\(slot)")
        } else if day <= today {
            Button { onSnap(day, slot) } label: {
                shape
                    .strokeBorder(Theme.muted.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .aspectRatio(1, contentMode: .fit)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), not logged")
            .accessibilityHint("Snap it")
            .accessibilityIdentifier("plate-\(day.rawValue)-\(slot)")
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }
}

// MARK: - Other weeks

/// Which week the diary shows, and how to show another.
struct WeekPage {
    let weeksBack: Int
    /// The furthest back it goes: the week of the household's first meal.
    let limit: Int
    let meals: Int
    let go: (Int) -> Void
}

/// The week's card's top row: "‹ Last week ›", with "Back to this week" when away from it.
/// Back stops at the first meal's week; forward isn't there on this week, which ends today.
private struct WeekPager: View {
    let page: WeekPage
    let days: [DayKey]

    @Environment(FoodStore.self) private var store
    @PhoneMetric(upTo: 1.4) private var chevron: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            arrow("chevron.left", label: "Previous week", id: "week-back", shown: page.weeksBack < page.limit) {
                page.go(page.weeksBack + 1)
            }
            VStack(spacing: 2) {
                Text(PocketFood.weekName(weeksBack: page.weeksBack))
                    .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(PocketFood.weekSpoken(days, weeksBack: page.weeksBack, meals: page.meals, calendar: store.calendar))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("week-name")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: if page.weeksBack > 0 { page.go(page.weeksBack - 1) }
                        case .decrement: if page.weeksBack < page.limit { page.go(page.weeksBack + 1) }
                        @unknown default: break
                        }
                    }
                // Always laid out, so the week below doesn't move when stepping away from
                // this week; on this week it is invisible and out of reach.
                let away = page.weeksBack > 0
                Button("Back to this week") { page.go(0) }
                    .phoneFont(.body, 12.5, weight: 800, relativeTo: .footnote)
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                    .opacity(away ? 1 : 0)
                    .disabled(!away)
                    .accessibilityHidden(!away)
                    .accessibilityIdentifier("week-this")
            }
            .frame(maxWidth: .infinity)
            // Grown to the largest sizes, the words would crowd out the week they name.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            arrow("chevron.right", label: "Next week", id: "week-forward", shown: page.weeksBack > 0) {
                page.go(page.weeksBack - 1)
            }
        }
    }

    /// A round chevron, or the room for one so the name stays centered.
    @ViewBuilder
    private func arrow(_ symbol: String, label: String, id: String, shown: Bool, action: @escaping () -> Void) -> some View {
        if shown {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: chevron * 0.42, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: chevron, height: chevron)
                    .background(Theme.surface2, in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
        } else {
            Color.clear.frame(width: max(chevron, 44), height: 1).accessibilityHidden(true)
        }
    }
}

// MARK: - On this day

/// A meal from this date a year (or some months) ago, as on the wall.
private struct PocketFoodMemory: View {
    let today: DayKey
    let onOpen: (JournalEntry) -> Void

    @Environment(FoodStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var hand: CGFloat = 19
    @PhoneMetric(upTo: 1.3) private var width: CGFloat = 84

    var body: some View {
        if let memory = store.memory(today: today) {
            Button { onOpen(memory.entry) } label: {
                Group {
                    if typeSize.isAccessibilitySize {
                        // Stacked: the title, the keepsake centered, then the sentence.
                        VStack(alignment: .leading, spacing: 10) {
                            title
                            polaroid(memory)
                                .frame(maxWidth: .infinity)
                            sentence(memory)
                        }
                    } else {
                        HStack(spacing: 14) {
                            polaroid(memory)
                            VStack(alignment: .leading, spacing: 3) {
                                title
                                sentence(memory)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .phoneCard()
            .accessibilityIdentifier("on-this-day")
        }
    }

    private var title: some View {
        Text("On this day")
            .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
    }

    private func polaroid(_ memory: FoodMemory) -> some View {
        Polaroid(entry: memory.entry, rotation: -3, emojiSize: 30, captionSize: 13, plate: 0.46, badgeSize: 18, showsPhotoCount: false)
            .frame(width: width)
            .padding(.vertical, 4)
    }

    private func sentence(_ memory: FoodMemory) -> some View {
        Text(FoodMemoryWords.sentence(memory, store: store, handSize: hand))
            .phoneFont(.body, 13.5, weight: 600, relativeTo: .footnote)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The diary

/// The week's meals day by day, newest first: each with its cover, its name in the
/// diary's hand, where it came from, who ate it and who added it.
private struct PocketFoodDays: View {
    let days: [DayKey]
    let today: DayKey
    let isThisWeek: Bool
    let onOpen: (JournalEntry) -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        let logged = days.filter { !store.entries(on: $0).isEmpty }
        if logged.isEmpty, isThisWeek {
            Text("Nothing in the diary this week. Snap your next meal, and it shows up here and on the wall.")
                .phoneFont(.body, 14, weight: 600)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .phoneCard()
        } else if logged.isEmpty {
            // A past week with nothing in it: an invitation to fill a slot in.
            let words = PocketFood.emptyWeek(days.reversed(), calendar: store.calendar)
            VStack(spacing: 6) {
                Text(words.title)
                    .phoneFont(.display, 18, weight: 600, relativeTo: .headline)
                    .foregroundStyle(Theme.ink)
                Text(words.detail)
                    .phoneFont(.body, 13.5, weight: 600)
                    .foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .phoneCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("week-empty")
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(logged, id: \.self) { day in
                    PocketFoodDay(day: day, today: today, onOpen: onOpen)
                }
            }
        }
    }
}

private struct PocketFoodDay: View {
    let day: DayKey
    let today: DayKey
    let onOpen: (JournalEntry) -> Void

    @Environment(AppModel.self) private var model
    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me
    @PhoneMetric(upTo: 1.3) private var thumb: CGFloat = 56

    var body: some View {
        let calendar = store.calendar
        let entries = store.entries(on: day)
        VStack(alignment: .leading, spacing: 4) {
            PhoneCardHeader(
                title: PocketFood.dayTitle(day, today: today, calendar: calendar),
                meta: day.startDate(in: calendar).formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
            )
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { RowDivider() }
                row(entry)
            }
        }
        .phoneCard()
    }

    private func row(_ entry: JournalEntry) -> some View {
        let who = PocketFood.eaters(store.eaters(of: entry), everyone: store.ateTogether(entry), householdSize: store.people.count, me: me?.id)
        let added = PocketFood.addedBy(entry.deviceId, devices: model.devices, everyone: model.everyone, me: me?.id)
        let photoCount = store.photos(of: entry).count
        return Button { onOpen(entry) } label: {
            HStack(spacing: 12) {
                MealThumbnail(entry: entry, size: thumb)
                    .overlay(alignment: .bottomTrailing) {
                        if photoCount > 1 { PhotoCountChip(count: photoCount, size: 8.5).padding(3) }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(handwritten: entry.title)
                        .phoneFont(.hand, 23, weight: 700, relativeTo: .title3)
                        .lineLimit(2)
                    Text(PocketFood.mealLine(entry, place: store.place(of: entry)))
                        .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    Text([who, added].compactMap { $0 }.joined(separator: " · "))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let rating = entry.rating {
                    Text(rating.emoji)
                        .phoneFont(.body, 18)
                        .accessibilityLabel(rating.phrase)
                }
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meal-\(entry.title)")
    }
}
