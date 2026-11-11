import PhotosUI
import SwiftUI

private enum HomeSettingsSheet: Identifiable {
    case chore(Chore?)
    case reward(Reward?)

    var id: String {
        switch self {
        case let .chore(chore): "chore-\(chore?.id ?? -1)"
        case let .reward(reward): "reward-\(reward?.id ?? -1)"
        }
    }
}

/// Chores, rewards, lists, the photo frame and night hours, inside Settings.
struct HomeSettingsSection: View {
    @State private var sheet: HomeSettingsSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ChoresSettings(present: present)
            RewardsSettings(present: present)
            ListsSettings()
            PhotoFrameSettings()
        }
        .frame(maxWidth: 720, alignment: .leading)
        .wallSheet(item: $sheet) { sheet in
            switch sheet {
            case let .chore(chore): ChoreEditor(chore: chore)
            case let .reward(reward): RewardEditor(reward: reward)
            }
        }
    }

    private func present(_ sheet: HomeSettingsSheet) {
        withoutAnimation { self.sheet = sheet }
    }
}

/// A settings group: label, then a card of rows.
private struct SettingsGroup<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title)
                Spacer()
                accessory()
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .card(padding: 6)
        }
    }
}

/// One row inside a settings card, with a hairline between rows.
private struct SettingsRow<Content: View>: View {
    var showsDivider = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) {
                if showsDivider { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 12) }
            }
    }
}

private struct SmallButton: View {
    let title: String
    var symbol: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
                Text(title)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .foregroundStyle(role == .destructive ? Theme.accent : Theme.ink)
    }
}

private struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body(15))
            .foregroundStyle(Theme.muted)
            .padding(14)
    }
}

// MARK: - Chores

private struct ChoresSettings: View {
    @Environment(HomeStore.self) private var store
    let present: (HomeSettingsSheet) -> Void
    @State private var showArchived = false

