import SwiftUI
import UIKit

/// "Where" for a meal out or delivered: type a restaurant and pick from live Apple Maps
/// suggestions (with address) or places eaten at before; a name that matches nothing is
/// kept as typed. A picked place shows as a card that can be cleared.
struct RestaurantField: View {
    @Binding var place: PlaceDraft?
    var prompt = "Search restaurants"

    @Environment(FoodStore.self) private var store
    @State private var search = RestaurantSearch()
    @State private var text = ""
    @State private var isResolving = false
    @FocusState private var isFocused: Bool
    /// The field's frame on screen and the keyboard's top, to open the list where it fits.
    @State private var fieldFrame: CGRect = .zero
    @State private var keyboardTop: CGFloat = .infinity

    private let rowHeight: CGFloat = 54
    private let fieldHeight: CGFloat = 46

    var body: some View {
        Group {
            if let place, !isFocused {
                PlaceCard(place: place) {
                    text = place.name
                    search.query = place.name
                    isFocused = true
                } onClear: {
                    self.place = nil
                    text = ""
                    search.query = ""
                }
            } else {
                field
            }
        }
        .frame(height: fieldHeight)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fieldFrame = $0 }
        .overlay(alignment: opensUp ? .bottomLeading : .topLeading) {
            if isFocused, !rows.isEmpty || search.isSearching || search.isOffline {
                dropdown
                    .offset(y: opensUp ? -(fieldHeight + 6) : fieldHeight + 6)
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardTop = frame.minY >= UIScreen.main.bounds.height ? .infinity : frame.minY
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardTop = .infinity
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onAppear { text = place?.name ?? "" }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.muted)
            TextField(prompt, text: $text)
                .font(.body(17, weight: 600))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    search.query = newValue
                    // A typed name counts until a suggestion replaces it.
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if place?.name != trimmed { place = trimmed.isEmpty ? nil : PlaceDraft(name: trimmed) }
                }
                .onSubmit { isFocused = false }
                .accessibilityLabel("Restaurant")
            if isResolving || search.isSearching {
                ProgressView().controlSize(.small)
            } else if !text.isEmpty {
                Button {
                    text = ""
                    place = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear restaurant")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: fieldHeight)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).stroke(isFocused ? Theme.ink.opacity(0.5) : Theme.line))
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    // MARK: Suggestions

    private enum Row: Identifiable {
        case recent(FoodPlace)
        case map(RestaurantSearch.Suggestion)

        var id: String {
            switch self {
            case let .recent(place): "recent-\(place.id ?? 0)"
            case let .map(suggestion): "map-\(suggestion.id)-\(suggestion.title)"
            }
        }
    }

    /// Places eaten at before that match the text (all of them, most recent first, when empty),
    /// then live map results not already among them.
    private var rows: [Row] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let recent = store.snapshot.places.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let recentRows = recent.prefix(query.isEmpty ? 5 : 2).map(Row.recent)
        guard !query.isEmpty else { return Array(recentRows) }
        let known = Set(recent.prefix(2).map { $0.name.lowercased() + "|" + ($0.address ?? "").lowercased() })
        let mapRows = search.suggestions
            .filter { !known.contains($0.title.lowercased() + "|" + $0.subtitle.lowercased()) }
            .map(Row.map)
        return Array((recentRows + mapRows).prefix(RestaurantSearch.maxSuggestions))
    }

    private var dropdownHeight: CGFloat {
        CGFloat(max(rows.count, 1)) * rowHeight + 12
    }

    /// Opens upward when the list would run under the keyboard (or off screen) below the field.
    private var opensUp: Bool {
        let bottomLimit = min(keyboardTop, UIScreen.main.bounds.height) - 12
        let roomBelow = bottomLimit - (fieldFrame.maxY + 6)
        let roomAbove = fieldFrame.minY - 6 - 12
        return roomBelow < dropdownHeight && roomAbove > roomBelow
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                HStack(spacing: 10) {
                    if search.isOffline {
                        Image(systemName: "wifi.slash").foregroundStyle(Theme.muted)
                        Text("Can't reach Maps. The name you type is saved as is.")
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Looking nearby…")
                    }
                }
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 14)
                .frame(height: rowHeight)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Theme.line).padding(.leading, 52) }
                Button { pick(row) } label: { rowLabel(row) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
        .shadow(color: FoodStyle.shadow.opacity(0.18), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Restaurant suggestions")
    }

    private func rowLabel(_ row: Row) -> some View {
        let (symbol, title, detail): (String, String, String) = switch row {
        case let .recent(place): ("clock.arrow.circlepath", place.name, [place.category, place.address].compactMap { $0 }.joined(separator: " · "))
        case let .map(suggestion): ("mappin.circle.fill", suggestion.title, suggestion.subtitle)
        }
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(symbol == "mappin.circle.fill" ? Theme.accent : Theme.muted)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body(15.5, weight: 700))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.body(13, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func pick(_ row: Row) {
        switch row {
        case let .recent(known):
            choose(PlaceDraft(known))
        case let .map(suggestion):
            // Show the name right away; fill in the details when Maps answers.
            choose(PlaceDraft(name: suggestion.title, address: suggestion.subtitle.isEmpty ? nil : suggestion.subtitle))
            isResolving = true
            Task {
                let resolved = await search.resolve(suggestion)
                isResolving = false
                if place?.name == suggestion.title { place = resolved }
            }
        }
    }

    private func choose(_ chosen: PlaceDraft) {
        place = chosen
        text = chosen.name
        isFocused = false
    }
}

/// A picked restaurant: name, then category and address; tap to change it.
private struct PlaceCard: View {
    let place: PlaceDraft
    let onEdit: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                HStack(spacing: 10) {
                    Image(systemName: place.address == nil ? "fork.knife" : "mappin.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(place.name)
                            .font(.body(16, weight: 700))
                            .lineLimit(1)
                        if let detail {
                            Text(detail)
                                .font(.body(12.5, weight: 600))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restaurant: \(place.name)")
            .accessibilityHint("Change the restaurant")
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.muted.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear restaurant")
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .background(Theme.accent.wash(0.08), in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).stroke(Theme.accent.opacity(0.35)))
        .foregroundStyle(Theme.ink)
    }

    private var detail: String? {
        let text = [place.category, place.address].compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}
