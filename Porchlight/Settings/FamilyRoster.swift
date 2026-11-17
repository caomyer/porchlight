import Foundation

/// Who has the app, as Family & devices (A3, D2) and the phone's You sheet list it: every
/// person with their state, then invites that name nobody yet, then the other shared
/// screens. A pure function of the household, its devices and its share, so every state
/// is tested without iCloud.
struct FamilyRoster: Equatable {
    struct Row: Identifiable, Equatable {
        enum State: Equatable {
            /// Has the app on a device of their own.
            case joined
            /// Invited, and hasn't joined yet.
            case invited
            /// No device of their own: pitches in on a shared screen.
            case noPhone
        }

        var id: String
        /// Nil for an invite that names nobody in the household yet.
        var person: Person?
        var title: String
        var detail: String
        var state: State
        var isOwner: Bool
        /// The share's participant behind it, when the owner can remove them.
        var removable: HouseholdParticipant?
        /// Their own devices, newest first.
        var devices: [Device]
    }

    var rows: [Row]
    /// The other shared screens in the household.
    var sharedScreens: [Device]

    /// "3 people · 2 with the app".
    var summary: String {
        let people = rows.filter { $0.person != nil }.count
        let joined = rows.filter { $0.person != nil && $0.state == .joined }.count
        return "\(people) \(people == 1 ? "person" : "people") · \(joined) with the app"
    }

    /// - Parameters:
    ///   - thisDevice: This device's row id, left out of the shared screens.
    ///   - thisUserName: This device's iCloud user, which owns a household that has no share yet.
    ///   - onSharedScreen: Whether this device is a shared screen, where people without a
    ///     phone pitch in.
    init(
        snapshot: HouseholdSnapshot, members: HouseholdMembers, thisDevice: Device.ID?, thisUserName: String?,
        onSharedScreen: Bool, now: Date = .now
    ) {
        let calendar = snapshot.household?.calendar ?? .current
        let ownerUser = members.owner?.userName ?? (members.participants.isEmpty ? thisUserName : nil)
        var unmatched = members.participants.filter { $0.role != .owner }

        // Once the share is known, a personal device whose iCloud user is neither the owner
        // nor someone who joined is left over from someone who was removed: it says so.
        let shareKnown = !members.participants.isEmpty
        func stillIn(_ device: Device) -> Bool {
            guard shareKnown, device.role == .personal, let user = device.userName else { return true }
            return user == ownerUser || members.participant(userName: user)?.status == .joined
        }
        var rows: [Row] = snapshot.people.map { person in
            let all = snapshot.devices(of: person.id)
            let devices = all.filter(stillIn)
            let leftOver = all.filter { !stillIn($0) }
            let isOwner = ownerUser != nil && devices.contains { $0.userName == ownerUser }
            let participant = devices.lazy.compactMap { members.participant(userName: $0.userName) }.first
                ?? (devices.isEmpty ? unmatched.first { $0.status == .invited && $0.names(person) } : nil)
            unmatched.removeAll { $0.id == participant?.id }
            let state: Row.State = !devices.isEmpty ? .joined : (participant?.status == .invited ? .invited : .noPhone)
            let detail: String
            switch state {
            case .joined:
                var names: [String] = []
                for name in devices.map(\.name) where !names.contains(name) { names.append(name) }
                let seen = Self.seen(devices[0].seenAt, now: now, calendar: calendar)
                detail = ((isOwner ? ["Owner"] : []) + names + [seen]).joined(separator: " · ")
            case .invited:
                detail = "Invited, hasn't joined yet"
            case .noPhone:
                detail = !leftOver.isEmpty
                    ? "Not joined: \(leftOver[0].name) no longer has access"
                    : onSharedScreen ? "Pitches in on this screen" : "No phone yet"
            }
            return Row(
                id: person.id.description, person: person, title: person.name, detail: detail, state: state,
                isOwner: isOwner,
                removable: members.isOwner && !isOwner && state == .joined ? participant : nil,
                devices: devices
            )
        }
        // People who joined or were invited and haven't said who they are yet.
        rows += unmatched.map { participant in
            Row(
                id: participant.id, person: nil, title: participant.name ?? "Someone with the link",
                detail: participant.status == .joined ? "Joined, hasn't picked who they are yet" : "Invited, hasn't joined yet",
                state: participant.status == .joined ? .joined : .invited, isOwner: false,
                removable: members.isOwner && participant.status == .joined ? participant : nil, devices: []
            )
        }
        self.rows = rows
        sharedScreens = snapshot.devices.filter { $0.role == .sharedScreen && $0.id != thisDevice }
    }

    /// "used today", "used yesterday", "used Nov 12".
    static func seen(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "used today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "used yesterday"
        }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return "used \(date.formatted(style))"
    }
}

private extension HouseholdParticipant {
    /// An invite names a person when iCloud's first name for them is theirs.
    func names(_ person: Person) -> Bool {
        guard let first = name?.split(separator: " ").first else { return false }
        return first.caseInsensitiveCompare(person.name.split(separator: " ").first ?? "") == .orderedSame
    }
}
