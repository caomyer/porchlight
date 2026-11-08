import SwiftUI

/// The default wall screen: a big clock, the date, and the day at a glance.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .top, spacing: 16) {
                agenda
                household
                    .frame(width: 400)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(Theme.pagePadding)
    }

    private var header: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .lastTextBaseline, spacing: 18) {
                Clock(date: context.date)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.weekday(.wide))
                        .font(.display(26))
                    Text(context.date, format: .dateTime.month(.wide).day())
                        .font(.body(16, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                HStack(spacing: -6) {
                    ForEach(model.people) { person in
                        Avatar(person: person, size: 34, ringed: true)
                    }
                }
            }
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today")
                .font(.display(22))
            Spacer()
            EmptyState(
                symbol: "calendar",
                title: "Your calendars are on their way",
                message: "The next update reads every calendar on this iPad, so add Google or iCloud accounts in Settings › Calendar › Accounts."
            )
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var household: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.household?.name ?? "")
                .font(.display(22))
            ForEach(model.people) { person in
                HStack(spacing: 12) {
                    Avatar(person: person, size: 40)
                    Text(person.name)
                        .font(.body(17, weight: 600))
                    Spacer()
                }
            }
        }
        .card()
    }
}

/// Big hour and minute, with a small AM/PM when the locale uses a 12-hour clock.
private struct Clock: View {
    let date: Date

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .font(.display(68))
                .monospacedDigit()
            if let period {
                Text(period)
                    .font(.body(18, weight: 700))
                    .foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private var period: String? {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        guard format.contains("a") else { return nil }
        let symbols = DateFormatter()
        symbols.locale = .current
        return Calendar.current.component(.hour, from: date) < 12 ? symbols.amSymbol : symbols.pmSymbol
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accent.opacity(0.12), in: Circle())
            Text(title)
                .font(.display(22))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body(15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
    }
}
