#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test
.build/debug/PoteNad --smoke-test
./scripts/build.sh
POTENAD_LAUNCH_CHECK=1 build/PoteNad.app/Contents/MacOS/PoteNad -startupBehavior newDocument
SAVE_TEST_ROOT="$(mktemp -d)"
POTENAD_SAVE_CHECK="$SAVE_TEST_ROOT/save-check.txt" \
  build/PoteNad.app/Contents/MacOS/PoteNad -startupBehavior newDocument
OPEN_TEST_ROOT="$(mktemp -d)"
POTENAD_OPEN_CHECK="$OPEN_TEST_ROOT/open-check.txt" \
  build/PoteNad.app/Contents/MacOS/PoteNad -startupBehavior newDocument
SESSION_TEST_ROOT="$(mktemp -d)"
POTENAD_SESSION_STORE="$SESSION_TEST_ROOT/session.json" POTENAD_SESSION_PREPARE=1 \
  build/PoteNad.app/Contents/MacOS/PoteNad -startupBehavior restorePreviousSession
POTENAD_SESSION_STORE="$SESSION_TEST_ROOT/session.json" POTENAD_SESSION_VERIFY=1 \
  build/PoteNad.app/Contents/MacOS/PoteNad -startupBehavior restorePreviousSession
POTENAD_SESSION_STORE="$SESSION_TEST_ROOT/session.json" POTENAD_SESSION_VERIFY_EMPTY=1 \
  build/PoteNad.app/Contents/MacOS/PoteNad -startupBehavior restorePreviousSession
POTENAD_CLICK_CHECK=1 build/PoteNad.app/Contents/MacOS/PoteNad -startupBehavior newDocument
