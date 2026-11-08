import PencilKit
import SwiftUI

/// Writing on one day: the same page as the month cell, zoomed so it is comfortable
/// to write on. Ink is saved in page coordinates when the sheet closes.
struct WriteDaySheet: View {
    let day: DayKey
    let today: DayKey
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @State private var editor: PageEditor?
    @State private var zoom: Zoom = .fit
    /// While the zoom animates, the canvas hides and a rendered copy of the ink scales with the paper.
    @State private var isZooming = false

    enum Zoom: String, CaseIterable, Identifiable {
        case double, fit, quadruple
        var id: String { rawValue }
        var label: String {
            switch self {
            case .double: "2×"
            case .fit: "Fit"
            case .quadruple: "4×"
            }
        }
    }

    private let stageSize = CGSize(width: 560, height: 596)
    private let captionSpace: CGFloat = 28

    var body: some View {
        ZStack {
            Color(hex: 0x14_0F0A).opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            HStack(alignment: .top, spacing: 26) {
                stage
                side
            }
            .padding(.leading, 20)
            .padding(.trailing, 26)
            .padding(.vertical, 20)
            .frame(width: 968)
            .background(SurfaceShape(cornerRadius: 28, elevation: 2.5))
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .onAppear {
            if editor == nil { editor = PageEditor(day: day, drawing: store.pageDrawing(for: day)) }
        }
    }

    // MARK: Stage

    private var fitScale: CGFloat {
        PageViewport.fitScale(in: CGSize(width: stageSize.width, height: stageSize.height - captionSpace * 2), inset: 22)
    }

    private func scale(for zoom: Zoom) -> CGFloat {
        switch zoom {
        case .double: 2
        case .fit: fitScale
        case .quadruple: 4
        }
    }

    private var stage: some View {
        let scale = scale(for: zoom)
        let pageSize = CGSize(width: PageGeometry.size.width * scale, height: PageGeometry.size.height * scale)
        return VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                PagePaper(number: dayNumber, scale: scale, numberColor: day == today ? Theme.accent : Theme.ink)
                if let editor {
                    // Saved ink is always drawn by our own Core Graphics renderer underneath the
                    // canvas: PencilKit's renderer has been seen to draw nothing for loaded drawings
                    // (verified on the iPad Pro 10.5 with iPadOS 17). It re-renders from the editor's
                    // live drawing, so erasing and undo stay in sync; where PencilKit does draw,
                    // the two layers coincide.
                    if !isZooming {
                        Image(uiImage: editor.drawing.pageImage(scale: scale, displayScale: displayScale))
                    }
                    if isZooming {
                        Image(uiImage: editor.drawing.pageImage(scale: 4, displayScale: displayScale))
                            .resizable()
                    } else {
                        PageCanvas(
                            editor: editor,
                            revision: editor.revision,
                            viewport: PageViewport(scale: scale, origin: .zero),
                            ink: store.ink,
                            tip: store.tip,
                            isErasing: store.isErasing,
                            allowsFinger: store.allowsFingerDrawing
                        )
                    }
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .clipped()
            .shadow(color: FoodStyle.shadow.opacity(0.3), radius: 15, y: 12)
            Text("Same page as the calendar, \(scaleText(scale)) bigger")
                .font(.body(12.5, weight: 600))
                .foregroundStyle(Theme.muted)
        }
        .frame(width: stageSize.width, height: stageSize.height)
        .background(Paper.desk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func scaleText(_ scale: CGFloat) -> String {
        (scale * 10).rounded() / 10 == scale.rounded() ? "\(Int(scale.rounded()))×" : String(format: "%.1f×", scale)
    }

    // MARK: Side panel

    private var side: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 0) {
            Text(day.startDate(in: store.calendar).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.display(28))
            Text(subtitle)
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)

            SheetLabel(title: "Zoom").padding(.top, 22).padding(.bottom, 8)
            HStack(spacing: 8) {
                ForEach(Zoom.allCases) { option in
                    FoodChoicePill(option.label, isSelected: zoom == option) { setZoom(option) }
                }
            }

            SheetLabel(title: "Actual size on the calendar").padding(.top, 20).padding(.bottom, 8)
            DayPageView(
                day: day,
                numberColor: day == today ? Theme.accent : Theme.ink,
                image: editor.map { $0.drawing.pageImage(scale: 1, displayScale: displayScale) }
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.line))
            .shadow(color: FoodStyle.shadow.opacity(0.18), radius: 7, y: 6)

            SheetLabel(title: "Pen", note: store.isErasing ? "Eraser" : store.ink.name).padding(.top, 20).padding(.bottom, 10)
            InkPalette(selected: store.isErasing ? nil : store.ink, size: 32, spacing: 12) { ink in
                store.chosenInk = ink
                store.isErasing = false
            }

            SheetLabel(title: "Tip").padding(.top, 20).padding(.bottom, 8)
            HStack(spacing: 8) {
                ForEach(PenTip.allCases) { tip in
                    FoodChoicePill(tip.label, isSelected: store.tip == tip && !store.isErasing) {
                        store.tip = tip
                        store.isErasing = false
                    }
                }
            }

            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Spacer()
                Button { editor?.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").fixedSize()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(editor?.canUndo != true)
                Button { store.isErasing.toggle() } label: {
                    Label("Eraser", systemImage: "eraser").fixedSize()
                }
                .buttonStyle(ToggleButtonStyle(isOn: store.isErasing))
                Button(action: close) {
                    Label("Done", systemImage: "checkmark").fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: stageSize.height)
    }

    private var subtitle: String {
        if day == today { return "Writing on today's page" }
        let weekday = day.startDate(in: store.calendar).formatted(.dateTime.weekday(.wide))
        return "Writing on \(weekday)'s page"
    }

    private var dayNumber: String { String(Int(day.rawValue.suffix(2)) ?? 0) }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
                .background(Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(20)
        .accessibilityLabel("Close")
    }

    private func setZoom(_ newZoom: Zoom) {
        guard newZoom != zoom else { return }
        isZooming = true
        withAnimation(.easeInOut(duration: 0.28)) { zoom = newZoom } completion: { isZooming = false }
    }

    /// Ink is saved on any close: there is Undo for mistakes, and nothing is lost by accident.
    private func close() {
        if let editor, editor.hasChanges { store.savePage(editor.drawing, for: day) }
        onClose()
    }
}

/// A secondary button that turns ink-filled while its mode is on (Eraser).
struct ToggleButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(15, weight: 700))
            .foregroundStyle(isOn ? Theme.surface : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isOn ? Theme.ink : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(isOn ? Theme.ink : Theme.line))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
