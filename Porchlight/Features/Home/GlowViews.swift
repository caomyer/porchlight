import SwiftUI

/// "Glow": what everyone gives the household, and what it adds up to. Every star earned
/// in the week (a chore done, a walk, a feed) is a spark around the porch light; below,
/// each person's week and what they did, the rewards being saved toward and already
/// enjoyed, and what happened lately. The week steps back as far as the first star, and a
/// person's card opens to their own week. The same reading as the phone's (`GlowStory`).
struct GlowScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @State private var editing: RewardSheet?
    /// How many weeks before this one the page shows.
    @State private var weeksBack = 0

    enum RewardSheet: Identifiable {
        case new
        case edit(Reward)
        case person(Person.ID)
        var id: String {
            switch self {
            case .new: "new"
            case let .edit(reward): "edit-\(reward.id)"
            case let .person(id): "person-\(id)"
            }
        }
    }

    var body: some View {
        let calendar = store.calendar
        let limit = GlowWeeks.limit(firstDay: store.snapshot.firstStarDay, today: store.today, calendar: calendar)
        let shown = min(max(weeksBack, 0), limit)
        let week = GlowWeeks.week(weeksBack: shown, today: store.today, calendar: calendar)
        let isThisWeek = shown == 0
        let summary = GlowSummary(
            people: model.people,
            earnings: store.snapshot.earnings,
            redemptions: store.snapshot.redemptions,
            rewards: store.snapshot.rewards,
            lifetime: store.snapshot.lifetimeStars,
            week: week,
            today: GlowWeeks.readThrough(week, today: store.today),
            calendar: calendar,
            feedWithinWeek: !isThisWeek
        )
        VStack(alignment: .leading, spacing: 16) {
            HomeHeader(title: "Glow", subtitle: "everyone's stars, " + WeekPaging.range(week.days, calendar: calendar)) {
                if limit > 0 {
                    WallWeekSteps(weeksBack: shown, limit: limit, spoken: "\(WeekPaging.weekName(weeksBack: shown)), \(WeekPaging.range(week.days, calendar: calendar))", go: go)
                        .padding(.trailing, 8)
                }
                HeaderChip(title: "New reward", symbol: "plus") { present(.new) }
            }
            HStack(alignment: .top, spacing: 16) {
                // The people's cards are as tall as what they say, all one height, and the
                // porch takes the rest of the column: no card is stretched over an empty band.
                GeometryReader { proxy in
                    VStack(spacing: 16) {
                        PorchLightHero(summary: summary, isThisWeek: isThisWeek)
                            .frame(minHeight: PersonGlowCard.porchAtLeast, maxHeight: .infinity)
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(summary.people) { glow in
                                PersonGlowCard(
                                    glow: glow, days: week.days, today: store.today, isThisWeek: isThisWeek,
                                    tasks: GlowStory.tasks(store.snapshot.earnings, in: week, people: model.people, person: glow.id),
                                    rows: PersonGlowCard.rows(inColumn: proxy.size.height)
                                ) { present(.person(glow.id)) }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    RewardsCard(week: isThisWeek ? nil : week, onNew: { present(.new) }, onEdit: { present(.edit($0)) })
                    LatelyCard(title: isThisWeek ? "Lately" : "That week", feed: summary.feed)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 340)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        // A new day starts on this week again.
        .onChange(of: store.today) { weeksBack = 0 }
        .wallSheet(item: $editing, width: 640) { sheet in
            switch sheet {
            case .new: RewardEditor(reward: nil)
            case let .edit(reward): RewardEditor(reward: reward)
            case let .person(id): GlowPersonSheet(personId: id, weeksBack: shown)
            }
        }
    }

    /// Steps to another week. Stars from before the usual window are read as a week is
    /// asked for, with the week before it for its trend.
    private func go(_ asked: Int) {
        let calendar = store.calendar
        store.include(from: GlowWeeks.loadFrom(GlowWeeks.week(weeksBack: asked, today: store.today, calendar: calendar), calendar: calendar))
        weeksBack = asked
    }

    private func present(_ sheet: RewardSheet) {
        withoutAnimation { editing = sheet }
    }
}

// MARK: - Porch light

/// An evening porch with its lantern: one spark for every star earned this week, in the
/// color of whoever earned it. The more the family pitches in, the brighter it glows.
private struct PorchLightHero: View {
    @Environment(AppModel.self) private var model
    let summary: GlowSummary
    var isThisWeek = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let lantern = CGPoint(x: size.width * 0.74, y: size.height * 0.5)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0x2B2440), Color(hex: 0x4A3352)], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [Color(hex: 0xFFD27A).opacity(0.55 * glow), Color(hex: 0xFF9F5A).opacity(0.18 * glow), .clear],
                    center: UnitPoint(x: lantern.x / size.width, y: lantern.y / size.height),
                    startRadius: 4,
                    endRadius: 60 + 150 * glow
                )
                Sparks(sparks: summary.sparks, center: lantern, maxRadius: Self.sparkRadius(in: size)) { personId in
                    personId.map { model.color(for: .person($0)) } ?? Theme.everyone
                }
                Lantern(glow: glow)
                    .frame(width: 54, height: 92)
                    .position(x: lantern.x, y: lantern.y - 6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(.display(30))
                        .foregroundStyle(Color(hex: 0xFFF3DC))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.body(15, weight: 600))
                        .foregroundStyle(Color(hex: 0xFFF3DC).opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: size.width * 0.5, alignment: .leading)
                .padding(26)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: Color(hex: 0x2B2440).opacity(0.25), radius: 14, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline + ". " + detail)
    }

    /// How far the sparks spread from the lantern: as far as the porch is tall, and never
    /// into the words, which have the left half (the spiral is a quarter wider than tall).
    static func sparkRadius(in size: CGSize) -> CGFloat {
        min(size.width * 0.18, size.height * 0.62)
    }

    /// 0...1: how brightly the porch glows, against last week by this day (or a gentle 10 to start).
    private var glow: Double {
        let goal = Double(max(summary.lastWeekSoFar, 10))
        return summary.weekStars == 0 ? 0.08 : min(0.25 + 0.75 * Double(summary.weekStars) / goal, 1)
    }

    private var headline: String {
        let when = isThisWeek ? "this week" : "that week"
        return summary.weekStars == 0
            ? (isThisWeek ? "The porch light is waiting" : "The porch stayed dark that week")
            : "\(StarWords.count(summary.weekStars)) lit the porch \(when)"
    }

    private var detail: String {
        if summary.weekStars == 0 {
            return isThisWeek ? "Check off a chore or look after a companion, and it starts to glow." : "Nobody earned a star."
        }
        let trend = GlowWords.trend(stars: summary.weekStars, before: summary.lastWeekSoFar, isThisWeek: isThisWeek).map { $0 + "." } ?? ""
        let helpers = summary.people.filter { $0.weekStars > 0 }.map(\.person.name)
        let thanks = helpers.isEmpty ? "" : " Thanks to " + ListFormat.join(helpers) + "."
        return trend + thanks
    }
}

