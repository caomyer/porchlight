import SwiftUI

/// The paper of a day page at `scale`: the day number and the ruled lines, no ink.
/// Rules continue past the page's bottom when the frame is taller than the page.
struct PagePaper: View {
    let number: String
    var scale: CGFloat = 1
    var numberColor: Color = Theme.ink
    var numberOpacity: Double = 1
    var paperColor: Color = Paper.color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                var y = PageGeometry.firstLineTop + PageGeometry.lineHeight
                while (y - 1) * scale < size.height {
                    let rect = CGRect(x: 0, y: (y - 1) * scale, width: size.width, height: max(scale, 0.5))
                    context.fill(Path(rect), with: .color(Paper.rule))
                    y += PageGeometry.lineHeight
                }
            }
            Text(number)
                .font(.display(16 * scale))
                .foregroundStyle(numberColor)
                .opacity(numberOpacity)
                .frame(height: 24 * scale)
                .padding(.leading, PageGeometry.margin * scale)
                .padding(.top, 4 * scale)
        }
        .background(paperColor)
    }
}

/// A whole day page (paper and ink) at `scale`, e.g. the "actual size" preview.
struct DayPageView: View {
    let day: DayKey
    var scale: CGFloat = 1
    var numberColor: Color = Theme.ink
    /// Live ink to show instead of the stored page (while editing).
    var image: UIImage?

    @Environment(FoodStore.self) private var store
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let ink = image ?? store.pageImage(for: day, scale: scale, displayScale: displayScale)
        PagePaper(number: dayNumber, scale: scale, numberColor: numberColor)
            .overlay(alignment: .topLeading) {
                if let ink {
                    Image(uiImage: ink)
                        .resizable()
                        .frame(width: PageGeometry.size.width * scale, height: PageGeometry.size.height * scale)
                }
            }
            .frame(width: PageGeometry.size.width * scale, height: PageGeometry.size.height * scale)
            .clipped()
    }

    private var dayNumber: String {
        String(Int(day.rawValue.suffix(2)) ?? 0)
    }
}

/// A tiny taped-on polaroid for a day cell in the handwritten month.
struct TapedPolaroid: View {
    let entry: JournalEntry
    var width: CGFloat = 34

    var body: some View {
        MealIllustration(entry: entry, plate: 0.62, emojiSize: width * 0.4)
            .frame(width: width - 6, height: width - 6)
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .padding(.bottom, 8)
            .background(Color.white)
            .shadow(color: FoodStyle.shadow.opacity(0.22), radius: 2.5, y: 2)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(red: 236 / 255, green: 214 / 255, blue: 150 / 255).opacity(0.75))
                    .frame(width: width * 0.7, height: 10)
                    .rotationEffect(.degrees(-10))
                    .offset(x: 10, y: -6)
            }
            .rotationEffect(.degrees(7))
            .accessibilityHidden(true)
    }
}
