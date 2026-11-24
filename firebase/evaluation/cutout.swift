// Cuts the pet out of a photo the way the app does before it asks for a character:
// Vision's subject lifting, cropped to the subject, on a transparent background, no
// longer than 1024 on its longest side.
// Usage: swift cutout.swift <photo> <out.png>
import AppKit
import CoreImage
import Vision

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = CIImage(contentsOf: URL(fileURLWithPath: arguments[1]), options: [.applyOrientationProperty: true]) else {
    print("usage: cutout.swift <photo> <out.png>")
    exit(2)
}
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: source)
try handler.perform([request])
guard let result = request.results?.first else {
    print("no subject found")
    exit(1)
}
let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
var cut = CIImage(cvPixelBuffer: buffer)
let scale = min(1, 1024 / max(cut.extent.width, cut.extent.height))
cut = cut.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
cut = cut.transformed(by: CGAffineTransform(translationX: -cut.extent.minX, y: -cut.extent.minY))
let bounds = CGRect(x: 0, y: 0, width: floor(cut.extent.width), height: floor(cut.extent.height))
guard let image = CIContext().createCGImage(cut, from: bounds) else {
    print("could not draw the cut-out")
    exit(1)
}
try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("wrote", arguments[2], Int(bounds.width), "x", Int(bounds.height), "subjects:", result.allInstances.count)