/// A warm hanging lantern.
private struct Lantern: View {
    let glow: Double

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: 0x1C1726)).frame(width: 3, height: 14)
            Capsule().fill(Color(hex: 0x1C1726)).frame(width: 34, height: 9)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFF1C2), Color(hex: 0xFFC56B)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(hex: 0x1C1726), lineWidth: 3)
                }
                .overlay { Rectangle().fill(Color(hex: 0x1C1726)).frame(width: 2.5) }
                .frame(width: 40, height: 52)
                .shadow(color: Color(hex: 0xFFD27A).opacity(0.4 + 0.6 * glow), radius: 10 + 14 * glow)
            Capsule().fill(Color(hex: 0x1C1726)).frame(width: 26, height: 8)
        }
    }
}

/// One spark per earning, spiralling out from the lantern; bigger for bigger jobs.
private struct Sparks: View {
    let sparks: [StarEarning]
    let center: CGPoint
    let maxRadius: CGFloat
    let color: (Person.ID?) -> Color

    @State private var twinkles = 0

    /// Twinkles twice on appear, then once a minute, so the screen can rest in between.
    var body: some View {
        let shown = Array(sparks.suffix(90))
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, spark in
                SparkShape()
                    .fill(color(spark.personId))
                    .frame(width: size(spark), height: size(spark))
                    .shadow(color: color(spark.personId).opacity(0.8), radius: 4)
                    .position(position(index, of: shown.count))
                    .phaseAnimator(index % 3 == 0 ? Restful.twice : [false], trigger: twinkles) { spark, dim in
                        spark.opacity(dim ? 0.55 : 1)
                    } animation: { _ in .easeInOut(duration: 1.6) }
            }
        }
        .task { await Restful.everyMinute { twinkles += 1 } }
    }

    private func size(_ spark: StarEarning) -> CGFloat {
        CGFloat(7 + min(spark.stars, 4) * 2)
    }

    /// A golden-angle spiral: evenly spread at any count, oldest closest to the light.
    private func position(_ index: Int, of count: Int) -> CGPoint {
        let angle = Double(index) * 2.399963
        let fraction = sqrt((Double(index) + 0.5) / Double(max(count, 12)))
        let radius = 42 + (maxRadius - 42) * CGFloat(fraction)
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)) * 1.25, y: center.y + radius * CGFloat(sin(angle)))
    }
}

