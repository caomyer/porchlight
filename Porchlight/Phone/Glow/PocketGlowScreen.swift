import SwiftUI

/// The Glow tab: what the household did for each other this week. The week's stars with
/// my share and the trend, what is being saved for, everyone side by side, what the stars
/// were for, and what just happened. Anyone opens to their own week. Cashing in asks once,
/// naming everyone who earned it, and this phone celebrates.
struct PocketGlowScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.me) private var me
    @State private var path: [GlowRoute] = []
    @State private var confirming: ChoreBoard.RewardStatus?
    @State private var celebrating: GlowCelebration?
    /// A cash-in made in the sheet, celebrated once the sheet has closed.
    @State private var cashedIn: GlowCelebration?

    var body: some View {
        NavigationStack(path: $path) {
            page
                .navigationTitle("Glow")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: GlowRoute.self) { route in
                    switch route {
                    case let .person(id):
                        PocketGlowPerson(personId: id) { confirming = $0 }
                            .toolbar { ToolbarItem(placement: .topBarTrailing) { PocketYouButton() } }
                            .toolbarBackground(Theme.background, for: .navigationBar)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
        }
        .tint(Theme.accent)
        .sheet(item: $confirming, onDismiss: celebrate) { status in
            CashInSheet(status: status, earners: earners(status.reward)) { cashIn(status) }
        }
        .overlay {
            if let celebrating {
                CashInCelebration(celebration: celebrating, me: me?.id) { self.celebrating = nil }
                    .transition(.opacity)
            }
        }
    }

    private var page: some View {
        let week = GlowReading(home: home, people: model.people, weeksBack: 0)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PocketHeader(small: WeekPaging.range(week.week.days, calendar: home.calendar), title: "Glow")
                hero(week)
                saving
                everyone(week)
                whereFrom(week)
                lately(week)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .paperUnderStatusBar()
    }

    private func earners(_ reward: Reward) -> [Person] {
        PocketGlowLogic.earners(of: reward, earnings: home.snapshot.earnings, redemptions: home.snapshot.redemptions, people: model.everyone)
    }

    private func cashIn(_ status: ChoreBoard.RewardStatus) {
        let earners = earners(status.reward)
        confirming = nil
        guard let redemption = home.cashIn(status.reward, now: CompanionClock.now()) else { return }
        cashedIn = GlowCelebration(reward: status.reward, stars: redemption.stars, earners: earners)
    }

    private func celebrate() {
        guard let cashedIn else { return }
        self.cashedIn = nil
        withAnimation(.easeOut(duration: 0.25)) { celebrating = cashedIn }
    }

    // MARK: The week

    private func hero(_ week: GlowReading) -> some View {
        let summary = week.summary
        let mine = me.flatMap { me in summary.people.first { $0.id == me.id } }?.weekStars
        let trend = GlowWords.trend(stars: summary.weekStars, before: summary.lastWeekSoFar, isThisWeek: week.isThisWeek)
        return VStack(alignment: .leading, spacing: 14) {
            AdaptiveRow(spacing: 14) {
                PorchLamp()
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(summary.weekStars)")
                        .phoneFont(.display, 42, weight: 600, relativeTo: .largeTitle)
                        .monospacedDigit()
                        .accessibilityIdentifier("glow-week-stars")
                    Text(GlowWords.total(stars: summary.weekStars, mine: mine, isThisWeek: week.isThisWeek))
                        .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    if let trend {
                        Text(trend)
                            .phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
                            .foregroundStyle(summary.weekStars > summary.lastWeekSoFar ? Theme.goodInk : Theme.muted)
                            .accessibilityIdentifier("glow-trend")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            GlowDayStrip(
                days: week.week.days, today: home.today,
                parts: week.week.days.indices.map { index in
                    summary.people.map { GlowDayStrip.Part(color: $0.person.color.color, stars: $0.byDay[index]) }
                },
                calendar: home.calendar
            )
        }
        .phoneCard(tint: Color(hex: 0xF2B36B))
    }

    // MARK: Saving for

    @ViewBuilder
    private var saving: some View {
        let statuses = me.map { me in PocketGlowLogic.rewards(home.snapshot.rewards, me: me.id) { home.earned(toward: $0) } }
            ?? home.snapshot.rewards.filter { !$0.archived && $0.isShared }.map { ChoreBoard.RewardStatus(reward: $0, earned: home.earned(toward: $0)) }
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PhoneCardHeader(title: "Saving for", meta: statuses.count == 1 ? (statuses[0].reward.isShared ? "family reward" : "your treat") : "\(statuses.count) rewards")
                ForEach(statuses) { status in
                    GlowRewardRow(status: status) { confirming = status }
                }
            }
            .phoneCard()
        } else if home.activeChores.isEmpty {
            PocketSetUpCard(
                emoji: "⭐",
                title: "Stars come from chores",
                detail: "Each chore earns stars when someone checks it off, and the stars count toward rewards the household saves for.",
                action: "Add chores",
                page: .chores
            )
        } else if home.snapshot.rewards.allSatisfy(\.archived) {
            PocketSetUpCard(
                emoji: "🎁",
                title: "Something to save for",
                detail: "A reward, for one person or everyone together, that chores' stars count toward.",
                action: "Add a reward",
                page: .rewards
            )
        }
    }

    // MARK: Everyone

    private func everyone(_ week: GlowReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: "Everyone", meta: week.isThisWeek ? "this week" : "that week")
            ForEach(Array(week.summary.people.enumerated()), id: \.element.id) { index, glow in
                if index > 0 { GlowDivider() }
                let name = glow.id == me?.id ? "You" : glow.person.name
                let line = GlowWords.personLine(glow, isThisWeek: week.isThisWeek)
                Button { path.append(.person(glow.id)) } label: {
                    HStack(spacing: 10) {
                        PersonAvatar(glow.person)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                            Text(line)
                                .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(glow.weekStars)")
                            .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(StarWords.count(glow.weekStars)) \(week.isThisWeek ? "this week" : "that week"), \(line)")
                .accessibilityHint("Opens \(glow.id == me?.id ? "your" : glow.person.name.possessive) week")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("glow-person-\(glow.person.name)")
            }
        }
        .phoneCard()
    }

    // MARK: Where the stars came from

    @ViewBuilder
    private func whereFrom(_ week: GlowReading) -> some View {
        if !week.tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PhoneCardHeader(title: "Where the stars came from", meta: week.isThisWeek ? "this week" : "that week")
                ForEach(Array(week.tasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { GlowDivider() }
                    GlowTaskRow(task: task, detail: GlowWords.taskDetail(task) { week.name($0, me: me?.id) })
                        .accessibilityIdentifier("glow-task-\(task.title)")
                }
            }
            .phoneCard()
        }
    }

    // MARK: Lately

    @ViewBuilder
    private func lately(_ week: GlowReading) -> some View {
        let days = GlowStory.lately(week.summary.feed, today: home.today, calendar: home.calendar)
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PhoneCardHeader(title: "Lately")
                ForEach(days) { day in
                    Text(day.title.uppercased())
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption2)
                        .kerning(1)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(day.items) { item in
                        GlowLatelyRow(item: item, who: who(item), person: item.personId.flatMap(model.person), time: time(item))
                    }
                }
            }
            .phoneCard()
            .accessibilityIdentifier("glow-lately")
        }
    }

    private func who(_ item: GlowSummary.FeedItem) -> String {
        guard let id = item.personId else { return item.isCashIn ? "Everyone" : "Someone" }
        return id == me?.id ? "You" : model.person(id)?.name ?? "Someone"
    }

    /// When it happened, unless it was written down for another day than it happened on.
    private func time(_ item: GlowSummary.FeedItem) -> String? {
        guard DayKey(item.at, calendar: home.calendar) == item.day else { return nil }
        return ClockFormat.phoneTime(item.at, calendar: home.calendar)
    }
}

