import SwiftUI

/// "Glow": what everyone gives the household, and what it adds up to. Every star earned
/// this week (a chore done, a walk, a feed) is a spark around the porch light; below,
/// each person's week, the rewards they're saving toward, and what happened lately.
struct GlowScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @State private var editing: RewardSheet?

    enum RewardSheet: Identifiable {
        case new
        case edit(Reward)
        var id: String {
            switch self {
            case .new: "new"
            case let .edit(reward): "edit-\(reward.id)"
            }
        }
    }

    var body: some View {
        let summary = GlowSummary(
            people: model.people,
            earnings: store.snapshot.earnings,
            redemptions: store.snapshot.redemptions,
            rewards: store.snapshot.rewards,
            lifetime: store.snapshot.lifetimeStars,
            week: store.week,
            today: store.today,
            calendar: store.calendar
        )
        VStack(alignment: .leading, spacing: 16) {
            HomeHeader(title: "Glow", subtitle: subtitle) {
                HeaderChip(title: "New reward", symbol: "plus") { present(.new) }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    PorchLightHero(summary: summary)
                        .frame(height: 236)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(summary.people) { glow in
                            PersonGlowCard(glow: glow, days: store.week.days, today: store.today)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    RewardsCard(onNew: { present(.new) }, onEdit: { present(.edit($0)) })
                    LatelyCard(feed: summary.feed)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 340)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .wallSheet(item: $editing, width: 640) { sheet in
            switch sheet {
            case .new: RewardEditor(reward: nil)
            case let .edit(reward): RewardEditor(reward: reward)
            }
        }
    }

    private var subtitle: String {
        "everyone's stars, " + store.week.first.formatted(.dateTime.month(.abbreviated).day(), calendar: store.calendar)
            + " - " + store.week.last.formatted(.dateTime.month(.abbreviated).day(), calendar: store.calendar)
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
                Sparks(sparks: summary.sparks, center: lantern, maxRadius: min(size.width * 0.3, size.height * 0.62)) { personId in
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

    /// 0...1: how brightly the porch glows, against last week by this day (or a gentle 10 to start).
    private var glow: Double {
        let goal = Double(max(summary.lastWeekSoFar, 10))
        return summary.weekStars == 0 ? 0.08 : min(0.25 + 0.75 * Double(summary.weekStars) / goal, 1)
    }

    private var headline: String {
        switch summary.weekStars {
        case 0: "The porch light is waiting"
        case 1: "1 star lit the porch this week"
        default: "\(summary.weekStars) stars lit the porch this week"
        }
    }

    private var detail: String {
        if summary.weekStars == 0 {
            return "Check off a chore or look after a companion, and it starts to glow."
        }
        let before = summary.lastWeekSoFar
        let change = summary.weekStars - before
        let trend = before == 0 ? "A bright start." : change > 0 ? "\(change) more than this time last week." : change == 0 ? "Right on pace with last week." : "This time last week: \(before)."
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

private struct PersonGlowCard: View {
    let glow: GlowSummary.PersonGlow
    let days: [DayKey]
    let today: DayKey

    @Environment(HomeStore.self) private var store

    var body: some View {
        let color = glow.person.color.color
        VStack(alignment: .leading, spacing: 14) {
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
                .accessibilityLabel("\(glow.weekStars) stars this week")
            }
            DayBars(values: glow.byDay, days: days, today: today, color: color, calendar: store.calendar)
                .frame(minHeight: 86, maxHeight: 150)
            VStack(alignment: .leading, spacing: 7) {
                line("🧹", count(glow.choresDone, "chore", "chores"))
                line("🐾", count(glow.careGiven, "time caring", "times caring"))
                if let favorite = glow.favorite {
                    line(favorite.emoji, "Most: \(favorite.title) ×\(favorite.count)")
                }
            }
            Spacer(minLength: 0)
            Text("\(glow.lifetimeStars) stars all time")
                .font(.body(12.5, weight: 700))
                .foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    private func line(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji).font(.system(size: 14)).frame(width: 20)
            Text(text).font(.body(14, weight: 600)).lineLimit(1)
        }
    }
}

/// Stars per day as soft bars, today's day letter in the accent color.
private struct DayBars: View {
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
    let onNew: () -> Void
    let onEdit: (Reward) -> Void

    var body: some View {
        let rewards = store.snapshot.rewards
            .filter { !$0.archived }
            .sorted { ($0.ownerId == nil ? 0 : 1, $0.sortOrder) < ($1.ownerId == nil ? 0 : 1, $1.sortOrder) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Saving up for").font(.display(19))
            if rewards.isEmpty {
                Button(action: onNew) {
                    Text("Add a treat to earn stars toward: an ice cream trip, a movie night, a day out together.")
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                }
                .buttonStyle(.plain)
            }
            ForEach(rewards) { reward in
                HStack(alignment: .center, spacing: 10) {
                    OwnerAvatar(owner: reward.owner, size: 30)
                    RewardCard(
                        status: ChoreBoard.RewardStatus(reward: reward, earned: store.earned(toward: reward)),
                        onEdit: { onEdit(reward) }
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }
}

// MARK: - Lately

private struct LatelyCard: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let feed: [GlowSummary.FeedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lately").font(.display(19))
            if feed.isEmpty {
                Text("Stars show up here as soon as someone pitches in.")
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
