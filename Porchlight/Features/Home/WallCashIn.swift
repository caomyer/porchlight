import SwiftUI

// Cashing in on the wall: it asks once, naming who earned the round, then the whole screen
// celebrates. A cash-in made on someone's phone is celebrated here too, the next time the
// wall is looked at. Calm: the confetti falls once and stays, nothing loops.

/// Asks before a reward is cashed in on the wall. Reward cards call it instead of spending.
struct AskCashInAction {
    let ask: @MainActor (ChoreBoard.RewardStatus) -> Void
    @MainActor func callAsFunction(_ status: ChoreBoard.RewardStatus) { ask(status) }
}

extension EnvironmentValues {
    @Entry var askCashIn: AskCashInAction? = nil
}

extension View {
    /// Hosts the wall's cash-in: the question, the celebration, and the celebration owed
    /// for a cash-in made on another device, which waits while the wall is resting.
    func celebratesCashIns(resting: Bool) -> some View {
        modifier(WallCashInHost(resting: resting))
    }
}

/// What the wall's celebration shows.
struct WallCashInCelebration: Identifiable, Equatable {
    let id = UUID()
    var emoji: String
    var title: String
    /// "20 stars from James and Mia".
    var line: String
    var faces: [Person]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    /// A cash-in made here, with everyone who earned the round (read before it was spent).
    static func made(_ reward: Reward, earners: [Person]) -> WallCashInCelebration {
        WallCashInCelebration(
            emoji: reward.emoji ?? "🎉", title: reward.title,
            line: "\(StarWords.count(reward.targetStars)) from \(PocketGlowLogic.names(earners, me: nil))",
            faces: earners
        )
    }

    /// A cash-in that arrived from another device. Its round has already started over, so
    /// it says whose it was and what it cost, not who earned each star.
    static func arrived(_ redemption: RewardRedemption, reward: Reward?, people: [Person]) -> WallCashInCelebration {
        let owner = redemption.personId.flatMap { id in people.first { $0.id == id } }
        let price = StarWords.count(reward?.targetStars ?? redemption.stars)
        return WallCashInCelebration(
            emoji: reward?.emoji ?? "🎉", title: reward?.title ?? "A reward",
            line: owner.map { "\($0.name.possessive) treat · \(price)" } ?? "\(price) from everyone",
            faces: owner.map { [$0] } ?? people
        )
    }
}

private struct WallCashInHost: ViewModifier {
    let resting: Bool

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @State private var asking: ChoreBoard.RewardStatus?
    @State private var celebrating: WallCashInCelebration?

    func body(content: Content) -> some View {
        content
            .environment(\.askCashIn, AskCashInAction { status in withoutAnimation { asking = status } })
            .wallSheet(item: $asking, width: 520) { status in
                WallCashInAsk(status: status, earners: earners(status.reward)) { cashIn(status) }
            }
            .wallCover(item: $celebrating) { celebration in
                WallCashInCelebrationView(celebration: celebration) { CompanionCover.instantly { celebrating = nil } }
            }
            .onChange(of: store.snapshot.redemptions, initial: true) { lookForNews() }
            .onChange(of: resting) { lookForNews() }
            .onChange(of: asking == nil) { lookForNews() }
    }

    private func earners(_ reward: Reward) -> [Person] {
        PocketGlowLogic.earners(of: reward, earnings: store.snapshot.earnings, redemptions: store.snapshot.redemptions, people: model.everyone)
    }

    private func cashIn(_ status: ChoreBoard.RewardStatus) {
        let earners = earners(status.reward)
        let redemption = store.cashIn(status.reward, now: CompanionClock.now())
        withoutAnimation { asking = nil }
        guard let redemption else { return }
        // Made here: celebrated now, and never again as news.
        mark(through: redemption.redeemedAt)
        CompanionCover.instantly { celebrating = .made(status.reward, earners: earners) }
    }

    // MARK: A cash-in made elsewhere

    private var markKey: String? {
        store.householdId.map { "glow.celebratedThrough.\($0)" }
    }

    private var marked: Date? {
        guard let markKey, let stored = UserDefaults.standard.object(forKey: markKey) as? Double else { return nil }
        return Date(timeIntervalSinceReferenceDate: stored)
    }

    private func mark(through date: Date) {
        guard let markKey, date > (marked ?? .distantPast) || marked == nil else { return }
        UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: markKey)
    }

    /// Celebrates the newest cash-in made on another device since the wall last looked,
    /// once someone is there to see it; otherwise remembers that everything has been seen.
    private func lookForNews() {
        let redemptions = store.snapshot.redemptions
        guard let news = CashInNews.toCelebrate(redemptions, through: marked, thisDevice: model.thisDeviceId, now: CompanionClock.now()) else {
            mark(through: CashInNews.newest(redemptions))
            return
        }
        guard !resting, asking == nil, celebrating == nil else { return }
        mark(through: CashInNews.newest(redemptions))
        let reward = store.snapshot.rewards.first { $0.id == news.rewardId }
        CompanionCover.instantly { celebrating = .arrived(news, reward: reward, people: model.people) }
    }
}

/// "Cash in Movie night?": names everyone who earned the round before it is spent.
private struct WallCashInAsk: View {
    let status: ChoreBoard.RewardStatus
    let earners: [Person]
    let onCashIn: () -> Void

    @Environment(\.closeWallSheet) private var close

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Text(status.reward.emoji ?? "🎉")
                    .font(.system(size: 44))
                    .accessibilityHidden(true)
                Text("Cash in \(status.reward.title)?")
                    .font(.display(28))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 40)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(PocketGlowLogic.cashInMessage(status, earners: earners, me: nil))
                .font(.body(16))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cash-in-message")
            if !earners.isEmpty {
                HStack(spacing: -8) {
                    ForEach(earners) { Avatar(person: $0, size: 40) }
                }
                .accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Not yet") { close() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Cash in", action: onCashIn)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("confirm-cash-in")
            }
        }
        .foregroundStyle(Theme.ink)
    }
}

/// The family moment: the reward, who it is from, confetti that falls once and stays.
/// It waits for a touch, and steps aside by itself after a while so the wall can rest.
private struct WallCashInCelebrationView: View {
    let celebration: WallCashInCelebration
    let onDone: () -> Void

    @State private var landed = false
    /// How long it stays up when nobody touches it.
    static let stays: Duration = .seconds(45)

    var body: some View {
        ZStack {
            Theme.everyone.wash(0.22, over: Theme.background)
                .ignoresSafeArea()
            ConfettiOnce(landed: landed, size: 40)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                Text(celebration.emoji)
                    .font(.system(size: 132))
                    .scaleEffect(landed ? 1 : 0.4)
                    .accessibilityHidden(true)
                Text("\(celebration.title)!")
                    .font(.display(50))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("cash-in-celebration")
                Text(celebration.line)
                    .font(.body(20, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                HStack(spacing: -10) {
                    ForEach(celebration.faces) { Avatar(person: $0, size: 56) }
                }
                .padding(.top, 18)
                .accessibilityHidden(true)
                Button("Done", action: onDone)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 26)
                    .accessibilityIdentifier("celebration-done")
            }
            .frame(maxWidth: 720)
            .padding(40)
        }
        .opacity(landed ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { landed = true }
        }
        .task {
            try? await Task.sleep(for: Self.stays)
            if !Task.isCancelled { onDone() }
        }
    }
}
