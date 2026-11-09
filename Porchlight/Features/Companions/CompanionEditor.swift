import PhotosUI
import SwiftUI

// Setting up companions: the onboarding step, the Settings section, and the
// shared editor (species, name, look, routines, caption personality, preview).

// MARK: - Onboarding

/// "Who else lives here?" Edits save as you go once the companion has a name,
/// so the host's Continue button needs no hook. Skipping is just not typing a name.
struct CompanionOnboardingEditor: View {
    @Environment(CompanionStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var draft = CompanionDraft.new(species: .dog)
    @State private var routinesEdited = false
    @State private var savedPhoto: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var didStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeading(title: "Who else lives here?", subtitle: "Pets, plants, anything that needs looking after. Skip if it's just humans.")
            if store.companions.count > (draft.companionId == nil ? 0 : 1) {
                savedRow
            }
            CompanionEditorForm(draft: $draft, routinesEdited: $routinesEdited, compact: true)
            HStack(spacing: 12) {
                Button(action: addAnother) {
                    Label("Add another companion", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(draft.companionId == nil)
                if let error = store.lastError, !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(error).font(.body(13, weight: 600)).foregroundStyle(Theme.accent)
                }
            }
        }
        // Win the host's spare height over its Spacer, so the routine list shows in full.
        .frame(maxHeight: .infinity, alignment: .top)
        .layoutPriority(1)
        .onAppear(perform: start)
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onDisappear { saveNow() }
    }

