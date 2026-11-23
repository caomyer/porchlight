import SwiftUI

// The pieces Glow's page and a person's page share: the lamp, the week's strip, a task's
// row, a reward's row, and cashing in.

/// The porch light: a warm glow with the bulb in it. It never pulses.
struct PorchLamp: View {
    @PhoneMetric(upTo: 1.3) private var side: CGFloat = 76

    var body: some View {
        Text("💡")
            .font(.system(size: side * 0.36))
            .frame(width: side, height: side)
            .background(
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0xFFE3A6), location: 0.3),
                        .init(color: Color(hex: 0xFFD28C).opacity(0.55), location: 0.31),
                        .init(color: Color(hex: 0xFFD28C).opacity(0.55), location: 0.5),
                        .init(color: Color(hex: 0xFFD28C).opacity(0), location: 0.78),
                    ],
                    center: .center, startRadius: 0, endRadius: side / 2
                ),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

/// A week's stars, a bar a day, each bar stacked in the colors of who earned them. A day
/// with nothing is a short line; a day still to come is fainter.
struct GlowDayStrip: View {
    struct Part: Equatable {
        var color: Color
        var stars: Int
    }

    let days: [DayKey]
    let today: DayKey
    /// Each day's parts, in the order they stack from the bottom.
    let parts: [[Part]]
    let calendar: Calendar
    /// What VoiceOver calls it: "Stars each day".
    var label = "Stars each day"

    @PhoneMetric(upTo: 1.3) private var height: CGFloat = 56

    var body: some View {
        let totals = parts.map { $0.map(\.stars).reduce(0, +) }
        let top = max(totals.max() ?? 0, 4)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let dayParts = parts.indices.contains(index) ? parts[index].filter { $0.stars > 0 } : []
                VStack(spacing: 5) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if dayParts.isEmpty {
                            Capsule()
                                .fill(Theme.line.opacity(day > today ? 0.5 : 1))
                                .frame(height: 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(dayParts.reversed().enumerated()), id: \.offset) { _, part in
                                    part.color.frame(height: max(4, height * CGFloat(part.stars) / CGFloat(top)))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    .frame(maxWidth: 24)
                    .frame(height: height)
                    Text(day.formatted(.dateTime.weekday(.narrow), calendar: calendar))
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption2)
                        .foregroundStyle(day == today ? Theme.accent : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken(totals))
    }

    /// "Tuesday 4 stars, Wednesday 2 stars": only the days with any.
    private func spoken(_ totals: [Int]) -> String {
        let said = zip(days, totals).filter { $0.1 > 0 }.map { day, stars in
            "\(day.formatted(.dateTime.weekday(.wide), calendar: calendar)) \(StarWords.count(stars))"
        }
        return said.isEmpty ? "None yet" : said.joined(separator: ", ")
    }
}

/// One thing done this week: its emoji, its name, how often and who, and what it earned.
struct GlowTaskRow: View {
    let task: GlowTask
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(task.emoji).phoneFont(.body, 22).frame(minWidth: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                Text(detail)
                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            GlowStars(stars: task.stars)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(task.title), \(detail), \(StarWords.count(task.stars))")
    }
}

/// "+12" at the end of a row, in the display face.
struct GlowStars: View {
    let stars: Int

    var body: some View {
        Text("+\(stars)")
            .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
            .monospacedDigit()
            .accessibilityLabel(StarWords.count(stars))
    }
}

/// A thin line between rows in a Glow card.
struct GlowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).accessibilityHidden(true)
    }
}

