#!/bin/zsh
set -u
cd "$(dirname "$0")/.."
PHONE_ID="${1:-7E4437E7-369A-466E-9C89-75FC93643440}"
IPAD_ID="${2:-AA1CD39D-8DB8-4E45-88B7-986F29B3B19F}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
BUILD_DIR="${TMPDIR:-/tmp}/swiftuiintelligence-final-$RUN_ID"
EVIDENCE="${SWIFTUIINTELLIGENCE_EVIDENCE_DIR:-evidence/final}"
mkdir -p "$EVIDENCE"
{
  date -u
  xcode-select -p
  xcodebuild -version
  swift --version
  xcrun simctl list devices available
} > "$EVIDENCE/environment.log" 2>&1
./scripts/test-package.sh > "$EVIDENCE/package.log" 2>&1
PACKAGE_STATUS=$?
print "Package exit: $PACKAGE_STATUS"
print "package=$PACKAGE_STATUS" > "$EVIDENCE/status.txt"
OVERALL_STATUS=$PACKAGE_STATUS
for kind in phone ipad; do
  if [[ "$kind" == phone ]]; then DEVICE_ID="$PHONE_ID"; else DEVICE_ID="$IPAD_ID"; fi
  RESULT_PATH="$BUILD_DIR-$kind.xcresult"
  xcodebuild -project Example/SwiftUIIntelligenceDemo.xcodeproj -scheme SwiftUIIntelligenceDemo \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    -derivedDataPath "$BUILD_DIR" -resultBundlePath "$RESULT_PATH" \
    CODE_SIGNING_ALLOWED=NO test > "$EVIDENCE/$kind.log" 2>&1
  TEST_STATUS=$?
  if (( TEST_STATUS != 0 )); then OVERALL_STATUS=1; fi
  print "$kind exit: $TEST_STATUS"
  print "$kind=$TEST_STATUS" >> "$EVIDENCE/status.txt"
  print "$kind-result=$RESULT_PATH" >> "$EVIDENCE/status.txt"
  if [[ -d "$RESULT_PATH" ]]; then
    xcrun xcresulttool export attachments --path "$RESULT_PATH" \
      --output-path "$EVIDENCE/$kind-attachments" > "$EVIDENCE/$kind-export.log" 2>&1
    print "$kind-export=$?" >> "$EVIDENCE/status.txt"
  fi
done

exit "$OVERALL_STATUS"
