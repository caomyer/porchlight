import GRDB
import Observation
import SwiftUI

/// A row another device wrote, as the wall names it.
struct ArrivedRow: Equatable, Sendable {
    enum Kind: String, Sendable { case care, meal, chore, reward, list }

    var kind: Kind
    var rowId: String
    var deviceId: Device.ID
    /// The companion, the dish, the chore, the reward or the item.
    var subject: String
    /// The routine's kind, the meal's slot or the list's title.
    var detail: String?
    /// The routine's title.
    var title: String?

    /// "James walked Yo-Yo", "Mia added lunch: Pho".
    func sentence(who: String) -> String {
        switch kind {
        case .care:
            let kind = detail.flatMap(CareKind.init(rawValue:)) ?? .custom
            return kind.sentence(who: who, name: subject, title: title ?? kind.defaultTitle)
        case .meal: return "\(who) added \(detail?.lowercased() ?? "a meal"): \(subject)"
        case .chore: return "\(who) did \(subject)"
        case .reward: return "\(who) cashed in \(subject)"
        case .list: return "\(who) added \(subject)\(detail.map { " to \($0)" } ?? "")"
        }
    }

    /// Rows written by any device but `excluded` since `since`, newest first.
    static func fetch(_ db: Database, excluding excluded: Device.ID?, since: Date) throws -> [ArrivedRow] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT 'care' AS kind, careLog.id, careLog.deviceId, careLog.createdAt AS at,
                   companion.name AS subject, careRoutine.kind AS detail, careRoutine.title AS title
            FROM careLog JOIN careRoutine ON careRoutine.id = careLog.careRoutineId
            JOIN companion ON companion.id = careRoutine.companionId
            WHERE careLog.deviceId IS NOT NULL AND careLog.deviceId IS NOT :excluded AND careLog.createdAt >= :since
            UNION ALL
            SELECT 'meal', id, deviceId, createdAt, title, slot, NULL FROM journalEntry
            WHERE deviceId IS NOT NULL AND deviceId IS NOT :excluded AND createdAt >= :since
            UNION ALL
            SELECT 'chore', choreCompletion.id, choreCompletion.deviceId, choreCompletion.completedAt, chore.title, NULL, NULL
            FROM choreCompletion JOIN chore ON chore.id = choreCompletion.choreId
            WHERE choreCompletion.deviceId IS NOT NULL AND choreCompletion.deviceId IS NOT :excluded AND choreCompletion.completedAt >= :since
            UNION ALL
            SELECT 'reward', rewardRedemption.id, rewardRedemption.deviceId, rewardRedemption.redeemedAt, reward.title, NULL, NULL
            FROM rewardRedemption JOIN reward ON reward.id = rewardRedemption.rewardId
            WHERE rewardRedemption.deviceId IS NOT NULL AND rewardRedemption.deviceId IS NOT :excluded AND rewardRedemption.redeemedAt >= :since
            UNION ALL
            SELECT 'list', listItem.id, listItem.deviceId, listItem.createdAt, listItem.title, homeList.title, NULL
            FROM listItem JOIN homeList ON homeList.id = listItem.listId
            WHERE listItem.deviceId IS NOT NULL AND listItem.deviceId IS NOT :excluded AND listItem.createdAt >= :since
            ORDER BY at DESC
            """, arguments: ["excluded": excluded, "since": since])
        return rows.compactMap { row in
            guard let kind = Kind(rawValue: row["kind"]), let deviceId = (row["deviceId"] as String?).flatMap(Device.ID.init) else { return nil }
            return ArrivedRow(kind: kind, rowId: row["id"], deviceId: deviceId, subject: row["subject"], detail: row["detail"], title: row["title"])
        }
    }
}

/// What arrived from people's phones while the wall was showing (journey D1): which rows
/// glow, once, and the one short toast that names who did it. A burst after being offline
/// gives one toast that sums it up. Nothing loops, and nothing shows while the wall rests.
@MainActor
@Observable
final class WallArrivals {
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        var text: String
        /// Whose avatar leads it; nil for several people.
        var person: Person?
    }

    /// Rows that just arrived, glowing once.
    private(set) var fresh: Set<String> = []
    private(set) var toast: Toast?
    /// The wall is resting (the photo frame): rows are noted, quietly.
    @ObservationIgnored var isResting = false

    @ObservationIgnored private var seen: Set<String>?
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    /// How long a toast stays, and how long a row counts as fresh.
    static let showFor: Duration = .seconds(6)

    /// Takes the rows the database has now. The first call only notes what is there.
    func update(_ rows: [ArrivedRow], snapshot: HouseholdSnapshot) {
        let ids = Set(rows.map(\.rowId))
        guard let seen else {
            self.seen = ids
            return
        }
        self.seen = seen.union(ids)
        let new = rows.filter { !seen.contains($0.rowId) && snapshot.tag(for: $0.deviceId) != nil }
        guard !new.isEmpty, !isResting else { return }
        fresh.formUnion(new.map(\.rowId))
        toast = Self.toast(for: new, snapshot: snapshot)
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showFor)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                self?.toast = nil
                self?.fresh = []
            }
        }
    }

    /// "James walked Yo-Yo · from their phone", or "3 updates from James's and Mia's phones".
    static func toast(for rows: [ArrivedRow], snapshot: HouseholdSnapshot) -> Toast? {
        let devices = rows.compactMap { row in snapshot.devices.first { $0.id == row.deviceId } }
        var people: [Person] = []
        for device in devices {
            if let person = snapshot.everyone.person(device.owner), !people.contains(where: { $0.id == person.id }) {
                people.append(person)
            }
        }
        guard let first = rows.first, let firstPerson = people.first else { return nil }
        if rows.count == 1 {
            let kind = devices.first?.kindWord ?? "phone"
            return Toast(text: "\(first.sentence(who: firstPerson.name)) · from their \(kind)", person: firstPerson)
        }
        let whose = ListFormatter.localizedString(byJoining: people.map { $0.name.possessive })
        let kinds = Set(devices.map(\.kindWord))
        let word = kinds.count == 1 ? kinds.first! : "device"
        return Toast(
            text: "\(rows.count) updates from \(whose) \(people.count == 1 ? word : word + "s")",
            person: people.count == 1 ? firstPerson : nil
        )
    }
}

/// The wall's toast for arrivals: a dark capsule at the top, with who did it.
struct ArrivalToastView: View {
    let toast: WallArrivals.Toast

    var body: some View {
        HStack(spacing: 11) {
            if let person = toast.person {
                Avatar(person: person, size: 29)
            } else {
                AnyoneAvatar(size: 29)
            }
            Text(toast.text)
                .font(.body(17, weight: 700))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.toastInk)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .background(Theme.toast, in: Capsule())
        .shadow(color: Color(hex: 0x28_190A).opacity(0.18), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("arrival-toast")
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: toast.text)
        }
    }
}

extension EnvironmentValues {
    /// Rows that just arrived from someone's phone, by row id, glowing once on Today.
    @Entry var freshRows: Set<String> = []
}

extension View {
    /// Watches for rows from people's phones and shows the toast over the wall, unless it
    /// is resting.
    func showsArrivals(resting: Bool) -> some View {
        modifier(ArrivalsHost(resting: resting))
    }
}

private struct ArrivalsHost: ViewModifier {
    let resting: Bool
    @Environment(AppModel.self) private var model
    @State private var arrivals = WallArrivals()

    func body(content: Content) -> some View {
        content
            .environment(\.freshRows, arrivals.fresh)
            .overlay(alignment: .top) {
                if let toast = arrivals.toast, !resting {
                    ArrivalToastView(toast: toast)
                        .padding(.top, 18)
                        .padding(.leading, Theme.railWidth)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .animation(.easeOut(duration: 0.3), value: arrivals.toast)
            .onChange(of: resting, initial: true) { _, resting in arrivals.isResting = resting }
            .task(id: model.thisDeviceId) {
                let excluded = model.thisDeviceId
                // Today's arrivals and a little before: enough to tell new rows from old.
                let since = Date.now.addingTimeInterval(-24 * 3600)
                let updates = ValueObservation
                    .tracking { try ArrivedRow.fetch($0, excluding: excluded, since: since) }
                    .removeDuplicates()
                do {
                    for try await rows in updates.values(in: model.database.writer) {
                        arrivals.update(rows, snapshot: model.snapshot)
                    }
                } catch {}
            }
    }
}
