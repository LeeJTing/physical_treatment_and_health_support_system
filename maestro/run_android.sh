#!/usr/bin/env bash
# Runs the Chapter 5 Maestro flows on an Android emulator (9 Nov). These are the test cases that
# pass through Android's own screens (permission dialogs, the photo picker, the notification and
# "Alarms & reminders" settings); the cases that stay inside the app are Flutter integration
# tests (integration_test/run_android.sh).
#
# Needs:
#   - Maestro CLI (https://maestro.mobile.dev) and Java 17 or later;
#   - the emulator (1080 x 2436 screen) with the release build on its in-memory test data (the
#     build that patients install, so a release-only fault such as a missing permission shows):
#       flutter build apk --release --target-platform android-x64 --dart-define=USE_FAKES=true \
#         --dart-define=AI_BASE_URL=http://10.0.2.2:8000
#       adb install -r build/app/outputs/flutter-apk/app-release.apk
#   - the two posture clips in the emulator's Movies folder (clip_019_correct.mp4, 29 s, and
#     clip_022_short_range.mp4, 27 s, from the fitness7 data set; see the flows);
#   - the AI server on the computer at port 8000 with DEV_AUTH_BYPASS=true.
# Results (logs, screenshots, alarm lists) go to build/maestro/ unless OUT is set.
set -u
cd "$(dirname "$0")"
DEVICE="${DEVICE:-emulator-5554}"
OUT="${OUT:-../build/maestro}"
PKG=com.physical_treatment_and_health_support_system.tarumt.physical_treatment_and_health_support_system
MAESTRO="${MAESTRO:-maestro}"
mkdir -p "$OUT"

FLOWS=(
  rem_01_permission_allowed
  rem_02_change_days
  rem_04_permission_refused
  s19_exact_alarms
  s11_second_plan
  pos_01_correct_clip
  pos_02_short_range_clip
)

alarms() { # the app's pending alarms, one "day date time" per line (the emulator's clock is GMT)
  MSYS_NO_PATHCONV=1 adb -s "$DEVICE" shell dumpsys alarm |
    grep "RTC_WAKEUP #.*$PKG" | grep -o "origWhen [0-9]*" | sort -u |
    while read -r _ ms; do date -u -d "@$((ms / 1000))" "+%a %Y-%m-%d %H:%M"; done
}

failed=0
for f in "${FLOWS[@]}"; do
  echo "=== $f"
  # Every flow starts as a fresh install: Maestro clears the data and the runtime permissions, and
  # this resets the special app access (Alarms & reminders), which clearing the data keeps.
  MSYS_NO_PATHCONV=1 adb -s "$DEVICE" shell cmd appops reset "$PKG"
  # Maestro stops the app when a flow ends, and Android cancels a stopped app's alarms, so the
  # alarms of the reminder cases are recorded while the flow runs (the last non-empty list).
  watcher=""
  case "$f" in
    rem_01_permission_allowed | rem_02_change_days)
      : > "$OUT/${f}_alarms.txt"
      ( while :; do a="$(alarms)"; [ -n "$a" ] && echo "$a" > "$OUT/${f}_alarms.txt"; sleep 3; done ) &
      watcher=$!
      ;;
  esac
  if "$MAESTRO" --device "$DEVICE" test --debug-output "$OUT/$f" "$f.yaml" > "$OUT/$f.log" 2>&1; then
    echo "PASS $f"
  else
    echo "FAIL $f (see $OUT/$f.log)"
    failed=$((failed + 1))
  fi
  if [ -n "$watcher" ]; then
    kill "$watcher" 2>/dev/null
    echo "  alarms while the flow ran: $(wc -l < "$OUT/${f}_alarms.txt")"
    sed 's/^/    /' "$OUT/${f}_alarms.txt"
  fi
  # takeScreenshot files land inside the debug output; gather them in one folder.
  mkdir -p "$OUT/evidence"
  find "$OUT/$f" -path "*takeScreenshot*" -name "*.png" -exec cp {} "$OUT/evidence/" \; 2>/dev/null
done
echo "$(( ${#FLOWS[@]} - failed )) of ${#FLOWS[@]} flows passed"
exit $failed
