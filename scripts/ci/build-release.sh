#!/bin/zsh
# Compiles what ships: the app and everything its archive builds (the widgets with it), in
# Release, for a device, with signing off. It builds nothing to run and uploads nothing; it
# is here because the tests only ever build Debug, and code that compiles in Debug can fail
# to compile in Release.
#
# On November 22, 2026 a `@State` was declared inside `#if DEBUG` and read outside it: Debug
# built, four full runs were green, and the TestFlight archive of that commit failed with
# "cannot find 'holdsStill' in scope" (docs/design/testing.md, the hard rule "The shipped
# configuration is compiled in CI"). This is the same compile `scripts/testflight.sh` makes
# when it archives, minus the signing.
#
#   zsh scripts/ci/build-release.sh
#
# Its status is xcodebuild's own. The whole log is kept beside the build; only errors and
# the last word are printed.
set -uo pipefail
cd "$(dirname "$0")/../.."
work=${PORCHLIGHT_RELEASE_BUILD_DIR:-${TMPDIR:-/tmp}/porchlight-release-build-${PWD:t}}
mkdir -p "$work"
log="$work/build.log"

xcodegen generate --quiet || { echo "xcodegen could not write the project"; exit 1; }
started=$SECONDS
build_status=0
xcodebuild build \
  -project Porchlight.xcodeproj \
  -scheme Porchlight \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$work/DerivedData" \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO > "$log" 2>&1 || build_status=$?

grep -E "error:|\*\* BUILD" "$log" | grep -v "Run script" | sort -u | head -40
echo "Took: release build $(( SECONDS - started ))s"
if (( build_status != 0 )); then
  echo "The Release build failed with status $build_status: what ships does not compile, whatever the tests say. See $log"
  exit $build_status
fi
grep -q "\*\* BUILD SUCCEEDED \*\*" "$log" || { echo "xcodebuild ended without saying the build succeeded: see $log"; exit 1; }
echo "What ships compiles in Release."
