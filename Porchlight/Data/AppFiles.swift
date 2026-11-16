import Foundation

/// The single root folder for everything Porchlight stores on the device
/// (database, meal photos, companion photos, ambient photos).
///
/// DEBUG launches with `-sampleHousehold` or `-resetData` use a separate sandbox
/// folder, so screenshots and UI tests on a real device never touch real data.
enum AppFiles {
    static let root: URL = folder(named: isSandboxed ? sampleName : "Porchlight")

    private static let sampleName = "PorchlightSample"

    private static func folder(named name: String) -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(name, isDirectory: true)
    }

    /// True when this launch must not read or write the household's real data.
    static var isSandboxed: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-sampleHousehold") || arguments.contains("-resetData")
        #else
        return false
        #endif
    }

    #if DEBUG
    /// The sample sandbox, wherever this launch keeps its data: iOS launches the app with
    /// no arguments to act on a reminder a sample launch scheduled.
    static var sampleRoot: URL { folder(named: sampleName) }
    #endif

    /// A subfolder of the root, e.g. "Photos".
    static func folder(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }
}
