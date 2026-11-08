import Foundation

/// The single root folder for everything Porchlight stores on the device
/// (database, meal photos, companion photos, ambient photos).
///
/// DEBUG launches with `-sampleHousehold` or `-resetData` use a separate sandbox
/// folder, so screenshots and UI tests on a real device never touch real data.
enum AppFiles {
    static let root: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(isSandboxed ? "PorchlightSample" : "Porchlight", isDirectory: true)
    }()

    /// True when this launch must not read or write the household's real data.
    static var isSandboxed: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-sampleHousehold") || arguments.contains("-resetData")
        #else
        return false
        #endif
    }

    /// A subfolder of the root, e.g. "Photos".
    static func folder(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }
}