/// A four-pointed sparkle.
struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.32
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : inner
            let point = CGPoint(x: c.x + radius * CGFloat(cos(angle)), y: c.y + radius * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - People

/// One person's week: their stars, their days, what they did in words and by task, and how
/// it sits beside their own last week. It opens to their own page.
struct PersonGlowCard: View {
    let glow: GlowSummary.PersonGlow
    let days: [DayKey]
    let today: DayKey
    var isThisWeek = true
    /// What they did that week, most stars first.
    var tasks: [GlowTask] = []
    /// How many of them the card lists before "and 3 more".
    var rows = PersonGlowCard.mostRows
    let onOpen: () -> Void

    /// The porch above the cards never gets less than this.
    static let porchAtLeast: CGFloat = 236
    static let mostRows = 6
    static let rowHeight: CGFloat = 36
    /// A card's height without its task rows: its padding, name, days, summary, "and more"
    /// and footer.
    static let heightWithoutRows: CGFloat = 310

    /// How many task rows fit when the column is `height` tall and the porch keeps its
    /// least: six on a 13-inch wall, four on a 10.5-inch one, never fewer than two.
    static func rows(inColumn height: CGFloat) -> Int {
        let room = height - porchAtLeast - 16 - heightWithoutRows
        return min(max(Int(room / rowHeight), 2), mostRows)
    }

    @Environment(HomeStore.self) private var store

    var body: some View {
        Button(action: onOpen) { card }
            .buttonStyle(PressableStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(glow.person.name.possessive) week")
            .accessibilityIdentifier("glow-person-\(glow.person.name)")
    }

    private var card: some View {
        let color = glow.person.color.color
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(person: glow.person, size: 44)
                Text(glow.person.name)
                    .font(.display(21))
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Text("\(glow.weekStars)")
                        .font(.display(28))
                        .monospacedDigit()
                    StarIcon(size: 22)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(StarWords.count(glow.weekStars)) \(isThisWeek ? "this week" : "that week")")
            }
            DayBars(values: glow.byDay, days: days, today: today, color: color, calendar: store.calendar)
                .frame(height: 104)
            Text(GlowWords.didLine(glow, isThisWeek: isThisWeek))
                .font(.body(14, weight: 600))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            // What they did, a row a task, as many as the wall has room for.
            if !tasks.isEmpty { taskRows(rows) }
            // Only the difference between two people's cards, which share one height.
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(footer)
                    .font(.body(12.5, weight: 700))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurfaceShape(cornerRadius: Theme.radius))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    /// The first `count` tasks as rows, then how many more there are.
    private func taskRows(_ count: Int) -> some View {
        let shown = Array(tasks.prefix(count))
        let more = tasks.count - shown.count
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, task in
                if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                HStack(spacing: 8) {
                    Text(task.emoji).font(.system(size: 16)).frame(width: 24)
                    Text(task.title)
                        .font(.body(14.5, weight: 700))
                        .lineLimit(1)
                    if task.times > 1 {
                        Text("×\(task.times)")
                            .font(.body(13, weight: 700))
                            .foregroundStyle(Theme.muted)
                            .fixedSize()
                    }
                    Spacer(minLength: 4)
                    Text("+\(task.stars)")
                        .font(.body(13.5, weight: 800))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                        .fixedSize()
                        .accessibilityLabel(StarWords.count(task.stars))
                }
                .frame(height: Self.rowHeight)
            }
            if more > 0 {
                Text("and \(more) more")
                    .font(.body(12.5, weight: 700))
                    .foregroundStyle(Theme.muted)
                    .frame(height: 26)
            }
        }
        .accessibilityIdentifier("glow-tasks-\(glow.person.name)")
    }

    /// "Up 3 on last week · 41 stars all time": their own trend, then all time.
    private var footer: String {
        let allTime = "\(StarWords.count(glow.lifetimeStars)) all time"
        guard let trend = glow.trend(isThisWeek: isThisWeek) else { return allTime }
        return trend + " · " + allTime
    }
}

