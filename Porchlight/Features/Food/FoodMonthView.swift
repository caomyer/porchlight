import SwiftUI

/// The handwritten paper month: every day is its own ruled page at 1x, with a tiny
/// taped polaroid on days with a favorite meal. Tapping a day opens it zoomed in.
struct FoodMonthView: View {
    /// Any day in the month to show.
    let month: Date
    let today: DayKey
    let onOpenDay: (DayKey) -> Void

    @Environment(FoodStore.self) private var store

    private let headerHeight: CGFloat = 37

    var body: some View {
        let calendar = store.calendar
        let days = calendar.monthGridDays(containing: month)
        let rows = max(days.count / 7, 1)
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / 7
            let cellHeight = (proxy.size.height - headerHeight) / CGFloat(rows)
            let scale = min(cellWidth / PageGeometry.size.width, cellHeight / PageGeometry.size.height)
            VStack(spacing: 0) {
                weekdayHeader(days: Array(days.prefix(7)))
                    .frame(height: headerHeight)
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let date = days[row * 7 + column]
                            DayCell(
                                day: DayKey(date, calendar: calendar),
                                date: date,
                                inMonth: calendar.isDate(date, equalTo: month, toGranularity: .month),
                                isToday: DayKey(date, calendar: calendar) == today,
                                scale: scale,
                                isLastColumn: column == 6,
                                onTap: onOpenDay
                            )
                            .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
        .background(Paper.color)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .background(SurfaceShape(cornerRadius: Theme.radius, fill: Paper.color))
    }

    private func weekdayHeader(days: [Date]) -> some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { date in
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.body(12, weight: 700))
                    .tracking(0.96)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Paper.headerRule).frame(height: 1.5)
        }
    }
}

private struct DayCell: View {
    let day: DayKey
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let scale: CGFloat
    let isLastColumn: Bool
    let onTap: (DayKey) -> Void

    @Environment(FoodStore.self) private var store
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button { onTap(day) } label: {
            ZStack(alignment: .topLeading) {
                PagePaper(
                    number: numberText,
                    scale: scale,
                    numberColor: isToday ? Theme.accent : Theme.ink,
                    numberOpacity: inMonth ? 1 : 0.35,
                    paperColor: isToday ? Theme.accent.wash(0.05, over: Paper.color) : Paper.color
                )
                if let ink = store.pageImage(for: day, scale: scale, displayScale: displayScale) {
                    Image(uiImage: ink)
                        .resizable()
                        .frame(width: PageGeometry.size.width * scale, height: PageGeometry.size.height * scale)
                        .opacity(inMonth ? 1 : 0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if let taped {
                    TapedPolaroid(entry: taped, width: 34 * min(scale, 1))
                        .padding(.top, 5)
                        .padding(.trailing, 7)
                }
            }
            .overlay(alignment: .trailing) {
                if !isLastColumn { Rectangle().fill(Paper.cellBorder).frame(width: 1) }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Paper.cellBorder).frame(height: 1)
            }
            .overlay {
                if isToday {
                    Rectangle().strokeBorder(Theme.accent.opacity(0.55), lineWidth: 2)
                }
            }
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityHint("Opens the page to write on")
    }

    private var numberText: String {
        let day = store.calendar.component(.day, from: date)
        if !inMonth && day == 1 { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return "\(day)"
    }

    /// One picture for the day, taped to the corner: the best-rated meal with photos
    /// (its cover), else the latest with photos, else the 🤩 favorite's illustration.
    private var taped: JournalEntry? {
        guard inMonth else { return nil }
        let entries = store.entries(on: day)
        let withPhotos = entries.filter { store.cover(of: $0) != nil }
        return withPhotos.max { ($0.rating?.rawValue ?? 0, $0.eatenAt) < ($1.rating?.rawValue ?? 0, $1.eatenAt) }
            ?? entries.last { $0.rating == .favorite }
    }
}

/// The floating tool bar at the bottom of the paper: pen, eraser, zoom in.
struct MonthToolBar: View {
    let onZoomIn: () -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            Text("PEN")
                .font(.body(12, weight: 800))
                .tracking(0.96)
                .foregroundStyle(Theme.muted)
            InkPalette(selected: store.isErasing ? nil : store.ink, size: 26, spacing: 10) { ink in
                store.chosenInk = ink
                store.isErasing = false
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 24).padding(.horizontal, 4)
            toolButton("Eraser", symbol: "eraser", isOn: store.isErasing) { store.isErasing.toggle() }
            toolButton("Zoom in", symbol: "plus.magnifyingglass", isOn: false, action: onZoomIn)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.line))
        .shadow(color: FoodStyle.shadow.opacity(0.28), radius: 15, y: 12)
    }

    private func toolButton(_ title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.body(13.5, weight: 700))
            }
            .foregroundStyle(isOn ? Theme.surface : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Theme.ink : Theme.surface2, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
