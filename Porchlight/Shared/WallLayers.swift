import SwiftUI

// Sheets that cover the whole wall, drawn as layers over the root view.
//
// They used to be full-screen covers with a clear presentation background, so a
// `WallSheet` could dim the wall instead of hiding it. On iOS 17 such a cover never
// finishes laying out once its content holds anything that can present (a
// PhotosPicker, or another cover): the main thread spins and every tap is lost.
// Layers stay in the app's own view tree, so pickers, menus and nested sheets
// present normally, and a layer can open another layer above itself.

extension View {
    /// Shows `content` over the whole screen while `item` is set, above the rail and
    /// any other layer. The content draws its own backdrop (a `WallSheet` dims the
    /// wall); set `item` inside `CompanionCover.instantly` and let the content fade itself in.
    func wallCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(WallLayerSource(item: item, layer: content))
    }

    /// Keeps the wall's screen from moving for the keyboard while `isOpen`: a sheet over it is
    /// what is being typed into, and only the sheet should lift or scroll. Without it the
    /// screen behind gives up the keyboard's height and squashes (the week's hours shrink,
    /// titles truncate). `wallCover` and `wallSheet` say so themselves; a system `.sheet`
    /// on the wall says it with this.
    func holdsWallStill(_ isOpen: Bool) -> some View {
        transformPreference(WallHoldsStillKey.self) { $0 = $0 || isOpen }
    }

    /// Draws the wall layers requested anywhere inside this view. Applied once at the
    /// root; each layer hosts its own, so sheets can open sheets.
    func hostsWallLayers() -> some View {
        modifier(WallLayerHost())
    }
}

private struct WallLayer: Identifiable {
    let id: String
    let view: AnyView
}

private struct WallLayerKey: PreferenceKey {
    static var defaultValue: [WallLayer] { [] }
    static func reduce(value: inout [WallLayer], nextValue: () -> [WallLayer]) {
        value.append(contentsOf: nextValue())
    }
}

/// Whether something over the wall's screen is open (`holdsWallStill`), read by `WallView`.
struct WallHoldsStillKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct WallLayerSource<Item: Identifiable, Layer: View>: ViewModifier {
    @Binding var item: Item?
    let layer: (Item) -> Layer

    /// Tells this source's layers from other sources showing an item with the same id.
    @State private var sourceId = UUID()

    func body(content: Content) -> some View {
        // A new item gets a new id, so the layer starts with fresh state, as a cover would.
        let id = item.map { "\(sourceId)-\($0.id)" }
        return content
            .transformPreference(WallLayerKey.self) { layers in
                if let item, let id { layers.append(WallLayer(id: id, view: AnyView(layer(item)))) }
            }
            .holdsWallStill(item != nil)
    }
}

private struct WallLayerHost: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(WallLayerKey.self) { layers in
                ZStack {
                    ForEach(layers) { layer in
                        // Erased: a layer hosting its own layers would otherwise be a recursive type.
                        AnyView(layer.view.hostsWallLayers())
                            // VoiceOver stays inside the top sheet; the dim already blocks touches.
                            .accessibilityElement(children: .contain)
                            .accessibilityAddTraits(.isModal)
                    }
                }
            }
            // Requests drawn here go no further up.
            .transformPreference(WallLayerKey.self) { $0 = [] }
    }
}
