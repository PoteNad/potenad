#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test
.build/debug/PoteNad --smoke-test
./scripts/build.sh
POTENAD_LAUNCH_CHECK=1 build/PoteNad.app/Contents/MacOS/PoteNad
