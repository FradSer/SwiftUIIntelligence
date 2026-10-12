#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
SIMULATOR_ID="${1:-7E4437E7-369A-466E-9C89-75FC93643440}"
BUILD_DIR="${TMPDIR:-/tmp}/swiftuiintelligence-demo-build"
xcodebuild -project Example/SwiftUIIntelligenceDemo.xcodeproj -scheme SwiftUIIntelligenceDemo \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO build
# Reuse a booted device; never erase or delete simulator data.
if ! xcrun simctl list devices booted | /usr/bin/grep -Fq "$SIMULATOR_ID"; then
  xcrun simctl boot "$SIMULATOR_ID"
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" "$BUILD_DIR/Build/Products/Debug-iphonesimulator/SwiftUIIntelligenceDemo.app"
xcrun simctl launch "$SIMULATOR_ID" dev.local.SwiftUIIntelligenceDemo
SIMULATOR_APP="$(xcode-select -p)/Applications/Simulator.app"
if [[ -d "$SIMULATOR_APP" ]]; then
  open "$SIMULATOR_APP"
else
  print "App launched in CoreSimulator. Simulator.app GUI is not installed in this Xcode distribution."
  print "Capture the running screen with: xcrun simctl io $SIMULATOR_ID screenshot /tmp/swiftuiintelligence.png"
fi
