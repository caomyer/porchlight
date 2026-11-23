import SwiftUI

/// One person's Glow, opened from "Everyone": their week beside their own last week (never
/// beside anyone else), their stars each day, what they did, and their own treat.
struct PocketGlowPerson: View {
    let personId: Person.ID
    let onCashIn: (ChoreBoard.RewardStatus) -> Void

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let week = GlowReading(home: home, people: model.people, weeksBack: 0)
        if let glow = week.summary.people.first(where: { $0.id == personId }) {
            let isMe = personId == me?.id
            let whose = isMe ? "Your" : glow.person.name.possessive
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        PageTitle(small: "Glow", title: isMe ? "You" : glow.person.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PersonAvatar(glow.person, size: .large)
                    }
                    numbers(glow, week: week)
                    days(glow, week: week, whose: whose)
                    did(week: week, isMe: isMe, name: glow.person.name)
                    treats(glow.person, whose: whose)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.background)
            .navigationTitle(isMe ? "You" : glow.person.name)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        } else {
            // Someone who no longer lives here: back to everyone.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func numbers(_ glow: GlowSummary.PersonGlow, week: GlowReading) -> some View {
        AdaptiveRow(spacing: 8, alignment: .top) {
            GlowNumber(
                number: glow.weekStars,
                title: "\(StarWords.noun(glow.weekStars)) \(week.isThisWeek ? "this week" : "that week")",
                detail: "\(glow.lastWeekStars) \(week.isThisWeek ? "last week" : "the week before")"
            )
            .accessibilityIdentifier("glow-person-week")
            GlowNumber(number: glow.lifetimeStars, title: "\(StarWords.noun(glow.lifetimeStars)) all time", detail: nil)
                .accessibilityIdentifier("glow-person-all-time")
        }
    }

    private func days(_ glow: GlowSummary.PersonGlow, week: GlowReading, whose: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PhoneCardHeader(title: "\(whose) week", meta: "stars each day")
            GlowDayStrip(
                days: week.week.days, today: home.today,
                parts: glow.byDay.map { [GlowDayStrip.Part(color: glow.person.color.color, stars: $0)] },
                calendar: home.calendar
            )
        }
        .phoneCard()
    }

    private func did(week: GlowReading, isMe: Bool, name: String) -> some View {
        let tasks = GlowStory.tasks(home.snapshot.earnings, in: week.week, people: model.people, person: personId)
        return VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: isMe ? "What you did" : "What \(name) did", meta: week.isThisWeek ? "this week" : "that week")
            if tasks.isEmpty {
                Text(week.isThisWeek ? "Nothing yet this week." : "Nothing that week.")
                    .phoneFont(.body, 13.5, weight: 600, relativeTo: .subheadline)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 { GlowDivider() }
                GlowTaskRow(task: task, detail: GlowWords.times(task.times))
            }
        }
        .phoneCard()
    }

    /// Their own treats, each with how far it is. Only its owner's phone cashes one in.
    @ViewBuilder
    private func treats(_ person: Person, whose: String) -> some View {
        let statuses = home.snapshot.rewards
            .filter { !$0.archived && $0.ownerId == person.id }
            .map { ChoreBoard.RewardStatus(reward: $0, earned: home.earned(toward: $0)) }
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PhoneCardHeader(title: statuses.count == 1 ? "\(whose) own treat" : "\(whose) own treats")
                ForEach(statuses) { status in
                    GlowRewardRow(status: status, canCashIn: person.id == me?.id || me == nil) { onCashIn(status) }
                }
            }
            .phoneCard()
        }
    }
}

/// A big number with what it counts under it.
struct GlowNumber: View {
    let number: Int
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(number)")
                .phoneFont(.display, 28, weight: 600, relativeTo: .title)
                .monospacedDigit()
            Text(title)
                .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
            if let detail {
                Text(detail)
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
