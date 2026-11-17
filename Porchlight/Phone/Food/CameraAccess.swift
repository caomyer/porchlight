@preconcurrency import AVFoundation
import UIKit

/// Whether this phone may use the camera to snap meals.
enum CameraAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
    /// No camera at all, like the simulator.
    case noCamera

    /// What iOS says now. DEBUG builds can pretend with `-cameraAccess
    /// notDetermined|denied|allowed`, so UI tests and screenshots show each state without
    /// the system prompt; asking then allows, like tapping Allow.
    @MainActor
    static func current() -> CameraAccess {
        #if DEBUG
        if let pretend = Pretend.access { return pretend }
        if SampleCamera.isOn { return .allowed }
        #endif
        guard MealCamera.hasCamera else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return .allowed
        default: return .denied
        }
    }

    /// Shows the system prompt, once; afterwards iOS answers without asking.
    @MainActor
    static func request() async -> CameraAccess {
        #if DEBUG
        if let pretend = Pretend.access {
            if pretend == .notDetermined { Pretend.access = .allowed }
            return Pretend.access ?? .allowed
        }
        #endif
        _ = await MealCamera.requestAccess()
        return current()
    }

    #if DEBUG
    @MainActor
    private enum Pretend {
        static var access: CameraAccess? = switch UserDefaults.standard.string(forKey: "cameraAccess") {
        case "notDetermined": .notDetermined
        case "denied": .denied
        case "allowed": .allowed
        default: nil
        }
    }
    #endif
}

#if DEBUG
/// `-debugCamera sample`: the simulator has no camera, so the viewfinder shows a generated
/// dish instead of a live picture and the shutter "takes" it. The shot goes through
/// `MealPhotoImaging.prepare` like a real one.
enum SampleCamera {
    @MainActor
    static var isOn: Bool { UserDefaults.standard.string(forKey: "debugCamera") == "sample" }

    /// Each shot a little different, as if from another angle.
    static func shot(_ index: Int) -> UIImage {
        SamplePhoto.image(palette: index + 1, emoji: "🍜")
    }
}
#endif
