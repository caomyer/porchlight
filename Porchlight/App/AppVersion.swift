import Foundation

/// Which build a device runs, as Settings on the wall and You on the phone show it:
/// "Porchlight 0.1.0 (20261117.061840)". The build number is the commit's time in UTC
/// (scripts/lib/version.sh), so a cable install and a TestFlight build of one commit match;
/// builds from Xcode say 0.
enum AppVersion {
    static var text: String { text(Bundle.main.infoDictionary ?? [:]) }

    static func text(_ info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Porchlight \(version) (\(build))"
    }
}
