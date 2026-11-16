import SwiftUI

/// The Glow tab: my stars this week, what the household is saving for, and everyone's
/// week. Cashing in asks once, naming everyone who earned it, and this phone celebrates.
struct PocketGlowScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.me) private var me
    @State private var confirming: ChoreBoard.RewardStatus?
    @State private var celebrating: Celebration?
    /// A cash-in made in the sheet, celebrated once the sheet has closed.
    @State private var cashedIn: Celebration?

    /// A cash-in this phone just made.
    struct Celebration: Identifiable {
        let id = UUID()
        let reward: Reward
        let stars: Int
        let earners: [Person]
    }

    var body: some View {
        let summary = GlowSummary(
            people: model.people, earnings: home.snapshot.earnings, redemptions: home.snapshot.redemptions,
            rewards: home.snapshot.rewards, lifetime: home.snapshot.lifetimeStars,
            week: home.week, today: home.today, calendar: home.calendar
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PocketHeader(small: "This week", title: "Glow")
                hero(summary)
                saving
                everyone(summary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .paperUnderStatusBar()
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

    private func earners(_ reward: Reward) -> [Person] {
        PocketGlowLogic.earners(of: reward, earnings: home.snapshot.earnings, redemptions: home.snapshot.redemptions, people: model.everyone)
    }

    private func cashIn(_ status: ChoreBoard.RewardStatus) {
        let earners = earners(status.reward)
        confirming = nil
        guard let redemption = home.cashIn(status.reward, now: CompanionClock.now()) else { return }
        cashedIn = Celebration(reward: status.reward, stars: redemption.stars, earners: earners)
    }

    private func celebrate() {
        guard let cashedIn else { return }
        self.cashedIn = nil
        withAnimation(.easeOut(duration: 0.25)) { celebrating = cashedIn }
    }

    // MARK: Cards

    private func hero(_ summary: GlowSummary) -> some View {
        let mine = me.map { PocketGlowLogic.mine(summary, me: $0.id) }
        return VStack(spacing: 4) {
            PorchLamp()
            Text("\(mine?.weekStars ?? summary.weekStars)")
                .phoneFont(.display, 42, weight: 600, relativeTo: .largeTitle)
                .monospacedDigit()
            Text(mine.map { "\(StarWords.noun($0.weekStars)) from you this week · \($0.lifetimeStars) all time" } ?? "\(StarWords.noun(summary.weekStars)) from the household this week")
                .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .phoneCard(tint: Color(hex: 0xF2B36B))
    }

    @ViewBuilder
    private var saving: some View {
        let statuses = me.map { me in PocketGlowLogic.rewards(home.snapshot.rewards, me: me.id) { home.earned(toward: $0) } }
            ?? home.snapshot.rewards.filter { !$0.archived && $0.isShared }.map { ChoreBoard.RewardStatus(reward: $0, earned: home.earned(toward: $0)) }
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PhoneCardHeader(title: "Saving for", meta: statuses.count == 1 ? (statuses[0].reward.isShared ? "family reward" : "your treat") : "\(statuses.count) rewards")
                ForEach(statuses) { status in
                    rewardRow(status)
                }
            }
            .phoneCard()
        }
    }

    private func rewardRow(_ status: ChoreBoard.RewardStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveRow(alignment: .firstTextBaseline) {
                Text([status.reward.emoji, status.reward.title].compactMap { $0 }.joined(separator: " "))
                    .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(min(status.earned, status.reward.targetStars)) of \(status.reward.targetStars)")
                    .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
            ProgressBar(fraction: status.fraction, fill: AnyShapeStyle(PersonColor.ochre.color), height: 8, track: Theme.surface2)
            if status.isReached {
                Button("Cash in 🎉") { confirming = status }
                    .buttonStyle(PhoneButtonStyle())
                    .accessibilityLabel("Cash in \(status.reward.title)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func everyone(_ summary: GlowSummary) -> some View {
        let most = max(summary.people.map(\.weekStars).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: "Everyone", meta: "this week")
            ForEach(summary.people) { glow in
                PersonBarRow(
                    name: glow.id == me?.id ? "You" : glow.person.name, count: glow.weekStars,
                    fraction: Double(glow.weekStars) / Double(most), color: glow.person.color.color
                ) {
                    PersonAvatar(glow.person, size: .small)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(glow.id == me?.id ? "You" : glow.person.name), \(StarWords.count(glow.weekStars)) this week")
            }
        }
        .phoneCard()
    }
}

/// The porch light: a warm glow with the bulb in it. It never pulses.
private struct PorchLamp: View {
    @PhoneMetric private var side: CGFloat = 112

    var body: some View {
        Text("💡")
            .font(.system(size: side * 0.29))
            .frame(width: side, height: side)
            .background(
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0xFFE3A6), location: 0.24),
                        .init(color: Color(hex: 0xFFD28C).opacity(0.55), location: 0.25),
                        .init(color: Color(hex: 0xFFD28C).opacity(0.55), location: 0.45),
                        .init(color: Color(hex: 0xFFD28C).opacity(0), location: 0.7),
                    ],
                    center: .center, startRadius: 0, endRadius: side / 2
                ),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

/// "Cash in Pizza night?": names everyone who earned it before it is spent.
private struct CashInSheet: View {
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
            Text(message)
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

    private var message: String {
        PocketGlowLogic.cashInMessage(status, earners: earners, me: me?.id)
    }
}

/// The moment after cashing in on this phone: the reward, who earned it, a few pieces
/// of confetti that fall once. Nothing loops; it waits for Done.
private struct CashInCelebration: View {
    let celebration: PocketGlowScreen.Celebration
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
private struct ConfettiOnce: View {
    let landed: Bool
    private static let pieces = ["🎉", "✨", "⭐", "🎊", "✨", "⭐", "🎉", "🎊", "✨", "⭐"]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(Self.pieces.enumerated()), id: \.offset) { index, piece in
                Text(piece)
                    .font(.system(size: 26))
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