    var body: some View {
        let active = store.activeChores
        let archived = store.snapshot.chores.filter(\.archived)
        SettingsGroup(title: "Chores") {
            SmallButton(title: "New chore", symbol: "plus") { present(.chore(nil)) }
        } content: {
            if active.isEmpty {
                EmptyRow(text: "No chores yet. They show up on the Chores board with a column for each person.")
            }
            ForEach(Array(active.enumerated()), id: \.element.id) { index, chore in
                ChoreSettingsRow(chore: chore, showsDivider: index < active.count - 1 || !archived.isEmpty) {
                    present(.chore(chore))
                }
            }
            if !archived.isEmpty {
                Button {
                    withAnimation { showArchived.toggle() }
                } label: {
                    HStack {
                        Text("Archived (\(archived.count))").font(.body(15, weight: 700))
                        Spacer()
                        Image(systemName: showArchived ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showArchived {
                    ForEach(Array(archived.enumerated()), id: \.element.id) { index, chore in
                        ChoreSettingsRow(chore: chore, showsDivider: index < archived.count - 1) { present(.chore(chore)) }
                            .opacity(0.7)
                    }
                }
            }
        }
    }
}

private struct ChoreSettingsRow: View {
    @Environment(HomeStore.self) private var store
    let chore: Chore
    let showsDivider: Bool
    let onEdit: () -> Void

    var body: some View {
        SettingsRow(showsDivider: showsDivider) {
            OwnerAvatar(owner: chore.owner, size: 32)
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text([chore.emoji, chore.title].compactMap { $0 }.joined(separator: " "))
                        .font(.body(16, weight: 700))
                        .foregroundStyle(Theme.ink)
                    Text(details)
                        .font(.body(13, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if chore.archived {
                SmallButton(title: "Restore") { store.setArchived(chore, false) }
                SmallButton(title: "Delete", role: .destructive) { store.delete(chore) }
            } else {
                SmallButton(title: "Edit", action: onEdit)
                SmallButton(title: "Archive") { store.setArchived(chore, true) }
            }
        }
    }

    private var details: String {
        var parts = [ChoreSchedule.describe(chore, today: store.today, calendar: store.calendar)]
        if let hint = chore.timeHint { parts.append(hint) }
        parts.append("+\(chore.stars) \(chore.stars == 1 ? "star" : "stars")")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Rewards

private struct RewardsSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let present: (HomeSettingsSheet) -> Void

    var body: some View {
        let rewards = store.snapshot.rewards
        let board = store.board(people: model.people)
        let earned = Dictionary(
            board.columns.flatMap(\.rewards).map { ($0.id, $0.earned) },
            uniquingKeysWith: { first, _ in first }
        )
        SettingsGroup(title: "Rewards") {
            SmallButton(title: "New reward", symbol: "plus") { present(.reward(nil)) }
        } content: {
            if rewards.isEmpty {
                EmptyRow(text: "Add a treat to earn stars toward, for one person or a shared goal for everyone.")
            }
            ForEach(Array(rewards.enumerated()), id: \.element.id) { index, reward in
                SettingsRow(showsDivider: index < rewards.count - 1) {
                    OwnerAvatar(owner: reward.owner, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text([reward.emoji, reward.title].compactMap { $0 }.joined(separator: " "))
                            .font(.body(16, weight: 700))
                        Text(reward.archived
                            ? "Archived · \(reward.targetStars) stars"
                            : "\(earned[reward.id ?? -1] ?? 0) of \(reward.targetStars) stars\(reward.isShared ? " together" : "")")
                            .font(.body(13, weight: 600))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(reward.archived ? 0.7 : 1)
                    SmallButton(title: "Edit") { present(.reward(reward)) }
                    if reward.archived {
                        SmallButton(title: "Delete", role: .destructive) { store.delete(reward) }
                    }
                }
            }
        }
    }
}

// MARK: - Lists

private struct ListsSettings: View {
    @Environment(HomeStore.self) private var store
    @State private var newTitle = ""
    @State private var newKind = ListKind.todo
    @State private var names: [Int64: String] = [:]

    var body: some View {
        let lists = store.snapshot.lists
        SettingsGroup(title: "Lists") {
            EmptyView()
        } content: {
            ForEach(lists) { list in
                SettingsRow {
                    Image(systemName: list.kind == .grocery ? "cart" : "checklist")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32)
                    TextField("List name", text: name(for: list))
                        .font(.body(16, weight: 700))
                        .submitLabel(.done)
                        .onSubmit { store.rename(list, to: names[list.id ?? -1] ?? list.title) }
                    Text("\(store.items(in: list).count) items · \(list.kind.label)")
                        .font(.body(13, weight: 600))
                        .foregroundStyle(Theme.muted)
                    SmallButton(title: "Delete", role: .destructive) { store.delete(list) }
                }
            }
            SettingsRow(showsDivider: false) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32)
                TextField("New list", text: $newTitle)
                    .font(.body(16, weight: 600))
                    .submitLabel(.done)
                    .onSubmit(add)
                Picker("Kind", selection: $newKind) {
                    ForEach(ListKind.allCases, id: \.self) { kind in
                        Text(kind == .grocery ? "Grocery" : "To-do").tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Button("Add", action: add)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func name(for list: HomeList) -> Binding<String> {
        let id = list.id ?? -1
        return Binding(get: { names[id] ?? list.title }, set: { names[id] = $0 })
    }

    private func add() {
        if store.createList(title: newTitle, kind: newKind) { newTitle = "" }
    }
}

// MARK: - Photo frame

private struct PhotoFrameSettings: View {
    @Environment(HomeStore.self) private var store
    @AppStorage(AmbientSettings.nightEnabledKey) private var nightEnabled = true
    @AppStorage(AmbientSettings.nightStartKey) private var nightStart = NightWindow.default.start
    @AppStorage(AmbientSettings.nightEndKey) private var nightEnd = NightWindow.default.end
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false

    var body: some View {
        let photos = store.snapshot.photos
        SettingsGroup(title: "Photo frame") {
            PhotosPicker(selection: $picked, maxSelectionCount: 30, matching: .images) {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("Add photos")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(importing)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if photos.isEmpty && !importing {
                    Text("Pick a few favorite photos for when the wall is idle. Until then it paints a gentle landscape.")
                        .font(.body(15))
                        .foregroundStyle(Theme.muted)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 10)], spacing: 10) {
                        ForEach(photos) { photo in
                            PhotoThumbnail(url: store.photoLibrary.url(for: photo.fileName))
                                .overlay(alignment: .topTrailing) {
                                    Button { store.remove(photo) } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 26, height: 26)
                                            .background(Color.black.opacity(0.55), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                        if importing {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 90)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                Text("Meal photos from the food diary join in too.")
                    .font(.body(13, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            .padding(10)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 12)
            nightRow
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
    }

    private var nightRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $nightEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dim at night")
                        .font(.body(17, weight: 600))
                    Text("Between these hours the photo frame becomes a dim clock and the screen turns down.")
                        .font(.body(14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.good)
            if nightEnabled {
                HoursField(
                    start: $nightStart,
                    end: $nightEnd,
                    allowsNextDay: true,
                    startSuggestions: [21 * 60, 22 * 60, 23 * 60],
                    endSuggestions: [6 * 60, 7 * 60, 8 * 60],
                    accessibilityLabel: "Night",
                    identifier: "night"
                ) {
                    Text("From").font(.body(15, weight: 700))
                }
            }
        }
        .padding(12)
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        importing = true
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                datas.append(data)
            }
        }
        await store.importPhotos(datas)
        picked = []
        importing = false
    }
}

private struct PhotoThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Color(Theme.surface2)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task(id: url) {
                image = await AmbientPhotoLibrary.loadForDisplay(url, maxPixelSize: 400)
            }
    }
}