/// A reward being saved for: its name, how far it is, and "Cash in" once it is reached.
struct GlowRewardRow: View {
    let status: ChoreBoard.RewardStatus
    /// "about 3 days away at this pace", when there is enough to go on.
    var pace: String?
    /// Whether this phone may cash it in: a person's own treat is theirs to spend.
    var canCashIn = true
    let onCashIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveRow(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text([status.reward.emoji, status.reward.title].compactMap { $0 }.joined(separator: " "))
                        .phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                    if let pace {
                        Text(pace)
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("pace-\(status.reward.title)")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(min(status.earned, status.reward.targetStars)) of \(status.reward.targetStars)")
                    .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
            ProgressBar(fraction: status.fraction, fill: AnyShapeStyle(PersonColor.ochre.color), height: 8, track: Theme.surface2)
            if status.isReached && canCashIn {
                Button("Cash in 🎉", action: onCashIn)
                    .buttonStyle(PhoneButtonStyle())
                    .accessibilityLabel("Cash in \(status.reward.title)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Nothing to save for yet: three rewards to start with in one tap, or your own. A picked
/// idea is an ordinary shared reward, to rename, reprice or give to one person afterwards.
struct GlowRewardIdeas: View {
    @Environment(HomeStore.self) private var home
    @Environment(\.openYou) private var openYou
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Chips side by side; at the largest text sizes a column, each as wide as the card,
        // so a long name wraps instead of running off the side.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(FlowLayout(spacing: 8, lineSpacing: 8))
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow(spacing: 12, alignment: .top) {
                Text("🎁").phoneFont(.body, 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Something to save for").phoneFont(.display, 18, weight: 600, relativeTo: .headline)
                    Text("A reward that chores' stars count toward. Pick one to start; you can change it any time.")
                        .phoneFont(.body, 13.5, weight: 500, relativeTo: .subheadline)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            layout {
                ForEach(RewardIdeas.all, id: \.title) { idea in
                    Button { home.saveReward(idea) } label: {
                        chip("\(idea.emoji ?? "🎁") \(idea.title) · \(idea.targetStars)")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save for \(idea.title), \(StarWords.count(idea.targetStars))")
                    .accessibilityIdentifier("reward-idea-\(idea.title)")
                }
                Button { openYou?(.rewards) } label: { chip("+ Your own") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your own reward")
                    .accessibilityIdentifier("set-up-rewards")
            }
            if let error = home.lastError {
                Text(error)
                    .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.accent)
            }
        }
        .phoneCard()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, typeSize.isAccessibilitySize ? 10 : 0)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44, alignment: .leading)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Cashing in

/// A cash-in this phone just made.
struct GlowCelebration: Identifiable {
    let id = UUID()
    let reward: Reward
    let stars: Int
    let earners: [Person]
}

/// "Cash in Pizza night?": names everyone who earned it before it is spent.
struct CashInSheet: View {
    let status: ChoreBoard.RewardStatus
    let earners: [Person]
    let onCashIn: () -> Void

    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let reward = status.reward
        PhoneSheet(title: "Cash in \(reward.title)?") {
            Text(reward.emoji ?? "🎉")
                .font(.system(size: 46))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(PocketGlowLogic.cashInMessage(status, earners: earners, me: me?.id))
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
        } footer: {
            VStack(spacing: 10) {
                Button("Cash in", action: onCashIn)
                    .buttonStyle(PhoneButtonStyle())
                    .accessibilityIdentifier("confirm-cash-in")
                Button("Not yet") { dismiss() }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
            }
        }
    }
}

/// The moment after cashing in on this phone: the reward, who earned it, a few pieces
/// of confetti that fall once. Nothing loops; it waits for Done.
struct CashInCelebration: View {
    let celebration: GlowCelebration
    let me: Person.ID?
    let onDone: () -> Void

    @State private var landed = false

    var body: some View {
        ZStack {
            // Opaque: nothing of the page behind should be legible under the title.
            Theme.background.ignoresSafeArea()
            ConfettiOnce(landed: landed)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 12) {
                Text(celebration.reward.emoji ?? "🎉")
                    .font(.system(size: 84))
                    .scaleEffect(landed ? 1 : 0.4)
                    .accessibilityHidden(true)
                Text("\(celebration.reward.title)!")
                    .phoneFont(.display, 32, weight: 600, relativeTo: .largeTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("\(StarWords.count(celebration.reward.targetStars)) from \(PocketGlowLogic.names(celebration.earners, me: me))")
                    .phoneFont(.body, 15, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                HStack(spacing: -6) {
                    ForEach(celebration.earners) { PersonAvatar($0) }
                }
                Button("Done", action: onDone)
                    .buttonStyle(PhoneButtonStyle())
                    .padding(.top, 12)
                    .accessibilityIdentifier("celebration-done")
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { landed = true }
        }
    }
}

/// Confetti that falls once from the top and stays where it lands.
struct ConfettiOnce: View {
    let landed: Bool
    var size: CGFloat = 26
    private static let pieces = ["🎉", "✨", "⭐", "🎊", "✨", "⭐", "🎉", "🎊", "✨", "⭐"]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(Self.pieces.enumerated()), id: \.offset) { index, piece in
                Text(piece)
                    .font(.system(size: size))
                    .position(
                        x: proxy.size.width * (0.08 + 0.09 * CGFloat(index)),
                        y: landed ? proxy.size.height * (0.12 + 0.07 * CGFloat(index % 4)) : -40
                    )
                    .animation(.easeOut(duration: 1.2).delay(0.05 * Double(index)), value: landed)
            }
        }
        .accessibilityHidden(true)
    }
}
