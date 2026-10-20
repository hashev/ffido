#!/usr/bin/env bash
# Install and start the validation APK in a disposable headless emulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_HOME:?Android SDK is required}"
IMAGE='system-images;android-35;google_apis;x86_64'
export ANDROID_USER_HOME="$RUNNER_TEMP/ffido-android"
export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
mkdir -p "$ANDROID_AVD_HOME"
if ! "$SDK/cmdline-tools/latest/bin/sdkmanager" 'emulator' "$IMAGE" > "$RUNNER_TEMP/android-sdk-smoke.log" 2>&1; then
  tail -80 "$RUNNER_TEMP/android-sdk-smoke.log"
  exit 1
fi
echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd --force --name ffido-smoke --package "$IMAGE" --path "$ANDROID_AVD_HOME/ffido-smoke.avd"
"$SDK/cmdline-tools/latest/bin/avdmanager" list avd
test -f "$ANDROID_AVD_HOME/ffido-smoke.ini"
sudo chmod a+rw /dev/kvm
"$SDK/emulator/emulator" -avd ffido-smoke -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect > "$RUNNER_TEMP/ffido-emulator.log" 2>&1 &
EMULATOR_PID=$!
trap 'kill "$EMULATOR_PID" 2>/dev/null || true' EXIT
ADB="$SDK/platform-tools/adb"
booted=false
for attempt in $(seq 1 120); do
  if [[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
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
"$ADB" install "$ROOT/$APK"
"$ADB" shell am start -W -n io.github.hashev.ffido/.MainActivity
sleep 8
"$ADB" shell pidof io.github.hashev.ffido
if "$ADB" logcat -d -b crash | grep -q 'FATAL EXCEPTION'; then
  "$ADB" logcat -d -b crash
  exit 1
fi
echo 'PASS: packaged Android APK installed and running on API 35 x86_64'
