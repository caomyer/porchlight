#if DEBUG
import Foundation
import Testing

/// A test that kills the unit test process when asked to, and does nothing otherwise.
///
/// It is here to check the harness, not the app: a unit run whose process dies partway
/// must be reported as failed (docs/design/testing.md, the hard rule "A run that loses its
/// process fails"). On November 22, 2026 a hosted screen that lacked a store crashed the
/// process in the middle of the suite and the run's summary still said it had passed.
///
///   TEST_RUNNER_PORCHLIGHT_CRASH_A_UNIT_TEST=1 zsh scripts/test.sh --unit-only
///
/// must end with "Unit: ... the test process was lost" and a failing status; the workflow's
/// `crash_a_unit_test` input does the same on a hosted Mac and fails if the run is called
/// green.
@Suite("The harness: a unit test that crashes the process when asked")
struct HarnessCrashTests {
    @Test("Crashes the test process when PORCHLIGHT_CRASH_A_UNIT_TEST is 1, and passes otherwise")
    func crashesWhenAsked() {
        guard ProcessInfo.processInfo.environment["PORCHLIGHT_CRASH_A_UNIT_TEST"] == "1" else { return }
        fatalError("Crashing the unit test process on purpose (PORCHLIGHT_CRASH_A_UNIT_TEST=1)")
    }
}
#endif
