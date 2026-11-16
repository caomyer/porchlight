import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code drawn on the device, with no network: one pixel per module, scaled up without
/// smoothing, so it stays crisp at any size. It is drawn off the main thread once per text,
/// since Core Image takes a moment to start.
struct QRCode: View {
    let text: String
    /// What VoiceOver reads for the code, once it is drawn.
    let label: String

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(image, scale: 1, label: Text(label))
                    .resizable()
                    .interpolation(.none)
                    .accessibilityIdentifier("join-code")
            } else {
                // The paper the placeholder uses, until the code is drawn.
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xF0E8DA))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: text) {
            let text = text
            image = await Task.detached(priority: .userInitiated) { QRCode.image(for: text) }.value
        }
    }

    /// One context for the app: making one is the slow part.
    private nonisolated static let context = CIContext()

    /// The code's modules as an image, with the generator's quiet zone around them.
    nonisolated static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // Medium correction: still reads with a glare across the iPad's glass.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}
