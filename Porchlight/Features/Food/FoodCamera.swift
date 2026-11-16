@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// The capture session behind the "Snap a meal" viewfinder. All session work runs on
/// a private serial queue; the class is only touched through that queue or its async API.
final class MealCamera: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.porchlight.porchlight.camera")
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var pending: CheckedContinuation<UIImage, any Error>?

    enum CameraError: Error, LocalizedError {
        case unavailable
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: "The camera is not available."
            case .captureFailed: "The photo could not be taken. Try again."
            }
        }
    }

    /// Whether this device has any camera at all (the simulator has none).
    static var hasCamera: Bool {
        !AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.isEmpty
    }

    /// Both cameras exist, so switching makes sense (the wall iPad usually faces the room).
    static var canSwitch: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    /// The camera currently in use.
    var device: AVCaptureDevice? { input?.device }

    func start(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                do {
                    try self.configure(position: position)
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video) else { throw CameraError.unavailable }
        let newInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else { throw CameraError.unavailable }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
    }

    /// Takes a photo at the given rotation (from the preview's rotation coordinator).
    func capture(rotationAngle: CGFloat) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning, self.pending == nil else {
                    continuation.resume(throwing: CameraError.captureFailed)
                    return
                }
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                self.pending = continuation
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }
}

extension MealCamera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        queue.async {
            let continuation = self.pending
            self.pending = nil
            if let data = photo.fileDataRepresentation(), let image = UIImage(data: data), error == nil {
                continuation?.resume(returning: image)
            } else {
                continuation?.resume(throwing: error ?? CameraError.captureFailed)
            }
        }
    }
}

/// The live camera image, kept upright with a rotation coordinator.
struct CameraPreview: UIViewRepresentable {
    let camera: MealCamera
    /// The camera in use; changing it re-attaches the rotation coordinator.
    let deviceID: String?
    let onRotationAngle: (CGFloat) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onRotationAngle = onRotationAngle
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onRotationAngle = onRotationAngle
        if view.deviceID != deviceID {
            view.deviceID = deviceID
            view.attach(device: camera.device)
        }
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var deviceID: String?
        var onRotationAngle: ((CGFloat) -> Void)?
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observations: [NSKeyValueObservation] = []

        func attach(device: AVCaptureDevice?) {
            observations = []
            guard let device else { coordinator = nil; return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            apply(coordinator)
            observations = [
                coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinator, _ in
                    DispatchQueue.main.async { self?.apply(coordinator) }
                },
            ]
        }

        private func apply(_ coordinator: AVCaptureDevice.RotationCoordinator) {
            let preview = coordinator.videoRotationAngleForHorizonLevelPreview
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(preview) {
                connection.videoRotationAngle = preview
            }
            onRotationAngle?(coordinator.videoRotationAngleForHorizonLevelCapture)
        }
    }
}
