#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
# /tmp avoids inherited Finder metadata that can prevent ad-hoc test signing.
BUILD_DIR="${TMPDIR:-/tmp}/swiftuiintelligence-package-build"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/ModuleCache"
swift test --scratch-path "$BUILD_DIR" --disable-sandbox
