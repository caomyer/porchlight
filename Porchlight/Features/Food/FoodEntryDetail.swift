import SwiftUI

/// A logged meal up close: the big polaroid, its details and a way to remove it.
struct MealDetailSheet: View {
    let entry: JournalEntry
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var confirmingDelete = false

    var body: some View {
        WallSheet(width: 600, onClose: onClose) {
            HStack(alignment: .top, spacing: 26) {
                Polaroid(entry: entry, rotation: -2, emojiSize: 84, captionSize: 22, plate: 0.5, badgeSize: 26)
                    .environment(\.foodPreferFullPhoto, true)
                    .frame(width: 220)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(.display(30))
                        .lineLimit(2)
                        .padding(.trailing, 40)
                    Text(dateLine)
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        detail(entry.source.emoji, entry.source.label)
                        if let rating = entry.rating {
                            detail(rating.emoji, rating.phrase.prefix(1).uppercased() + rating.phrase.dropFirst())
                        }
                        HStack(spacing: 10) {
                            EaterBadge(people: store.eaters(of: entry), everyone: store.ateTogether(entry), size: 26)
                            Text(whoText).font(.body(16, weight: 600))
                        }
                        if let line = entry.noteLine {
                            detail("✍️", "Note on line \(line + 1) of the day's page")
                        }
                    }
                    .padding(.top, 18)
                    Spacer(minLength: 24)
                    HStack {
                        Spacer()
                        if confirmingDelete {
                            Button("Keep it") { confirmingDelete = false }
                                .buttonStyle(SecondaryButtonStyle())
                            Button("Remove meal") {
                                store.deleteMeal(entry)
                                onClose()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        } else {
                            Button {
                                confirmingDelete = true
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
            }
        }
    }

    private var dateLine: String {
        let date = entry.dayKey.startDate(in: store.calendar)
        return "\(entry.slot) · " + date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var whoText: String {
        if store.ateTogether(entry) { return "Everyone ate" }
        return ListFormat.join(store.eaters(of: entry).map(\.name)) + " ate"
    }

    private func detail(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 18)).frame(width: 26)
            Text(text).font(.body(16, weight: 600))
        }
    }
}

private struct PreferFullPhotoKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Big polaroids load the full photo instead of the thumbnail.
    var foodPreferFullPhoto: Bool {
        get { self[PreferFullPhotoKey.self] }
        set { self[PreferFullPhotoKey.self] = newValue }
    }
}
