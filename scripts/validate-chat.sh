#!/bin/zsh
set -u
cd "$(dirname "$0")/.."
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE="${SWIFTUIINTELLIGENCE_CHAT_EVIDENCE_DIR:-evidence/chat-runs/$RUN_ID}"
BUILD_DIR="${TMPDIR:-/tmp}/swiftuiintelligence-chat-$RUN_ID"
PHONE_ID="${1:-7E4437E7-369A-466E-9C89-75FC93643440}"
IPAD_ID="${2:-AA1CD39D-8DB8-4E45-88B7-986F29B3B19F}"
mkdir -p "$EVIDENCE"
./scripts/test-package.sh > "$EVIDENCE/package.log" 2>&1
OVERALL_STATUS=$?
print "package=$OVERALL_STATUS" > "$EVIDENCE/status.txt"
for kind in phone ipad; do
  if [[ "$kind" == phone ]]; then DEVICE_ID="$PHONE_ID"; else DEVICE_ID="$IPAD_ID"; fi
  RESULT="$BUILD_DIR-$kind.xcresult"
  xcodebuild -project Example/SwiftUIIntelligenceDemo.xcodeproj -scheme SwiftUIIntelligenceDemo \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath "$BUILD_DIR" \
    -resultBundlePath "$RESULT" CODE_SIGNING_ALLOWED=NO \
    -only-testing:SwiftUIIntelligenceDemoUITests/DemoUITests/testSyntheticChatUpdatesCallbacksAndJSON \
    -only-testing:SwiftUIIntelligenceDemoUITests/DemoUITests/testChatProviderMalformedAndUnknownResponsesCanRetry \
    -only-testing:SwiftUIIntelligenceDemoUITests/DemoUITests/testRecordedAppleDocumentsInLightAndDark \
    -only-testing:SwiftUIIntelligenceDemoUITests/DemoUITests/testGenericSDKGlassAndHostCallbacks test \
    > "$EVIDENCE/$kind.log" 2>&1
  TEST_STATUS=$?
  print "$kind=$TEST_STATUS" >> "$EVIDENCE/status.txt"
  print "$kind-result=$RESULT" >> "$EVIDENCE/status.txt"
  if (( TEST_STATUS != 0 )); then OVERALL_STATUS=1; fi
  if [[ -d "$RESULT" ]]; then
    xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EVIDENCE/$kind-attachments" > "$EVIDENCE/$kind-export.log" 2>&1
    EXPORT_STATUS=$?
    print "$kind-export=$EXPORT_STATUS" >> "$EVIDENCE/status.txt"
    if (( EXPORT_STATUS != 0 )); then OVERALL_STATUS=1; fi
  fi
  print "$kind exit: $TEST_STATUS"
done
print "Evidence: $EVIDENCE"
exit "$OVERALL_STATUS"
