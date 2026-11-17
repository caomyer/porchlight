import Foundation

/// The sample household as a widget summary: the widget gallery's preview, and what the
/// render tests draw. "Now" is `date`; the evening walk is open from 5 to 8 pm.
enum WidgetPreviewData {
    static func summary(at date: Date, timeZone: TimeZone = .current) -> WidgetSummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = WidgetMoment.dayKey(date, calendar: calendar)
        let tomorrow = WidgetMoment.dayKey(calendar.date(byAdding: .day, value: 1, to: date) ?? date, calendar: calendar)
        let start = calendar.startOfDay(for: date)
        func at(_ hour: Int, _ minute: Int) -> Date { start.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        func slots(_ windows: [(String, Int, Int)], done: [Int: (String, Date)] = [:]) -> [WidgetSummary.Slot] {
            [today, tomorrow].flatMap { day in
                windows.enumerated().map { index, window in
                    let logged = day == today ? done[index] : nil
                    return WidgetSummary.Slot(
                        day: day, index: index, name: window.0, start: window.1, end: window.2,
                        doneBy: logged?.0, doneAt: logged?.1
                    )
                }
            }
        }
        return WidgetSummary(
            writtenAt: date,
            household: .init(name: "The Lake House", timeZone: timeZone.identifier),
            me: .init(name: "James", color: 0x4C7BB0),
            days: [today, tomorrow],
            companions: [
                .init(
                    id: "yoyo", name: "Yo-Yo", face: "🐕",
                    routines: [
                        .init(id: "walk", title: "Walk", emoji: "🦮", doneWord: "Walked", slots: slots(
                            [("morning walk", 6 * 60, 10 * 60), ("evening walk", 17 * 60, 20 * 60)],
                            done: [0: ("Mia", at(7, 40))]
                        )),
                        .init(id: "feed", title: "Feed", emoji: "🥣", doneWord: "Fed", slots: slots(
                            [("breakfast", 6 * 60, 9 * 60), ("dinner", 17 * 60, 19 * 60)],
                            done: [0: ("you", at(7, 5))]
                        )),
                    ],
                    lastCare: at(7, 40)
                ),
                .init(
                    id: "miso", name: "Miso", face: "🐈",
                    routines: [
                        .init(id: "litter", title: "Litter", emoji: "🧹", doneWord: "Litter done", slots: slots(
                            [("litter", 0, 24 * 60)], done: [0: ("Mia", at(8, 15))]
                        )),
                    ],
                    lastCare: at(8, 15)
                ),
            ],
            chores: [
                .init(id: "faucet", day: today, title: "Fix the leaky faucet", emoji: "🔧", stars: 3, done: false),
                .init(id: "recycling", day: today, title: "Recycling", emoji: "♻️", stars: 1, done: true),
                .init(id: "plants", day: tomorrow, title: "Water the plants", emoji: "🪴", stars: 1, done: false),
            ],
            glow: .init(myStarsThisWeek: 23, goalTitle: "Pizza night", goalEmoji: "🍕", goalEarned: 72, goalTarget: 80),
            groceries: .init(listId: "groceries", title: "Groceries", count: 8, firstItems: ["Oat milk", "Avocados", "Scallions"])
        )
    }
}
