import Foundation

/// Builds the widgets' summary from the same snapshots and rules the phone's Today uses
/// (`CareLogic`, `ChoreBoard`, the star ledger), so a widget never disagrees with the app.
/// Pure, and covered by `WidgetSummaryBuilderTests`.
enum WidgetSummaryBuilder {
    /// How many grocery items a widget lists by name.
    static let groceryNames = 3

    /// - Parameter households: How many households this phone belongs to; widgets follow
    ///   the one on screen and name it when there is more than one.
    static func make(companions: CompanionSnapshot, home: HomeSnapshot, me meId: Person.ID?, role: DeviceRole, now: Date, households: Int = 1) -> WidgetSummary {
        guard role == .personal else { return WidgetSummary(writtenAt: now, isSharedScreen: true) }
        guard let household = companions.household else { return WidgetSummary(writtenAt: now) }
        var summary = WidgetSummary(
            writtenAt: now,
            household: .init(name: household.name, timeZone: household.timeZoneIdentifier, isOneOfSeveral: households > 1 ? true : nil)
        )
        // "Me" must still live here: someone removed from the household is nobody's phone.
        guard let meId, let me = companions.people.first(where: { $0.id == meId }) else { return summary }
        summary.me = .init(name: me.name, color: me.color.hex)
        let calendar = companions.calendar
        let today = DayKey(now, calendar: calendar)
        let days = [today, today.adding(days: 1, calendar: calendar)]
        summary.days = days.map(\.rawValue)
        summary.companions = companionInfo(companions, me: meId, days: days, now: now)
        summary.chores = days.flatMap { chores(home, me: meId, on: $0, calendar: calendar) }
        summary.glow = glow(home, me: meId, today: today, calendar: calendar)
        summary.groceries = groceries(home)
        return summary
    }

    private static func companionInfo(_ snapshot: CompanionSnapshot, me: Person.ID, days: [DayKey], now: Date) -> [WidgetSummary.CompanionInfo] {
        let calendar = snapshot.calendar
        let names = snapshot.names
        return snapshot.companions.map { companion in
            let routines = snapshot.routines(of: companion.id)
            let infos = routines.map { routine in
                let byDay = CareLogic.byDay(snapshot.entries(of: routine.id), calendar: calendar)
                let slots = days.flatMap { day in
                    CareLogic.slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar).map { slot in
                        WidgetSummary.Slot(
                            day: day.rawValue, index: slot.index,
                            name: CareCatchUp.slotName(slot.window, of: routine),
                            start: max(slot.window.start, 0), end: min(slot.window.end, 24 * 60),
                            doneBy: slot.entry.map { PocketToday.who($0.people, me: me, names: names) },
                            doneAt: slot.entry?.time
                        )
                    }
                }
                return WidgetSummary.CompanionInfo.Routine(
                    id: routine.id.description, title: routine.title, emoji: routine.emoji,
                    doneWord: routine.kind.pastVerb, slots: slots
                )
            }
            return WidgetSummary.CompanionInfo(
                id: companion.id.description, name: companion.name, face: companion.species.emoji,
                routines: infos, lastCare: snapshot.entries(of: routines.first?.id).last?.time
            )
        }
    }

    private static func chores(_ home: HomeSnapshot, me: Person.ID, on day: DayKey, calendar: Calendar) -> [WidgetSummary.Chore] {
        let board = ChoreBoard(
            people: home.people, chores: home.chores, completions: home.completions, earnings: home.earnings,
            redemptions: home.redemptions, rewards: home.rewards, today: day, calendar: calendar
        )
        return PocketToday.chores(board, me: me).mine.map { task in
            WidgetSummary.Chore(
                id: task.chore.id.description, day: day.rawValue, title: task.chore.title,
                emoji: task.chore.emoji, stars: task.chore.stars, done: task.isDone
            )
        }
    }

    private static func glow(_ home: HomeSnapshot, me: Person.ID, today: DayKey, calendar: Calendar) -> WidgetSummary.Glow {
        let week = HomeWeek(containing: today, calendar: calendar)
        let goal = PocketGlowLogic.rewards(home.rewards, me: me) {
            RewardProgress.earned(for: $0, earnings: home.earnings, redemptions: home.redemptions)
        }.first
        return WidgetSummary.Glow(
            myStarsThisWeek: StarTotals.byPerson(home.earnings, in: week)[me] ?? 0,
            goalTitle: goal?.reward.title, goalEmoji: goal?.reward.emoji,
            goalEarned: goal?.earned ?? 0, goalTarget: goal?.reward.targetStars ?? 0
        )
    }

    private static func groceries(_ home: HomeSnapshot) -> WidgetSummary.Groceries? {
        guard let list = home.lists.filter({ $0.kind == .grocery }).min(by: { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }) else { return nil }
        let open = home.items.filter { $0.listId == list.id && !$0.checked }.sorted { $0.sortOrder < $1.sortOrder }
        return WidgetSummary.Groceries(
            listId: list.id.description, title: list.title, count: open.count,
            firstItems: open.prefix(groceryNames).map(\.title)
        )
    }
}
