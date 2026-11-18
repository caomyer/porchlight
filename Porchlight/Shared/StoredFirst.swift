import Observation

/// An `@Observable` type's property that is stored before observers are told it changed.
///
/// `@Observable` tells observers in `willSet`, and SwiftUI may redraw right there when other
/// updates are pending. A screen redrawn then reads the old value and misses the change, so
/// it stays out of date until something else redraws it (a chore still checked after Undo,
/// "Allow calendar access" after Allow). A value that arrives from outside a SwiftUI action
/// (the database, iCloud, the network, a timer, a system callback) is at risk.
///
/// Use it with `@ObservationIgnored`, so the macro leaves the property to it:
///
///     @ObservationIgnored @StoredFirst var members: HouseholdMembers = .none
///
/// The type conforms to `StoredFirstObservable`, which its `@Observable` macro already
/// satisfies; `AppModel.snapshot` and the stores' snapshots do the same by hand.
@MainActor
@propertyWrapper
struct StoredFirst<Value> {
    private var value: Value

    init(wrappedValue: Value) {
        value = wrappedValue
    }

    @available(*, unavailable, message: "Only for properties of an @Observable type")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    static subscript<Owner: StoredFirstObservable>(
        _enclosingInstance owner: Owner,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Owner, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Owner, StoredFirst<Value>>
    ) -> Value {
        get {
            owner.access(keyPath: wrappedKeyPath)
            return owner[keyPath: storageKeyPath].value
        }
        set {
            owner[keyPath: storageKeyPath].value = newValue
            owner.withMutation(keyPath: wrappedKeyPath) {}
        }
    }
}

/// An `@Observable` type: the macro gives it both methods.
@MainActor
protocol StoredFirstObservable: AnyObject, Observable {
    nonisolated func access<Member>(keyPath: KeyPath<Self, Member>)
    nonisolated func withMutation<Member, MutationResult>(keyPath: KeyPath<Self, Member>, _ mutation: () throws -> MutationResult) rethrows -> MutationResult
}
