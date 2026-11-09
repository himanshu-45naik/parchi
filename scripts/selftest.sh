#!/bin/bash
# Runs the in-app self-test on throwaway data. Note windows appear on screen while it runs.
# Usage: scripts/selftest.sh <output folder>
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: selftest.sh <output folder>}"
rm -rf "$OUT"
mkdir -p "$OUT/data"

swift build --product Parchi 2>&1 | grep -E "error:" && exit 1
BIN="$(swift build --product Parchi --show-bin-path)/Parchi"

# A bundle is needed for the app to behave like a real one.
APP="$OUT/ParchiDebug.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Parchi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

for phase in first restart; do
    PARCHI_DATA_DIR="$OUT/data" PARCHI_SELFTEST="$OUT" PARCHI_SELFTEST_PHASE="$phase" \
        "$APP/Contents/MacOS/Parchi" >"$OUT/log-$phase.txt" 2>&1 &
    PID=$!
    for _ in $(seq 1 240); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.5
    done
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        echo "phase $phase timed out"
    fi
    wait "$PID" 2>/dev/null
    echo "=== $phase"
    grep -E "^(FAIL|info)|failures$" "$OUT/result-$phase.txt" 2>/dev/null || { echo "no result"; tail -20 "$OUT/log-$phase.txt"; }
    grep -c "^ok" "$OUT/result-$phase.txt" 2>/dev/null
done