/// Stars per day as soft bars, today's day letter in the accent color.
struct DayBars: View {
    let values: [Int]
    let days: [DayKey]
    let today: DayKey
    let color: Color
    let calendar: Calendar

    var body: some View {
        let top = max(values.max() ?? 0, 4)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(zip(days, values)), id: \.0) { day, value in
                VStack(spacing: 5) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day > today ? Theme.surface2 : color.opacity(value == 0 ? 0.15 : 0.85))
                                .frame(height: max(4, proxy.size.height * CGFloat(value) / CGFloat(top)))
                        }
                    }
                    Text(day.formatted(.dateTime.weekday(.narrow), calendar: calendar))
                        .font(.body(10.5, weight: 800))
                        .foregroundStyle(day == today ? Theme.accent : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stars by day")
    }
}

// MARK: - Rewards

private struct RewardsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    /// The earlier week the page is on, when it is: what was cashed in is that week's then.
    var week: HomeWeek?
    let onNew: () -> Void
    let onEdit: (Reward) -> Void

    var body: some View {
        let rewards = store.snapshot.rewards
            .filter { !$0.archived }
            .sorted { ($0.ownerId == nil ? 0 : 1, $0.sortOrder) < ($1.ownerId == nil ? 0 : 1, $1.sortOrder) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saving up for").font(.display(19))
                Spacer(minLength: 4)
                if week != nil {
                    Text("now").font(.body(12.5, weight: 700)).foregroundStyle(Theme.muted)
                }
            }
            if rewards.isEmpty {
                // Nothing to save for yet: three to start with in one tap, or your own.
                Text("Pick a treat to earn stars toward. You can change it any time.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 8) {
                    ForEach(RewardIdeas.all, id: \.title) { idea in
                        Button { store.saveReward(idea) } label: {
                            ideaChip("\(idea.emoji ?? "🎁") \(idea.title) · \(idea.targetStars)")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Save for \(idea.title), \(StarWords.count(idea.targetStars))")
                        .accessibilityIdentifier("reward-idea-\(idea.title)")
                    }
                    Button(action: onNew) { ideaChip("+ Your own") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Your own reward")
                }
            }
            ForEach(rewards) { reward in
                HStack(alignment: .center, spacing: 10) {
                    OwnerAvatar(owner: reward.owner, size: 30)
                    RewardCard(
                        status: ChoreBoard.RewardStatus(reward: reward, earned: store.earned(toward: reward)),
                        showsPace: true,
                        onEdit: { onEdit(reward) }
                    )
                }
            }
            cashedIn
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }
}

extension RewardsCard {
    fileprivate func ideaChip(_ text: String) -> some View {
        Text(text)
            .font(.body(14, weight: 700))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Theme.surface2, in: Capsule())
            .contentShape(Capsule())
    }

    /// The rewards already enjoyed: the last few, or an earlier week's own.
    @ViewBuilder
    fileprivate var cashedIn: some View {
        let all = GlowStory.cashedIn(store.snapshot.redemptions, rewards: store.snapshot.rewards, in: week)
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(week == nil ? "CASHED IN" : "CASHED IN THAT WEEK")
                    .font(.body(11, weight: 800))
                    .kerning(1)
                    .foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                ForEach(all.prefix(week == nil ? 2 : 4)) { item in
                    let who = item.personId.flatMap(model.person)?.name ?? "everyone"
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.emoji).font(.system(size: 14)).frame(width: 20)
                        Text(item.title).font(.body(14, weight: 700)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(GlowWords.day(item.day, today: store.today, calendar: store.calendar)) · \(who)")
                            .font(.body(12.5, weight: 600))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 2)
            .accessibilityIdentifier("glow-cashed-in")
        }
    }
}