enum GlowRoute: Hashable {
    case person(Person.ID)
}

/// One week of Glow read from the store: the same reading for the page and a person's page.
@MainActor
struct GlowReading {
    let week: HomeWeek
    let isThisWeek: Bool
    let summary: GlowSummary
    /// The household's tasks that week.
    let tasks: [GlowTask]
    private let everyone: [Person]

    init(home: HomeStore, people: [Person], weeksBack: Int, feedLimit: Int = 8) {
        let calendar = home.calendar
        week = GlowWeeks.week(weeksBack: weeksBack, today: home.today, calendar: calendar)
        isThisWeek = weeksBack <= 0
        summary = GlowSummary(
            people: people, earnings: home.snapshot.earnings, redemptions: home.snapshot.redemptions,
            rewards: home.snapshot.rewards, lifetime: home.snapshot.lifetimeStars,
            week: week, today: GlowWeeks.readThrough(week, today: home.today), calendar: calendar,
            feedLimit: feedLimit, feedWithinWeek: weeksBack > 0
        )
        tasks = GlowStory.tasks(home.snapshot.earnings, in: week, people: people)
        everyone = home.snapshot.everyone
    }

    /// "you", or their name: who did a task, in a sentence.
    func name(_ id: Person.ID, me: Person.ID?) -> String {
        id == me ? "you" : everyone.person(id)?.name ?? "someone"
    }
}

/// One line of "Lately": who, what, when, and what it earned.
struct GlowLatelyRow: View {
    let item: GlowSummary.FeedItem
    let who: String
    let person: Person?
    let time: String?

    var body: some View {
        HStack(spacing: 10) {
            if item.personId == nil {
                Text(item.emoji).phoneFont(.body, 20).frame(minWidth: 32).accessibilityHidden(true)
            } else {
                PersonAvatar(person)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.text).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                Text([who, time].compactMap { $0 }.joined(separator: " · "))
                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let stars = item.stars {
                GlowStars(stars: stars)
            } else {
                Text("🎉").phoneFont(.body, 18).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}
