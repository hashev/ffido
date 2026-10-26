#!/usr/bin/env bash
# Install and start the validation APK in a disposable headless emulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_HOME:?Android SDK is required}"
API="${FFIDO_ANDROID_SMOKE_API:-35}"
case "$API" in
  24|25|35) ;;
  *) echo "Unsupported smoke API: $API" >&2; exit 1 ;;
esac
IMAGE="$(python3 "$ROOT/scripts/release/dependency_lock.py" android "$API" package)"
AVD="ffido-smoke-$API"
export ANDROID_USER_HOME="$RUNNER_TEMP/ffido-android"
export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
mkdir -p "$ANDROID_AVD_HOME"
python3 "$ROOT/scripts/release/android_sdk.py" "$SDK" emulator
python3 "$ROOT/scripts/release/android_sdk.py" "$SDK" "$API"
echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd --force --name "$AVD" --package "$IMAGE" --path "$ANDROID_AVD_HOME/${AVD}.avd"
"$SDK/cmdline-tools/latest/bin/avdmanager" list avd
test -f "$ANDROID_AVD_HOME/${AVD}.ini"
sudo chmod a+rw /dev/kvm
"$SDK/emulator/emulator" -avd "$AVD" -port 5554 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect > "$RUNNER_TEMP/ffido-emulator.log" 2>&1 &
EMULATOR_PID=$!
trap 'kill "$EMULATOR_PID" 2>/dev/null || true; wait "$EMULATOR_PID" 2>/dev/null || true' EXIT
ADB="$SDK/platform-tools/adb"
SERIAL=emulator-5554
booted=false
for attempt in $(seq 1 120); do
  if [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    booted=true
    break
  fi
  if ! kill -0 "$EMULATOR_PID" 2>/dev/null; then
    cat "$RUNNER_TEMP/ffido-emulator.log"
    exit 1
  fi
  sleep 2
done
[[ "$booted" == true ]] || { cat "$RUNNER_TEMP/ffido-emulator.log"; exit 1; }
APK="$(python3 -c 'import json,pathlib; p=next(pathlib.Path("build/packages").glob("*client-android-universal.package.json")); print(p.parent/json.loads(p.read_text())["file"])')"
"$ADB" -s "$SERIAL" install "$ROOT/$APK"
"$ADB" -s "$SERIAL" shell am start -W -n io.github.hashev.ffido/.MainActivity
sleep 8
"$ADB" -s "$SERIAL" shell pidof io.github.hashev.ffido
if "$ADB" -s "$SERIAL" logcat -d -b crash | grep -q 'FATAL EXCEPTION'; then
  "$ADB" -s "$SERIAL" logcat -d -b crash
  exit 1
fi
echo "PASS: packaged Android APK installed and running on API $API x86_64"

# Real release A→B through FFIDO and the OS installer, with isolated QA keys.
# This uses the disposable emulator above and never a user's device.
python3 "$ROOT/scripts/update/test_android_flow.py" \
  --sdk "$SDK" \
  --serial "$SERIAL" \
  --directory "$ROOT/build/android-update-qa-api$API" \
  --fixtures "${FFIDO_ANDROID_FIXTURES:?Prepared QA fixtures are required}"