// MARK: - Lately

private struct LatelyCard: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    var title = "Lately"
    let feed: [GlowSummary.FeedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.display(19))
            if feed.isEmpty {
                Text(title == "Lately" ? "Stars show up here as soon as someone pitches in." : "Nothing happened that week.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(feed) { item in row(item) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }

    private func row(_ item: GlowSummary.FeedItem) -> some View {
                HStack(spacing: 10) {
                    Text(item.emoji)
                        .font(.system(size: 16))
                        .frame(width: 34, height: 34)
                        .background(tint(item).wash(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.text)
                            .font(.body(14, weight: 700))
                            .lineLimit(1)
                        Text(byline(item))
                            .font(.body(12, weight: 600))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let stars = item.stars {
                        StarsTag(stars: stars)
                    } else {
                        Text("🎉").font(.system(size: 16))
                    }
                }
                .accessibilityElement(children: .combine)
    }

    private func tint(_ item: GlowSummary.FeedItem) -> Color {
        item.personId.map { model.color(for: .person($0)) } ?? Theme.everyone
    }

    private func byline(_ item: GlowSummary.FeedItem) -> String {
        let who = item.personId.flatMap(model.person)?.name ?? (item.isCashIn ? "Everyone" : "Someone")
        let calendar = store.calendar
        let day = item.day
        let when: String
        if day == store.today, DayKey(item.at, calendar: calendar) == day {
            when = item.at.formatted(date: .omitted, time: .shortened)
        } else if day == store.today {
            when = "today"
        } else if day == store.today.adding(days: -1, calendar: calendar) {
            when = "yesterday"
        } else {
            when = day.formatted(.dateTime.weekday(.wide), calendar: calendar)
        }
        return "\(who) · \(when)"
    }
}

// MARK: - Week steps

/// "‹ Last week ›" in a wall page's header: Food's steps, as a companion's page has them.
/// Back stops at the first week there is; forward isn't there on this week.
struct WallWeekSteps: View {
    let weeksBack: Int
    let limit: Int
    /// What VoiceOver reads for the week: "Last week, Nov 8 to 14".
    let spoken: String
    let go: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if weeksBack < limit {
                PagerButton(symbol: "chevron.left", label: "Previous week") { go(weeksBack + 1) }
                    .accessibilityIdentifier("week-back")
            }
            Text(WeekPaging.weekName(weeksBack: weeksBack))
                .font(.body(14, weight: 700))
                .foregroundStyle(weeksBack == 0 ? Theme.muted : Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(spoken)
                .accessibilityIdentifier("week-name")
            if weeksBack > 0 {
                PagerButton(symbol: "chevron.right", label: "Next week") { go(weeksBack - 1) }
                    .accessibilityIdentifier("week-forward")
            }
        }
    }
}

// MARK: - One person

/// One person's Glow on the wall, opened from their card: the week beside their own last
/// week, their stars each day, what they did, and their own treats.
struct GlowPersonSheet: View {
    let personId: Person.ID
    let weeksBack: Int

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @Environment(\.closeWallSheet) private var close

    var body: some View {
        let calendar = store.calendar
        let week = GlowWeeks.week(weeksBack: weeksBack, today: store.today, calendar: calendar)
        let isThisWeek = weeksBack == 0
        let summary = GlowSummary(
            people: model.people, earnings: store.snapshot.earnings, redemptions: store.snapshot.redemptions,
            rewards: store.snapshot.rewards, lifetime: store.snapshot.lifetimeStars,
            week: week, today: GlowWeeks.readThrough(week, today: store.today), calendar: calendar
        )
        if let glow = summary.people.first(where: { $0.id == personId }) {
            let tasks = GlowStory.tasks(store.snapshot.earnings, in: week, people: model.people, person: personId)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Avatar(person: glow.person, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(glow.person.name.possessive) week").font(.display(28))
                        Text(WeekPaging.weekName(weeksBack: weeksBack) + ", " + WeekPaging.range(week.days, calendar: calendar))
                            .font(.body(15))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.trailing, 40)
                }
                HStack(spacing: 12) {
                    number(glow.weekStars, "\(StarWords.noun(glow.weekStars)) \(isThisWeek ? "this week" : "that week")")
                    // The same comparison as their card and the phone: last week up to this weekday.
                    number(glow.lastWeekSoFar, isThisWeek ? "\(StarWords.noun(glow.lastWeekSoFar)) by this time last week" : "\(StarWords.noun(glow.lastWeekSoFar)) the week before")
                    number(glow.lifetimeStars, "\(StarWords.noun(glow.lifetimeStars)) all time")
                }
                DayBars(values: glow.byDay, days: week.days, today: store.today, color: glow.person.color.color, calendar: calendar)
                    .frame(height: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Text("What \(glow.person.name) did").font(.display(19))
                    if tasks.isEmpty {
                        Text(isThisWeek ? "Nothing yet this week." : "Nothing that week.")
                            .font(.body(14, weight: 600))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(tasks.prefix(6)) { task in
                        HStack(spacing: 10) {
                            Text(task.emoji).font(.system(size: 18)).frame(width: 26)
                            Text(task.title).font(.body(15.5, weight: 700)).lineLimit(1)
                            Text(GlowWords.times(task.times)).font(.body(13.5, weight: 600)).foregroundStyle(Theme.muted)
                            Spacer(minLength: 4)
                            StarsTag(stars: task.stars)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                let treats = store.snapshot.rewards.filter { !$0.archived && $0.ownerId == personId }
                if !treats.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(treats.count == 1 ? "\(glow.person.name.possessive) own treat" : "\(glow.person.name.possessive) own treats").font(.display(19))
                        ForEach(treats) { reward in
                            RewardCard(status: ChoreBoard.RewardStatus(reward: reward, earned: store.earned(toward: reward)), showsPace: true, onEdit: nil)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Done") { close() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .foregroundStyle(Theme.ink)
        }
    }

    private func number(_ value: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.display(30)).monospacedDigit()
            Text(title).font(.body(13, weight: 600)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