    /// Companions already added in this step (or before), tap to edit.
    private var savedRow: some View {
        HStack(spacing: 8) {
            ForEach(store.snapshot.companions.filter { $0.id != draft.companionId }) { companion in
                Button { edit(companion) } label: {
                    HStack(spacing: 8) {
                        CompanionFace(look: CompanionLook(companion), size: 26)
                        Text(companion.name).font(.body(14, weight: 700))
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.good)
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.line))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        // Resume the first companion if setup was interrupted, else start a fresh dog.
        if let first = store.snapshot.companions.first, let id = first.id {
            draft = CompanionDraft(first, routines: store.snapshot.routines(of: id))
            routinesEdited = true
            savedPhoto = first.photoFile
        } else {
            draft = .new(species: .dog)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let id = store.save(draft, previousPhoto: savedPhoto) {
            savedPhoto = draft.photoFile
            if draft.companionId == nil {
                // Keep routine ids in sync so later saves update rather than duplicate.
                draft.companionId = id
                draft.routines = store.snapshot.routines(of: id).map(CareRoutineDraft.init)
            }
        }
    }

    private func addAnother() {
        saveNow()
        draft = .new(species: .dog)
        routinesEdited = false
        savedPhoto = nil
    }

    private func edit(_ companion: Companion) {
        saveNow()
        guard let id = companion.id else { return }
        draft = CompanionDraft(companion, routines: store.snapshot.routines(of: id))
        routinesEdited = true
        savedPhoto = companion.photoFile
    }
}

// MARK: - Settings

struct CompanionSettingsList: View {
    @Environment(CompanionStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var editing: EditingCompanion?
    @State private var removing: Companion?

    struct EditingCompanion: Identifiable {
        var draft: CompanionDraft
        var id: String { draft.companionId.map { "c\($0)" } ?? "new" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Companions")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(store.snapshot.companions) { companion in
                    row(companion)
                }
                HStack(spacing: 12) {
                    Button {
                        CompanionCover.instantly {
                            editing = EditingCompanion(draft: .new(species: .dog))
                        }
                    } label: {
                        Label(store.companions.isEmpty ? "Add a pet or plant" : "Add a companion", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if store.companions.isEmpty {
                        Text("Pets, plants, anything that needs looking after.")
                            .font(.body(14))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
        .wallCover(item: $editing) { item in
            CompanionEditSheet(initial: item.draft) {
                CompanionCover.instantly { editing = nil }
            }
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove and delete history", role: .destructive) {
                if let id = removing?.id { store.delete(companionId: id) }
                removing = nil
            }
        } message: {
            Text("Their routines and every logged walk or meal go too. This can't be undone.")
        }
        #if DEBUG
        .onAppear {
            if ["editor", "routine"].contains(UserDefaults.standard.string(forKey: "debugCompanionSheet")), let first = store.snapshot.companions.first, let id = first.id {
                CompanionCover.instantly { editing = EditingCompanion(draft: CompanionDraft(first, routines: store.snapshot.routines(of: id))) }
            }
        }
        #endif
    }

    private func row(_ companion: Companion) -> some View {
        let routines = store.snapshot.routines(of: companion.id ?? -1)
        return HStack(spacing: 14) {
            CompanionFace(look: CompanionLook(companion), size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(companion.name).font(.body(17, weight: 700))
                Text(([companion.about.isEmpty ? companion.species.label : companion.about]
                      + routines.map { "\($0.emoji) \($0.title) \($0.cadenceText(calendar: .current))" }).joined(separator: " · "))
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Edit") {
                CompanionCover.instantly {
                    editing = EditingCompanion(draft: CompanionDraft(companion, routines: routines))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            Button { removing = companion } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 38, height: 38)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(companion.name)")
        }
        .padding(12)
        .background(SurfaceShape(cornerRadius: Theme.smallRadius + 4, elevation: 0.7))
    }
}

/// The companion editor in a sheet, with Save and Cancel.
private struct CompanionEditSheet: View {
    let initial: CompanionDraft
    let onClose: () -> Void

    @Environment(CompanionStore.self) private var store
    @State private var draft: CompanionDraft
    @State private var routinesEdited: Bool
    @State private var isShown = false

    init(initial: CompanionDraft, onClose: @escaping () -> Void) {
        self.initial = initial
        self.onClose = onClose
        _draft = State(initialValue: initial)
        _routinesEdited = State(initialValue: initial.companionId != nil)
    }

    var body: some View {
        WallSheet(width: 1000, onClose: cancel) {
            VStack(alignment: .leading, spacing: 16) {
                Text(initial.companionId == nil ? "Add a companion" : "Edit \(initial.name)")
                    .font(.display(30))
                CompanionEditorForm(draft: $draft, routinesEdited: $routinesEdited, compact: false)
                HStack {
                    if let error = store.lastError {
                        Text(error).font(.body(14, weight: 600)).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Button("Cancel", action: cancel).buttonStyle(SecondaryButtonStyle())
                    Button("Save", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxHeight: 720)
        }
        .opacity(isShown ? 1 : 0)
        .onAppear {
            store.lastError = nil
            withAnimation(.easeOut(duration: 0.2)) { isShown = true }
        }
    }

    private func save() {
        guard store.save(draft, previousPhoto: initial.photoFile) != nil else { return }
        close()
    }

    private func cancel() {
        // A photo picked but never saved is an orphan file.
        if let photo = draft.photoFile, photo != initial.photoFile { CompanionPhotoStore.shared.delete(photo) }
        store.lastError = nil
        close()
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { isShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }
}

// MARK: - Shared form

/// Species, name, look, routines, caption personality and a live preview.
struct CompanionEditorForm: View {
    @Binding var draft: CompanionDraft
    /// Once routines are touched, switching species no longer replaces them with presets.
    @Binding var routinesEdited: Bool
    /// Onboarding layout: details live under the preview to keep the page short.
    var compact: Bool

    @Environment(AppModel.self) private var model
    @State private var editingRoutine: RoutineEditing?
    @State private var photoItem: PhotosPickerItem?

    struct RoutineEditing: Identifiable {
        var draft: CareRoutineDraft
        var isNew: Bool
        var id: UUID { draft.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            speciesTiles
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        field("Name") {
                            TextField("e.g. Biscuit", text: $draft.name)
                                .font(.body(15, weight: 700))
                                .textInputAutocapitalization(.words)
                                .fieldStyle()
                        }
                        .frame(maxWidth: 260)
                        field("Look") { lookPicker }
                            .fixedSize()
                    }
                    SectionLabel("Care routines")
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(draft.routines) { routine in
                                RoutineRow(routine: routine) {
                                    present(RoutineEditing(draft: routine, isNew: false))
                                }
                            }
                            addRoutineRow
                        }
                        // Room for the cards' shadows inside the clip.
                        .padding(6)
                    }
                    .padding(-6)
                    // Two preset routines plus "Add routine" fit without scrolling on the wall.
                    .frame(minHeight: 250)
                    .scrollBounceBehavior(.basedOnSize)
                    field("Caption personality") {
                        HStack(spacing: 6) {
                            ForEach(CompanionTone.allCases, id: \.self) { tone in
                                Button { draft.tone = tone } label: {
                                    Text(tone.label)
                                        .font(.body(13, weight: 700))
                                        .foregroundStyle(draft.tone == tone ? Theme.surface : Theme.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(draft.tone == tone ? Theme.ink : Theme.surface2, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 12) {
                    CompanionPreviewCard(draft: draft)
                    detailsFields
                }
                .frame(width: 290)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .wallCover(item: $editingRoutine) { item in
            RoutineEditorSheet(
                initial: item.draft,
                isNew: item.isNew,
                companionName: draft.name.isEmpty ? draft.species.label.lowercased() : draft.name,
                onSave: { saved in
                    if let index = draft.routines.firstIndex(where: { $0.id == saved.id }) {
                        draft.routines[index] = saved
                    } else {
                        draft.routines.append(saved)
                    }
                    routinesEdited = true
                },
                onDelete: {
                    draft.routines.removeAll { $0.id == item.draft.id }
                    routinesEdited = true
                },
                onClose: { CompanionCover.instantly { editingRoutine = nil } }
            )
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let file = try? CompanionPhotoStore.shared.save(imageData: data) {
                    draft.photoFile = file
                }
                photoItem = nil
            }
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "debugCompanionSheet") == "routine", let first = draft.routines.first {
                present(RoutineEditing(draft: first, isNew: false))
            }
        }
        #endif
    }

    private func present(_ editing: RoutineEditing) {
        CompanionCover.instantly { editingRoutine = editing }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            content()
        }
    }

    private var speciesTiles: some View {
        HStack(spacing: 10) {
            ForEach(Species.allCases.filter { $0 != .other || !compact }, id: \.self) { species in
                let isSelected = draft.species == species
                Button { choose(species) } label: {
                    VStack(spacing: 2) {
                        Text(species.emoji).font(.system(size: 30))
                        Text(species.label).font(.body(13.5, weight: 700)).foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(SurfaceShape(cornerRadius: Theme.smallRadius, fill: isSelected ? Theme.accent.wash(0.08) : Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func choose(_ species: Species) {
        guard species != draft.species else { return }
        draft.species = species
        if !routinesEdited {
            draft.routines = CompanionPresets.routines(for: species)
        }
    }

    private var lookPicker: some View {
        HStack(spacing: 8) {
            ForEach(CoatPreset.allCases, id: \.self) { coat in
                let isSelected = draft.photoFile == nil && draft.coat == coat
                Button {
                    draft.coat = coat
                    draft.photoFile = nil
                } label: {
                    Circle()
                        .fill(coat.main)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                        .frame(width: 30, height: 30)
                        .padding(2)
                        .overlay(Circle().stroke(isSelected ? Theme.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(coat.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            let hasPhoto = draft.photoFile != nil
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 5) {
                    Image(systemName: hasPhoto ? "checkmark.circle.fill" : "camera")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Photo")
                }
                    .font(.body(12.5, weight: 700))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasPhoto ? Theme.surface2 : Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.line))
            }
        }
        .frame(height: 44)
    }

    private var addRoutineRow: some View {
        Button {
            let kind: CareKind = draft.species == .plant ? .water : .custom
            var routine = CareRoutineDraft(kind: kind, windows: CompanionPresets.windows(count: 1))
            routine.title = kind == .custom ? "" : routine.title
            present(RoutineEditing(draft: routine, isNew: true))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add routine").font(.body(15, weight: 700))
                    Text("Meds, grooming, vet visits, litter, watering...")
                        .font(.body(12.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Optional "about" line and birthday, shown under the name on the companion page.
    private var detailsFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Details")
            TextField(aboutPlaceholder, text: $draft.about)
                .font(.body(14, weight: 600))
                .fieldStyle()
            HStack {
                Toggle(isOn: Binding(
                    get: { draft.birthDate != nil },
                    set: { draft.birthDate = $0 ? (draft.birthDate ?? Calendar.current.date(byAdding: .year, value: -1, to: .now)) : nil }
                )) {
                    Text("Birthday").font(.body(14, weight: 700))
                }
                .tint(Theme.good)
                .fixedSize()
                Spacer()
                if let birth = draft.birthDate {
                    DatePicker("Birthday", selection: Binding(get: { birth }, set: { draft.birthDate = $0 }), in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var aboutPlaceholder: String {
        switch draft.species {
        case .dog: "Breed, e.g. Toy poodle"
        case .cat: "e.g. Tabby, indoor"
        case .plant: "e.g. Fiddle-leaf fig"
        default: "A few words"
        }
    }
}

/// One routine in the editor: "Walk · 2× a day", windows and tags.
private struct RoutineRow: View {
    let routine: CareRoutineDraft
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(routine.emoji)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(CoatPreset.honey.tint.wash(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(routine.title) · \(routine.routine().cadenceText(calendar: .current))").font(.body(15, weight: 700))
                Text(meta)
                    .font(.body(12.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if !tags.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.body(11.5, weight: 700))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Theme.surface2, in: Capsule())
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            Button("Edit", action: onEdit)
                .font(.body(13, weight: 700))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.line))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(SurfaceShape(cornerRadius: Theme.smallRadius))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }

    private var meta: String {
        let windows = routine.routine().effectiveWindows
        let parts = windows.allSatisfy(\.isAllDay) ? ["Any time of day"] : windows.map { "\($0.label) \($0.rangeText)" }
        return parts.joined(separator: " · ")
    }

    private var tags: [String] {
        var tags = CareField.allCases.filter(routine.trackedFields.contains).map(\.label)
        if routine.stars > 0 {
            let noun = routine.kind.noun(title: routine.title)
            tags.append(routine.stars == 1 ? "⭐ 1 per \(noun)" : "⭐ \(routine.stars) each")
        }
        return tags
    }
}

/// The live preview: what the Today card will look like.
private struct CompanionPreviewCard: View {
    let draft: CompanionDraft

    var body: some View {
        let look = CompanionLook(draft)
        let name = draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Your \(draft.species.label.lowercased())" : draft.name
        let first = draft.routines.first?.routine()
        VStack(alignment: .leading, spacing: 0) {
            Text("PREVIEW")
                .font(.body(11, weight: 800))
                .tracking(1.1)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 14) {
                CompanionFace(look: look, size: 66)
                    .frame(width: 78, height: 78)
                    .background(look.tint.wash(0.3), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.display(26)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(first.map { "Waiting for first \($0.kind.noun(title: $0.title))" } ?? draft.species.label)
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.top, 8)
            if let first {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(first.effectiveWindows.enumerated()), id: \.offset) { index, window in
                        SlotTile(
                            slot: CareSlot(index: index, window: window, entry: nil, state: .upcoming),
                            title: window.isAllDay ? first.title : window.label,
                            carers: nil,
                            pendingDetail: window.isAllDay ? first.cadenceText(calendar: .current) : window.rangeText,
                            doneDetail: "",
                            compact: true
                        )
                    }
                }
                .padding(.top, 14)
            }
            Text("\"\(CompanionPresets.welcome(name: name, routines: draft.routines))\"")
                .font(.body(13, weight: 600))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PetCardBackground(tint: look.tint))
        .foregroundStyle(Theme.ink)
    }
}

// MARK: - Routine editor

private struct RoutineEditorSheet: View {
    let initial: CareRoutineDraft
    let isNew: Bool
    let companionName: String
    let onSave: (CareRoutineDraft) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @State private var draft: CareRoutineDraft
    @State private var repeatChoice: RepeatChoice?
    @State private var error: String?
    @State private var isShown = false
    @State private var confirmDelete = false

    init(initial: CareRoutineDraft, isNew: Bool, companionName: String,
         onSave: @escaping (CareRoutineDraft) -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.initial = initial
        self.isNew = isNew
        self.companionName = companionName
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        _draft = State(initialValue: initial)
    }

    var body: some View {
        WallSheet(width: 900, onClose: close) {
            VStack(alignment: .leading, spacing: 0) {
                Text(isNew ? "New routine" : "Edit \(initial.title.lowercased())")
                    .font(.display(30))
                    .padding(.trailing, 50)
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 0) {
                        label("Kind")
                        FlowLayout(spacing: 6) {
                            ForEach(CareKind.allCases, id: \.self) { kind in
                                ChoicePill(title: "\(kind.defaultEmoji) \(kind == .custom ? "Custom" : kind.defaultTitle)", isSelected: draft.kind == kind) {
                                    choose(kind)
                                }
                            }
                        }
                        label("Name")
                        HStack(spacing: 10) {
                            TextField("Emoji", text: $draft.emoji)
                                .font(.system(size: 20))
                                .multilineTextAlignment(.center)
                                .fieldStyle()
                                .frame(width: 64)
                            TextField("e.g. Brush teeth", text: $draft.title)
                                .font(.body(16, weight: 700))
                                .textInputAutocapitalization(.sentences)
                                .fieldStyle()
                        }
                        label("How often")
                        cadence
                        label("Times of day")
                        windows
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        label("Log details")
                        FlowLayout(spacing: 6) {
                            ForEach(CareField.allCases, id: \.self) { field in
                                ChoicePill(title: field.label, isSelected: draft.trackedFields.contains(field)) {
                                    if let index = draft.trackedFields.firstIndex(of: field) {
                                        draft.trackedFields.remove(at: index)
                                    } else {
                                        draft.trackedFields.append(field)
                                    }
                                }
                            }
                        }
                        label("Stars each time")
                        stepper(value: $draft.stars, range: 0...CareRules.maxStars) { "⭐ \($0)" }
                        label("Flag as due")
                        FlowLayout(spacing: 6) {
                            ForEach([nil, 30, 60, 120] as [Int?], id: \.self) { minutes in
                                ChoicePill(title: nudgeTitle(minutes), isSelected: draft.nudgeAfterMinutes == minutes) {
                                    draft.nudgeAfterMinutes = minutes
                                }
                            }
                        }
                    }
                    .frame(width: 330, alignment: .leading)
                }
                HStack(spacing: 10) {
                    if !isNew {
                        Button("Delete routine", role: .destructive) { confirmDelete = true }
                            .buttonStyle(SecondaryButtonStyle())
                            .foregroundStyle(Theme.accent)
                    }
                    if let error {
                        Text(error).font(.body(14, weight: 600)).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Button("Cancel", action: close).buttonStyle(SecondaryButtonStyle())
                    Button("Done", action: save).buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 22)
            }
        }
        .opacity(isShown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { isShown = true } }
        .confirmationDialog("Delete this routine?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete routine and its history", role: .destructive) {
                onDelete()
                close()
            }
        } message: {
            Text("Saving the companion removes \(initial.title.lowercased()) and everything logged for it.")
        }
    }

    private func label(_ text: String) -> some View {
        SectionLabel(text).padding(.top, 16).padding(.bottom, 8)
    }

    private func choose(_ kind: CareKind) {
        let defaultTitles = Set(CareKind.allCases.map(\.defaultTitle)).union([""])
        if defaultTitles.contains(draft.title) { draft.title = kind == .custom ? "" : kind.defaultTitle }
        if CareKind.allCases.map(\.defaultEmoji).contains(draft.emoji) || draft.emoji.isEmpty { draft.emoji = kind.defaultEmoji }
        if kind == .walk && draft.trackedFields.isEmpty { draft.trackedFields = CareField.allCases }
        draft.kind = kind
    }

    /// The same repeat picker chores use, minus "Just once".
    @ViewBuilder
    private var cadence: some View {
        let calendar = model.calendar
        if repeatChoice == nil {
            Color.clear.frame(height: 1).onAppear {
                repeatChoice = RepeatChoice(recurrence: draft.recurrence, start: draft.startDay ?? DayKey(.now, calendar: calendar), calendar: calendar)
            }
        } else {
            RepeatPicker(
                choice: Binding(get: { repeatChoice! }, set: { repeatChoice = $0 }),
                kinds: [.daily, .weekdays, .interval, .monthly],
                calendar: calendar,
                today: DayKey(.now, calendar: calendar),
                maxInterval: CareRules.maxEveryDays
            )
        }
    }

    private func resizeWindows(to count: Int) {
        let defaults = CompanionPresets.windows(count: count)
        if count > draft.windows.count {
            draft.windows = Array(draft.windows.prefix(count)) + defaults.suffix(count - draft.windows.count)
            draft.windows.sort { $0.start < $1.start }
        } else {
            draft.windows = Array(draft.windows.prefix(count))
        }
    }

    private var windows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { draft.windows.first?.isAllDay ?? true },
                    set: { draft.windows = $0 ? [.anyTime] : CompanionPresets.windows(count: 1) }
                )) {
                    Text("Any time of day").font(.body(15, weight: 600))
                }
                .tint(Theme.good)
                .fixedSize()
                Spacer(minLength: 0)
                if !(draft.windows.first?.isAllDay ?? true) {
                    stepper(value: Binding(
                        get: { draft.windows.count },
                        set: { count in resizeWindows(to: count) }
                    ), range: 1...4) { "\($0)× a day" }
                }
            }
            ForEach(draft.windows.indices, id: \.self) { index in
                if !draft.windows[index].isAllDay {
                    WindowRow(window: $draft.windows[index])
                }
            }
        }
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, text: @escaping (Int) -> String) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value.wrappedValue > range.lowerBound) { value.wrappedValue -= 1 }
            Text(text(value.wrappedValue))
                .font(.body(14.5, weight: 700))
                .monospacedDigit()
                .frame(minWidth: 96)
            stepButton("plus", enabled: value.wrappedValue < range.upperBound) { value.wrappedValue += 1 }
        }
        .padding(3)
        .background(Theme.surface2, in: Capsule())
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func nudgeTitle(_ minutes: Int?) -> String {
        guard let minutes else { return "Never" }
        return minutes < 60 ? "After \(minutes) min" : "After \(minutes / 60) hr"
    }

    private func save() {
        if let repeatChoice {
            draft.recurrence = repeatChoice.recurrence
            draft.startDay = repeatChoice.startDay(calendar: model.calendar)
        }
        do {
            let checked = try CareRules.validated(draft, companionId: 0, sortOrder: 0)
            var result = draft
            result.title = checked.title
            result.emoji = checked.emoji
            result.windows = checked.windows
            onSave(result)
            close()
        } catch {
            self.error = error.userMessage
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { isShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }
}

/// One time-of-day window: label, from, to.
private struct WindowRow: View {
    @Binding var window: CareWindow

    var body: some View {
        HStack(spacing: 8) {
            TextField("Label", text: $window.label)
                .font(.body(14.5, weight: 700))
                .fieldStyle()
                .frame(width: 130)
            DatePicker("From", selection: time(\.start), displayedComponents: .hourAndMinute)
                .labelsHidden()
            Text("to").font(.body(14, weight: 600)).foregroundStyle(Theme.muted)
            DatePicker("To", selection: time(\.end), displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    /// Minutes from midnight as a Date on a fixed reference day.
    private func time(_ keyPath: WritableKeyPath<CareWindow, Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return Binding(
            get: { calendar.date(byAdding: .minute, value: min(window[keyPath: keyPath], 1439), to: base) ?? base },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                window[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
