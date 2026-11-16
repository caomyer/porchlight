import PhotosUI
import SwiftUI

private enum HomeSettingsSheet: Identifiable {
    case chore(Chore?)
    case reward(Reward?)
    case photos

    var id: String {
        switch self {
        case let .chore(chore): "chore-\(chore?.id.description ?? "new")"
        case let .reward(reward): "reward-\(reward?.id.description ?? "new")"
        case .photos: "photos"
        }
    }

    var width: CGFloat {
        if case .photos = self { 780 } else { 640 }
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
            PhotoFrameSettings(managePhotos: { present(.photos) })
        }
        .frame(maxWidth: 720, alignment: .leading)
        .wallSheet(item: $sheet, width: sheet?.width ?? 640) { sheet in
            switch sheet {
            case let .chore(chore): ChoreEditor(chore: chore)
            case let .reward(reward): RewardEditor(reward: reward)
            case .photos: PhotoManager()
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
                            : "\(earned[reward.id] ?? 0) of \(reward.targetStars) stars\(reward.isShared ? " together" : "")")
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
    @State private var names: [HomeList.ID: String] = [:]

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
                        .onSubmit { store.rename(list, to: names[list.id] ?? list.title) }
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
        let id = list.id
        return Binding(get: { names[id] ?? list.title }, set: { names[id] = $0 })
    }

    private func add() {
        if store.createList(title: newTitle, kind: newKind) { newTitle = "" }
    }
}

// MARK: - Photo frame

/// Settings > Photo frame: what the idle wall shows, the photos, and night hours.
private struct PhotoFrameSettings: View {
    var managePhotos: () -> Void

    @Environment(HomeStore.self) private var store
    @AppStorage(AmbientSettings.showKey) private var show = FrameShow.photos
    @AppStorage(AmbientSettings.nightEnabledKey) private var nightEnabled = true
    @AppStorage(AmbientSettings.nightStartKey) private var nightStart = NightWindow.default.start
    @AppStorage(AmbientSettings.nightEndKey) private var nightEnd = NightWindow.default.end

    var body: some View {
        SettingsGroup(title: "Photo frame") {
            if show == .photos { AddPhotosButton() }
        } content: {
            showRow
            if show == .photos {
                divider
                photosRow
            }
            divider
            nightRow
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 12)
    }

    private var showRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show")
                    .font(.body(17, weight: 600))
                Text("What the wall shows when nobody's using it.")
                    .font(.body(14))
                    .foregroundStyle(Theme.muted)
            }
            FrameShowPicker(selection: $show)
        }
        .padding(12)
    }

    private var photosRow: some View {
        let count = store.snapshot.photos.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "No photos yet" : "\(count) photo\(count == 1 ? "" : "s")")
                    .font(.body(17, weight: 600))
                    .accessibilityIdentifier("photoCount")
                Text(count == 0 ? "Add a few favorites. Meal photos from the food diary join in too." : "Plus meal photos from the food diary.")
                    .font(.body(14))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if count > 0 {
                Button("Manage", action: managePhotos)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("managePhotos")
            }
        }
        .padding(12)
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
}

/// Our photos or the porch view, as two big halves with a line on what each does.
private struct FrameShowPicker: View {
    @Binding var selection: FrameShow

    var body: some View {
        HStack(spacing: 3) {
            option(.photos, title: "Our photos", detail: "Shuffled, slow drift")
            option(.porchView, title: "Porch view", detail: "A quiet sky, follows the day")
        }
        .padding(3)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func option(_ value: FrameShow, title: String, detail: String) -> some View {
        let isOn = selection == value
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = value }
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.body(15, weight: 700))
                    .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                Text(detail)
                    .font(.body(12, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("show-\(value.rawValue)")
    }
}

/// Picks photos from the iPad's library (up to 30 at a time) and adds them to the frame.
private struct AddPhotosButton: View {
    var title = "Add photos"

    @Environment(HomeStore.self) private var store
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false

    var body: some View {
        // Read here, on the main actor: the picker's label closure isn't isolated to it.
        let isImporting = importing
        let title = title
        PhotosPicker(selection: $picked, maxSelectionCount: 30, matching: .images) {
            HStack(spacing: 6) {
                if isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                }
                Text(isImporting ? "Adding" : title)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(importing)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
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

/// Every photo in the frame, newest first: add more, or select several and remove them.
private struct PhotoManager: View {
    @Environment(HomeStore.self) private var store
    @State private var selecting = false
    @State private var selected: Set<AmbientPhoto.ID> = []

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        let photos = Array(store.snapshot.photos.reversed())
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Our photos")
                        .font(.display(28))
                    Text(photos.isEmpty ? "No photos yet" : "\(photos.count) photo\(photos.count == 1 ? "" : "s") · newest first")
                        .font(.body(14))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                AddPhotosButton(title: "Add")
                Button(selecting ? "Cancel" : "Select") {
                    selecting.toggle()
                    selected = []
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(photos.isEmpty)
                .accessibilityIdentifier("selectPhotos")
            }
            // Room for the sheet's close button.
            .padding(.trailing, 44)

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(photos) { photo in
                        tile(photo)
                    }
                }
            }
            .frame(height: 440)
            .scrollIndicators(.automatic)

            if selecting {
                HStack(spacing: 12) {
                    Text(selected.isEmpty ? "Tap photos to select them." : "\(selected.count) selected")
                        .font(.body(15, weight: 600))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    Button(selected.isEmpty ? "Remove" : "Remove \(selected.count)") {
                        store.remove(photos.filter { selected.contains($0.id) })
                        selected = []
                        selecting = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("removePhotos")
                }
            }
        }
    }

    private func tile(_ photo: AmbientPhoto) -> some View {
        let isSelected = selected.contains(photo.id)
        return Button {
            guard selecting else { return }
            if isSelected { selected.remove(photo.id) } else { selected.insert(photo.id) }
        } label: {
            PhotoThumbnail(url: store.photoLibrary.url(for: photo.fileName), aspectRatio: 1)
                .overlay(alignment: .topLeading) {
                    if let caption = photo.caption {
                        Text(caption)
                            .font(.body(10.5, weight: 700))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.4), in: Capsule())
                            .padding(5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSelected ? Theme.accent : Color.black.opacity(0.25))
                            .padding(6)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(selecting)
        .accessibilityLabel(photo.caption.map { "Photo, \($0)" } ?? "Photo")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("framePhoto")
    }
}

private struct PhotoThumbnail: View {
    let url: URL
    var aspectRatio: CGFloat = 4 / 3
    @State private var image: UIImage?

    var body: some View {
        Color(Theme.surface2)
            .aspectRatio(aspectRatio, contentMode: .fit)
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
