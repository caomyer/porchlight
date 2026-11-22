#if DEBUG
import Foundation
import Testing

/// A test that kills the unit test process when asked to, and does nothing otherwise.
///
/// It is here to check the harness, not the app: a unit run whose process dies partway
/// must be reported as failed (docs/design/testing.md, the hard rule "A run that loses its
/// process fails"). On November 22, 2026 a hosted screen that lacked a store crashed the
/// process in the middle of the suite, and a private script that read only xcodebuild's
/// last summary line called the run passed; scripts/test.sh did not, and this is how to
/// see that it still does not:
///
///   TEST_RUNNER_PORCHLIGHT_CRASH_A_UNIT_TEST=1 zsh scripts/test.sh --unit-only
///
/// must end with "Unit: the test process was lost" and a failing status.
@Suite("The harness: a unit test that crashes the process when asked")
struct HarnessCrashTests {
    @Test("Crashes the test process when PORCHLIGHT_CRASH_A_UNIT_TEST is 1, and passes otherwise")
    func crashesWhenAsked() {
        guard ProcessInfo.processInfo.environment["PORCHLIGHT_CRASH_A_UNIT_TEST"] == "1" else { return }
        fatalError("Crashing the unit test process on purpose (PORCHLIGHT_CRASH_A_UNIT_TEST=1)")
    }
}
#endif
