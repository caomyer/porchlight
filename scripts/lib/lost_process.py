#!/usr/bin/env python3
"""Whether a test run lost its process, from xcodebuild's log.

A test process that crashes or exits partway takes with it every test that had not yet
reported, and what is printed afterwards can still read as a pass: when xcodebuild starts
the process again, the last launch ends with "Test run with N tests passed" for the tests
that were left. So a run is failed, whatever its result bundle says, when its log shows

  - the process being started again after it went ("Restarting after unexpected exit,
    crash, or test timeout"), or a crash with nothing started after it;
  - a test that started and never said passed, failed or skipped, in any launch;
  - a suite that started and never said it ended.

    lost_process.py <name> <log>

prints nothing and exits 0 when the log shows none of these; otherwise prints what was
lost, each line beginning "<name>:", and exits 1. scripts/test.sh calls it for the unit
tests and for each UI suite; scripts/ci/check-lost-process.sh checks it against sample
logs. It reads both XCTest's lines and Swift Testing's.

This is not the rule for a UI test whose app could not be launched, which runs once more
(launch_retry.py), nor the one for a runner that never started a single test, which also
runs once more (runner-start.sh): neither of those has lost a test that had begun.
"""
import re
import sys

RESTART = "Restarting after unexpected exit, crash, or test timeout"
STAMP = re.compile(r"^\d{4}-\d\d-\d\d [\d:.+-]+ \S+\[\d+:\d+\] ")
CRASH = re.compile(r"Fatal error|Thread \d+: EXC_|crashed with signal|Crash: |Terminating app due to uncaught exception")

# Swift Testing. A parameterized test's cases have lines of their own ("Test case passing
# ..."), and the whole run has one ("Test run with ..."); neither is a test.
ST_STARTED = re.compile(r"^◇ Test (?!case |run )(.+) started\.$")
# A parameterized test ends as `Test "name" with 5 test cases passed after ...`.
ST_ENDED = re.compile(r"[✔✘] Test (?!case |run )(.+?)(?: with \d+ test cases?)? (?:passed|failed) after ")
ST_SKIPPED = re.compile(r"➜ Test (?!case |run )(.+?) skipped")
ST_SUITE_STARTED = re.compile(r"^◇ Suite (.+) started\.$")
ST_SUITE_ENDED = re.compile(r"[✔✘] Suite (.+?) (?:passed|failed) after ")
# XCTest.
#
# A line that starts something must be a whole line of its own to count; a line that ends
# something counts wherever it is found. Output from the app is written into the same log
# and now and then runs into a result line (a stray character before the check mark was
# seen), and a result that is missed would fail a good run, while a start that is missed
# only leaves one test unwatched.
XC_STARTED = re.compile(r"^Test Case '(.+)' started\.$")
XC_ENDED = re.compile(r"Test Case '(.+)' (?:passed|failed|skipped) \(")
XC_SUITE_STARTED = re.compile(r"^Test Suite '(.+)' started at ")
XC_SUITE_ENDED = re.compile(r"Test Suite '(.+)' (?:passed|failed) at ")


def lost(log_text):
    """The problems in a log, as sentences; empty when the run kept its process."""
    restarts = 0
    crashes = []
    started, ended = [], set()
    suites_started, suites_ended = [], set()
    for line in log_text.splitlines():
        # --progress prefixes nothing in the log itself; a timestamped CI line would.
        line = line.rstrip()
        if RESTART in line:
            restarts += 1
            continue
        if CRASH.search(line) and len(crashes) < 3:
            # The same words come twice, once bare and once with the system log's stamp.
            said = STAMP.sub("", line.strip())[:200]
            if said not in crashes:
                crashes.append(said)
        for pattern, bucket in ((ST_STARTED, started), (XC_STARTED, started), (ST_SUITE_STARTED, suites_started), (XC_SUITE_STARTED, suites_started)):
            found = pattern.match(line)
            if found and found.group(1) not in bucket:
                bucket.append(found.group(1))
        for pattern, bucket in ((ST_ENDED, ended), (ST_SKIPPED, ended), (XC_ENDED, ended), (ST_SUITE_ENDED, suites_ended), (XC_SUITE_ENDED, suites_ended)):
            found = pattern.search(line)
            if found:
                bucket.add(found.group(1))
    unfinished = [name for name in started if name not in ended]
    open_suites = [name for name in suites_started if name not in suites_ended]
    problems = []
    if restarts:
        problems.append("the test process was lost %s (it exited or crashed) and was started again" % ("once" if restarts == 1 else "%d times" % restarts))
    if unfinished:
        shown = ", ".join(unfinished[:5]) + (" and %d more" % (len(unfinished) - 5) if len(unfinished) > 5 else "")
        problems.append("%d of the %d tests that started never reported a result: %s" % (len(unfinished), len(started), shown))
    if open_suites:
        shown = ", ".join(open_suites[:5]) + (" and %d more" % (len(open_suites) - 5) if len(open_suites) > 5 else "")
        problems.append("%d suite%s began and never finished: %s" % (len(open_suites), "" if len(open_suites) == 1 else "s", shown))
    if problems and crashes:
        problems.append("the log says: " + " | ".join(crashes))
    return problems


def main():
    name, path = sys.argv[1], sys.argv[2]
    try:
        text = open(path, errors="replace").read()
    except OSError:
        return 0
    problems = lost(text)
    if not problems:
        return 0
    print("%s: the test process was lost, so this run is failed whatever its totals say (docs/design/testing.md, \"A run that loses its process fails\")." % name)
    for problem in problems:
        print("%s: %s" % (name, problem))
    print("%s: see %s" % (name, path))
    return 1


if __name__ == "__main__":
    sys.exit(main())
