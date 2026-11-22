#!/usr/bin/env python3
"""The tests of a UI suite that ran too long or waited on an app that never went idle.

A test can pass and still be wrong in a way only its log shows. On November 22, 2026 the
onboarding test passed in 2,020 seconds, where it takes 60: before every tap XCTest waited
its full 60 seconds for the app to go idle and gave up ("App animations complete
notification not received, will attempt to continue"), 33 times, and the run was green
(docs/design/testing.md, "Known and not yet explained"). So after each UI suite this reads
xcodebuild's log and names

  - every test that took longer than the ceiling (120 seconds), and
  - every test in which XCTest gave up waiting for the app to go idle more than twice,

each with its seconds and its count, on the output and, on GitHub, in the job's summary,
where it shows in a green run too.

    slow_tests.py <name> <log> [<keep file>]

always exits 0: it reports, it does not judge (a test that runs away is stopped and failed
by the time limit scripts/test.sh gives xcodebuild). When any test is named and a keep
file is given, it is written with one line a test, "<class> <test> <start> <end>", in the
log's own time: scripts/test.sh then keeps the simulator's log of the app for that span,
and scripts/ci/collect-results.sh keeps the suite's whole result bundle, which has the
app's own log. scripts/ci/check-slow-tests.sh checks it against sample logs.
"""
import datetime
import os
import re
import sys

CEILING = 120.0
IDLE_GIVEN_UP = "App animations complete notification not received"
MOST_IDLE = 2

STARTED = re.compile(r"^Test Case '-\[\w+\.(\w+) (\w+)\]' started\.$")
ENDED = re.compile(r"Test Case '-\[\w+\.(\w+) (\w+)\]' (passed|failed|skipped) \(([\d.]+) seconds\)")
BEGAN_AT = re.compile(r"t = +[\d.]+s Start Test at (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)")
STAMP = "%Y-%m-%d %H:%M:%S"


def read(text):
    """Each test in the log: class, test, how it ended, its seconds, its idle waits given
    up, and when it began."""
    tests = []
    current = None
    for line in text.splitlines():
        line = line.rstrip()
        began = STARTED.match(line)
        if began:
            current = {"class": began.group(1), "test": began.group(2), "result": None, "seconds": None, "idle": 0, "began": None}
            tests.append(current)
            continue
        if current is None:
            continue
        ended = ENDED.search(line)
        if ended and (ended.group(1), ended.group(2)) == (current["class"], current["test"]):
            current["result"] = ended.group(3)
            current["seconds"] = float(ended.group(4))
            current = None
            continue
        if IDLE_GIVEN_UP in line:
            current["idle"] += 1
        at = BEGAN_AT.search(line)
        if at and current["began"] is None:
            current["began"] = at.group(1)
    return tests


def named(tests):
    """The tests worth a word: over the ceiling, with more idle waits given up than a busy
    Mac explains, or with no end at all (stopped at the time limit, or lost with the
    process)."""
    return [t for t in tests if t["seconds"] is None or t["seconds"] > CEILING or t["idle"] > MOST_IDLE]


def sentence(test):
    parts = []
    if test["seconds"] is None:
        parts.append("never finished")
    elif test["seconds"] > CEILING:
        parts.append("took %d seconds, over the ceiling of %d" % (round(test["seconds"]), CEILING))
    else:
        parts.append("took %d seconds" % round(test["seconds"]))
    if test["idle"]:
        parts.append("gave up waiting for the app to go idle %d time%s" % (test["idle"], "" if test["idle"] == 1 else "s"))
    return "%s.%s %s (%s)" % (test["class"], test["test"], " and ".join(parts), test["result"] or "no result")


def main():
    name, path = sys.argv[1], sys.argv[2]
    keep = sys.argv[3] if len(sys.argv) > 3 else None
    try:
        text = open(path, errors="replace").read()
    except OSError:
        return 0
    tests = read(text)
    worth = named(tests)
    idle = sum(t["idle"] for t in tests)
    if idle and not worth:
        print("%s: XCTest gave up waiting for the app to go idle %d time%s, no test more than %d" % (name, idle, "" if idle == 1 else "s", MOST_IDLE))
    for test in worth:
        print("%s: %s" % (name, sentence(test)))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary and (worth or idle):
        with open(summary, "a") as out:
            out.write("\n**%s: tests over %d seconds, or waiting on an app that would not go idle**\n\n" % (name, CEILING))
            out.write("| Test | Seconds | Idle waits given up | Result |\n|---|---|---|---|\n")
            for test in (worth or [t for t in tests if t["idle"]]):
                seconds = "%d" % round(test["seconds"]) if test["seconds"] is not None else "never finished"
                out.write("| %s.%s | %s | %d | %s |\n" % (test["class"], test["test"], seconds, test["idle"], test["result"] or "none"))
            out.write("\nIdle waits given up in the whole suite: %d.\n" % idle)
    if keep and worth:
        with open(keep, "w") as out:
            for test in worth:
                start = test["began"] or ""
                end = ""
                if start:
                    length = (test["seconds"] or 600) + 5
                    end = (datetime.datetime.strptime(start, STAMP) + datetime.timedelta(seconds=length)).strftime(STAMP)
                out.write("%s %s %s|%s\n" % (test["class"], test["test"], start, end))
    return 0


if __name__ == "__main__":
    sys.exit(main())
