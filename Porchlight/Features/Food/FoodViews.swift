import SwiftUI

/// The Food destination: week of polaroids, handwritten month, capture.
struct FoodScreen: View {
    @Environment(FoodStore.self) private var store

    enum Mode { case week, month }

    @State private var mode: Mode = .week
    /// Weeks or months away from the current one (0 = now, -1 = previous).
    @State private var offset = 0
    @State private var capture: CaptureRequest?
    @State private var writingDay: DayKey?
    @State private var openEntry: JournalEntry?
    @State private var debugSaved: JournalEntry?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = store.today(context.date)
            ZStack {
                VStack(alignment: .leading, spacing: 16) {
                    header(today: today)
                    content(today: today)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)

                overlays(today: today)
            }
        }
        .onAppear(perform: applyDebugLaunch)
    }

    // MARK: Header

    private func header(today: DayKey) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            Text("What we ate")
                .font(.display(40))
            Text(subtitle(today: today))
                .font(.body(15))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .layoutPriority(-1)
                .padding(.bottom, 6)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                PagerButton(symbol: "chevron.left", label: mode == .week ? "Previous week" : "Previous month") { offset -= 1 }
                if offset < 0 {
                    PagerButton(symbol: "chevron.right", label: mode == .week ? "Next week" : "Next month") { offset += 1 }
                }
                Spacer().frame(width: 6)
                FoodHeaderChip(title: "Week", isSelected: mode == .week) { select(.week) }
                FoodHeaderChip(title: "Month", isSelected: mode == .month) { select(.month) }
                Button {
                    capture = CaptureRequest(day: today)
                } label: {
                    Label("Snap a meal", systemImage: "camera")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.leading, 6)
            }
        }
        .frame(minHeight: 56, alignment: .bottom)
    }

    private func select(_ newMode: Mode) {
        if mode != newMode { offset = 0 }
        mode = newMode
    }

    private func subtitle(today: DayKey) -> String {
        switch mode {
        case .week:
            let days = weekDays(today: today)
            guard let first = days.first, let last = days.last else { return "" }
            let calendar = store.calendar
            let start = first.startDate(in: calendar)
            let end = last.startDate(in: calendar)
            let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
            let range = start.formatted(.dateTime.month(.abbreviated).day()) + " – "
                + (sameMonth ? "\(calendar.component(.day, from: end))" : end.formatted(.dateTime.month(.abbreviated).day()))
            let count = days.reduce(0) { $0 + store.entries(on: $1).count }
            return "\(range) · \(count == 1 ? "1 meal" : "\(count) meals") logged"
        case .month:
            let month = monthDate(today: today)
            let name = month.formatted(.dateTime.month(.wide))
            let sameYear = store.calendar.isDate(month, equalTo: today.startDate(in: store.calendar), toGranularity: .year)
            return (sameYear ? name : month.formatted(.dateTime.month(.wide).year())) + " · tap a day to write"
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(today: DayKey) -> some View {
        switch mode {
        case .week:
            FoodWeekView(
                days: weekDays(today: today),
                today: today,
                onSnap: { day, slot in capture = CaptureRequest(day: day, slot: slot) },
                onOpen: { openEntry = $0 }
            )
        case .month:
            FoodMonthView(month: monthDate(today: today), today: today) { writingDay = $0 }
                .overlay(alignment: .bottom) {
                    MonthToolBar { writingDay = today }
                        .padding(.bottom, 26)
                }
        }
    }

    /// Seven days ending today (or the same span `offset` weeks back), so the
    /// current week is always full and today sits on the right.
    private func weekDays(today: DayKey) -> [DayKey] {
        let end = today.adding(days: offset * 7, calendar: store.calendar)
        return (-6...0).map { end.adding(days: $0, calendar: store.calendar) }
    }

    private func monthDate(today: DayKey) -> Date {
        let start = today.startDate(in: store.calendar)
        return store.calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }

    // MARK: Overlays

    @ViewBuilder
    private func overlays(today: DayKey) -> some View {
        if let day = writingDay {
            WriteDaySheet(day: day, today: today) {
                withAnimation(.easeInOut(duration: 0.2)) { writingDay = nil }
            }
            .transition(.opacity)
            .zIndex(1)
        }
        if let request = capture {
            CaptureSheet(request: request, previewSaved: debugSaved) {
                withAnimation(.easeInOut(duration: 0.2)) { capture = nil }
            }
            .id(request.id)
            .transition(.opacity)
            .zIndex(2)
        }
        if let entry = openEntry {
            MealDetailSheet(entry: entry) {
                withAnimation(.easeInOut(duration: 0.2)) { openEntry = nil }
            }
            .zIndex(3)
        }
    }

    private func applyDebugLaunch() {
        #if DEBUG
        // e.g. `-debugFoodView month|write|capture|detail` for screenshots
        let today = store.today()
        switch UserDefaults.standard.string(forKey: "debugFoodView") {
        case "month": mode = .month
        case "write":
            mode = .month
            writingDay = today
        case "capture": capture = CaptureRequest(day: today)
        case "saved":
            debugSaved = store.entries(on: today).last
            capture = CaptureRequest(day: today)
        case "detail": openEntry = store.entries(on: today).first ?? store.snapshot.entries.last
        default: break
        }
        #endif
    }
}

/// "Today's plates" card: the day's main meals as polaroids, empty ones open the camera.
struct FoodTodayCard: View {
    @Environment(FoodStore.self) private var store
    @State private var capture: CaptureRequest?

    var body: some View {
        if store.isEnabled {
            TimelineView(.everyMinute) { context in
                let today = store.today(context.date)
                card(today: today)
            }
            .fullScreenCover(item: $capture) { request in
                CaptureSheet(request: request, doneTitle: "Done") { present(nil) }
                    .presentationBackground(.clear)
            }
        }
    }

    /// The capture sheet draws its own dimmed backdrop, so the cover appears without sliding.
    private func present(_ request: CaptureRequest?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { capture = request }
    }

    private func card(today: DayKey) -> some View {
        let streak = store.streak(today: today)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's plates").font(.display(19))
                Spacer()
                if streak > 1 {
                    Text("\(streak)-day diary streak")
                        .font(.body(13, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(store.mainSlots.enumerated()), id: \.element) { index, slot in
                    VStack(spacing: 8) {
                        plate(today: today, slot: slot, index: index)
                        Text(slot)
                            .font(.body(12, weight: 700))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .card(padding: 20)
    }

    @ViewBuilder
    private func plate(today: DayKey, slot: String, index: Int) -> some View {
        if let entry = store.entries(on: today, slot: slot).last {
            Polaroid(entry: entry, rotation: [-2, 1.5, -1][index % 3], emojiSize: 40, captionSize: 15, plate: 0.44)
        } else {
            Button { present(CaptureRequest(day: today, slot: slot)) } label: {
                EmptyPolaroid(label: "snap \(slot.lowercased())", showsPlate: false, captionSize: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Snap \(slot.lowercased())")
        }
    }
}

/// Food diary section inside Settings.
struct FoodSettingsSection: View {
    @Environment(FoodStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Food diary")
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep a food diary")
                            .font(.body(17, weight: 600))
                        Text("Snap meals, write on each day with Apple Pencil, and see your plates on Today.")
                            .font(.body(14))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.good)
                if store.isEnabled {
                    Divider().overlay(Theme.line).padding(.vertical, 14)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meals").font(.body(17, weight: 600))
                        HStack(spacing: 8) {
                            ForEach(MealSlot.known, id: \.name) { slot in
                                let isOn = store.slots.contains(slot.name)
                                FoodChoicePill("\(slot.emoji) \(slot.name)", isSelected: isOn) {
                                    store.setSlot(slot.name, on: !isOn)
                                }
                                .disabled(isOn && store.slots.count == 1)
                            }
                        }
                    }
                    Divider().overlay(Theme.line).padding(.vertical, 14)
                    Toggle(isOn: $store.allowsFingerDrawing) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow finger drawing")
                                .font(.body(17, weight: 600))
                            Text("Off: only Apple Pencil writes, so a resting hand never leaves marks on this iPad.")
                                .font(.body(14))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.good)
                }
            }
            .card(padding: 16)
            .frame(maxWidth: 720)
            if let error = store.lastError {
                Text(error)
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

/// Onboarding step: journals. Turning it on creates the food diary right away.
struct FoodOnboardingStep: View {
    @Environment(FoodStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingHeading(
                title: "A food diary, if you like",
                subtitle: "Snap what you eat, write on the day with Apple Pencil, and look back at a wall of polaroids. Totally optional."
            )
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep a food diary").font(.body(17, weight: 600))
                            Text("Breakfast, lunch and dinner. You can change the meals in Settings.")
                                .font(.body(14))
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.good)
                    .card(padding: 16)
                    tip("camera", "Snap a meal", "The iPad's camera takes the photo and guesses the meal from the time of day.")
                    tip("pencil.and.scribble", "Write on the day", "Every day has its own ruled page. Write what you ate, in your own pen color.")
                }
                .frame(maxWidth: 460)
                samplePolaroids
                    .padding(.top, 10)
            }
        }
        .onAppear {
            // Default on: the first visit creates the diary; turning it off later keeps it off.
            if store.journal == nil { store.setEnabled(true) }
        }
    }

    private var samplePolaroids: some View {
        ZStack {
            sample("🥞", "pancakes", tint: 0xF3D9A4).rotationEffect(.degrees(-6)).offset(x: -60, y: 10)
            sample("🍜", "dan dan noodles", tint: 0xF0D5B8).rotationEffect(.degrees(4)).offset(x: 50, y: -6)
        }
        .frame(width: 260, height: 220)
        .accessibilityHidden(true)
    }

    private func sample(_ emoji: String, _ caption: String, tint: UInt32) -> some View {
        VStack(spacing: 0) {
            PlateArt(emoji: emoji, tint: Color(hex: tint), plate: 0.5, emojiSize: 48)
                .frame(width: 118, height: 118)
            Text(caption)
                .font(.hand(18, weight: 700))
                .foregroundStyle(FoodStyle.caption)
                .frame(height: 28)
        }
        .padding([.top, .horizontal], 7)
        .background(FoodStyle.polaroidPaper, in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: FoodStyle.shadow.opacity(0.22), radius: 8, y: 6)
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.wash(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body(16, weight: 700))
                Text(detail).font(.body(14)).foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 16)
    }
}
