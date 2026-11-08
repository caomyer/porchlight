import SwiftUI

struct ChoresScreen: View {
    var body: some View { EmptyState(symbol: "checkmark.square", title: "Chores", message: "Coming soon.") }
}

struct ListsScreen: View {
    var body: some View { EmptyState(symbol: "list.bullet", title: "Lists", message: "Coming soon.") }
}

/// Full-screen photo frame shown when the wall is idle, or from the rail (STUB).
/// `photoURLs` are extra photos from other features (meal photos).
struct AmbientView: View {
    var extraPhotoURLs: [URL]
    var onWake: () -> Void
    var body: some View { Color.black.onTapGesture(perform: onWake) }
}

/// Chores, lists and display sections inside Settings (STUB).
struct HomeSettingsSection: View {
    var body: some View { EmptyView() }
}
