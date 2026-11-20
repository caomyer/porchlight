"""Second launches for UI tests whose app never started, for scripts/test.sh.

On a busy simulator XCTest can give up starting the app ("Failed to launch ... Timed out
while launching application via Xcode"), or quitting the copy left from the test before,
which every launch does first ("Failed to terminate com...porchlight:<pid>"): the test
never ran, so its failure says nothing about it. Such a test, and only such a test (every
one of its failures is one of these), runs once more on its own; any other failure stands
as it is, and so does a test that fails its second launch too.

  launch_retry.py failures <bundle>              the tests to run again, one "Class/test" a line
  launch_retry.py report <name> <bundle> <retry> the suite's result, counting each retried
                                                 test by its second run; exits 1 unless all passed
"""

import json
import subprocess
import sys

LAUNCH_FAILURES = ("Failed to launch ", "Failed to terminate ")


def test_cases(bundle):
    """Every test case in a result bundle: {"Class/test()": (result, [failure messages])}."""
    output = subprocess.check_output(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", bundle],
        stderr=subprocess.DEVNULL,
    )
    cases = {}

    def walk(node):
        if node.get("nodeType") == "Test Case":
            messages = [child["name"] for child in node.get("children", []) if child.get("nodeType") == "Failure Message"]
            cases[node["nodeIdentifier"]] = (node.get("result"), messages)
        for child in node.get("children", []):
            walk(child)

    for node in json.loads(output)["testNodes"]:
        walk(node)
    return cases


def launch_failures(bundle):
    """Failed tests whose every failure is XCTest not starting the app, or not quitting it."""
    return sorted(
        identifier
        for identifier, (result, messages) in test_cases(bundle).items()
        if result == "Failed" and messages and all(message.startswith(LAUNCH_FAILURES) for message in messages)
    )


def main():
    command = sys.argv[1]
    if command == "failures":
        for identifier in launch_failures(sys.argv[2]):
            print(identifier.removesuffix("()"))
    elif command == "report":
        name, bundle, retry = sys.argv[2:5]
        cases = test_cases(bundle)
        retried = test_cases(retry)
        for identifier, outcome in retried.items():
            if identifier in cases:
                cases[identifier] = outcome
        results = [result for result, _ in cases.values()]
        passed = results.count("Passed") + results.count("Expected Failure")
        failed = results.count("Failed")
        skipped = results.count("Skipped")
        second = [i.removesuffix("()") for i, (result, _) in retried.items() if result == "Passed"]
        line = "%s: %d/%d passed" % (name, passed, len(results))
        if failed:
            line += ", %d failed" % failed
        if skipped:
            line += " (%d skipped)" % skipped
        if second:
            line += "; passed on a second launch: %s" % ", ".join(second)
        print(line)
        sys.exit(0 if failed == 0 else 1)
    else:
        sys.exit("unknown command %s" % command)


if __name__ == "__main__":
    main()
