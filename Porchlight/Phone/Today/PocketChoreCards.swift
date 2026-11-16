import SwiftUI

/// "Yours today": my chores on the wall's board, checked off with one tap. When none
/// are left it folds into a quiet banner instead of an empty list.
struct YoursTodayCard: View {
    let tasks: [ChoreBoard.Task]
    /// Stars I earned today, chores and care.
    let starsToday: Int
    let onCheck: (Chore) -> Void

    @Environment(HomeStore.self) private var home

    var body: some View {
        let done = tasks.filter(\.isDone)
        if tasks.allSatisfy(\.isDone) {
            StatusBanner(tone: .good, emoji: "🌙", title: tasks.isEmpty ? "Nothing for you today" : "Nothing else for you today", detail: detail(done: done))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                PhoneCardHeader(title: "Yours today", meta: "\(done.count) of \(tasks.count) done")
                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { RowDivider() }
                        PhoneChoreRow(
                            kind: .mine, emoji: task.chore.emoji, title: task.chore.title,
                            subtitle: PocketChoreWords.subtitle(task, today: home.today, calendar: home.calendar),
                            stars: task.chore.stars, isDone: task.isDone
                        ) { onCheck(task.chore) }
                    }
                }
            }
            .phoneCard()
        }
    }

    /// "Recycling and the faucet done. +5 stars today."
    private func detail(done: [ChoreBoard.Task]) -> String {
        let stars = starsToday > 0 ? "+\(starsToday) \(starsToday == 1 ? "star" : "stars") today." : nil
        let chores: String? = switch done.count {
        case 0: tasks.isEmpty ? "No chores of yours today." : nil
        case 1, 2: ListFormatter.localizedString(byJoining: done.map(\.chore.title)) + " done."
        default: "All \(done.count) of your chores done."
        }
        return [chores, stars].compactMap { $0 }.joined(separator: " ")
    }
}

/// "Anyone can take": the household's shared chores today. Taking one checks it off,
/// credited to you; what others already did stays, crossed out under their name.
struct AnyoneCanTakeCard: View {
    let tasks: [ChoreBoard.Task]
    let onTake: (Chore) -> Void

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.me) private var me

    var body: some View {
        let open = tasks.filter { !$0.isDone }.count
        VStack(alignment: .leading, spacing: 4) {
            PhoneCardHeader(title: "Anyone can take", meta: open == 0 ? "All taken" : "\(open) open")
            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { RowDivider() }
                    PhoneChoreRow(
                        kind: .anyone, emoji: task.chore.emoji, title: task.chore.title,
                        subtitle: PocketChoreWords.subtitle(task, today: home.today, calendar: home.calendar, people: model.everyone, me: me?.id),
                        stars: task.chore.stars, isDone: task.isDone,
                        doneBy: task.completion?.personId.flatMap(model.person)
                    ) { onTake(task.chore) }
                }
            }
        }
        .phoneCard()
    }
}

enum PocketChoreWords {
    /// "this weekend" while open; "Done 7:05am", or "Done by Mia, 7:05am" for a shared one.
    static func subtitle(_ task: ChoreBoard.Task, today: DayKey, calendar: Calendar, people: [Person]? = nil, me: Person.ID? = nil) -> String? {
        guard let completion = task.completion else {
            return ChoreSchedule.subtitle(for: task.chore, today: today, calendar: calendar)
        }
        let time = CareText.timeWithPeriod(completion.completedAt, calendar: calendar)
        guard let people, let person = completion.personId.flatMap(people.person) else { return "Done \(time)" }
        return "Done by \(person.id == me ? "you" : person.name), \(time)"
    }
}
