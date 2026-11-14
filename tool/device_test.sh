#!/bin/sh
# Runs integration_test/flow_test.dart on the phone connected via adb.
#
# Builds the test app in dagger (ci DeviceTestApks), installs it next to the
# release app (id ...phoneme_party.test, name "PP Test", own storage), runs
# it, prints the result and the audio log, and uninstalls it again.
# KEEP=1 keeps it installed; APKS=dir uses APKs built before.
#
# Needs: adb with one device, dagger. Turn the screen on and unlock first.
set -eu
app=de.relaxandplay.phoneme_party.test
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cd "$(dirname "$0")/.."

apks=${APKS:-}
if [ -z "$apks" ]; then
	dagger call -q -m ci device-test-apks ${1:+--target "$1"} export --path "$out" >/dev/null
	apks=$out
fi
# each build has its own debug key: replace, never update (test app only)
adb uninstall "$app" >/dev/null 2>&1 || true
adb uninstall "$app.test" >/dev/null 2>&1 || true
adb install -r -t "$apks/app.apk" >/dev/null
adb install -r -t "$apks/test.apk" >/dev/null
adb shell pm grant "$app" android.permission.RECORD_AUDIO
adb shell input keyevent KEYCODE_WAKEUP
adb logcat -c

runner=$(adb shell pm list instrumentation | sed -n "s/^instrumentation:\([^ ]*\) (target=$app)$/\1/p")
adb shell am instrument -w -r "$runner" >"$out/instrument.txt" || true

echo "== log (ms device on/off what)"
adb logcat -d -s flutter:I | sed -n 's/.*IOLOG //p'
echo "== Android audio events of the test app (the TTS engine plays under its own uid)"
uid=$(adb shell dumpsys package "$app" | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1)
adb shell dumpsys audio | grep -E "u/pid:$uid|uid:$uid|pack:$app" | tail -60 || true
echo "== result"
grep -E "^(OK|FAILURES|INSTRUMENTATION_STATUS: (test|stack)=|Tests run)" "$out/instrument.txt" || cat "$out/instrument.txt"

if [ "${KEEP:-}" != 1 ]; then
	adb uninstall "$app" >/dev/null || true
	adb uninstall "$app.test" >/dev/null || true
fi
grep -q "^OK (" "$out/instrument.txt"
